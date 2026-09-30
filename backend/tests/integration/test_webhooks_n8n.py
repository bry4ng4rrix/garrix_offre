from fastapi.testclient import TestClient

from tests.factories import API, create_job, job_payload, setup_candidate

WEBHOOKS = f"{API}/webhooks/n8n"


def test_webhooks_require_the_secret(client: TestClient) -> None:
    assert client.get(f"{WEBHOOKS}/sources").status_code == 401
    wrong = client.get(f"{WEBHOOKS}/sources", headers={"X-N8N-Webhook-Secret": "wrong"})
    assert wrong.status_code == 401
    assert wrong.json()["error"]["code"] == "INVALID_WEBHOOK_SECRET"


def test_sources_endpoint_lists_collectable_sources(
    client: TestClient, n8n_headers: dict[str, str]
) -> None:
    sources = client.get(f"{WEBHOOKS}/sources", headers=n8n_headers).json()["data"]
    names = {source["name"] for source in sources}
    assert {"Remote OK", "We Work Remotely", "Codeur.com", "Freelancer.com"} <= names
    assert "France Travail" not in names  # désactivée tant que les identifiants ne sont pas fournis
    assert "LinkedIn" not in names  # alimentée par les alertes email, pas collectée
    assert all(source["fetch_mode"] == "backend" for source in sources)


def test_receive_jobs_batch_is_idempotent(
    client: TestClient, n8n_headers: dict[str, str], user_headers: dict[str, str]
) -> None:
    setup_candidate(client, user_headers)
    body = {
        "source_name": "We Work Remotely",
        "jobs": [
            job_payload(),
            job_payload(
                external_id="2", url="https://example.com/jobs/2", title="Autre offre Python Django"
            ),
        ],
    }
    headers = {**n8n_headers, "Idempotency-Key": "exec-42", "X-N8N-Workflow": "job-scraping"}
    first = client.post(f"{WEBHOOKS}/jobs", headers=headers, json=body)
    assert first.status_code == 200, first.text
    data = first.json()["data"]
    assert (data["received"], data["created"]) == (2, 2)
    assert data["notification_delivery"] == "backend"
    assert data["high_matches"]

    replay = client.post(f"{WEBHOOKS}/jobs", headers=headers, json=body)
    assert replay.headers["Idempotent-Replayed"] == "true"
    assert replay.json()["data"]["created"] == 2  # réponse enregistrée, rien de refait
    without_key = client.post(f"{WEBHOOKS}/jobs", headers=n8n_headers, json=body).json()["data"]
    assert (without_key["created"], without_key["duplicates"]) == (0, 2)
    assert (
        client.get(f"{API}/jobs?status=all", headers=user_headers).json()["data"]["pagination"][
            "total"
        ]
        == 2
    )


def test_single_job_and_unknown_source(client: TestClient, n8n_headers: dict[str, str]) -> None:
    created = client.post(f"{WEBHOOKS}/job", headers=n8n_headers, json=job_payload())
    assert created.json()["data"]["created"] == 1
    unknown = client.post(
        f"{WEBHOOKS}/job", headers=n8n_headers, json=job_payload(source_name="Nope")
    )
    assert unknown.status_code == 404
    assert unknown.json()["error"]["code"] == "SOURCE_NOT_FOUND"


def test_job_alert_email(
    client: TestClient, n8n_headers: dict[str, str], admin_headers: dict[str, str]
) -> None:
    html = (
        '<a href="https://www.linkedin.com/comm/jobs/view/111/?trackingId=x">Développeur Python</a>'
        '<a href="https://www.linkedin.com/comm/psettings/email-unsubscribe">Se désabonner</a>'
    )
    response = client.post(
        f"{WEBHOOKS}/job-alert-email",
        headers={**n8n_headers, "Idempotency-Key": "<alert-1@linkedin.com>"},
        json={
            "sender_email": "jobalerts-noreply@linkedin.com",
            "subject": "Offres Python",
            "html": html,
        },
    )
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    assert (data["source"], data["extracted"], data["created"]) == ("LinkedIn", 1, 1)
    job = client.get(f"{API}/jobs?source=LinkedIn&status=all", headers=admin_headers).json()[
        "data"
    ]["items"][0]
    assert job["title"] == "Développeur Python"
    assert job["status"]["state"] == "new"  # incomplète : titre + lien seulement
    assert job["source"]["url"] == "https://www.linkedin.com/comm/jobs/view/111"


