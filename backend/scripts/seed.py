"""Données initiales.

    python -m scripts.seed          # référentiels uniquement (idempotent, lancé par "migrate")
    python -m scripts.seed --dev    # + données de démonstration (compte, profil, offres fictives)

Référentiels : types de contrat, catégories de compétences, niveaux d'expérience,
catalogue de compétences, sources techniques et sources d'exemple (désactivées).
Aucune information personnelle réelle n'est utilisée.
"""

import argparse
import logging
from typing import Any

from sqlalchemy import select
from sqlalchemy.orm import Session

import app.modules.models  # noqa: F401 - enregistre tous les modèles
from app.core.config import get_settings
from app.core.database import session_scope
from app.core.logging import setup_logging
from app.modules.auth.service import AuthService
from app.modules.contract_types.models import ContractType
from app.modules.experiences.models import ExperienceLevel
from app.modules.preferences.schemas import PreferencesUpdate
from app.modules.preferences.service import PreferencesService
from app.modules.profile.schemas import ProfileUpdate
from app.modules.profile.service import ProfileService
from app.modules.scraping.pipeline import JobIngestionService
from app.modules.scraping.schemas import JobPayload
from app.modules.skills.models import Skill, SkillCategory
from app.modules.skills.schemas import ProfileSkillCreate
from app.modules.skills.service import SkillService
from app.modules.sources.models import Source
from app.modules.sources.service import DEFAULT_MANUAL_SOURCE, SourceService
from app.modules.users.repository import UserRepository
from app.shared.enums import DataOrigin, SourceType
from app.shared.utils import normalize_text

logger = logging.getLogger("app.seed")

CONTRACT_TYPES = [
    ("cdi", "CDI", ["permanent", "contrat a duree indeterminee", "permanent contract"]),
    ("cdd", "CDD", ["contrat a duree determinee", "fixed term", "temporary", "temporaire"]),
    ("freelance", "Freelance", ["independant", "contractor", "self employed", "mission freelance"]),
    ("stage", "Stage", ["internship", "intern", "stagiaire"]),
    ("alternance", "Alternance", ["apprentissage", "apprenticeship", "work study", "contrat pro"]),
    ("contract", "Contract", ["contrat", "contract to hire"]),
    ("part_time", "Part-time", ["part time", "temps partiel", "mi temps"]),
    ("full_time", "Full-time", ["full time", "temps plein", "temps complet"]),
]

SKILL_CATEGORIES = [
    ("frontend", "Frontend"),
    ("backend", "Backend"),
    ("mobile", "Mobile"),
    ("devops", "DevOps"),
    ("database", "Bases de données"),
    ("data", "Data / IA"),
    ("cloud", "Cloud"),
    ("testing", "Tests / Qualité"),
    ("design", "Design"),
    ("soft_skills", "Savoir-être"),
    ("other", "Autre"),
]

EXPERIENCE_LEVELS = [
    (
        "internship",
        "Stage / Alternance",
        0,
        0,
        ["intern", "stagiaire", "internship", "trainee", "alternant"],
    ),
    ("junior", "Junior", 1, 0, ["jr", "entry level", "debutant", "graduate"]),
    ("mid", "Confirmé", 2, 2, ["confirme", "intermediate", "mid level", "medior", "regular"]),
    ("senior", "Senior", 3, 5, ["sr", "experimente", "experienced"]),
    (
        "lead",
        "Lead / Expert",
        4,
        8,
        ["lead", "tech lead", "principal", "staff", "architect", "architecte", "expert"],
    ),
]

