#!/usr/bin/env bash
set -euo pipefail

# Enhanced Addok Docker Entrypoint v2.0
# Combines your improvements with production-ready patterns

# Default configuration
USE_PRE_INDEXED_DATA_URL=${PRE_INDEXED_DATA_URL:-"https://adresse.data.gouv.fr/data/ban/adresses/latest/addok/addok-france-bundle.zip"}
DOWNLOAD_TIMEOUT=${DOWNLOAD_TIMEOUT:-300}
MAX_DOWNLOAD_RETRIES=${MAX_DOWNLOAD_RETRIES:-3}
HEALTH_CHECK_PORT=${PORT:-7878}

echo "=== Enhanced Addok BAN Initialization v2.0 ==="
echo "Data URL: ${USE_PRE_INDEXED_DATA_URL}"
echo "Redis Host: ${REDIS_HOST:-redis}"
echo "Workers: ${WORKERS:-2}"
echo "Environment: ${DD_ENV:-production}"

# Function to log with timestamp
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Function to check if Redis is available
wait_for_redis() {
    log "Waiting for Redis to be ready..."
    local max_attempts=30
    local attempt=1

    while ! nc -z "${REDIS_HOST:-redis}" "${REDIS_PORT:-6379}"; do
        if [ $attempt -eq $max_attempts ]; then
            log "ERROR: Redis is not available after ${max_attempts} attempts"
            exit 1
        fi
        log "Redis is not ready yet. Waiting 5 seconds... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    log "Redis is ready!"
}

