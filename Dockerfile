FROM python:3.12-slim-bullseye@sha256:411fa4dcfdce7e7a3057c45662beba9dcd4fa36b2e50a2bfcd6c9333e59bf0db AS python-base
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_SYSTEM_PYTHON=1 \
    PATH="/usr/local/bin:$PATH"

WORKDIR /app


FROM python-base AS builder-base

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# install uv from official image — no curl pipe to sh
COPY --from=ghcr.io/astral-sh/uv:0.4.18 /uv /usr/local/bin/uv

ENV PATH="/root/.local/bin:$PATH"

COPY requirements.txt ./

RUN uv pip install --no-cache-dir -r requirements.txt

COPY . .

FROM builder-base AS development

ENV FASTAPI_ENV=development

COPY requirements-dev.txt ./
RUN uv pip install --no-cache-dir -r requirements-dev.txt

EXPOSE 9090

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "9090"]

FROM python-base AS production

ENV FASTAPI_ENV=production


RUN groupadd -g 1500 produser && \
    useradd --no-log-init -m -u 1500 -g produser appuser

COPY --from=builder-base /usr/local/lib/python3.12/site-packages \
     /usr/local/lib/python3.12/site-packages
COPY --from=builder-base /usr/local/bin/uvicorn /usr/local/bin/uvicorn
COPY --from=builder-base /usr/local/bin/gunicorn /usr/local/bin/gunicorn

COPY --chown=appuser:produser . .

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c \
    "import urllib.request; urllib.request.urlopen('http://localhost:3000/health')" \
    || exit 1

CMD ["gunicorn", "--worker-class", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:3000", "src.main:app"]