"""
Gunicorn configuration for Addok with OpenTelemetry support.
Ensures telemetry is properly initialized in each worker process.
"""

import os
import sys
import logging

# Add monitoring modules to path
sys.path.insert(0, '/app/monitoring')

def post_fork(server, worker):
    """Initialize telemetry in each worker after fork"""
    try:
        # Import here to avoid issues during master process startup
        from monitoring.telemetry import initialize_telemetry
        
        worker_pid = os.getpid()
        server.log.info(f"🚀 Initializing telemetry in worker pid={worker_pid}")
        
        # Initialize telemetry for this worker
        success = initialize_telemetry()
        
        if success:
            server.log.info(f"✅ Telemetry initialized successfully in worker pid={worker_pid}")
        else:
            server.log.warning(f"⚠️ Telemetry initialization failed in worker pid={worker_pid}")
            
    except Exception as e:
        server.log.error(f"❌ Failed to initialize telemetry in worker pid={os.getpid()}: {e}")

def worker_exit(server, worker):
    """Cleanup telemetry when worker exits"""
    try:
        from monitoring.telemetry import get_telemetry
        
        telemetry = get_telemetry()
        if telemetry and telemetry.tracer_provider:
            telemetry.tracer_provider.force_flush()
            server.log.info(f"🔄 Flushed spans on worker exit pid={os.getpid()}")
    except Exception as e:
        server.log.debug(f"Failed to flush spans on worker exit: {e}")

# Gunicorn server configuration
bind = "0.0.0.0:7878"
workers = int(os.getenv('WORKERS', '4'))  # Redis 8 optimization: 4 workers aligned with 4 I/O threads
worker_class = "sync"
worker_connections = 1000
timeout = int(os.getenv('WORKER_TIMEOUT', '600'))  # Enhanced timeout for large CSV processing (12k rows)
keepalive = 2
max_requests = 1000
max_requests_jitter = 100
preload_app = False  # Important: Don't preload to ensure proper fork behavior
accesslog = "-"
errorlog = "-"
loglevel = "info"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s"'