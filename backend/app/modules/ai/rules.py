"""Implémentations déterministes (sans IA) des fonctions d'AIService.

Elles sont utilisées quand AI_PROVIDER=none ou quand le fournisseur échoue :
l'application reste entièrement fonctionnelle sans IA (RG-09).
"""

import re
from typing import Any

from app.modules.scraping import text_parsing
from app.modules.skills.extraction import PREFERRED_MARKERS, SkillExtractor
from app.shared.enums import ApplicationStatus, RecruiterResponseType, SkillRequirement
from app.shared.geo import HYBRID_KEYWORDS, REMOTE_KEYWORDS, contains_keyword
from app.shared.utils import strip_accents

_SENTENCES = re.compile(r"(?<=[.!?])\s+")
REQUIREMENT_MARKERS = (
    "requis",
    "obligatoire",
    "exige",
    "maitrise",
    "required",
    "must",
    "you have",
    "vous avez",
)
EDUCATION_PATTERN = re.compile(
    r"(bac\s*\+\s*\d|master|licence|bachelor|doctorat|phd|degree|diplome d.ingenieur|ecole d.ingenieur)",
    re.IGNORECASE,
)

RESPONSE_KEYWORDS: list[tuple[RecruiterResponseType, tuple[str, ...]]] = [
    (RecruiterResponseType.REJECTION, (
        "malheureusement", "pas retenu", "pas ete retenue", "ne pas donner suite", "pas donner suite",
        "unfortunately", "not been selected", "not moving forward", "other candidates", "regret",
    )),
    (RecruiterResponseType.OFFER, (
        "offre d emploi", "proposition d embauche", "promesse d embauche", "job offer",
        "pleased to offer", "heureux de vous proposer",
    )),
    (RecruiterResponseType.INTERVIEW, (
        "entretien", "interview", "rencontrer", "echange telephonique", "visio", "vos disponibilites",
        "your availability", "schedule a call", "appel",
    )),
    (RecruiterResponseType.INFORMATION_REQUEST, (
        "pourriez vous", "merci de nous transmettre", "merci de nous envoyer", "could you", "please send",
        "complement d information", "additional information",
    )),
    (RecruiterResponseType.ACKNOWLEDGEMENT, (
        "bien recu", "accuse de reception", "avons bien recu", "received your application",
        "thank you for applying", "merci pour votre candidature",
    )),
]  # fmt: skip

SUGGESTED_STATUS = {
    RecruiterResponseType.INTERVIEW: ApplicationStatus.INTERVIEW.value,
    RecruiterResponseType.OFFER: ApplicationStatus.OFFER.value,
    RecruiterResponseType.REJECTION: ApplicationStatus.REJECTED.value,
}


def summarize(text: str | None, max_sentences: int = 2, max_length: int = 400) -> str:
    if not text:
        return ""
    sentences = _SENTENCES.split(" ".join(text.split()))
    return " ".join(sentences[:max_sentences])[:max_length]


def extract_skills(
    extractor: SkillExtractor, title: str, description: str | None
) -> dict[str, list[str]]:
    found = extractor.extract(title, description)
    return {
        "required": [name for name, req in found if req == SkillRequirement.REQUIRED],
        "preferred": [name for name, req in found if req == SkillRequirement.PREFERRED],
    }


def extract_requirements(description: str | None) -> dict[str, Any]:
    lines = [line.strip(" -•*\t") for line in (description or "").splitlines() if line.strip()]
    must_have, nice_to_have = [], []
    for line in lines:
        normalized = strip_accents(line.lower())
        if any(marker in normalized for marker in PREFERRED_MARKERS):
            nice_to_have.append(line)
        elif any(marker in normalized for marker in REQUIREMENT_MARKERS):
            must_have.append(line)
    education = EDUCATION_PATTERN.search(strip_accents(description or ""))
    return {
        "must_have": must_have[:10],
        "nice_to_have": nice_to_have[:10],
        "min_years_experience": text_parsing.parse_min_years(description) or 0,
        "education": education.group(0) if education else "",
        "languages": text_parsing.detect_languages(description),
    }


