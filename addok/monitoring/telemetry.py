"""
OpenTelemetry telemetry configuration for Addok geocoding service.
Provides centralized setup for tracing, metrics, and logging.
"""

import os
import sys
import logging
import time
from typing import Dict, Any, Optional
from datetime import datetime

# OpenTelemetry imports
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, ConsoleSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader, ConsoleMetricExporter
from opentelemetry.sdk.resources import Resource
# Note: Falcon instrumentation is not directly available, we'll create custom middleware
from opentelemetry.instrumentation.redis import RedisInstrumentor  
from opentelemetry.instrumentation.sqlite3 import SQLite3Instrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

# OTLP exporters
try:
    from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
    from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
    OTLP_AVAILABLE = True
except ImportError:
    OTLP_AVAILABLE = False

logger = logging.getLogger(__name__)

class AddokTelemetry:
    """Centralized OpenTelemetry configuration for Addok"""
    
    def __init__(self):
        self.resource = self._create_resource()
        self.tracer_provider = None
        self.meter_provider = None
        self.tracer = None
        self.meter = None
        self.metrics = {}
        self.initialized = False
        
    def _create_resource(self) -> Resource:
        """Create OpenTelemetry resource with service information"""
        attributes = {
            "service.name": os.getenv("OTEL_SERVICE_NAME", "addok-ban"),
            "service.version": os.getenv("OTEL_SERVICE_VERSION", "2.1.5"),
            "deployment.environment": os.getenv("DEPLOYMENT_ENV", "production"),
        }
        
        # Add Kubernetes attributes if available
        if os.getenv("K8S_NAMESPACE"):
            attributes.update({
                "k8s.namespace.name": os.getenv("K8S_NAMESPACE"),
                "k8s.pod.name": os.getenv("K8S_POD_NAME", "unknown"),
                "k8s.node.name": os.getenv("K8S_NODE_NAME", "unknown"),
            })
        
        return Resource.create(attributes)
    
    def initialize_tracing(self) -> bool:
        """Initialize distributed tracing"""
        try:
            # Configure tracer provider
            self.tracer_provider = TracerProvider(resource=self.resource)
            trace.set_tracer_provider(self.tracer_provider)
            
            # Configure exporters based on environment
            otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
            
            if otlp_endpoint and OTLP_AVAILABLE:
                # Production: Use OTLP exporter
                try:
                    otlp_exporter = OTLPSpanExporter(
                        endpoint=otlp_endpoint,
                        insecure=True  # Using internal cluster communication
                    )
                    span_processor = BatchSpanProcessor(otlp_exporter)
                    self.tracer_provider.add_span_processor(span_processor)
                    logger.info(f"OTLP tracing initialized: {otlp_endpoint}")
                except Exception as e:
                    logger.warning(f"OTLP tracer setup failed: {e}, falling back to console")
                    console_processor = BatchSpanProcessor(ConsoleSpanExporter())
                    self.tracer_provider.add_span_processor(console_processor)
            else:
                # Development: Use console exporter
                console_processor = BatchSpanProcessor(ConsoleSpanExporter())
                self.tracer_provider.add_span_processor(console_processor)
                logger.info("Console tracing initialized (development mode)")
            
            # Get tracer instance
            self.tracer = trace.get_tracer(__name__, version="2.1.5")
            
            logger.info("OpenTelemetry tracing initialized successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize tracing: {e}")
            return False
            
    def initialize_metrics(self) -> bool:
        """Initialize metrics collection"""
        try:
            # Configure exporters
            otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
            
            if otlp_endpoint and OTLP_AVAILABLE:
                # Production: Use OTLP exporter
                try:
                    metric_exporter = OTLPMetricExporter(
                        endpoint=otlp_endpoint,
                        insecure=True
                    )
                    metric_reader = PeriodicExportingMetricReader(
                        exporter=metric_exporter,
                        export_interval_millis=15000,  # Export every 15 seconds
                    )
                    logger.info(f"OTLP metrics initialized: {otlp_endpoint}")
                except Exception as e:
                    logger.warning(f"OTLP metrics setup failed: {e}, falling back to console")
                    metric_reader = PeriodicExportingMetricReader(
                        exporter=ConsoleMetricExporter(),
                        export_interval_millis=60000,  # Less frequent for console
                    )
            else:
                # Development: Use console exporter
                metric_reader = PeriodicExportingMetricReader(
                    exporter=ConsoleMetricExporter(),
                    export_interval_millis=60000,
                )
                logger.info("Console metrics initialized (development mode)")
            
            # Configure meter provider
            self.meter_provider = MeterProvider(
                resource=self.resource,
                metric_readers=[metric_reader]
            )
            metrics.set_meter_provider(self.meter_provider)
            
            # Get meter instance
            self.meter = metrics.get_meter(__name__, version="2.1.5")
            
            # Initialize custom metrics
            self._initialize_custom_metrics()
            
            logger.info("OpenTelemetry metrics initialized successfully")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize metrics: {e}")
            return False
    
    def _initialize_custom_metrics(self):
        """Initialize application-specific metrics"""
        try:
            self.metrics = {
                # Request metrics
                'geocoding_requests_total': self.meter.create_counter(
                    "addok_geocoding_requests_total",
                    description="Total number of geocoding requests",
                    unit="1"
                ),
                'geocoding_requests_duration': self.meter.create_histogram(
                    "addok_geocoding_request_duration_seconds",
                    description="Duration of geocoding requests in seconds",
                    unit="s"
                ),
                
                # CSV processing metrics
                'csv_uploads_total': self.meter.create_counter(
                    "addok_csv_uploads_total",
                    description="Total number of CSV uploads",
                    unit="1"
                ),
                'csv_rows_processed': self.meter.create_counter(
                    "addok_csv_rows_processed_total",
                    description="Total number of CSV rows processed", 
                    unit="1"
                ),
                'csv_processing_duration': self.meter.create_histogram(
                    "addok_csv_processing_duration_seconds",
                    description="Duration of CSV processing in seconds",
                    unit="s"
                ),
                
                # Cache metrics
                'cache_hits_total': self.meter.create_counter(
                    "addok_cache_hits_total",
                    description="Total number of cache hits",
                    unit="1"
                ),
                'cache_misses_total': self.meter.create_counter(
                    "addok_cache_misses_total",
                    description="Total number of cache misses",
                    unit="1"
                ),
                
                # Error metrics
                'errors_total': self.meter.create_counter(
                    "addok_errors_total",
                    description="Total number of errors",
                    unit="1"
                ),
                
                # Performance metrics
                'active_requests': self.meter.create_up_down_counter(
                    "addok_active_requests",
                    description="Number of active requests",
                    unit="1"
                ),
            }
            logger.info(f"Initialized {len(self.metrics)} custom metrics")
        except Exception as e:
            logger.error(f"Failed to initialize custom metrics: {e}")
    
    def initialize_auto_instrumentation(self, app=None) -> bool:
        """Initialize automatic instrumentation for frameworks"""
        try:
            instrumentation_count = 0
            
            # Redis instrumentation
            try:
                RedisInstrumentor().instrument()
                instrumentation_count += 1
                logger.info("Redis auto-instrumentation enabled")
            except Exception as e:
                logger.warning(f"Redis instrumentation failed: {e}")
            
            # SQLite instrumentation
            try:
                SQLite3Instrumentor().instrument()
                instrumentation_count += 1
                logger.info("SQLite auto-instrumentation enabled")
            except Exception as e:
                logger.warning(f"SQLite instrumentation failed: {e}")
            
            # Requests instrumentation
            try:
                RequestsInstrumentor().instrument()
                instrumentation_count += 1
                logger.info("Requests auto-instrumentation enabled")
            except Exception as e:
                logger.warning(f"Requests instrumentation failed: {e}")
            
            logger.info(f"Auto-instrumentation initialized: {instrumentation_count}/3 components")
            return instrumentation_count > 0
            
        except Exception as e:
            logger.error(f"Failed to initialize auto-instrumentation: {e}")
            return False
    
    def initialize_all(self, app=None) -> bool:
        """Initialize all telemetry components"""
        if self.initialized:
            logger.info("Telemetry already initialized")
            return True
            
        try:
            success = True
            
            # Initialize tracing
            if not self.initialize_tracing():
                success = False
                
            # Initialize metrics  
            if not self.initialize_metrics():
                success = False
            
            # Initialize auto-instrumentation if Flask app provided
            if app and not self.initialize_auto_instrumentation(app):
                logger.warning("Auto-instrumentation failed, continuing anyway")
                
            self.initialized = success
            
            if success:
                logger.info("🚀 OpenTelemetry telemetry fully initialized")
            else:
                logger.error("⚠️ OpenTelemetry telemetry initialization incomplete")
                
            return success
            
        except Exception as e:
            logger.error(f"Failed to initialize telemetry: {e}")
            return False
    
    def record_geocoding_request(self, endpoint: str, status: str, duration: float, 
                               query_length: int = 0, results_count: int = 0):
        """Record metrics for geocoding requests"""
        if not self.metrics:
            return
            
        try:
            attributes = {
                "endpoint": endpoint,
                "status": status,
                "query_length_range": self._get_length_range(query_length),
                "results_range": self._get_results_range(results_count)
            }
            
            self.metrics['geocoding_requests_total'].add(1, attributes)
            self.metrics['geocoding_requests_duration'].record(duration, attributes)
        except Exception as e:
            logger.debug(f"Failed to record geocoding metrics: {e}")
    
    def record_csv_processing(self, operation: str, rows_count: int, 
                            duration: float, success: bool):
        """Record metrics for CSV processing"""
        if not self.metrics:
            return
            
        try:
            attributes = {
                "operation": operation,
                "success": str(success).lower(),
                "rows_range": self._get_rows_range(rows_count)
            }
            
            self.metrics['csv_uploads_total'].add(1, attributes)
            self.metrics['csv_rows_processed'].add(rows_count, attributes)
            self.metrics['csv_processing_duration'].record(duration, attributes)
        except Exception as e:
            logger.debug(f"Failed to record CSV metrics: {e}")
    
    def record_cache_hit(self, cache_type: str):
        """Record cache hit"""
        if not self.metrics:
            return
            
        try:
            self.metrics['cache_hits_total'].add(1, {"cache_type": cache_type})
        except Exception as e:
            logger.debug(f"Failed to record cache hit: {e}")
    
    def record_cache_miss(self, cache_type: str):
        """Record cache miss"""
        if not self.metrics:
            return
            
        try:
            self.metrics['cache_misses_total'].add(1, {"cache_type": cache_type})
        except Exception as e:
            logger.debug(f"Failed to record cache miss: {e}")
    
    def record_error(self, error_type: str, endpoint: str):
        """Record application error"""
        if not self.metrics:
            return
            
        try:
            attributes = {"error_type": error_type, "endpoint": endpoint}
            self.metrics['errors_total'].add(1, attributes)
        except Exception as e:
            logger.debug(f"Failed to record error metrics: {e}")
    
    def increment_active_requests(self, delta: int = 1):
        """Increment active request counter"""
        if not self.metrics:
            return
            
        try:
            self.metrics['active_requests'].add(delta)
        except Exception as e:
            logger.debug(f"Failed to update active requests: {e}")
    
    def get_tracer(self):
        """Get the tracer instance"""
        return self.tracer
    
    def _get_length_range(self, length: int) -> str:
        """Get query length range for metrics"""
        if length <= 10: return "0-10"
        elif length <= 50: return "11-50"
        elif length <= 100: return "51-100"
        else: return "100+"
    
    def _get_results_range(self, count: int) -> str:
        """Get results count range for metrics"""
        if count == 0: return "0"
        elif count <= 5: return "1-5"
        elif count <= 20: return "6-20"
        else: return "20+"
    
    def _get_rows_range(self, rows: int) -> str:
        """Get CSV rows range for metrics"""
        if rows <= 100: return "0-100"
        elif rows <= 1000: return "101-1000"
        elif rows <= 10000: return "1001-10000"
        else: return "10000+"

# Global telemetry instance
telemetry = AddokTelemetry()

def get_telemetry() -> AddokTelemetry:
    """Get the global telemetry instance"""
    return telemetry

def initialize_telemetry(app=None) -> bool:
    """Initialize telemetry - convenience function"""
    return telemetry.initialize_all(app)