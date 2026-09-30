from fastapi.testclient import TestClient

from app.core.config import get_settings
from tests.factories import API, PASSWORD, register_and_login


def test_root_page(client: TestClient) -> None:
    body = client.get("/").json()
    assert body["docs"] == "/docs"
    assert body["name"] == get_settings().APP_NAME


def test_health_and_ready(client: TestClient) -> None:
    health = client.get("/health").json()
    assert health["status"] == "ok"
    assert health["checks"] == {"api": "ok", "postgres": "ok", "redis": "ok"}
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.headers["X-Request-ID"]
    # En-têtes de sécurité (l'API est exposée directement, sans reverse proxy).
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert response.headers["Referrer-Policy"] == "no-referrer"


def test_register_first_user_becomes_admin(client: TestClient) -> None:
    first = client.post(
        f"{API}/auth/register", json={"email": "Admin@Example.com", "password": PASSWORD}
    )
    second = client.post(
        f"{API}/auth/register", json={"email": "user@example.com", "password": PASSWORD}
    )
    assert first.status_code == 201
    assert first.json()["data"]["email"] == "admin@example.com"
    assert first.json()["data"]["is_superuser"] is True
    assert second.json()["data"]["is_superuser"] is False
    assert "hashed_password" not in first.json()["data"]


def test_duplicate_email_is_rejected(client: TestClient) -> None:
    client.post(f"{API}/auth/register", json={"email": "a@example.com", "password": PASSWORD})
    response = client.post(
        f"{API}/auth/register", json={"email": "A@example.com", "password": PASSWORD}
    )
    assert response.status_code == 409
    assert response.json() == {
        "success": False,
        "error": {"code": "EMAIL_ALREADY_USED", "message": "A user with this email already exists"},
    }


def test_validation_errors_do_not_echo_input(client: TestClient) -> None:
    response = client.post(
        f"{API}/auth/register", json={"email": "a@example.com", "password": "short"}
    )
    assert response.status_code == 422
    body = response.json()
    assert body["error"]["code"] == "VALIDATION_ERROR"
    assert "short" not in response.text


def test_login_and_me(client: TestClient) -> None:
    headers = register_and_login(client, "jane@example.com")
    me = client.get(f"{API}/auth/me", headers=headers)
    assert me.status_code == 200
    assert me.json()["data"]["email"] == "jane@example.com"
    assert me.json()["data"]["last_login_at"] is not None


def test_login_with_wrong_password(client: TestClient) -> None:
    register_and_login(client, "jane@example.com")
    response = client.post(
        f"{API}/auth/login", json={"email": "jane@example.com", "password": "Wrong123!"}
    )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "INVALID_CREDENTIALS"
    unknown = client.post(
        f"{API}/auth/login", json={"email": "nobody@example.com", "password": "Wrong123!"}
    )
    assert unknown.json()["error"]["code"] == "INVALID_CREDENTIALS"


def test_protected_endpoints_require_a_token(client: TestClient) -> None:
    assert client.get(f"{API}/auth/me").status_code == 401
    bad = client.get(f"{API}/auth/me", headers={"Authorization": "Bearer not-a-jwt"})
    assert bad.status_code == 401
    assert bad.json()["error"]["code"] == "INVALID_TOKEN"


def test_refresh_rotation_and_reuse_detection(client: TestClient) -> None:
    client.post(f"{API}/auth/register", json={"email": "jane@example.com", "password": PASSWORD})
    tokens = client.post(
        f"{API}/auth/login", json={"email": "jane@example.com", "password": PASSWORD}
    ).json()["data"]
    refreshed = client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert refreshed.status_code == 200
    new_tokens = refreshed.json()["data"]
    assert new_tokens["refresh_token"] != tokens["refresh_token"]

    reused = client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert reused.status_code == 401
    # La réutilisation révoque toutes les sessions, y compris le nouveau refresh token.
    after = client.post(f"{API}/auth/refresh", json={"refresh_token": new_tokens["refresh_token"]})
    assert after.status_code == 401


def test_logout_revokes_access_and_refresh_tokens(client: TestClient) -> None:
    client.post(f"{API}/auth/register", json={"email": "jane@example.com", "password": PASSWORD})
    tokens = client.post(
        f"{API}/auth/login", json={"email": "jane@example.com", "password": PASSWORD}
    ).json()["data"]
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    response = client.post(
        f"{API}/auth/logout", headers=headers, json={"refresh_token": tokens["refresh_token"]}
    )
    assert response.status_code == 200
    assert client.get(f"{API}/auth/me", headers=headers).json()["error"]["code"] == "TOKEN_REVOKED"
    assert (
        client.post(
            f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
        ).status_code
        == 401
    )


