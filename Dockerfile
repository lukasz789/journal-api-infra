# syntax=docker/dockerfile:1

FROM python:3.14-slim

# copy uv from the official uv image to avoid installing it from PyPI
COPY --from=ghcr.io/astral-sh/uv:0.11.30 /uv /bin/uv

ENV PYTHONPATH=/app \
    PATH="/app/.venv/bin:$PATH"

WORKDIR /app

# Install production dependencies before copying the application so this layer
# can be reused when only the source code changes.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY api/ ./api/

# The application does not need root privileges at runtime, so create a non-root user and switch to it.
RUN groupadd --system app && useradd --system --gid app app
USER app

EXPOSE 8000

CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