# nom, catégorie, alias
SKILLS = [
    ("Python", "backend", []), ("Django", "backend", []), ("FastAPI", "backend", []),
    ("Flask", "backend", []), ("Node.js", "backend", ["nodejs", "node js"]),
    ("Express", "backend", ["expressjs"]), ("NestJS", "backend", ["nest js"]),
    ("PHP", "backend", []), ("Laravel", "backend", []), ("Symfony", "backend", []),
    ("Java", "backend", []), ("Spring", "backend", ["spring boot", "springboot"]),
    ("Go", "backend", ["golang"]), ("Rust", "backend", []), ("C#", "backend", ["csharp"]),
    (".NET", "backend", ["dotnet", "asp.net"]), ("Ruby on Rails", "backend", ["rails"]),
    ("GraphQL", "backend", []), ("REST API", "backend", ["api rest", "restful"]),
    ("Celery", "backend", []),
    ("JavaScript", "frontend", ["js", "ecmascript"]), ("TypeScript", "frontend", ["ts"]),
    ("React", "frontend", ["reactjs", "react js", "react.js"]), ("Next.js", "frontend", ["nextjs", "next js"]),
    ("Vue.js", "frontend", ["vue", "vuejs", "vue js"]), ("Angular", "frontend", []),
    ("Svelte", "frontend", []), ("HTML", "frontend", ["html5"]), ("CSS", "frontend", ["css3"]),
    ("Tailwind CSS", "frontend", ["tailwind"]), ("Redux", "frontend", []),
    ("Flutter", "mobile", []), ("Dart", "mobile", []), ("React Native", "mobile", []),
    ("Kotlin", "mobile", []), ("Swift", "mobile", []),
    ("Docker", "devops", []), ("Kubernetes", "devops", ["k8s"]), ("Linux", "devops", []),
    ("Git", "devops", []), ("CI/CD", "devops", ["ci cd", "continuous integration"]),
    ("GitHub Actions", "devops", []), ("GitLab CI", "devops", []), ("Terraform", "devops", []),
    ("Ansible", "devops", []), ("Nginx", "devops", []),
    ("PostgreSQL", "database", ["postgres", "postgre"]), ("MySQL", "database", []),
    ("MariaDB", "database", []), ("MongoDB", "database", ["mongo"]), ("Redis", "database", []),
    ("SQL", "database", []), ("Elasticsearch", "database", ["elastic search"]),
    ("AWS", "cloud", ["amazon web services"]), ("Azure", "cloud", []),
    ("GCP", "cloud", ["google cloud"]),
    ("Pandas", "data", []), ("Machine Learning", "data", ["ml"]), ("LLM", "data", []),
    ("Pytest", "testing", []), ("Jest", "testing", []), ("Cypress", "testing", []),
    ("Figma", "design", []),
    ("Agile", "soft_skills", ["scrum", "kanban"]), ("Anglais", "soft_skills", ["english"]),
]  # fmt: skip

TECHNICAL_SOURCES = [
    {
        "name": "Saisie manuelle",
        "type": "manual",
        "notes": "Offres ajoutées à la main (POST /jobs).",
    },
    {"name": "n8n", "type": "webhook", "notes": "Offres envoyées par n8n sans source précisée."},
]

