import time
from typing import Any

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from starlette.websockets import WebSocketDisconnect

from app.core.config import get_settings
from app.core.redis import get_redis
from app.modules.integrations.telegram.service import TelegramService
from app.modules.notifications.dispatcher import NotificationDispatcher
from app.modules.notifications.service import NotificationService
from app.modules.realtime.events import EVENTS_CHANNEL
from app.modules.users.repository import UserRepository
from app.shared.enums import NotificationType
from tests.factories import API, PASSWORD


def _user_id(db: Session, email: str) -> Any:
    user = UserRepository(db).get_by_email(email)
    assert user is not None
    return user.id


def test_notifications_list_read_and_delete(
    client: TestClient, user_headers: dict[str, str], db: Session
) -> None:
    service = NotificationService(db)
    user_id = _user_id(db, "user@example.com")
    first = service.notify(
        user_id, NotificationType.SYSTEM, "Bienvenue", "Premier message", send_external=False
    )
    service.notify(
        user_id, NotificationType.NEW_JOB, "Nouvelle offre", "Offre", send_external=False
    )

    assert client.get(f"{API}/notifications/unread-count", headers=user_headers).json()["data"] == {
        "unread": 2
    }
    listed = client.get(f"{API}/notifications?type=system", headers=user_headers).json()["data"]
    assert listed["pagination"]["total"] == 1

    read = client.patch(f"{API}/notifications/{first.id}/read", headers=user_headers).json()["data"]
    assert read["is_read"] is True and read["read_at"]
    assert client.patch(f"{API}/notifications/read-all", headers=user_headers).json()["data"] == {
        "updated": 1
    }
    assert (
        client.get(f"{API}/notifications?is_read=false", headers=user_headers).json()["data"][
            "pagination"
        ]["total"]
        == 0
    )
    assert client.delete(f"{API}/notifications/{first.id}", headers=user_headers).status_code == 204


def test_notifications_are_private(
    client: TestClient, user_headers: dict[str, str], admin_headers: dict[str, str], db: Session
) -> None:
    notification = NotificationService(db).notify(
        _user_id(db, "user@example.com"), NotificationType.SYSTEM, "Privé", "x", send_external=False
    )
    assert (
        client.patch(
            f"{API}/notifications/{notification.id}/read", headers=admin_headers
        ).status_code
        == 404
    )


def test_notification_settings(client: TestClient, user_headers: dict[str, str]) -> None:
    settings = client.get(f"{API}/notifications/settings", headers=user_headers).json()["data"]
    assert settings["telegram_configured"] is False
    assert "high_match" in settings["external_types"]
    updated = client.put(
        f"{API}/notifications/settings", headers=user_headers,
        json={"email_enabled": True, "email_to": "me@example.com", "external_types": ["recruiter_response", "high_match"]},
    ).json()["data"]  # fmt: skip
    assert updated["email_enabled"] is True
    assert updated["external_types"] == ["high_match", "recruiter_response"]
    bad = client.put(
        f"{API}/notifications/settings",
        headers=user_headers,
        json={"telegram_chat_id": "not a chat"},
    )
    assert bad.status_code == 422


class FakeTelegram(TelegramService):
    def __init__(self) -> None:
        self.sent: list[tuple[str, str]] = []

    @property
    def is_configured(self) -> bool:
        return True

    def send_message(self, chat_id: str, text: str) -> None:
        self.sent.append((chat_id, text))


def test_dispatcher_sends_to_telegram(
    client: TestClient,
    admin_headers: dict[str, str],
    user_headers: dict[str, str],
    db: Session,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(get_settings(), "TELEGRAM_CHAT_ID", "12345")
    admin_id = _user_id(db, "admin@example.com")
    user_id = _user_id(db, "user@example.com")
    service = NotificationService(db)
    admin_notification = service.notify(
        admin_id, NotificationType.HIGH_MATCH, "Offre compatible", "Python Developer",
        {"job_id": "1", "job_title": "Python Developer", "score": 91, "url": "https://example.com/j"},
        send_external=False,
    )  # fmt: skip
    user_notification = service.notify(
        user_id, NotificationType.HIGH_MATCH, "Offre", "x", {"score": 80}, send_external=False
    )

    telegram = FakeTelegram()
    channels = NotificationDispatcher(db, telegram=telegram).deliver(admin_notification.id)
    assert channels == ["telegram"]
    assert telegram.sent[0][0] == "12345"
    assert "91/100" in telegram.sent[0][1]
    # Le chat Telegram du .env appartient au propriétaire : jamais utilisé pour un autre compte.
    assert NotificationDispatcher(db, telegram=telegram).deliver(user_notification.id) == []
    assert len(telegram.sent) == 1


def test_websocket_requires_a_valid_token(client: TestClient) -> None:
    with (
        pytest.raises(WebSocketDisconnect) as missing,
        client.websocket_connect(f"{API}/ws") as websocket,
    ):
        websocket.receive_json()
    assert missing.value.code == 1008
    with (
        pytest.raises(WebSocketDisconnect),
        client.websocket_connect(f"{API}/ws?token=bad") as websocket,
    ):
        websocket.receive_json()


def _wait_for_listener() -> None:
    for _ in range(50):
        if get_redis().pubsub_numsub(EVENTS_CHANNEL)[0][1] > 0:
            return
        time.sleep(0.05)
    raise AssertionError("Realtime listener not subscribed")


def test_websocket_receives_notifications(client: TestClient, db: Session) -> None:
    client.post(f"{API}/auth/register", json={"email": "ws@example.com", "password": PASSWORD})
    token = client.post(
        f"{API}/auth/login", json={"email": "ws@example.com", "password": PASSWORD}
    ).json()["data"]["access_token"]
    with client.websocket_connect(f"{API}/ws?token={token}") as websocket:
        connected = websocket.receive_json()
        assert connected["type"] == "connected"
        assert connected["data"]["unread_notifications"] == 0
        websocket.send_text("ping")
        assert websocket.receive_json() == {"type": "pong"}

        _wait_for_listener()
        NotificationService(db).notify(
            _user_id(db, "ws@example.com"),
            NotificationType.SYSTEM,
            "Temps réel",
            "Bonjour",
            send_external=False,
        )
        event = websocket.receive_json()
        assert event["type"] == "notification"
        assert event["data"]["title"] == "Temps réel"
