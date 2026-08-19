"""OpenTelemetry configuration shared by the Journal API."""

import os

from fastapi import FastAPI
from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.prometheus import PrometheusMetricReader
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.resources import SERVICE_NAME, Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from prometheus_client import start_http_server

_initialized = False


def setup_telemetry(app: FastAPI) -> None:
    """Configure OpenTelemetry and connect it to the FastAPI application."""
    global _initialized

    if not _initialized:
        resource = Resource.create({SERVICE_NAME: "journal-api"})

        # Send traces only when a Collector endpoint has been configured.
        tracer_provider = TracerProvider(resource=resource)
        if traces_endpoint := os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"):
            tracer_provider.add_span_processor(
                BatchSpanProcessor(OTLPSpanExporter(endpoint=traces_endpoint))
            )
        trace.set_tracer_provider(tracer_provider)

        # Expose metrics on a separate internal port for Prometheus.
        metrics.set_meter_provider(
            MeterProvider(
                resource=resource,
                metric_readers=[PrometheusMetricReader()],
            )
        )
        start_http_server(port=9464, addr="0.0.0.0")  # noqa: S104

        # Add trace IDs to stdout logs without creating a second log exporter.
        LoggingInstrumentor().instrument(
            inject_trace_context=True,
            enable_log_auto_instrumentation=False,
        )

        # Tests reload api.main, so the global providers and port must be created once.
        _initialized = True

    # Create traces and standard HTTP metrics for requests, except health probes.
    FastAPIInstrumentor.instrument_app(
        app,
        excluded_urls="/health",
    )
