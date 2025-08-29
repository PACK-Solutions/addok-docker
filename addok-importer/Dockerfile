FROM python:3.11-alpine

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    g++ \
    python3-dev \
    musl-dev \
    linux-headers

# Create non-root user
RUN addgroup -g 1000 addok && \
    adduser -u 1000 -G addok -s /bin/sh -D addok

RUN pip install --no-cache-dir \
    cython \
    addok==1.0.3 \
    addok-fr==1.0.1 \
    addok-france==1.1.3 \
    addok-sqlite-store==1.0.1

COPY addok.conf /etc/addok/

ENV ADDOK_CONFIG_MODULE /etc/addok/addok.conf
ENV REDIS_HOST redis
ENV REDIS_PORT 6379
ENV REDIS_DB_INDEXES 0
ENV SQLITE_DB_PATH /data/addok.db

# Create data directory with proper ownership
RUN mkdir -p /data && chown -R addok:addok /data

VOLUME ["/data"]

# Run as non-root user
USER addok

ENTRYPOINT ["addok"]
