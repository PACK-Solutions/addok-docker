"""
Custom Falcon middleware for OpenTelemetry integration.
Provides distributed tracing and metrics collection for Falcon applications.
"""

import time
import logging
from typing import Optional
from opentelemetry import trace
from opentelemetry.semconv.trace import SpanAttributes
from opentelemetry.trace import Status, StatusCode
from .telemetry import get_telemetry
from .metrics_endpoint import (
    record_http_request, 
    record_geocoding_operation, 
    record_error
)

logger = logging.getLogger(__name__)

class OpenTelemetryMiddleware:
    """Falcon middleware for OpenTelemetry tracing and metrics"""
    
    def __init__(self):
        self.telemetry = get_telemetry()
        self.tracer = None
        
    def process_request(self, req, resp):
        """Process incoming request - start span and record metrics"""
        try:
            # Initialize tracer if not done
            if not self.tracer and self.telemetry.tracer:
                self.tracer = self.telemetry.tracer
            
            # Start timing
            req.start_time = time.time()
            
            # Increment active requests
            self.telemetry.increment_active_requests(1)
            
            # Start span if tracer available
            if self.tracer:
                # Extract operation name from path
                operation_name = self._get_operation_name(req)
                
                # Create span
                span = self.tracer.start_span(
                    name=operation_name,
                    kind=trace.SpanKind.SERVER
                )
                
                # Set span attributes
                span.set_attributes({
                    SpanAttributes.HTTP_METHOD: req.method,
                    SpanAttributes.HTTP_URL: req.url,
                    SpanAttributes.HTTP_SCHEME: req.scheme,
                    SpanAttributes.HTTP_USER_AGENT: req.user_agent or "",
                    SpanAttributes.HTTP_CLIENT_IP: self._get_client_ip(req),
                    "addok.query": req.get_param('q', '')[:100] if req.get_param('q') else "",
                    "addok.limit": req.get_param_as_int('limit', 5),
                    "addok.autocomplete": req.get_param_as_bool('autocomplete', True),
                })
                
                # Store span in request context
                req.span = span
            else:
                req.span = None
                
        except Exception as e:
            logger.debug(f"Error in process_request: {e}")
            req.start_time = time.time()
            req.span = None
    
    def process_response(self, req, resp, resource, req_succeeded):
        """Process response - complete span and record metrics"""
        try:
            # Calculate duration
            duration = time.time() - getattr(req, 'start_time', time.time())
            
            # Decrement active requests
            self.telemetry.increment_active_requests(-1)
            
            # Record HTTP metrics
            self._record_http_metrics(req, resp, duration, req_succeeded)
            
            # Record geocoding-specific metrics
            self._record_geocoding_metrics(req, resp, resource, duration, req_succeeded)
            
            # Complete span
            self._complete_span(req, resp, req_succeeded)
            
        except Exception as e:
            logger.debug(f"Error in process_response: {e}")
    
    def process_resource(self, req, resp, resource, params):
        """Process resource - add resource-specific attributes"""
        try:
            if hasattr(req, 'span') and req.span:
                req.span.set_attribute("addok.resource", resource.__class__.__name__)
        except Exception as e:
            logger.debug(f"Error in process_resource: {e}")
    
    def _get_operation_name(self, req) -> str:
        """Extract operation name from request path"""
        path = req.path
        
        if path.startswith('/search'):
            return 'geocode_search'
        elif path.startswith('/reverse'):
            return 'geocode_reverse'
        elif path.startswith('/health'):
            return 'health_check'
        elif path.startswith('/metrics'):
            return 'metrics'
        else:
            return f"{req.method} {path}"
    
    def _get_client_ip(self, req) -> str:
        """Extract client IP from request"""
        # Check for forwarded headers first
        forwarded = req.get_header('X-Forwarded-For')
        if forwarded:
            return forwarded.split(',')[0].strip()
        
        real_ip = req.get_header('X-Real-IP')
        if real_ip:
            return real_ip
            
        return req.remote_addr or 'unknown'
    
    def _record_http_metrics(self, req, resp, duration: float, req_succeeded: bool):
        """Record HTTP request metrics"""
        try:
            status_code = resp.status[:3] if resp.status else '500'
            endpoint = self._get_operation_name(req)
            
            record_http_request(
                method=req.method,
                endpoint=endpoint,
                status_code=int(status_code),
                duration=duration
            )
            
        except Exception as e:
            logger.debug(f"Failed to record HTTP metrics: {e}")
    
    def _record_geocoding_metrics(self, req, resp, resource, duration: float, req_succeeded: bool):
        """Record geocoding-specific metrics"""
        try:
            if not resource:
                return
                
            resource_name = resource.__class__.__name__
            
            if resource_name == 'Search':
                query = req.get_param('q', '')
                results_count = self._estimate_results_count(resp)
                status = 'success' if req_succeeded and results_count > 0 else 'no_results' if req_succeeded else 'error'
                
                record_geocoding_operation('search', status, duration)
                
                # Record telemetry metrics
                self.telemetry.record_geocoding_request(
                    endpoint='search',
                    status=status,
                    duration=duration,
                    query_length=len(query),
                    results_count=results_count
                )
                
            elif resource_name == 'Reverse':
                results_count = self._estimate_results_count(resp)
                status = 'success' if req_succeeded and results_count > 0 else 'no_results' if req_succeeded else 'error'
                
                record_geocoding_operation('reverse', status, duration)
                
                # Record telemetry metrics
                self.telemetry.record_geocoding_request(
                    endpoint='reverse', 
                    status=status,
                    duration=duration,
                    results_count=results_count
                )
                
        except Exception as e:
            logger.debug(f"Failed to record geocoding metrics: {e}")
    
    def _estimate_results_count(self, resp) -> int:
        """Estimate number of results from response"""
        try:
            # This is a rough estimation since we don't have direct access to results
            if hasattr(resp, 'text') and resp.text and 'features' in resp.text:
                # Count occurrences of feature objects (rough estimation)
                import json
                try:
                    data = json.loads(resp.text)
                    if isinstance(data, dict) and 'features' in data:
                        return len(data['features'])
                except:
                    pass
            return 1 if resp.status and resp.status.startswith('200') else 0
        except:
            return 0
    
    def _complete_span(self, req, resp, req_succeeded: bool):
        """Complete the OpenTelemetry span"""
        try:
            span = getattr(req, 'span', None)
            if not span:
                return
                
            # Set response attributes
            status_code = int(resp.status[:3]) if resp.status else 500
            span.set_attribute(SpanAttributes.HTTP_STATUS_CODE, status_code)
            
            # Set span status
            if req_succeeded and 200 <= status_code < 400:
                span.set_status(Status(StatusCode.OK))
            else:
                span.set_status(Status(StatusCode.ERROR))
                
                # Record error
                error_type = f"HTTP_{status_code}"
                endpoint = self._get_operation_name(req)
                record_error(error_type)
                self.telemetry.record_error(error_type, endpoint)
            
            # End span
            span.end()
            
        except Exception as e:
            logger.debug(f"Error completing span: {e}")

