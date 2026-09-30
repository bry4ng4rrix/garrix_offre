import logging
import uuid

import pytest

from app.core.exceptions import AuthenticationError
from app.core.logging import SensitiveDataFilter, redact_text
from app.core.security import (
    create_access_token,
    decode_access_token,
    generate_refresh_token,
    hash_password,
    hash_token,
    secrets_are_equal,
    verify_password,
)


def test_password_hashing() -> None:
    hashed = hash_password("Passw0rd!")
    assert hashed != "Passw0rd!"
    assert hashed.startswith("$argon2")
    assert verify_password("Passw0rd!", hashed)
    assert not verify_password("wrong", hashed)
    assert not verify_password("Passw0rd!", "not-a-hash")


def test_access_token_roundtrip() -> None:
    user_id = uuid.uuid4()
    token = create_access_token(user_id)
    payload = decode_access_token(token.token)
    assert payload["sub"] == str(user_id)
    assert payload["jti"] == token.jti


def test_tampered_token_is_rejected() -> None:
    token = create_access_token(uuid.uuid4()).token
    with pytest.raises(AuthenticationError):
        decode_access_token(token[:-2] + "xx")


def test_refresh_tokens_are_random_and_hashed() -> None:
    first, second = generate_refresh_token(), generate_refresh_token()
    assert first != second
    assert len(hash_token(first)) == 64
    assert hash_token(first) != first


def test_constant_time_comparison() -> None:
    assert secrets_are_equal("secret", "secret")
    assert not secrets_are_equal("other", "secret")
    assert not secrets_are_equal(None, "secret")


def test_redact_text_masks_tokens() -> None:
    assert "abc.def" not in redact_text("Authorization: Bearer abc.def")
    assert "123456:ABC" not in redact_text("https://api.telegram.org/bot123456:ABC-xyz/sendMessage")
    assert "secretpwd" not in redact_text("postgresql://user:secretpwd@db:5432/app")
    jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl"
    assert jwt not in redact_text(f"token={jwt}")


def test_log_filter_masks_sensitive_extra_fields() -> None:
    record = logging.LogRecord("app", logging.INFO, __file__, 1, "login %s", ("ok",), None)
    record.password = "Passw0rd!"  # type: ignore[attr-defined]
    record.details = {"api_key": "sk-123", "count": 2}  # type: ignore[attr-defined]
    SensitiveDataFilter().filter(record)
    assert record.password == "***"  # type: ignore[attr-defined]
    assert record.details == {"api_key": "***", "count": 2}  # type: ignore[attr-defined]
