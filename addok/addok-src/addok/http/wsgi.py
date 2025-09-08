import falcon

from addok.config import config, hooks

from .base import CorsMiddleware

config.load()
middlewares = [CorsMiddleware()]
hooks.register_http_middleware(middlewares)
# The name `application` is expected by wsgi by default.
application = api = falcon.App(middleware=middlewares)
# Do not let Falcon split query string on commas.
application.req_options.auto_parse_qs_csv = False
application.req_options.strip_url_path_trailing_slash = True

# Configure multipart limits for large CSV processing
# Set to 50MB to handle large CSV chunks (7000+ rows)
multipart_options = falcon.media.MultipartParseOptions(
    max_body_part_buffer_size=50 * 1024 * 1024,  # 50MB per part
    max_body_part_count=100,  # Allow up to 100 parts  
    max_body_part_headers=10  # Max 10 headers per part
)
application.req_options.media_handlers[falcon.MEDIA_MULTIPART] = falcon.media.MultipartFormHandler(
    parse_options=multipart_options
)

hooks.register_http_endpoint(api)


def simple(args):
    from wsgiref.simple_server import make_server

    httpd = make_server(args.host, int(args.port), application)
    print("Serving HTTP on {}:{}…".format(args.host, args.port))
    try:
        httpd.serve_forever()
    except (KeyboardInterrupt, EOFError):
        print("Bye!")
