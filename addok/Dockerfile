# Build stage
FROM python:3.11-alpine AS builder

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

# Build the source distribution
RUN python3 setup.py sdist

# Pre-compile all Python packages in builder stage
RUN pip wheel --no-cache-dir \
    cython \
    ./dist/addok-*.tar.gz \
    addok-fr==1.0.1 \
    addok-france==1.1.3 \
    addok-csv==1.1.0 \
    addok-sqlite-store==1.0.1 \
    gunicorn==23.0.0 \
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
    addok \
    addok-fr==1.0.1 \
    addok-france==1.1.3 \
    addok-csv==1.0.1 \
    addok-sqlite-store==1.0.1 \
    gunicorn==23.0.0 \
    ddtrace \
    python-geohash==0.8.5 \
    setuptools>=78.1.1 \
    pip>=23.3

# --- Final production image ---
FROM python:3.11-alpine

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

COPY --from=builder /build/python-install/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages/
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
ENV PYTHONPATH=/usr/local/lib/python3.11/site-packages

# Datadog tracing
ENV DD_SERVICE="addok"
ENV DD_ENV="production"
ENV DD_VERSION="2.1.0"
ENV DD_TRACE_ENABLED="true"
ENV DD_LOGS_INJECTION="true"

# Application configuration
ENV WORKERS=2
ENV WORKER_TIMEOUT=30
ENV LOG_QUERIES=0
ENV LOG_NOT_FOUND=0
ENV SLOW_QUERIES=500

# Pre-indexed data configuration
ENV PRE_INDEXED_DATA_URL="https://adresse.data.gouv.fr/data/ban/adresses/latest/addok/addok-france-bundle.zip"
ENV DOWNLOAD_TIMEOUT=300
ENV MAX_DOWNLOAD_RETRIES=3

# Security labels
LABEL com.datadoghq.tags.service="addok"
LABEL com.datadoghq.tags.env="production"
LABEL com.datadoghq.tags.version="2.1.0"
LABEL org.opencontainers.image.title="Addok Geocoding Service (Alpine)"
LABEL org.opencontainers.image.version="2.1.0"
LABEL org.opencontainers.image.base.name="python:3.11-alpine"
LABEL org.opencontainers.image.description="Production-ready French address geocoding service (Alpine Linux)"

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
