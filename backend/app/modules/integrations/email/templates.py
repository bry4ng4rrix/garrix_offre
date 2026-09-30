"""Gabarits des emails envoyés par l'application (texte brut + HTML simple).

Chaque fonction retourne (sujet, texte, html). Toutes les valeurs dynamiques sont
échappées dans la version HTML.
"""

from html import escape
from typing import Any

EmailContent = tuple[str, str, str]


def _html_page(title: str, body_html: str) -> str:
    return (
        "<!doctype html><html><body style='font-family:Arial,sans-serif;color:#222'>"
        f"<h2 style='color:#1f4e79'>{escape(title)}</h2>{body_html}"
        "<hr><p style='font-size:12px;color:#888'>Garrix Offre — notification automatique</p>"
        "</body></html>"
    )


def new_job_email(data: dict[str, Any], high_match: bool = False) -> EmailContent:
    title = data.get("job_title") or "Nouvelle offre"
    subject = f"{'🔥 Offre très compatible' if high_match else 'Nouvelle offre'} : {title}"
    details = [
        ("Entreprise", data.get("company_name")),
        ("Lieu", data.get("location")),
        ("Score", f"{data['score']}/100" if data.get("score") is not None else None),
        ("Compétences", ", ".join(data.get("matched_skills") or []) or None),
    ]
    text_lines = [title, ""] + [f"{label} : {value}" for label, value in details if value]
    if data.get("url"):
        text_lines += ["", f"Voir l'offre : {data['url']}"]
    rows = "".join(
        f"<li><b>{escape(label)}</b> : {escape(str(value))}</li>"
        for label, value in details
        if value
    )
    link = (
        f"<p><a href='{escape(str(data['url']), quote=True)}'>Voir l'offre</a></p>"
        if data.get("url")
        else ""
    )
    return subject, "\n".join(text_lines), _html_page(title, f"<ul>{rows}</ul>{link}")


def recruiter_response_email(data: dict[str, Any]) -> EmailContent:
    subject = f"Réponse recruteur : {data.get('subject') or '(sans objet)'}"
    text = (
        f"Vous avez reçu une réponse de {data.get('sender_email')}.\n"
        f"Objet : {data.get('subject')}\n"
        f"Type détecté : {data.get('response_type')}\n"
    )
    body = (
        f"<p>Vous avez reçu une réponse de <b>{escape(str(data.get('sender_email')))}</b>.</p>"
        f"<p>Objet : {escape(str(data.get('subject')))}<br>"
        f"Type détecté : {escape(str(data.get('response_type')))}</p>"
    )
    return subject, text, _html_page("Réponse d'un recruteur", body)


def application_status_email(data: dict[str, Any]) -> EmailContent:
    subject = f"Candidature {data.get('job_title') or ''} : {data.get('status')}"
    text = (
        f"Le statut de votre candidature « {data.get('job_title')} » "
        f"({data.get('company_name') or 'entreprise inconnue'}) est maintenant : {data.get('status')}."
    )
    return subject, text, _html_page("Mise à jour de candidature", f"<p>{escape(text)}</p>")


def error_email(title: str, message: str) -> EmailContent:
    return f"⚠️ {title}", f"{title}\n\n{message}", _html_page(title, f"<p>{escape(message)}</p>")


def generic_email(title: str, message: str) -> EmailContent:
    return title, message, _html_page(title, f"<p>{escape(message)}</p>")
