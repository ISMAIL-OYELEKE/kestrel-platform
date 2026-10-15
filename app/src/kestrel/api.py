"""The loan API. Run with: uvicorn kestrel.api:create_app --factory"""

import logging
import re
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, StrictStr, StringConstraints

from . import db, repository
from .bvn import BvnProtector, build_protector
from .config import Settings, load_settings
from .logs import configure_logging, request_id_var
from .messaging import ScoringQueue

log = logging.getLogger("kestrel.api")

# Accept a caller's request ID only if it is short and plain, so it is safe to log and to forward.
_SAFE_REQUEST_ID = re.compile(r"^[A-Za-z0-9-]{1,64}$")

Money = Annotated[Decimal, Field(gt=0, max_digits=14, decimal_places=2)]


class ApplicationIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    applicant_name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]
    # StrictStr: a JSON number would silently lose leading zeros. repr=False keeps it out of debug output.
    bvn: Annotated[StrictStr, StringConstraints(pattern=r"^[0-9]{11}$"), Field(repr=False)]
    monthly_salary: Money
    requested_amount: Money


class ApplicationCreated(BaseModel):
    id: uuid.UUID
    status: Literal["PENDING"]


class ApplicationOut(BaseModel):
    # No BVN field exists on this model, so FastAPI cannot return it even by mistake.
    id: uuid.UUID
    applicant_name: str
    monthly_salary: Decimal
    requested_amount: Decimal
    status: Literal["PENDING", "APPROVED", "DECLINED"]
    created_at: datetime
    decided_at: datetime | None


def create_app(
    settings: Settings | None = None,
    protector: BvnProtector | None = None,
    queue: ScoringQueue | None = None,
    pool=None,
) -> FastAPI:
    settings = settings or load_settings()
    configure_logging()

    if pool is None:
        from psycopg_pool import ConnectionPool

        pool = ConnectionPool(
            conninfo=db.conninfo(settings),
            # A function, not a dict: it runs for every new connection, so a rotated password is used.
            kwargs=lambda: db.connection_kwargs(settings),
            min_size=1,
            max_size=settings.db_pool_max,
            check=ConnectionPool.check_connection,
            open=False,
        )
    protector = protector or build_protector(settings)
    if queue is None:
        import boto3

        queue = ScoringQueue(boto3.client("sqs", endpoint_url=settings.sqs_endpoint_url), settings.queue_url)

    @asynccontextmanager
    async def lifespan(_app: FastAPI):
        pool.open()
        with pool.connection() as conn:
            db.ensure_schema(conn)
        log.info("api_started")
        yield
        pool.close()

    app = FastAPI(title="Kestrel loan API", lifespan=lifespan, docs_url=None, redoc_url=None)

    @app.middleware("http")
    async def request_context(request: Request, call_next):
        incoming = request.headers.get("x-request-id", "")
        request_id = incoming if _SAFE_REQUEST_ID.match(incoming) else str(uuid.uuid4())
        token = request_id_var.set(request_id)
        started = time.perf_counter()
        try:
            response = await call_next(request)
        finally:
            request_id_var.reset(token)
        response.headers["X-Request-ID"] = request_id
        # Logged with an explicit request_id because the context was reset above.
        log.info(
            "request_completed",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "duration_ms": round((time.perf_counter() - started) * 1000, 1),
            },
        )
        return response

    @app.exception_handler(RequestValidationError)
    async def validation_error(_request: Request, exc: RequestValidationError):
        # FastAPI's default 422 echoes the submitted value back. That would put a BVN in a response,
        # so only the field, the message and the error type are returned.
        errors = [{"loc": e["loc"], "msg": e["msg"], "type": e["type"]} for e in exc.errors()]
        return JSONResponse(status_code=422, content={"detail": errors})

    @app.exception_handler(Exception)
    async def unexpected_error(_request: Request, exc: Exception):
        log.exception("unhandled_error")
        return JSONResponse(status_code=500, content={"detail": "internal error", "request_id": request_id_var.get()})

    @app.post("/applications", status_code=201, response_model=ApplicationCreated)
    def create_application(body: ApplicationIn, response: Response):
        application_id = str(uuid.uuid4())
        request_id = request_id_var.get()

        with pool.connection() as conn:  # commits when the block ends without an error
            repository.insert_application(
                conn,
                application_id=application_id,
                applicant_name=body.applicant_name,
                bvn_ciphertext=protector.encrypt(body.bvn, application_id),
                bvn_lookup_hash=protector.lookup_hash(body.bvn),
                monthly_salary=body.monthly_salary,
                requested_amount=body.requested_amount,
                request_id=request_id,
            )

        try:
            queue.send(application_id, request_id)
        except Exception:
            # Without a queue message the application would stay PENDING forever. Remove it and ask the
            # client to retry, rather than accept something that will never be scored.
            log.exception("enqueue_failed", extra={"application_id": application_id})
            with pool.connection() as conn:
                repository.delete_application(conn, application_id)
            raise HTTPException(status_code=503, detail="could not accept application, please retry") from None

        log.info("application_created", extra={"application_id": application_id})
        response.headers["Location"] = f"/applications/{application_id}"
        return {"id": application_id, "status": "PENDING"}

    @app.get("/applications/{application_id}", response_model=ApplicationOut)
    def read_application(application_id: uuid.UUID):
        with pool.connection() as conn:
            row = repository.get_application(conn, str(application_id))
        if row is None:
            raise HTTPException(status_code=404, detail="application not found")
        return row

    @app.get("/health/live")
    def liveness():
        # Used by the load balancer. It does not touch the database on purpose: if the database is
        # busy, marking every task unhealthy would turn a slowdown into a full outage (incident 1).
        return {"status": "ok"}

    @app.get("/health")
    def health():
        try:
            with pool.connection(timeout=2) as conn:
                repository.ping(conn)
        except Exception:
            log.warning("health_database_unreachable")
            return JSONResponse(status_code=503, content={"status": "degraded", "database": "unreachable"})
        return {"status": "ok", "database": "ok"}

    return app
