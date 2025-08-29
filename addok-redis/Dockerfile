FROM redis:7-alpine

# Create non-root user
RUN addgroup -g 999 redis-user && \
    adduser -u 999 -G redis-user -s /bin/sh -D redis-user

COPY redis.conf /usr/local/etc/redis/redis.conf

# Create data directory with proper ownership
RUN mkdir -p /data && chown -R redis-user:redis-user /data /usr/local/etc/redis

# Run as non-root user
USER redis-user

CMD [ "redis-server", "/usr/local/etc/redis/redis.conf" ]