def test_scraping_status_is_recorded(
    client: TestClient, n8n_headers: dict[str, str], admin_headers: dict[str, str]
) -> None:
    body = {
        "source_name": "We Work Remotely",
        "status": "failed",
        "execution_id": "exec-1",
        "error_message": "Timeout",
    }
    first = client.post(f"{WEBHOOKS}/scraping-status", headers=n8n_headers, json=body).json()[
        "data"
    ]
    second = client.post(f"{WEBHOOKS}/scraping-status", headers=n8n_headers, json=body).json()[
        "data"
    ]
    assert first["run_id"] == second["run_id"]  # même execution_id = même collecte
    runs = client.get(f"{API}/scraping/runs?status_filter=failed", headers=admin_headers).json()[
        "data"
    ]
    assert runs["items"][0]["trigger"] == "n8n"
    alerts = client.get(f"{API}/notifications?type=scraping_error", headers=admin_headers).json()[
        "data"
    ]
    assert alerts["pagination"]["total"] >= 1


def test_application_status_webhook_rules(
    client: TestClient, n8n_headers: dict[str, str], user_headers: dict[str, str]
) -> None:
    job = create_job(client, user_headers)
    application = client.post(
        f"{API}/applications",
        headers=user_headers,
        json={"job_id": job["id"], "status": "preparing"},
    ).json()["data"]
    client.patch(
        f"{API}/applications/{application['id']}/status",
        headers=user_headers,
        json={"status": "ready"},
    )

    # n8n ne peut jamais valider l'envoi à la place de l'utilisateur.
    submit = client.post(
        f"{WEBHOOKS}/application-status",
        headers=n8n_headers,
        json={"application_id": application["id"], "status": "submitted"},
    )
    assert submit.json()["error"]["code"] == "SUBMIT_REQUIRES_CONFIRMATION"
    client.post(
        f"{API}/applications/{application['id']}/submit",
        headers=user_headers,
        json={"confirm": True},
    )
    follow_up = client.post(
        f"{WEBHOOKS}/application-status",
        headers=n8n_headers,
        json={"application_id": application["id"], "status": "follow_up"},
    )
    assert follow_up.json()["data"]["status"] == "follow_up"
    again = client.post(
        f"{WEBHOOKS}/application-status",
        headers=n8n_headers,
        json={"application_id": application["id"], "status": "follow_up"},
    )
    assert again.status_code == 200  # idempotent
    history = client.get(
        f"{API}/applications/{application['id']}/history", headers=user_headers
    ).json()["data"]
    assert [entry["to_status"] for entry in history].count("follow_up") == 1
    assert history[-1]["actor_type"] == "n8n"


def test_follow_ups_due(client: TestClient, n8n_headers: dict[str, str], user_headers: dict[str, str], db) -> None:  # type: ignore[no-untyped-def]
    from datetime import timedelta

    from app.modules.applications.models import Application
    from app.shared.utils import utcnow

    job = create_job(client, user_headers)
    application = client.post(
        f"{API}/applications",
        headers=user_headers,
        json={"job_id": job["id"], "status": "preparing"},
    ).json()["data"]
    client.patch(
        f"{API}/applications/{application['id']}/status",
        headers=user_headers,
        json={"status": "ready"},
    )
    client.post(
        f"{API}/applications/{application['id']}/submit",
        headers=user_headers,
        json={"confirm": True},
    )
    assert (
        client.get(f"{WEBHOOKS}/applications/follow-ups-due", headers=n8n_headers).json()["data"]
        == []
    )
    stored = db.get(Application, application["id"])
    stored.follow_up_at = utcnow() - timedelta(days=1)
    db.commit()
    due = client.get(f"{WEBHOOKS}/applications/follow-ups-due", headers=n8n_headers).json()["data"]
    assert [item["application_id"] for item in due] == [application["id"]]


def test_recruiter_response_webhook(
    client: TestClient, n8n_headers: dict[str, str], user_headers: dict[str, str]
) -> None:
    job = create_job(client, user_headers)
    application = client.post(
        f"{API}/applications", headers=user_headers, json={"job_id": job["id"]}
    ).json()["data"]
    body = {
        "application_id": application["id"],
        "sender_email": "rh@exemple.example",
        "subject": "Votre candidature",
        "body": "Malheureusement, nous ne pouvons pas donner suite à votre candidature.",
        "message_id": "<resp-1@exemple>",
    }
    first = client.post(f"{WEBHOOKS}/recruiter-response", headers=n8n_headers, json=body).json()[
        "data"
    ]
    assert first["correlation_method"] == "application_id"
    assert first["response_type"] == "rejection"
    assert first["duplicate"] is False
    second = client.post(f"{WEBHOOKS}/recruiter-response", headers=n8n_headers, json=body).json()[
        "data"
    ]
    assert second["duplicate"] is True and second["response_id"] == first["response_id"]
    notifications = client.get(
        f"{API}/notifications?type=recruiter_response", headers=user_headers
    ).json()["data"]
    assert notifications["pagination"]["total"] == 1


