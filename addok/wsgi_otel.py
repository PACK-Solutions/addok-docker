"""
Enhanced WSGI application for Addok with OpenTelemetry integration.
This file replaces the default wsgi.py with telemetry capabilities.
"""

import os
import sys
import logging
from pathlib import Path

# Add monitoring modules to path  
sys.path.insert(0, '/app/monitoring')

import falcon
from addok.config import config, hooks
from addok.http.base import CorsMiddleware, register_http_endpoint

# Import monitoring components
from monitoring.telemetry import initialize_telemetry
from monitoring.falcon_middleware import create_telemetry_middleware, add_metrics_routes

logger = logging.getLogger(__name__)

def create_application():
    """Create Falcon application with OpenTelemetry integration"""
    try:
        # Load Addok configuration
        config.load()
        
        # Initialize OpenTelemetry
        telemetry_initialized = initialize_telemetry()
        if telemetry_initialized:
            logger.info("OpenTelemetry initialized successfully")
        else:
            logger.warning("OpenTelemetry initialization failed, continuing without telemetry")
        
        # Create middleware list
        middlewares = [CorsMiddleware()]
        
        # Add telemetry middleware
        try:
            telemetry_middleware = create_telemetry_middleware()
            middlewares.append(telemetry_middleware)
            logger.info("Telemetry middleware added to Falcon application")
        except Exception as e:
            logger.warning(f"Failed to add telemetry middleware: {e}")
        
        # Register additional middleware from hooks
        hooks.register_http_middleware(middlewares)
        
        # Create Falcon application
        app = falcon.App(middleware=middlewares)
        
        # Configure request options
        app.req_options.auto_parse_qs_csv = False
        app.req_options.strip_url_path_trailing_slash = True
        
        # Configure multipart limits for large CSV processing
        # Set to 50MB to handle large CSV chunks (7000+ rows)
        multipart_options = falcon.media.MultipartParseOptions(
            max_body_part_buffer_size=50 * 1024 * 1024,  # 50MB per part
            max_body_part_count=100,  # Allow up to 100 parts  
            max_body_part_headers=10  # Max 10 headers per part
        )
        app.req_options.media_handlers[falcon.MEDIA_MULTIPART] = falcon.media.MultipartFormHandler(
            parse_options=multipart_options
        )
        
        # Register standard Addok endpoints
        register_http_endpoint(app)
        
        # Add metrics endpoints using Falcon resources
        add_metrics_routes(app)
        
        # Register additional endpoints from hooks
        hooks.register_http_endpoint(app)
        
        logger.info("Addok WSGI application created successfully with OpenTelemetry")
        return app
        
    except Exception as e:
        logger.error(f"Failed to create WSGI application: {e}")
        raise


# Create the WSGI application
try:
    application = create_application()
    api = application  # Alias for compatibility
except Exception as e:
    logger.error(f"Critical error creating WSGI application: {e}")
    
    # Create minimal fallback application
    from addok.http.wsgi import application
    logger.warning("Using fallback WSGI application without telemetry")

def simple(args):
    """Simple development server"""
    from wsgiref.simple_server import make_server
    
    httpd = make_server(args.host, int(args.port), application)
    print("Serving HTTP with OpenTelemetry on {}:{}…".format(args.host, args.port))
    try:
        httpd.serve_forever()
    except (KeyboardInterrupt, EOFError):
        print("Bye!")

# Configure logging for startup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)