# --- Sources d'offres ------------------------------------------------------------------
# Trois catégories : "jobs" (offres d'emploi), "clients" (missions freelance),
# "services" (API de données d'offres). Deux modes d'accès :
#
# 1) Collecte automatique, UNIQUEMENT via un accès officiel (API ou flux RSS publics).
#    Les clés d'API éventuelles sont dans le .env (variables SOURCE_*), jamais en base.
API_AND_RSS_SOURCES: list[dict[str, Any]] = [
    # ----- jobs -----
    {
        "name": "Remote OK",
        "category": "jobs",
        "type": "api",
        "adapter": "json_api",
        "base_url": "https://remoteok.com",
        "scraping_enabled": True,
        "rate_limit": 1,
        "configuration": {
            "url": "https://remoteok.com/api",
            "field_map": {
                "external_id": "id", "title": "position", "description": "description", "url": "url",
                "company": "company", "company_logo": "company_logo", "location": "location",
                "published_at": "date", "skills": "tags", "salary_min": "salary_min",
                "salary_max": "salary_max", "application_url": "apply_url",
            },
            "defaults": {"salary_currency": "USD", "salary_period": "year"},
            "remote_only": True,
        },
        "notes": "Site + API officielle (« Remote OK API »). Conditions : afficher le lien vers l'offre "
        "sur Remote OK et citer la source (fait par l'application). Quelques appels par jour maximum.",
    },
    {
        "name": "We Work Remotely",
        "category": "jobs",
        "type": "rss",
        "adapter": "rss_feed",
        "base_url": "https://weworkremotely.com",
        "scraping_enabled": True,
        "rate_limit": 6,
        "configuration": {
            "feed_url": "https://weworkremotely.com/categories/remote-programming-jobs.rss",
            "extra_feed_urls": [
                "https://weworkremotely.com/categories/remote-full-stack-programming-jobs.rss",
                "https://weworkremotely.com/categories/remote-back-end-programming-jobs.rss",
                "https://weworkremotely.com/categories/remote-front-end-programming-jobs.rss",
                "https://weworkremotely.com/categories/remote-devops-sysadmin-jobs.rss",
            ],
            "title_separator": ":",
            "remote_only": True,
        },
        "notes": "Flux RSS publics par catégorie (titres au format « Entreprise: Poste »).",
    },
    {
        "name": "France Travail",
        "category": "jobs",
        "type": "api",
        "adapter": "france_travail_api",
        "base_url": "https://www.francetravail.fr",
        "enabled": False,
        "scraping_enabled": True,
        "rate_limit": 30,
        "configuration": {"keywords": "développeur", "published_since_days": 7},
        "notes": "Site + API officielle « Offres d'emploi v2 » (francetravail.io). À activer après avoir "
        "renseigné FRANCE_TRAVAIL_CLIENT_ID et FRANCE_TRAVAIL_CLIENT_SECRET (application gratuite).",
    },
    {
        "name": "Jobgether",
        "category": "jobs",
        "type": "api",
        "adapter": "json_api",
        "base_url": "https://jobgether.com",
        "scraping_enabled": True,
        "rate_limit": 20,
        "configuration": {
            "url": "https://jobgether.com/astroapi/ai/jobs.json",
            "query_params": {"keyword": "developer", "limit": "25"},
            "items_path": "jobs",
            "field_map": {
                "external_id": "id", "title": "title", "company": "company", "url": "url",
                "location": "location", "remote": "remote", "contract": "contractType",
                "experience_level": "experience", "published_at": "postedAt",
            },
            "page_param": "page",
            "max_pages": 2,
        },
        "notes": "Flux JSON public explicitement autorisé par le robots.txt du site "
        "(/astroapi/ai/jobs.json, 25 offres par page, délai de 2 s entre requêtes).",
    },
    {
        "name": "Codeko.tech",
        "category": "jobs",
        "type": "rss",
        "adapter": "rss_feed",
        "base_url": "https://codeko.tech",
        "scraping_enabled": True,
        "rate_limit": 6,
        "configuration": {"feed_url": "https://codeko.tech/?post_type=job_listing&feed=rss2"},
        "notes": "Flux RSS WordPress des annonces (vide lors de la configuration) : vérifiez avec "
        "POST /sources/{id}/test.",
    },
    # ----- clients (missions freelance) -----
    {
        "name": "Codeur.com",
        "category": "clients",
        "type": "rss",
        "adapter": "rss_feed",
        "base_url": "https://www.codeur.com",
        "scraping_enabled": True,
        "rate_limit": 6,
        "configuration": {"feed_url": "https://www.codeur.com/projects.rss", "default_contract": "Freelance"},
        "notes": "Flux RSS public des projets freelance.",
    },
    {
        "name": "Freelancer.com",
        "category": "clients",
        "type": "api",
        "adapter": "json_api",
        "base_url": "https://www.freelancer.com",
        "scraping_enabled": True,
        "rate_limit": 6,
        "configuration": {
            "url": "https://www.freelancer.com/api/projects/0.1/projects/active/",
            "query_params": {"query": "python", "limit": "50", "job_details": "true", "full_description": "true"},
            "items_path": "result.projects",
            "field_map": {"external_id": "id", "title": "title", "description": "description",
                          "published_at": "time_submitted", "skills": "jobs"},
            "url_template": "https://www.freelancer.com/projects/{seo_url}",
            "extra_description_fields": {"Budget minimum": "budget.minimum", "Budget maximum": "budget.maximum",
                                         "Devise": "currency.code", "Type de projet": "type"},
            "defaults": {"contract": "Freelance", "location": "Remote"},
            "description_is_html": False,
        },
        "notes": "API publique officielle (developers.freelancer.com). Modifiez query_params.query "
        "pour vos mots-clés.",
    },
    # ----- services (API de données d'offres, clé gratuite à demander) -----
    {
        "name": "Adzuna",
        "category": "services",
        "type": "api",
        "adapter": "json_api",
        "base_url": "https://developer.adzuna.com",
        "enabled": False,
        "scraping_enabled": True,
        "rate_limit": 10,
        "configuration": {
            "url": "https://api.adzuna.com/v1/api/jobs/fr/search/1",
            "query_params": {"what": "développeur", "results_per_page": "50", "content-type": "application/json"},
            "secret_query_params": {"app_id": "SOURCE_ADZUNA_APP_ID", "app_key": "SOURCE_ADZUNA_APP_KEY"},
            "items_path": "results",
            "field_map": {
                "external_id": "id", "title": "title", "description": "description", "url": "redirect_url",
                "company": "company.display_name", "location": "location.display_name",
                "contract": "contract_type", "salary_min": "salary_min", "salary_max": "salary_max",
                "published_at": "created",
            },
            "defaults": {"salary_currency": "EUR", "salary_period": "year"},
            "description_is_html": False,
        },
        "notes": "API officielle (clé gratuite sur developer.adzuna.com) : SOURCE_ADZUNA_APP_ID et "
        "SOURCE_ADZUNA_APP_KEY dans le .env. Conditions : mentionner « Jobs by Adzuna ». "
        "Changez /fr/ dans l'URL pour un autre pays.",
    },
    {
        "name": "Findwork.dev",
        "category": "services",
        "type": "api",
        "adapter": "json_api",
        "base_url": "https://findwork.dev",
        "enabled": False,
        "scraping_enabled": True,
        "rate_limit": 10,
        "configuration": {
            "url": "https://findwork.dev/api/jobs/",
            "query_params": {"search": "python", "sort_by": "date"},
            "secret_headers": {"Authorization": "Token {SOURCE_FINDWORK_API_KEY}"},
            "items_path": "results",
            "field_map": {
                "external_id": "id", "title": "role", "company": "company_name", "company_logo": "logo",
                "url": "url", "description": "text", "location": "location", "remote": "remote",
                "contract": "employment_type", "published_at": "date_posted", "skills": "keywords",
            },
        },
        "notes": "API officielle (clé gratuite sur findwork.dev) : SOURCE_FINDWORK_API_KEY dans le .env.",
    },
    {
        "name": "The Muse",
        "category": "services",
        "type": "api",
        "adapter": "json_api",
        "base_url": "https://www.themuse.com",
        "enabled": False,
        "scraping_enabled": True,
        "rate_limit": 10,
        "configuration": {
            "url": "https://www.themuse.com/api/public/jobs",
            "query_params": {"page": "1", "category": "Software Engineering"},
            "secret_query_params": {"api_key": "SOURCE_THE_MUSE_API_KEY"},
            "items_path": "results",
            "field_map": {
                "external_id": "id", "title": "name", "description": "contents", "url": "refs.landing_page",
                "company": "company.name", "location": "locations.0.name",
                "experience_level": "levels.0.name", "published_at": "publication_date",
            },
        },
        "notes": "API officielle v2. Lors de la configuration, le service a refusé (HTTP 403) les "
        "requêtes automatisées sans clé : créez une clé (SOURCE_THE_MUSE_API_KEY) puis testez avec "
        "POST /sources/{id}/test. Aucun contournement n'est tenté.",
    },
    {
        "name": "JobDataLake",
        "category": "services",
        "type": "api",
        "adapter": "json_api",
        "base_url": "https://www.jobdatalake.com",
        "enabled": False,
        "scraping_enabled": True,
        "rate_limit": 2,
        "configuration": {
            "url": "https://api.jobdatalake.com/v1/jobs",
            "query_params": {"q": "python", "per_page": "50"},
            "secret_headers": {"X-API-Key": "SOURCE_JOBDATALAKE_API_KEY"},
            "items_path": "jobs",
            "field_map": {
                "external_id": "job_handle", "title": "title", "company": "company_name", "url": "url",
                "location": "locations.0", "remote": "remote_type", "contract": "employment_type",
                "experience_level": "seniority", "salary_min": "salary_min_usd",
                "salary_max": "salary_max_usd", "published_at": "posted_at", "skills": "required_skills",
            },
            "salary_multiplier": 1000,
            "defaults": {"salary_currency": "USD", "salary_period": "year"},
        },
        "notes": "API officielle (1 000 crédits gratuits, 1 crédit par requête) : "
        "SOURCE_JOBDATALAKE_API_KEY dans le .env. Les descriptions complètes ne sont pas incluses "
        "dans la recherche.",
    },
]  # fmt: skip

