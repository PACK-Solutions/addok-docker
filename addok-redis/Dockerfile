FROM redis:8.2.1-alpine

# Redis 8.2.1-alpine already has redis user (UID 999, GID 1000)
# No need to create additional users - use the existing redis user

COPY redis.conf /usr/local/etc/redis/redis.conf

# Create data directory with proper ownership for existing redis user
RUN mkdir -p /data && chown -R redis:redis /data /usr/local/etc/redis

# Run as non-root user (use existing redis user)
USER redis

CMD [ "redis-server", "/usr/local/etc/redis/redis.conf" ]