# Function to download and extract data with retries and integrity checks
download_and_extract_data() {
    log "Checking if data exists..."

    if [[ -f /data/addok.db ]] && [[ -f /data/dump.rdb ]] && [[ -f /etc/addok/addok.conf ]]; then
        log "Data files already exist. Performing integrity check..."
        if check_data_integrity; then
            log "Data integrity check passed. Skipping download."
            return 0
        else
            log "Data integrity check failed. Re-downloading..."
        fi
    fi

    log "Data files missing or corrupted. Downloading from ${USE_PRE_INDEXED_DATA_URL}"

    local attempt=1
    while [ $attempt -le $MAX_DOWNLOAD_RETRIES ]; do
        log "Download attempt $attempt/$MAX_DOWNLOAD_RETRIES"

        # Clean up any partial downloads
        rm -rf /tmp/addok-download/*

        # Download with progress, timeout, and retry
        if timeout $DOWNLOAD_TIMEOUT wget \
            --progress=bar:force \
            --retry-connrefused \
            --waitretry=5 \
            --read-timeout=20 \
            --timeout=15 \
            --tries=3 \
            --no-check-certificate \
            "${USE_PRE_INDEXED_DATA_URL}" \
            -O /tmp/addok-download/addok-pre-indexed-data.zip; then

            log "Download completed successfully"
            break
        else
            log "Download attempt $attempt failed"
            if [ $attempt -eq $MAX_DOWNLOAD_RETRIES ]; then
                log "ERROR: All download attempts failed"
                exit 1
            fi
            ((attempt++))
            sleep 10
        fi
    done

    # Verify downloaded file
    if [[ ! -f /tmp/addok-download/addok-pre-indexed-data.zip ]] || [[ ! -s /tmp/addok-download/addok-pre-indexed-data.zip ]]; then
        log "ERROR: Downloaded file is missing or empty"
        exit 1
    fi

    log "Extracting data..."
    if ! unzip -o /tmp/addok-download/addok-pre-indexed-data.zip -d /tmp/addok-download/extracted/; then
        log "ERROR: Failed to extract downloaded data"
        exit 1
    fi

    # Move files to correct locations with verification
    log "Installing configuration and data files..."

    # Install addok configuration
    if [[ -f /tmp/addok-download/extracted/addok.conf ]]; then
        cp /tmp/addok-download/extracted/addok.conf /etc/addok/addok.conf
        log "✓ Addok configuration installed"
    else
        log "ERROR: addok.conf not found in extracted data"
        exit 1
    fi

    # Install addok database
    if [[ -f /tmp/addok-download/extracted/addok.db ]]; then
        cp /tmp/addok-download/extracted/addok.db /data/addok.db
        log "✓ Addok database installed"
    else
        log "ERROR: addok.db not found in extracted data"
        exit 1
    fi

    # Install Redis dump
    if [[ -f /tmp/addok-download/extracted/dump.rdb ]]; then
        cp /tmp/addok-download/extracted/dump.rdb /data/dump.rdb
        log "✓ Redis dump installed"
    else
        log "ERROR: dump.rdb not found in extracted data"
        exit 1
    fi

    # Cleanup
    rm -rf /tmp/addok-download/*
    log "✓ Data installation completed and cleanup done"
}

# Function to check data integrity
check_data_integrity() {
    log "Performing data integrity check..."

    # Check if files exist and are not empty
    if [[ ! -s /data/addok.db ]]; then
        log "ERROR: addok.db is empty or missing"
        return 1
    fi

    if [[ ! -s /data/dump.rdb ]]; then
        log "ERROR: dump.rdb is empty or missing"
        return 1
    fi

    if [[ ! -f /etc/addok/addok.conf ]]; then
        log "ERROR: addok.conf is missing"
        return 1
    fi

    # Basic file size checks (addok.db should be substantial)
    local db_size=$(stat -c%s /data/addok.db 2>/dev/null || echo 0)
    if [ "$db_size" -lt 1000000 ]; then  # Less than 1MB is suspicious
        log "ERROR: addok.db appears to be too small ($db_size bytes)"
        return 1
    fi

    log "✓ Data integrity check passed"
    return 0
}

# Function to update configuration with runtime settings
fix_octal_literals() {
python3 <<EOF
import re
conf = open("/etc/addok/addok.conf").read()
patched = re.sub(r'(?<![0-9a-zA-Z_])0([0-7]+)', r'0o\1', conf)
open("/etc/addok/addok.patched.conf", "w").write(patched)
EOF
}

update_configuration() {
    log "Updating configuration..."
    fix_octal_literals
    {
        echo ""
        echo "# Runtime configuration - Generated $(date)"
        echo "LOG_DIR = '/logs'"

        [[ "${LOG_QUERIES:-0}" = "1" ]] && echo "LOG_QUERIES = True"
        [[ "${LOG_NOT_FOUND:-0}" = "1" ]] && echo "LOG_NOT_FOUND = True"
        [[ -n "${SLOW_QUERIES:-}" ]] && echo "SLOW_QUERIES = ${SLOW_QUERIES}"

        echo ""
        echo "# Health check configuration"
        echo "EXTRA_FIELDS = ["
        echo '    {"key": "citycode"},'
        echo '    {"key": "oldcitycode"},'
        echo '    {"key": "oldcity"},'
        echo '    {"key": "district"},'
        echo "]"
    } >> /etc/addok/addok.patched.conf

    export ADDOK_CONFIG_MODULE="/etc/addok/addok.patched.conf"
    log "✓ Configuration updated"
}

# Function to wait for dependencies with timeout
wait_for_dependencies() {
    log "Waiting for dependencies to be ready..."

    wait_for_redis

    # Give a moment for any other services
    sleep 5
    log "✓ All dependencies are ready"
}

# Function to start application with proper signal handling
start_application() {
    log "Starting Addok application..."

    # Validate environment
    local workers=${WORKERS:-2}
    local timeout=${WORKER_TIMEOUT:-30}

    log "Configuration:"
    log "  Workers: $workers"
    log "  Worker timeout: ${timeout}s"
    log "  Redis: ${REDIS_HOST:-redis}:${REDIS_PORT:-6379}"
    log "  Database: ${SQLITE_DB_PATH:-/data/addok.db}"

    # Start with ddtrace for observability
    log "Starting gunicorn with Datadog tracing..."
    exec ddtrace-run gunicorn \
        --workers "$workers" \
        --timeout "$timeout" \
        --bind "0.0.0.0:${HEALTH_CHECK_PORT}" \
        --access-logfile - \
        --error-logfile - \
        --log-level info \
        --preload \
        addok.http.wsgi
}

# Signal handler for graceful shutdown
graceful_shutdown() {
    log "Received shutdown signal, stopping services gracefully..."

    # Send SIGTERM to gunicorn if it's running
    if [ -n "${GUNICORN_PID:-}" ]; then
        kill -TERM "$GUNICORN_PID" 2>/dev/null || true
        wait "$GUNICORN_PID" 2>/dev/null || true
    fi

    log "Graceful shutdown completed"
    exit 0
}

# Set up signal handlers
trap 'graceful_shutdown' SIGTERM SIGINT

# Main execution flow
main() {
    log "Starting Enhanced Addok deployment..."

    # Step 1: Wait for dependencies
    wait_for_dependencies

    # Step 2: Download and extract data
    download_and_extract_data

    # Step 3: Check data integrity
    check_data_integrity

    # Step 4: Update configuration
    update_configuration

    # Step 5: Start the application
    start_application
}

# Run main function
main "$@"