# 2) Sites sans accès automatique autorisé : les offres arrivent par leurs ALERTES EMAIL
#    (workflow n8n "job-alerts-email") ou par ajout manuel depuis Flutter.
MADAGASCAR_NOTE = (
    "Pas de flux RSS ni d'API détectés. Si les conditions d'utilisation du site autorisent la "
    "collecte, transformez cette source en source HTML (adapter html_page, terms_reviewed=true) "
    "et testez-la avec POST /sources/{id}/test. Sinon : alertes email ou ajout manuel."
)
# nom : (catégorie, URL, domaines des liens d'alerte, raison, active)
ALERT_EMAIL_SITES: dict[str, tuple[str, str, list[str], str, bool]] = {
    # ----- jobs -----
    "LinkedIn": ("jobs", "https://www.linkedin.com/jobs", ["linkedin.com"],
                 "CGU : collecte automatique interdite, API réservée aux partenaires. Créez des alertes "
                 "emploi et missions.", True),
    "Indeed": ("jobs", "https://www.indeed.com", ["indeed.com", "indeed.fr"],
               "CGU : collecte interdite, API éditeur fermée. Utilisez les alertes email.", True),
    "Glassdoor": ("jobs", "https://www.glassdoor.com", ["glassdoor.com", "glassdoor.fr"],
                  "CGU : collecte interdite, API fermée. Utilisez les alertes email.", True),
    "Welcome to the Jungle": ("jobs", "https://www.welcometothejungle.com", ["welcometothejungle.com"],
                              "Pas d'API publique, collecte interdite par les CGU. Alertes email.", True),
    "APEC": ("jobs", "https://www.apec.fr", ["apec.fr"],
             "Pas d'API publique d'offres (les données ouvertes de l'APEC sont des études et "
             "statistiques) ; réutilisation des offres interdite par les CGU. Alertes email.", True),
    "Madajob": ("jobs", "https://madajob.mg", ["madajob.mg"], MADAGASCAR_NOTE, True),
    "Job2Mada": ("jobs", "https://job2mada.com", ["job2mada.com"], MADAGASCAR_NOTE, True),
    "Remote.co": ("jobs", "https://remote.co", ["remote.co"],
                  "Pas d'API ; site injoignable lors de la configuration. Alertes email ou ajout manuel.", True),
    "Hellowork": ("jobs", "https://www.hellowork.com", ["hellowork.com"],
                  "robots.txt restrictif et pas d'API publique. Alertes email.", True),
    "Monster": ("jobs", "https://www.monster.com", ["monster.com", "monster.fr"],
                "CGU : collecte interdite, pas d'API publique. Alertes email.", True),
    "Talent.com": ("jobs", "https://www.talent.com", ["talent.com"],
                   "Flux XML réservés aux partenaires (accord commercial). Alertes email.", True),
    "Arc.dev": ("jobs", "https://arc.dev", ["arc.dev"],
                "Pas d'API ni de flux publics. Alertes email.", True),
    "Stack Overflow Jobs": ("jobs", "https://stackoverflow.jobs", ["stackoverflow.jobs"],
                            "Service Stack Overflow Jobs fermé en 2022 ; domaine protégé par un anti-bot.", False),
    "GitHub Jobs": ("jobs", "https://github.com", ["github.com"],
                    "Service GitHub Jobs fermé en 2021 (les listes GitHub recensent des entreprises, "
                    "pas des offres). Utilisez Remote OK, We Work Remotely ou Jobgether.", False),
    "Jobnet.dk": ("jobs", "https://jobsearch.api.jobnet.dk", ["jobnet.dk"],
                  "API non joignable lors de la configuration (Danemark).", False),
    # ----- clients (missions freelance) -----
    "Malt": ("clients", "https://www.malt.fr", ["malt.fr", "malt.com"],
             "Pas d'API publique des missions ; collecte interdite. Alertes email.", True),
    "Upwork": ("clients", "https://www.upwork.com", ["upwork.com"],
               "Flux RSS supprimés, API officielle soumise à validation, collecte interdite. Alertes email.", True),
    "Fiverr": ("clients", "https://www.fiverr.com", ["fiverr.com"],
               "Marketplace de services (vous y vendez une offre) : pas d'offres publiques à collecter.", True),
    "Free-Work": ("clients", "https://www.free-work.com", ["free-work.com"],
                  "Pas de flux RSS ni d'API publics. Alertes email.", True),
    "Work IT Mada": ("clients", "https://www.workitmada.com", ["workitmada.com"], MADAGASCAR_NOTE, True),
    "ComeUp": ("clients", "https://comeup.com", ["comeup.com"],
               "Marketplace de services : pas d'offres publiques à collecter.", True),
    "Toptal": ("clients", "https://www.toptal.com", ["toptal.com"],
               "Réseau sur sélection : missions proposées aux membres par email.", True),
    "Workana": ("clients", "https://www.workana.com", ["workana.com"],
                "Pas de flux RSS ni d'API publics. Alertes email.", True),
    "Crème de la Crème": ("clients", "https://www.cremedelacreme.io", ["cremedelacreme.io"],
                          "Réseau sur sélection : missions envoyées aux membres par email.", True),
    "Jobbers": ("clients", "https://www.jobbers.io", ["jobbers.io"],
                "Site protégé par un anti-bot (défi Cloudflare) : alertes email ou ajout manuel.", True),
    "Guru": ("clients", "https://www.guru.com", ["guru.com"],
             "Accès refusé aux robots (HTTP 403). Alertes email.", True),
    "Sortlist": ("clients", "https://www.sortlist.com", ["sortlist.com"],
                 "Marketplace d'agences : briefs réservés aux agences inscrites (emails).", True),
}  # fmt: skip

