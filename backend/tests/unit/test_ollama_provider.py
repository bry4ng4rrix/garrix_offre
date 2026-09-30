import json

import httpx
import pytest

from app.modules.ai.base import AIProviderError
from app.modules.ai.providers.ollama_provider import OllamaProvider


def provider_answering(handler) -> OllamaProvider:  # type: ignore[no-untyped-def]
    return OllamaProvider(
        "http://ollama:11434/", "qwen3:4b", transport=httpx.MockTransport(handler)
    )


def chat_reply(content: str, done_reason: str = "stop") -> httpx.Response:
    return httpx.Response(
        200,
        json={"model": "qwen3:4b", "message": {"role": "assistant", "content": content},
              "done_reason": done_reason, "prompt_eval_count": 12, "eval_count": 30},
    )  # fmt: skip


def test_json_uses_structured_output_without_thinking() -> None:
    seen: dict = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen.update(json.loads(request.content), path=request.url.path)
        return chat_reply('{"subject": "Candidature", "content": "Bonjour"}')

    schema = {"type": "object", "properties": {"subject": {"type": "string"}}}
    data = provider_answering(handler).complete_json("Système", "Offre", schema, effort="medium")

    assert data == {"subject": "Candidature", "content": "Bonjour"}
    assert seen["path"] == "/api/chat"
    assert seen["format"] == schema
    assert seen["think"] is False
    assert seen["stream"] is False
    assert seen["messages"][0] == {"role": "system", "content": "Système"}


def test_text_strips_think_block() -> None:
    provider = provider_answering(
        lambda _: chat_reply("<think>brouillon</think>\n Madame, Monsieur")
    )
    assert provider.complete_text("s", "p") == "Madame, Monsieur"


@pytest.mark.parametrize(
    ("response", "code"),
    [
        (chat_reply("tronqué", done_reason="length"), "AI_TRUNCATED"),
        (chat_reply("   "), "AI_EMPTY_RESPONSE"),
        (httpx.Response(404, json={"error": "model 'x' not found"}), "AI_PROVIDER_ERROR"),
    ],
)
def test_errors_raise_provider_error(response: httpx.Response, code: str) -> None:
    with pytest.raises(AIProviderError) as error:
        provider_answering(lambda _: response).complete_text("s", "p")
    assert error.value.code == code


def test_unreachable_server() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("refused", request=request)

    with pytest.raises(AIProviderError) as error:
        provider_answering(handler).complete_text("s", "p")
    assert error.value.code == "AI_UNREACHABLE"


def test_invalid_json() -> None:
    with pytest.raises(AIProviderError) as error:
        provider_answering(lambda _: chat_reply("pas du JSON")).complete_json("s", "p", {})
    assert error.value.code == "AI_INVALID_RESPONSE"


def test_long_job_description_is_cut() -> None:
    from app.modules.ai.prompts import MAX_DESCRIPTION_CHARS, job_block

    block = job_block("Dev", None, "mot " * 5000)
    assert len(block) < MAX_DESCRIPTION_CHARS + 200
    assert block.rstrip().endswith("[…]\n</job_posting>".strip())
    assert "(pas de description)" in job_block("Dev", None, None)
