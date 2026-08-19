"""Task 4: Implement analyze_journal_entry using any OpenAI-compatible API.

This project mandates the OpenAI Python SDK, which works with:
  - GitHub Models (default, free, no credit card required)
  - OpenAI proper
  - Azure OpenAI
  - Groq, Together, OpenRouter, Fireworks, DeepInfra
  - Ollama, LM Studio, vLLM (local)
  - Anthropic via their OpenAI-compat endpoint

Set OPENAI_API_KEY, and optionally OPENAI_BASE_URL and OPENAI_MODEL
in your .env file. Settings are loaded by ``api.config.Settings``.
"""

import json
from typing import cast

from openai import AsyncOpenAI
from openai.types.chat import ChatCompletionMessageParam
from opentelemetry import trace

from api.config import get_settings

tracer = trace.get_tracer(__name__)


def _normalize_llm_json(content: str) -> dict:
    """Extract a JSON object from LLM content, tolerating code fences."""
    cleaned = content.strip()

    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:].lstrip()

    try:
        payload = json.loads(cleaned)
    except json.JSONDecodeError:
        start = cleaned.find("{")
        if start == -1:
            raise
        payload, _ = json.JSONDecoder().raw_decode(cleaned[start:])

    if not isinstance(payload, dict):
        raise ValueError("LLM response was not a JSON object")

    return payload


def _default_client() -> AsyncOpenAI:
    """Construct the real OpenAI client from application settings.

    Called lazily from ``analyze_journal_entry`` so tests can inject a
    ``MockAsyncOpenAI`` without ever triggering this code path.
    """
    settings = get_settings()
    return AsyncOpenAI(
        api_key=settings.openai_api_key,
        base_url=settings.openai_base_url,
    )


async def analyze_journal_entry(
    entry_id: str,
    entry_text: str,
    client: AsyncOpenAI | None = None,
) -> dict:
    """Analyze a journal entry using an OpenAI-compatible LLM.

    Args:
        entry_id: ID of the entry being analyzed (pass through to the result).
        entry_text: Combined work + struggle + intention text.
        client: OpenAI client. If None, a default one is constructed from
            application settings. Tests pass in a MockAsyncOpenAI here; production code
            in the router calls this with no ``client`` argument.

    Returns:
        A dict matching AnalysisResponse:
            {
                "entry_id":  str,
                "sentiment": str,   # "positive" | "negative" | "neutral"
                "summary":   str,
                "topics":    list[str],
            }
    """
    if client is None:
        client = _default_client()

    settings = get_settings()
    messages: list[ChatCompletionMessageParam] = [
        cast(
            ChatCompletionMessageParam,
            {
                "role": "system",
                "content": (
                    "You are a journal analyzer. Reply with valid JSON only containing "
                    "sentiment, summary, and topics fields."
                ),
            },
        ),
        cast(
            ChatCompletionMessageParam,
            {
                "role": "user",
                "content": (
                    f"Analyze this journal entry and respond with JSON.\n\nEntry text:\n{entry_text}"
                ),
            },
        ),
    ]

    # Create a child span so the trace shows how long the external LLM call took.
    with tracer.start_as_current_span("llm.analyze_entry"):
        response = await client.chat.completions.create(
            model=settings.openai_model,
            messages=messages,
            response_format={"type": "json_object"},
        )

    content = response.choices[0].message.content
    if content is None:
        raise ValueError("LLM returned no content")

    payload = _normalize_llm_json(content)

    return {
        "entry_id": entry_id,
        "sentiment": payload["sentiment"],
        "summary": payload["summary"],
        "topics": payload["topics"],
    }