ALERT_EMAIL_SOURCES: list[dict[str, Any]] = [
    {
        "name": name,
        "category": category,
        "type": "webhook",
        "fetch_mode": "n8n",
        "base_url": base_url,
        "enabled": enabled,
        "scraping_enabled": False,
        "configuration": {"alert_emails": True, "alert_link_domains": domains},
        "notes": reason,
    }
    for name, (category, base_url, domains, reason, enabled) in ALERT_EMAIL_SITES.items()
]

# 3) Exemples désactivés montrant les autres modes.
EXAMPLE_SOURCES: list[dict[str, Any]] = [
    {
        "name": "Exemple flux RSS lu par n8n",
        "type": "rss",
        "fetch_mode": "n8n",
        "base_url": "https://example.com",
        "enabled": False,
        "scraping_enabled": False,
        "configuration": {"feed_url": "https://example.com/jobs.rss"},
        "notes": "Exemple désactivé : c'est le workflow n8n qui lit ce flux (fetch_mode=n8n).",
    },
    {
        "name": "Exemple page carrières (HTML)",
        "type": "html",
        "adapter": "html_page",
        "base_url": "https://example.com",
        "enabled": False,
        "scraping_enabled": False,
        "terms_reviewed": False,
        "rate_limit": 6,
        "configuration": {
            "list_url": "https://example.com/careers",
            "item_selector": "article.job",
            "fields": {
                "title": "h2",
                "url": "a@href",
                "location": ".location",
                "contract": ".contract",
            },
            "company_name": "Exemple SAS",
        },
        "notes": "Exemple désactivé. N'activer que si les conditions d'utilisation du site "
        "autorisent la collecte automatique (puis terms_reviewed=true).",
    },
]


