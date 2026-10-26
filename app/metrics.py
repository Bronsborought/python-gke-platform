import time

from fastapi import Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Histogram,
    generate_latest,
)

REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "path", "status_code"],
)

DURATION = Histogram(
    "http_request_duration_seconds",
    "HTTP request processing duration in seconds",
    ["method", "path"],
)


def setup_metrics(app):
    @app.middleware("http")
    async def observe_request(request: Request, call_next):
        if request.url.path == "/metrics":
            return await call_next(request)

        started = time.perf_counter()
        status_code = 500

        try:
            response = await call_next(request)
            status_code = response.status_code
            return response
        finally:
            elapsed = time.perf_counter() - started
            route = request.scope.get("route")
            path = getattr(route, "path", "unmatched")

            REQUESTS.labels(
                method=request.method,
                path=path,
                status_code=str(status_code),
            ).inc()

            DURATION.labels(
                method=request.method,
                path=path,
            ).observe(elapsed)

    @app.get("/metrics", include_in_schema=False)
    def metrics():
        return Response(
            content=generate_latest(),
            headers={"Content-Type": CONTENT_TYPE_LATEST},
        )