def test_matching_maintenance_and_monitoring_webhooks(
    client: TestClient, n8n_headers: dict[str, str], admin_headers: dict[str, str]
) -> None:
    create_job(client, admin_headers)
    assert client.post(f"{WEBHOOKS}/matching/recalculate", headers=n8n_headers).status_code == 202
    assert client.post(f"{WEBHOOKS}/maintenance/expire-jobs", headers=n8n_headers).json()[
        "data"
    ] == {"expired": 0, "archived": 0, "stale_runs_failed": 0}
    summary = client.get(f"{WEBHOOKS}/monitoring/summary", headers=n8n_headers).json()["data"]
    assert summary["new_jobs_24h"] == 1
    alert = client.post(
        f"{WEBHOOKS}/monitoring-alert",
        headers=n8n_headers,
        json={"title": "API lente", "message": "Latence élevée"},
    )
    assert alert.json()["data"] == {"notified": 1}


def test_monitoring_endpoints(
    client: TestClient,
    admin_headers: dict[str, str],
    user_headers: dict[str, str],
    n8n_headers: dict[str, str],
) -> None:
    setup_candidate(client, user_headers)
    client.post(
        f"{WEBHOOKS}/jobs",
        headers={**n8n_headers, "X-N8N-Workflow": "job-scraping"},
        json={"jobs": [job_payload()]},
    )
    overview = client.get(f"{API}/monitoring/overview", headers=user_headers).json()["data"]
    assert overview["new_jobs_today"] == 1
    assert overview["jobs_found_today"] == 1
    assert overview["matching_jobs_total"] == 1
    assert overview["services"] == {"api": "ok", "postgres": "ok", "redis": "ok"}
    assert overview["last_n8n_executions"][0]["workflow"] == "job-scraping"

    assert client.get(f"{API}/monitoring/system", headers=user_headers).status_code == 403
    system = client.get(f"{API}/monitoring/system", headers=admin_headers).json()["data"]
    assert system["services"]["postgres"]["status"] == "ok"
    assert system["services"]["worker"]["status"] == "eager"
    assert system["users"] == 2
    scraping = client.get(f"{API}/monitoring/scraping", headers=admin_headers).json()["data"]
    assert any(source["name"] == "Remote OK" for source in scraping["sources"])
    applications = client.get(f"{API}/monitoring/applications", headers=user_headers).json()["data"]
    assert applications == {**applications, "total": 0, "response_rate": 0.0}


def test_source_categories_and_freelance_missions(
    client: TestClient, n8n_headers: dict[str, str], user_headers: dict[str, str]
) -> None:
    def names(category: str) -> set[str]:
        items = client.get(
            f"{API}/sources?category={category}&page_size=100", headers=user_headers
        ).json()["data"]["items"]
        return {item["name"] for item in items}

    assert {"LinkedIn", "Madajob", "Job2Mada", "Remote OK", "France Travail", "Jobgether"} <= names(
        "jobs"
    )
    assert {"Malt", "Upwork", "Codeur.com", "Work IT Mada", "Workana", "Freelancer.com"} <= names(
        "clients"
    )
    assert {"Adzuna", "Findwork.dev", "The Muse", "JobDataLake"} <= names("services")

    mission = job_payload(
        title="Création d'une API Django",
        url="https://www.codeur.com/projects/1",
        contract=None,
        company=None,
    )
    client.post(
        f"{WEBHOOKS}/jobs",
        headers=n8n_headers,
        json={"source_name": "Codeur.com", "jobs": [mission]},
    )
    client.post(
        f"{WEBHOOKS}/jobs",
        headers=n8n_headers,
        json={"source_name": "Remote OK", "jobs": [job_payload()]},
    )
    missions = client.get(
        f"{API}/jobs?source_category=clients&status=all", headers=user_headers
    ).json()["data"]
    assert missions["pagination"]["total"] == 1
    item = missions["items"][0]
    assert item["source"]["category"] == "clients"
    assert item["contract"]["type"] == "freelance"
    jobs = client.get(f"{API}/jobs?source_category=jobs&status=all", headers=user_headers).json()[
        "data"
    ]
    assert jobs["pagination"]["total"] == 1