def seed_reference_data(session: Session | None = None) -> dict[str, int]:
    """Crée les données de référence manquantes. Ne modifie jamais une donnée existante."""
    if session is None:
        with session_scope() as own_session:
            return seed_reference_data(own_session)

    created = {
        "contract_types": 0,
        "skill_categories": 0,
        "experience_levels": 0,
        "skills": 0,
        "sources": 0,
    }

    existing = set(session.scalars(select(ContractType.code)))
    for order, (code, name, aliases) in enumerate(CONTRACT_TYPES):
        if code not in existing:
            session.add(ContractType(code=code, name=name, aliases=aliases, sort_order=order))
            created["contract_types"] += 1

    categories = {category.code: category for category in session.scalars(select(SkillCategory))}
    for code, name in SKILL_CATEGORIES:
        if code not in categories:
            categories[code] = SkillCategory(code=code, name=name)
            session.add(categories[code])
            created["skill_categories"] += 1

    existing = set(session.scalars(select(ExperienceLevel.code)))
    for code, name, rank, min_years, aliases in EXPERIENCE_LEVELS:
        if code not in existing:
            session.add(
                ExperienceLevel(
                    code=code, name=name, rank=rank, min_years=min_years, aliases=aliases
                )
            )
            created["experience_levels"] += 1

    existing = set(session.scalars(select(Skill.normalized_name)))
    for name, category_code, aliases in SKILLS:
        normalized = normalize_text(name)
        if normalized not in existing:
            session.add(
                Skill(
                    name=name,
                    normalized_name=normalized,
                    category=categories[category_code],
                    aliases=aliases,
                )
            )
            existing.add(normalized)
            created["skills"] += 1

    existing = set(session.scalars(select(Source.name)))
    for source in TECHNICAL_SOURCES + API_AND_RSS_SOURCES + ALERT_EMAIL_SOURCES + EXAMPLE_SOURCES:
        if source["name"] not in existing:
            session.add(Source(**source))
            created["sources"] += 1

    session.commit()
    logger.info("Reference data seeded", extra=created)
    return created


