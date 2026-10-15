"""Structured JSON logging with a request ID, and a last line of defence that masks anything shaped like a BVN."""

import contextvars
import json
import logging
import re
import sys
from datetime import datetime, timezone

# Holds the request ID for whatever request or message is being handled right now.
request_id_var: contextvars.ContextVar[str] = contextvars.ContextVar("request_id", default="-")

# A BVN is exactly 11 digits. Mask any 11 digit run, even if a developer logs one by mistake.
BVN_PATTERN = re.compile(r"(?<!\d)\d{11}(?!\d)")
REDACTED = "[REDACTED]"

# Attributes every LogRecord has; anything else was passed by us through `extra=`.
_STANDARD_ATTRS = set(vars(logging.LogRecord("", 0, "", 0, "", None, None))) | {"message", "asctime"}


def redact(value):
    if isinstance(value, str):
        return BVN_PATTERN.sub(REDACTED, value)
    if isinstance(value, dict):
        return {k: redact(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [redact(v) for v in value]
    return value


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "timestamp": datetime.fromtimestamp(record.created, timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": request_id_var.get(),
        }
        for key, value in vars(record).items():
            if key not in _STANDARD_ATTRS:
                entry[key] = value
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(redact(entry), default=str)


def configure_logging(level: str = "INFO") -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level)
