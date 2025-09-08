# Build stage
FROM python:3.13-alpine AS builder

WORKDIR /build

# Install ALL build dependencies (Alpine packages)
RUN apk add --no-cache \
    gcc \
    g++ \
    wget \
    unzip \
    build-base \
    python3-dev \
    musl-dev \
    linux-headers \
    patch \
    ncurses-dev \
    readline-dev

# Copy source code from addok-src
COPY ./addok-src ./addok-src

WORKDIR /build/addok-src

# Install setuptools for Python 3.13
RUN pip install --no-cache-dir setuptools wheel

# Build the source distribution
RUN python3 setup.py sdist

# Pre-compile all Python packages in builder stage
RUN pip wheel --no-cache-dir \
    cython \
    falcon==4.0.2 \
    ./dist/addok-*.tar.gz \
    addok-fr==1.0.1 \
    addok-france==1.1.3 \
    addok-csv==1.1.0 \
    addok-sqlite-store==1.0.1 \
    gunicorn==23.0.0 \
    opentelemetry-api \
    opentelemetry-sdk \
    opentelemetry-exporter-otlp \
    opentelemetry-instrumentation-redis \
    opentelemetry-instrumentation-sqlite3 \
    opentelemetry-instrumentation-requests \
    opentelemetry-propagator-b3 \
    prometheus-client==0.19.0 \
    psutil \
    ddtrace \
    python-geohash==0.8.5 \
    setuptools>=78.1.1 \
    pip>=23.3 \
    --wheel-dir /build/wheels

# Install packages to a target directory for copying
RUN pip install --no-cache-dir \
    --find-links /build/wheels \
    --prefix /build/python-install \
    cython \
    falcon==4.0.2 \
    addok \
    addok-fr==1.0.1 \
    addok-france==1.1.3 \
    addok-csv==1.1.0 \
    addok-sqlite-store==1.0.1 \
    gunicorn==23.0.0 \
    opentelemetry-api \
    opentelemetry-sdk \
    opentelemetry-exporter-otlp \
    opentelemetry-instrumentation-redis \
    opentelemetry-instrumentation-sqlite3 \
    opentelemetry-instrumentation-requests \
    opentelemetry-propagator-b3 \
    prometheus-client==0.19.0 \
    psutil \
    ddtrace \
    python-geohash==0.8.5 \
    setuptools>=78.1.1 \
    pip>=23.3

# Force upgrade Falcon to ensure 4.1.0+ is used
# Remove explicit falcon upgrade since addok conflicts with 4.1.0
# RUN pip install --no-cache-dir --prefix /build/python-install --upgrade falcon==4.1.0

# --- Final production image ---
FROM python:3.13-alpine

# Create non-root user (Alpine way)
RUN addgroup -g 1000 addok && \
    adduser -u 1000 -G addok -s /bin/sh -D addok

WORKDIR /app

# Install ONLY runtime dependencies (Alpine packages)
RUN apk add --no-cache \
    wget \
    unzip \
    netcat-openbsd \
    curl \
    bash \
    ncurses \
    readline

COPY --from=builder /build/python-install/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages/
COPY --from=builder /build/python-install/bin /usr/local/bin/

# Create directories with proper ownership
RUN mkdir -p /data /logs /etc/addok /tmp/addok-download \
    && chown -R addok:addok /data /logs /etc/addok /tmp/addok-download

# Environment variables
ENV ADDOK_CONFIG_MODULE=/etc/addok/addok.patched.conf
ENV REDIS_HOST=redis
ENV REDIS_PORT=6379
ENV REDIS_DB_INDEXES=0
ENV SQLITE_DB_PATH=/data/addok.db
ENV PYTHONPATH=/usr/local/lib/python3.13/site-packages

# OpenTelemetry configuration
ENV OTEL_SERVICE_NAME="addok-ban"
ENV OTEL_SERVICE_VERSION="2.1.5"
ENV OTEL_RESOURCE_ATTRIBUTES="service.name=addok-ban,service.version=2.1.5,deployment.environment=production"
ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://alloy.monitoring.svc.cluster.local:4317"
ENV OTEL_EXPORTER_OTLP_PROTOCOL="grpc"
ENV OTEL_TRACES_EXPORTER="otlp"
ENV OTEL_METRICS_EXPORTER="otlp"
ENV OTEL_LOGS_EXPORTER="otlp"
ENV OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED="true"
ENV OTEL_LOG_LEVEL="debug"

# Application configuration - aligned with gunicorn.conf.py  
ENV WORKERS=4
ENV WORKER_TIMEOUT=600
ENV LOG_QUERIES=0
ENV LOG_NOT_FOUND=0
ENV SLOW_QUERIES=500

# Pre-indexed data configuration
ENV PRE_INDEXED_DATA_URL="https://adresse.data.gouv.fr/data/ban/adresses/latest/addok/addok-france-bundle.zip"
ENV DOWNLOAD_TIMEOUT=300
ENV MAX_DOWNLOAD_RETRIES=3

# OpenTelemetry labels
LABEL otel.service.name="addok-ban"
LABEL otel.service.version="2.1.5"
LABEL otel.deployment.environment="production"
LABEL org.opencontainers.image.title="Addok Geocoding Service with OpenTelemetry (Alpine)"
LABEL org.opencontainers.image.version="2.1.5"
LABEL org.opencontainers.image.base.name="python:3.11-alpine"
LABEL org.opencontainers.image.description="Production-ready French address geocoding service with OpenTelemetry tracing (Alpine Linux)"

# Copy OpenTelemetry monitoring modules
COPY monitoring/ /app/monitoring/
COPY wsgi_otel.py /app/wsgi_otel.py
COPY gunicorn.conf.py /app/gunicorn.conf.py

# Copy enhanced entrypoint script
COPY docker-entrypoint.sh /bin/docker-entrypoint.sh
RUN chmod +x /bin/docker-entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=3 \
    CMD curl -f http://localhost:7878/search?q=test || exit 1

# Security: Run as non-root user
USER addok

VOLUME ["/data"]
EXPOSE 7878

ENTRYPOINT ["/bin/docker-entrypoint.sh"]
