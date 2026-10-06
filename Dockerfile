# syntax=docker/dockerfile:1

############################
# Builder — resolve deps reproducibly with uv against uv.lock
############################
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# Dependencies only, as a cached layer (no project source yet).
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --no-install-project --no-dev

# Then the project itself (README.md is required by pyproject).
COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

############################
# Runtime — slim, non-root, read-only-rootfs friendly
############################
FROM python:3.12-slim-bookworm AS runtime

# Non-root uid matching the k8s securityContext (10001).
RUN groupadd --gid 10001 app \
 && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app

COPY --from=builder --chown=10001:10001 /app/.venv /app/.venv

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER 10001:10001
WORKDIR /app
EXPOSE 8080

# GITEA_URL and GITEA_TOKEN are injected at runtime (env / k8s secret).
# The server does a credential check() on boot and will exit if they are wrong.
ENTRYPOINT ["gitea-mcp"]
CMD ["--http", "--host", "0.0.0.0", "--port", "8080"]
