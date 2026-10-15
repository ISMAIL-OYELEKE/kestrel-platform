# Base image from Amazon ECR Public, not Docker Hub: no anonymous pull rate limit in CI or ECS.
FROM public.ecr.aws/docker/library/python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

WORKDIR /app

# Dependencies first, so this layer is cached when only the code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/

# Run as an unprivileged user, never as root.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER 10001

EXPOSE 8000
# Request logs come from our JSON middleware, so uvicorn's own access log is turned off.
CMD ["uvicorn", "kestrel.api:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
