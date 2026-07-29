# syntax=docker/dockerfile:1.7

FROM python:3.13-slim-bookworm AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build
COPY requirements.txt .
RUN python -m pip install --prefix=/install --requirement requirements.txt

FROM python:3.13-slim-bookworm AS runtime

ARG APP_VERSION=development
ARG VCS_REF=local
ARG BUILD_TIME=unknown

LABEL org.opencontainers.image.title="secure-web" \
      org.opencontainers.image.description="Website used to demonstrate a secure automated Kubernetes delivery pipeline" \
      org.opencontainers.image.source="https://github.com/adityendra15/project-1" \
      org.opencontainers.image.revision="$VCS_REF" \
      org.opencontainers.image.created="$BUILD_TIME"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION="$APP_VERSION" \
    COMMIT_SHA="$VCS_REF" \
    BUILD_TIME="$BUILD_TIME" \
    PORT=8080

RUN groupadd --gid 10001 appgroup \
    && useradd --uid 10001 --gid appgroup --no-create-home --shell /usr/sbin/nologin appuser

COPY --from=builder /install /usr/local
WORKDIR /app
COPY --chown=appuser:appgroup app ./app

USER 10001:10001
EXPOSE 8080

CMD ["gunicorn", "--bind=0.0.0.0:8080", "--workers=2", "--threads=4", "--timeout=30", "--graceful-timeout=25", "--access-logfile=-", "--error-logfile=-", "app.main:app"]
