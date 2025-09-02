#!/usr/bin/env bash
set -euo pipefail

# Enhanced Addok Entrypoint with OpenTelemetry - Application Mode
echo "=== Addok BAN Application Startup v2.1.5-otel ==="

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

# Initialize OpenTelemetry environment
setup_telemetry() {
    log "Setting up OpenTelemetry..."
    
    # Validate OTEL configuration
    local otel_endpoint=${OTEL_EXPORTER_OTLP_ENDPOINT:-}
    local otel_service=${OTEL_SERVICE_NAME:-addok-ban}
    local otel_version=${OTEL_SERVICE_VERSION:-2.1.5}
    
    if [[ -n "$otel_endpoint" ]]; then
        log "OpenTelemetry enabled:"
        log "  Service: $otel_service"
        log "  Version: $otel_version"
        log "  Endpoint: $otel_endpoint"
        log "  Protocol: ${OTEL_EXPORTER_OTLP_PROTOCOL:-grpc}"
        export OTEL_PYTHON_LOG_CORRELATION=true
    else
        log "OpenTelemetry endpoint not configured, using console export"
    fi
    
    # Set additional OTEL environment variables
    export OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED=${OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED:-true}
    export OTEL_PYTHON_LOG_LEVEL=${OTEL_PYTHON_LOG_LEVEL:-info}
    
    log "✓ OpenTelemetry configuration ready"
}

# Start the application
start_application() {
    log "Starting Addok application with OpenTelemetry..."

    local workers=${WORKERS:-4}
    local timeout=${WORKER_TIMEOUT:-30}
    local port=${PORT:-7878}

    log "Configuration:"
    log "  Workers: $workers"
    log "  Worker timeout: ${timeout}s"
    log "  Port: $port"
    log "  Redis: ${REDIS_HOST:-redis}:${REDIS_PORT:-6379}"
    log "  Database: /data/addok.db"
    log "  OTEL Endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT:-console}"

    # Check if monitoring modules are available
    if [[ -f "/app/monitoring/telemetry.py" ]] && [[ -f "/app/wsgi_otel.py" ]]; then
        log "✓ OpenTelemetry modules found, using enhanced WSGI"
        WSGI_MODULE="wsgi_otel:application"
    else
        log "WARNING: OpenTelemetry monitoring modules not found, falling back to standard WSGI"
        WSGI_MODULE="addok.http.wsgi"
    fi
    
    # Start gunicorn with OpenTelemetry using configuration file
    exec gunicorn \
        --config /app/gunicorn.conf.py \
        --workers "$workers" \
        --timeout "$timeout" \
        --bind "0.0.0.0:$port" \
        "$WSGI_MODULE"
}

# Main execution
log "Verifying data files..."
if [[ ! -f /data/addok.db ]]; then
    log "ERROR: /data/addok.db not found!"
    exit 1
fi

setup_configuration
setup_telemetry
start_application