DEMO_EMAIL = "demo@example.com"
DEMO_PASSWORD = "DemoPassw0rd!"  # compte de démonstration local uniquement

DEMO_JOBS = [
    {
        "external_id": "demo-1",
        "title": "Développeur Full Stack Python / React (H/F)",
        "description": "Exemple SAS recherche un développeur Full Stack pour son équipe produit. "
        "Stack : Python, Django, React, TypeScript, PostgreSQL. Docker est un plus. "
        "3 ans d'expérience minimum. Télétravail partiel possible.\nSalaire : 45 - 55 k€ par an.",
        "url": "https://example.com/jobs/demo-1",
        "company": {
            "name": "Exemple SAS",
            "website": "https://example.com",
            "city": "Paris",
            "country": "France",
        },
        "location": "Paris, France",
        "contract": "CDI",
        "recruiter": {
            "name": "Recrutement Exemple",
            "email": "jobs@example.com",
            "contact_source": "job_listing",
        },
    },
    {
        "external_id": "demo-2",
        "title": "Backend Developer FastAPI (Remote)",
        "description": "Démo Tech is hiring a backend developer to build APIs with Python and FastAPI. "
        "You will work with Redis, Celery and Docker. English fluent required. Full remote.",
        "url": "https://example.org/careers/backend-fastapi",
        "company": {"name": "Démo Tech", "website": "https://example.org"},
        "location": "Remote",
        "contract": "Freelance",
        "salary": "450 € / jour",
    },
    {
        "external_id": "demo-3",
        "title": "Senior Java Engineer",
        "description": "Poste de développeur Java Spring senior, 7 ans d'expérience, sur site à Lyon.",
        "url": "https://example.net/jobs/java-senior",
        "company": {"name": "Société Fictive"},
        "location": "Lyon, France",
        "contract": "CDI",
    },
]