def test_registration_can_be_disabled(client: TestClient, monkeypatch) -> None:  # type: ignore[no-untyped-def]
    register_and_login(client, "owner@example.com")
    monkeypatch.setattr(get_settings(), "ALLOW_REGISTRATION", False)
    response = client.post(
        f"{API}/auth/register", json={"email": "other@example.com", "password": PASSWORD}
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "REGISTRATION_DISABLED"


def test_change_password(client: TestClient) -> None:
    headers = register_and_login(client, "jane@example.com")
    wrong = client.put(
        f"{API}/users/me/password", headers=headers,
        json={"current_password": "Wrong123!", "new_password": "NewPassw0rd!"},
    )  # fmt: skip
    assert wrong.json()["error"]["code"] == "INVALID_PASSWORD"
    ok = client.put(
        f"{API}/users/me/password", headers=headers,
        json={"current_password": PASSWORD, "new_password": "NewPassw0rd!"},
    )  # fmt: skip
    assert ok.status_code == 200
    login = client.post(
        f"{API}/auth/login", json={"email": "jane@example.com", "password": "NewPassw0rd!"}
    )
    assert login.status_code == 200


def test_admin_endpoints_are_restricted(
    client: TestClient, admin_headers: dict[str, str], user_headers: dict[str, str]
) -> None:
    assert client.get(f"{API}/users", headers=user_headers).status_code == 403
    users = client.get(f"{API}/users", headers=admin_headers).json()["data"]
    assert users["pagination"]["total"] == 2
    admin_id = next(u["id"] for u in users["items"] if u["is_superuser"])
    user_id = next(u["id"] for u in users["items"] if not u["is_superuser"])
    assert (
        client.patch(
            f"{API}/users/{admin_id}", headers=admin_headers, json={"is_active": False}
        ).status_code
        == 422
    )
    assert (
        client.patch(
            f"{API}/users/{user_id}", headers=admin_headers, json={"is_active": False}
        ).status_code
        == 200
    )
    assert client.get(f"{API}/auth/me", headers=user_headers).status_code == 401


def test_admin_can_create_accounts_when_registration_is_closed(
    client: TestClient, admin_headers: dict[str, str], user_headers: dict[str, str], monkeypatch
) -> None:  # type: ignore[no-untyped-def]
    monkeypatch.setattr(get_settings(), "ALLOW_REGISTRATION", False)
    payload = {"email": "Colleague@Example.com", "password": PASSWORD}
    assert client.post(f"{API}/users", headers=user_headers, json=payload).status_code == 403
    assert client.post(f"{API}/users", json=payload).status_code == 401
    weak = client.post(f"{API}/users", headers=admin_headers, json={**payload, "password": "weak"})
    assert weak.status_code == 422

    created = client.post(f"{API}/users", headers=admin_headers, json=payload)
    assert created.status_code == 201
    assert created.json()["data"]["email"] == "colleague@example.com"
    assert created.json()["data"]["is_superuser"] is False
    duplicate = client.post(f"{API}/users", headers=admin_headers, json=payload)
    assert duplicate.json()["error"]["code"] == "EMAIL_ALREADY_USED"

    second_admin = client.post(
        f"{API}/users", headers=admin_headers,
        json={"email": "ops@example.com", "password": PASSWORD, "is_superuser": True},
    )  # fmt: skip
    assert second_admin.json()["data"]["is_superuser"] is True

    login = client.post(
        f"{API}/auth/login", json={"email": "colleague@example.com", "password": PASSWORD}
    )
    assert login.status_code == 200
    logs = client.get(f"{API}/audit-logs?action=user.created", headers=admin_headers).json()
    assert logs["data"]["pagination"]["total"] == 2


def test_audit_log_records_logins(client: TestClient, admin_headers: dict[str, str]) -> None:
    logs = client.get(f"{API}/audit-logs?action=auth.", headers=admin_headers).json()["data"][
        "items"
    ]
    assert {"auth.register", "auth.login"} <= {log["action"] for log in logs}


def test_create_admin_script(client: TestClient, monkeypatch) -> None:  # type: ignore[no-untyped-def]
    import io
    import sys

    from scripts import create_admin

    monkeypatch.setattr(
        sys, "argv", ["create_admin", "--email", "Owner@Example.com", "--password-stdin"]
    )
    monkeypatch.setattr(sys, "stdin", io.StringIO("Sup3rPassw0rd!\n"))
    assert create_admin.main() == 0
    login = client.post(
        f"{API}/auth/login", json={"email": "owner@example.com", "password": "Sup3rPassw0rd!"}
    )
    headers = {"Authorization": f"Bearer {login.json()['data']['access_token']}"}
    assert client.get(f"{API}/auth/me", headers=headers).json()["data"]["is_superuser"] is True

    monkeypatch.setattr(sys, "stdin", io.StringIO("weak\n"))
    assert create_admin.main() == 1


def test_create_user_script(client: TestClient, monkeypatch) -> None:  # type: ignore[no-untyped-def]
    import io
    import sys

    from scripts import create_user

    def run(password: str, *args: str) -> int:
        monkeypatch.setattr(sys, "stdin", io.StringIO(f"{password}\n"))
        return create_user.main(["--email", "member@example.com", "--password-stdin", *args])

    def me(password: str) -> dict:  # type: ignore[type-arg]
        login = client.post(
            f"{API}/auth/login", json={"email": "member@example.com", "password": password}
        )
        headers = {"Authorization": f"Bearer {login.json()['data']['access_token']}"}
        return client.get(f"{API}/auth/me", headers=headers).json()["data"]  # type: ignore[no-any-return]

    assert run("Sup3rPassw0rd!") == 0
    assert me("Sup3rPassw0rd!")["is_superuser"] is False
    # Compte existant : mot de passe remplacé, promotion avec --admin.
    assert run("N3wPassw0rd!", "--admin") == 0
    assert me("N3wPassw0rd!")["is_superuser"] is True
    # Sans --admin, un administrateur n'est jamais rétrogradé.
    assert run("N3wPassw0rd!") == 0
    assert me("N3wPassw0rd!")["is_superuser"] is True
