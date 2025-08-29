FROM python:3.11-alpine

# Install system dependencies for both addok and redis
RUN apk add --no-cache \
    gcc \
    g++ \
    python3-dev \
    musl-dev \
    linux-headers \
    supervisor \
    bash \
    wget \
    unzip \
    redis

# Create non-root user
RUN addgroup -g 1000 addok && \
    adduser -u 1000 -G addok -s /bin/sh -D addok

# Install Python packages
RUN pip install --no-cache-dir \
    cython \
    addok==1.0.3 \
    addok-fr==1.0.1 \
    addok-france==1.1.3 \
    addok-sqlite-store==1.0.1

# Create directories with proper ownership
RUN mkdir -p /etc/addok /data /var/log/supervisor /usr/local/etc/redis && \
    chown -R addok:addok /etc/addok /data

# Copy supervisor configuration
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Create basic redis configuration for standalone mode
RUN echo "dir /data/" > /usr/local/etc/redis/redis.conf && \
    echo "save 900 1" >> /usr/local/etc/redis/redis.conf && \
    echo "save 300 10" >> /usr/local/etc/redis/redis.conf && \
    echo "save 60 10000" >> /usr/local/etc/redis/redis.conf

ENV REDIS_HOST localhost

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Run as non-root user
USER addok

ENTRYPOINT ["/docker-entrypoint.sh"]
