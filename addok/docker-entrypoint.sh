#!/usr/bin/env bash
set -euo pipefail

# Simplified Addok Entrypoint - Application Mode Only
echo "=== Addok BAN Application Startup v2.1 ==="

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Copy and patch addok.conf from data directory
setup_configuration() {
    log "Setting up configuration..."

    if [[ -f /data/addok.conf ]]; then
        log "Copying addok.conf from data directory..."
        mkdir -p /etc/addok
        cp /data/addok.conf /etc/addok/addok.conf
        log "✓ addok.conf copied"
    else
        log "ERROR: No addok.conf found in /data/"
        exit 1
    fi

    # Fix Python 3 octal literals
    log "Patching configuration for Python 3..."
    python3 <<EOF
import re
conf = open("/etc/addok/addok.conf").read()
patched = re.sub(r'(?<![0-9a-zA-Z_])0([0-7]+)', r'0o\1', conf)
open("/etc/addok/addok.patched.conf", "w").write(patched)
EOF

    # Add runtime configuration
    {
        echo ""
        echo "# Runtime configuration - Generated $(date)"
        echo "LOG_DIR = '/logs'"
        [[ "${LOG_QUERIES:-0}" = "1" ]] && echo "LOG_QUERIES = True"
        [[ "${LOG_NOT_FOUND:-0}" = "1" ]] && echo "LOG_NOT_FOUND = True"
        [[ -n "${SLOW_QUERIES:-}" ]] && echo "SLOW_QUERIES = ${SLOW_QUERIES}"
    } >> /etc/addok/addok.patched.conf

    export ADDOK_CONFIG_MODULE="/etc/addok/addok.patched.conf"
    log "✓ Configuration ready"
}

# Start the application
start_application() {
    log "Starting Addok application..."

    local workers=${WORKERS:-4}
    local timeout=${WORKER_TIMEOUT:-30}
    local port=${PORT:-7878}

    log "Configuration:"
    log "  Workers: $workers"
    log "  Worker timeout: ${timeout}s"
    log "  Port: $port"
    log "  Redis: ${REDIS_HOST:-redis}:${REDIS_PORT:-6379}"
    log "  Database: /data/addok.db"

    # Start gunicorn
    exec gunicorn \
        --workers "$workers" \
        --timeout "$timeout" \
        --bind "0.0.0.0:$port" \
        --access-logfile - \
        --error-logfile - \
        --log-level info \
        --preload \
        addok.http.wsgi
}

# Main execution
log "Verifying data files..."
if [[ ! -f /data/addok.db ]]; then
    log "ERROR: /data/addok.db not found!"
    exit 1
fi

setup_configuration
start_application
