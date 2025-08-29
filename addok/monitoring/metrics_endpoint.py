"""
Prometheus metrics endpoint for Addok geocoding service.
Provides /metrics endpoint for Prometheus scraping.
"""

import os
import sys
import psutil
import logging
from flask import Blueprint, Response
from prometheus_client import generate_latest, CollectorRegistry, CONTENT_TYPE_LATEST
from prometheus_client import Counter, Histogram, Gauge, Info, Enum
from datetime import datetime

logger = logging.getLogger(__name__)

# Create blueprint for metrics
metrics_bp = Blueprint('metrics', __name__)

# Create custom registry for Prometheus metrics
registry = CollectorRegistry()

# Application information
app_info = Info('addok_application_info', 'Application information', registry=registry)
app_info.info({
    'version': os.getenv('OTEL_SERVICE_VERSION', '2.1.5'),
    'python_version': f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
    'environment': os.getenv('DEPLOYMENT_ENV', 'production'),
    'build_date': datetime.now().isoformat(),
    'otel_enabled': str(bool(os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT'))).lower()
})

# System metrics
memory_usage = Gauge('addok_memory_usage_bytes', 'Memory usage in bytes', registry=registry)
cpu_usage = Gauge('addok_cpu_usage_percent', 'CPU usage percentage', registry=registry)
open_files = Gauge('addok_open_files', 'Number of open files', registry=registry)
uptime_seconds = Gauge('addok_uptime_seconds', 'Application uptime in seconds', registry=registry)

# Application health
health_status = Enum('addok_health_status', 'Application health status', 
                    states=['healthy', 'unhealthy', 'starting'], registry=registry)
health_status.state('starting')  # Initial state

# Request metrics (separate from OpenTelemetry for Prometheus compatibility)
request_counter = Counter('addok_http_requests_total', 
                         'Total HTTP requests', 
                         ['method', 'endpoint', 'status_code'], 
                         registry=registry)

request_duration = Histogram('addok_http_request_duration_seconds',
                           'HTTP request duration in seconds',
                           ['method', 'endpoint'],
                           registry=registry)

# Geocoding-specific metrics
geocoding_counter = Counter('addok_geocoding_operations_total',
                          'Total geocoding operations',
                          ['operation_type', 'result_status'],
                          registry=registry)

cache_operations = Counter('addok_cache_operations_total',
                         'Cache operations',
                         ['operation', 'result'],
                         registry=registry)

# Database metrics
redis_connections = Gauge('addok_redis_connections_active', 
                         'Active Redis connections', registry=registry)

sqlite_operations = Counter('addok_sqlite_operations_total',
                          'SQLite operations',
                          ['operation_type'],
                          registry=registry)

# CSV processing metrics
csv_processing_counter = Counter('addok_csv_processing_total',
                               'CSV processing operations',
                               ['operation_type', 'status'],
                               registry=registry)

csv_rows_gauge = Gauge('addok_csv_rows_processed_current', 
                      'Currently processing CSV rows', registry=registry)

# Error tracking
error_counter = Counter('addok_errors_total',
                      'Application errors',
                      ['error_type', 'severity'],
                      registry=registry)

# Performance indicators
response_time_summary = Histogram('addok_response_time_seconds',
                                'Response time for different operations',
                                ['operation'],
                                buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0],
                                registry=registry)

# Application startup time
startup_time = datetime.now()

@metrics_bp.route('/metrics')
def prometheus_metrics():
    """Prometheus metrics endpoint"""
    try:
        # Update system metrics
        _update_system_metrics()
        
        # Update application metrics
        _update_application_metrics()
        
        # Generate Prometheus metrics
        return Response(generate_latest(registry), mimetype=CONTENT_TYPE_LATEST)
        
    except Exception as e:
        logger.error(f"Error generating Prometheus metrics: {e}")
        # Return empty metrics on error to avoid scraping failures
        return Response("# Error generating metrics\n", mimetype=CONTENT_TYPE_LATEST)

@metrics_bp.route('/health/metrics')
def health_metrics():
    """Health check with basic metrics"""
    try:
        _update_system_metrics()
        
        # Basic health information
        process = psutil.Process()
        memory_info = process.memory_info()
        
        health_data = {
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'uptime_seconds': (datetime.now() - startup_time).total_seconds(),
            'memory_usage_mb': round(memory_info.rss / 1024 / 1024, 2),
            'cpu_percent': process.cpu_percent(),
            'open_files': getattr(process, 'num_fds', lambda: 0)(),
            'metrics_endpoint': '/metrics'
        }
        
        return health_data, 200
        
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {
            'status': 'unhealthy',
            'timestamp': datetime.now().isoformat(),
            'error': str(e)
        }, 500

def _update_system_metrics():
    """Update system-level metrics"""
    try:
        process = psutil.Process()
        memory_info = process.memory_info()
        
        # Update gauges
        memory_usage.set(memory_info.rss)
        cpu_usage.set(process.cpu_percent())
        uptime_seconds.set((datetime.now() - startup_time).total_seconds())
        
        # Update open files (Linux/macOS only)
        try:
            open_files.set(process.num_fds())
        except AttributeError:
            # Windows doesn't have num_fds
            pass
            
    except Exception as e:
        logger.debug(f"Failed to update system metrics: {e}")

def _update_application_metrics():
    """Update application-specific metrics"""
    try:
        # Set health status based on application state
        # This could be enhanced with actual health checks
        health_status.state('healthy')
        
        # Update Redis connection count if available
        try:
            import redis
            # This would require access to the Redis client instance
            # For now, we'll leave it as a placeholder
        except ImportError:
            pass
            
    except Exception as e:
        logger.debug(f"Failed to update application metrics: {e}")

# Utility functions for recording metrics from the application

def record_http_request(method: str, endpoint: str, status_code: int, duration: float):
    """Record HTTP request metrics"""
    try:
        request_counter.labels(
            method=method,
            endpoint=endpoint, 
            status_code=str(status_code)
        ).inc()
        
        request_duration.labels(
            method=method,
            endpoint=endpoint
        ).observe(duration)
        
    except Exception as e:
        logger.debug(f"Failed to record HTTP request metrics: {e}")

def record_geocoding_operation(operation_type: str, result_status: str, duration: float):
    """Record geocoding operation metrics"""
    try:
        geocoding_counter.labels(
            operation_type=operation_type,
            result_status=result_status
        ).inc()
        
        response_time_summary.labels(operation=operation_type).observe(duration)
        
    except Exception as e:
        logger.debug(f"Failed to record geocoding metrics: {e}")

def record_cache_operation(operation: str, result: str):
    """Record cache operation metrics"""
    try:
        cache_operations.labels(operation=operation, result=result).inc()
    except Exception as e:
        logger.debug(f"Failed to record cache metrics: {e}")

def record_csv_processing(operation_type: str, status: str, rows_count: int = 0):
    """Record CSV processing metrics"""
    try:
        csv_processing_counter.labels(
            operation_type=operation_type,
            status=status
        ).inc()
        
        if rows_count > 0:
            csv_rows_gauge.set(rows_count)
            
    except Exception as e:
        logger.debug(f"Failed to record CSV metrics: {e}")

def record_error(error_type: str, severity: str = 'error'):
    """Record error metrics"""
    try:
        error_counter.labels(error_type=error_type, severity=severity).inc()
    except Exception as e:
        logger.debug(f"Failed to record error metrics: {e}")

def record_sqlite_operation(operation_type: str):
    """Record SQLite operation metrics"""
    try:
        sqlite_operations.labels(operation_type=operation_type).inc()
    except Exception as e:
        logger.debug(f"Failed to record SQLite metrics: {e}")

# Initialize metrics on import
try:
    _update_system_metrics()
    logger.info("Prometheus metrics endpoint initialized successfully")
except Exception as e:
    logger.warning(f"Failed to initialize metrics endpoint: {e}")