# --- Build stage ---
FROM python:3.10 AS builder

WORKDIR /build

# Copy source code from ../addok-src into the build stage
COPY ./addok-src ./addok-src

WORKDIR /build/addok-src

# Build the source distribution
RUN python3 setup.py sdist

# --- Final image ---
FROM python:3.10

WORKDIR /app

# Copy the built tar.gz from the builder stage
COPY --from=builder /build/addok-src/dist/addok-*.tar.gz ./addok-1.2.0.tar.gz

RUN pip install cython ./addok-1.2.0.tar.gz addok-fr==1.0.1 addok-france==1.1.3 addok-csv==1.0.1 addok-sqlite-store==1.0.1 gunicorn==20.1.0

ENV ADDOK_CONFIG_MODULE=/etc/addok/addok.patched.conf
ENV REDIS_HOST=redis
ENV REDIS_PORT=6379
ENV REDIS_DB_INDEXES=0
ENV SQLITE_DB_PATH=/data/addok.db

ENV DD_SERVICE="addok"
ENV DD_ENV="dev"
ENV DD_VERSION="1.2.0"

LABEL com.datadoghq.tags.service="addok"
LABEL com.datadoghq.tags.env="dev"
LABEL com.datadoghq.tags.version="1.2.0"

COPY docker-entrypoint.sh /bin

VOLUME ["/data"]
EXPOSE 7878

CMD ["docker-entrypoint.sh"]