class MetricsMiddleware:
    """Simplified metrics-only middleware for cases where OTEL tracing is disabled"""
    
    def __init__(self):
        self.telemetry = get_telemetry()
        
    def process_request(self, req, resp):
        """Start request timing"""
        req.start_time = time.time()
        self.telemetry.increment_active_requests(1)
    
    def process_response(self, req, resp, resource, req_succeeded):
        """Record metrics without tracing"""
        try:
            duration = time.time() - getattr(req, 'start_time', time.time())
            self.telemetry.increment_active_requests(-1)
            
            # Record basic HTTP metrics
            status_code = int(resp.status[:3]) if resp.status else 500
            endpoint = req.path.split('?')[0] if req.path else 'unknown'
            
            record_http_request(req.method, endpoint, status_code, duration)
            
        except Exception as e:
            logger.debug(f"Error in metrics middleware: {e}")

def create_telemetry_middleware() -> object:
    """Factory function to create appropriate telemetry middleware"""
    try:
        telemetry = get_telemetry()
        
        # Use full OTEL middleware if tracing is initialized
        if telemetry.tracer:
            logger.info("Creating full OpenTelemetry middleware")
            return OpenTelemetryMiddleware()
        else:
            logger.info("Creating metrics-only middleware")
            return MetricsMiddleware()
            
    except Exception as e:
        logger.warning(f"Failed to create telemetry middleware: {e}")
        return MetricsMiddleware()  # Fallback to metrics only