def seed_dev_data() -> None:
    """Compte de démonstration + profil + préférences + offres fictives."""
    with session_scope() as session:
        user = UserRepository(session).get_by_email(DEMO_EMAIL)
        if user is None:
            user = AuthService(session).register(DEMO_EMAIL, DEMO_PASSWORD)
        ProfileService(session).update_profile(
            user,
            ProfileUpdate(
                first_name="Jane",
                last_name="Doe",
                professional_title="Développeuse Full Stack Python / React",
                city="Paris",
                country="France",
                years_of_experience=4,
                experience_level="mid",
                languages=[{"code": "fr", "level": "native"}, {"code": "en", "level": "fluent"}],  # type: ignore[list-item]
                minimum_salary=40000,
                currency="EUR",
                salary_period="year",  # type: ignore[arg-type]
            ),
        )
        skills = SkillService(session)
        existing = {item.skill.normalized_name for item in skills.list_skills(user)}
        for name, level in (("Python", "advanced"), ("Django", "advanced"), ("React", "intermediate"),
                            ("TypeScript", "intermediate"), ("PostgreSQL", "advanced"), ("Docker", "intermediate")):  # fmt: skip
            if normalize_text(name) not in existing:
                skills.add_skill(user, ProfileSkillCreate(name=name, level=level))  # type: ignore[arg-type]
        PreferencesService(session).update_preferences(
            user,
            PreferencesUpdate(
                job_titles=["Full Stack Developer", "Python Developer", "Backend Developer"],
                contract_types=["cdi", "freelance"],
                skills=["Python", "React"],
                experience_levels=["mid", "senior"],
                locations=[{"city": "Paris", "country": "France"}],  # type: ignore[list-item]
                remote=True,
                hybrid=True,
                languages=["fr", "en"],
                matching_threshold=70,
            ),
        )
        source = SourceService(session).get_or_create_default(
            DEFAULT_MANUAL_SOURCE, SourceType.MANUAL
        )
        session.commit()
        result = JobIngestionService(session).ingest(
            [JobPayload.model_validate(job) for job in DEMO_JOBS], source, origin=DataOrigin.MANUAL
        )
        logger.info("Demo data seeded", extra={"jobs_created": result.created, "email": DEMO_EMAIL})
        print(
            f"Compte de démo : {DEMO_EMAIL} / {DEMO_PASSWORD} — {result.created} offre(s) créée(s)"
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Charge les données initiales")
    parser.add_argument("--dev", action="store_true", help="Ajoute les données de démonstration")
    args = parser.parse_args()
    setup_logging(get_settings())
    print("Référentiels :", seed_reference_data())
    if args.dev:
        seed_dev_data()


if __name__ == "__main__":
    main()
