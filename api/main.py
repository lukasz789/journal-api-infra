import logging

from fastapi import FastAPI

from api.routers.journal_router import router as journal_router

logger = logging.getLogger(__name__)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)

logger.info("Journal API starting up")

app = FastAPI(
    title="Journal API",
    description="A simple journal API for tracking daily work, struggles, and intentions",
)
app.include_router(journal_router)


@app.get("/health")
async def health() -> dict[str, str]:
    """Return a simple response used by Kubernetes health probes."""
    return {"status": "healthy"}
