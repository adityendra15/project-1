"""Small web service used to demonstrate a secure Kubernetes delivery pipeline.

The application deliberately exposes separate liveness and readiness endpoints so
Kubernetes can make different decisions:

* liveness: should the container be restarted?
* readiness: should the Pod receive traffic?
"""

from __future__ import annotations

import json
import logging
import os
import socket
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from flask import Flask, Response, g, jsonify, render_template, request

STARTED_AT = time.monotonic()
NOT_READY_FILE = Path("/tmp/not-ready")


class JsonFormatter(logging.Formatter):
    """Format application logs as one JSON object per line."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.now(UTC).isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        for field in ("method", "path", "status", "duration_ms", "remote_addr"):
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = value
        return json.dumps(payload, separators=(",", ":"))


def configure_logging() -> None:
    """Configure deterministic JSON logging for container log collection."""

    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    root_logger = logging.getLogger()
    root_logger.handlers.clear()
    root_logger.addHandler(handler)
    root_logger.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())


def create_app() -> Flask:
    """Create and configure the Flask application."""

    configure_logging()
    application = Flask(__name__)
    application.config.update(
        APP_VERSION=os.getenv("APP_VERSION", "development"),
        COMMIT_SHA=os.getenv("COMMIT_SHA", "local"),
        BUILD_TIME=os.getenv("BUILD_TIME", "unknown"),
    )

    @application.before_request
    def start_request_timer() -> None:
        g.request_started_at = time.perf_counter()

    @application.after_request
    def log_request(response: Response) -> Response:
        duration_ms = round((time.perf_counter() - g.request_started_at) * 1000, 2)
        application.logger.info(
            "request_completed",
            extra={
                "method": request.method,
                "path": request.path,
                "status": response.status_code,
                "duration_ms": duration_ms,
                "remote_addr": request.headers.get("X-Forwarded-For", request.remote_addr),
            },
        )
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; style-src 'self'; img-src 'self'; frame-ancestors 'none'"
        )
        return response

    @application.get("/")
    def index() -> str:
        return render_template(
            "index.html",
            version=application.config["APP_VERSION"],
            commit_sha=application.config["COMMIT_SHA"],
            hostname=socket.gethostname(),
        )

    @application.get("/health/live")
    def liveness() -> tuple[Response, int]:
        """Return 200 while the process is alive and able to serve requests."""

        return jsonify(status="alive", uptime_seconds=round(time.monotonic() - STARTED_AT, 3)), 200

    @application.get("/health/ready")
    def readiness() -> tuple[Response, int]:
        """Return whether this instance should currently receive Service traffic.

        Creating /tmp/not-ready is a safe demonstration switch. It makes the Pod
        unready without killing the process, showing why readiness and liveness
        are separate concepts.
        """

        if NOT_READY_FILE.exists():
            return jsonify(status="not-ready", reason="readiness switch is active"), 503
        return jsonify(status="ready"), 200

    @application.get("/version")
    def version() -> tuple[Response, int]:
        return (
            jsonify(
                version=application.config["APP_VERSION"],
                commit_sha=application.config["COMMIT_SHA"],
                build_time=application.config["BUILD_TIME"],
                hostname=socket.gethostname(),
            ),
            200,
        )

    @application.errorhandler(404)
    def not_found(_: Exception) -> tuple[Response, int]:
        return jsonify(error="not_found", path=request.path), 404

    return application


app = create_app()