def analyze_job(
    extractor: SkillExtractor, title: str, description: str | None, level: str | None
) -> dict[str, Any]:
    skills = extract_skills(extractor, title, description)
    requirements = extract_requirements(description)
    text = f"{title}\n{description or ''}"
    if contains_keyword(text, REMOTE_KEYWORDS):
        remote_policy = "remote"
    elif contains_keyword(text, HYBRID_KEYWORDS):
        remote_policy = "hybrid"
    else:
        remote_policy = "unknown"
    return {
        "summary": summarize(description),
        "responsibilities": [],
        "required_skills": skills["required"],
        "preferred_skills": skills["preferred"],
        "experience_level": level or "unknown",
        "min_years_experience": requirements["min_years_experience"],
        "languages": requirements["languages"],
        "remote_policy": remote_policy,
        "highlights": [],
        "red_flags": [],
    }


def classify_response(subject: str | None, body: str | None) -> dict[str, Any]:
    text = (
        " "
        + " ".join(strip_accents(f"{subject or ''} {body or ''}".lower()).replace("'", " ").split())
        + " "
    )
    response_type = RecruiterResponseType.OTHER
    for candidate_type, keywords in RESPONSE_KEYWORDS:
        if any(keyword in text for keyword in keywords):
            response_type = candidate_type
            break
    return {
        "response_type": response_type.value,
        "summary": summarize(body, max_sentences=2),
        "suggested_status": SUGGESTED_STATUS.get(response_type, "none"),
        "next_steps": [],
    }


def cover_letter(candidate: dict[str, Any], job_title: str, company: str | None) -> str:
    name = candidate.get("full_name") or "Le candidat"
    title = candidate.get("professional_title") or "développeur"
    skills = ", ".join(candidate.get("skills", [])[:6])
    company_name = company or "votre entreprise"
    paragraphs = [
        "Madame, Monsieur,",
        f"Je vous propose ma candidature au poste de {job_title} au sein de {company_name}.",
        f"{title.capitalize()}"
        + (
            f" avec {candidate['years_of_experience']} ans d'expérience"
            if candidate.get("years_of_experience")
            else ""
        )
        + (f", je travaille notamment avec {skills}." if skills else "."),
        "Votre offre correspond à mon parcours et à ce que je souhaite apporter à une équipe. "
        "Je serais ravi(e) d'échanger avec vous pour vous présenter plus en détail mes réalisations.",
        "Je vous prie d'agréer, Madame, Monsieur, l'expression de mes salutations distinguées.",
        name,
    ]
    return "\n\n".join(paragraphs)


def application_email(
    candidate: dict[str, Any], job_title: str, company: str | None
) -> dict[str, str]:
    name = candidate.get("full_name") or ""
    body = (
        "Bonjour,\n\n"
        f"Je vous adresse ma candidature pour le poste de {job_title}"
        + (f" chez {company}" if company else "")
        + ". Vous trouverez mon CV en pièce jointe.\n\n"
        "Je reste à votre disposition pour un échange.\n\n"
        f"Cordialement,\n{name}".rstrip()
    )
    return {"subject": f"Candidature : {job_title}"[:255], "body": body}


def recruiter_reply(response_type: str, candidate: dict[str, Any]) -> str:
    name = candidate.get("full_name") or ""
    replies = {
        RecruiterResponseType.INTERVIEW.value: "Merci beaucoup pour votre retour. Je suis disponible pour "
        "un entretien et vous propose les créneaux suivants : [à compléter].",
        RecruiterResponseType.REJECTION.value: "Merci pour votre retour et le temps consacré à ma "
        "candidature. Je reste intéressé(e) par de futures opportunités au sein de votre entreprise.",
        RecruiterResponseType.OFFER.value: "Merci beaucoup pour cette proposition. Je reviens vers vous "
        "très rapidement après l'avoir étudiée.",
        RecruiterResponseType.INFORMATION_REQUEST.value: "Merci pour votre message. Vous trouverez "
        "ci-joint les éléments demandés : [à compléter].",
    }
    body = replies.get(response_type, "Merci pour votre message.")
    return f"Bonjour,\n\n{body}\n\nCordialement,\n{name}".rstrip()
