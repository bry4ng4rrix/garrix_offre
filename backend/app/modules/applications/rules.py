"""Cycle de vie d'une candidature (UML 18 / RG-10).

    NOT_APPLIED -> PREPARING -> READY -> SUBMITTED -> FOLLOW_UP -> INTERVIEW -> OFFER
    REJECTED et WITHDRAWN sont terminaux.

Règles importantes :
- READY -> SUBMITTED uniquement via POST /applications/{id}/submit avec confirm=true
  (jamais d'envoi automatique sans validation explicite) ;
- n8n ne peut signaler que des événements externes (relance, entretien, offre, refus).

Hypothèses ajoutées par rapport au diagramme (cas réels courants) :
READY -> PREPARING (retour en rédaction), SUBMITTED -> INTERVIEW (entretien sans relance),
INTERVIEW -> REJECTED / WITHDRAWN, OFFER -> WITHDRAWN (offre déclinée),
NOT_APPLIED / SUBMITTED -> WITHDRAWN.
"""

from app.shared.enums import ActorType, ApplicationStatus

S = ApplicationStatus

ALLOWED_TRANSITIONS: dict[ApplicationStatus, set[ApplicationStatus]] = {
    S.NOT_APPLIED: {S.PREPARING, S.WITHDRAWN},
    S.PREPARING: {S.READY, S.WITHDRAWN},
    S.READY: {S.PREPARING, S.SUBMITTED, S.WITHDRAWN},
    S.SUBMITTED: {S.FOLLOW_UP, S.INTERVIEW, S.REJECTED, S.WITHDRAWN},
    S.FOLLOW_UP: {S.INTERVIEW, S.REJECTED, S.WITHDRAWN},
    S.INTERVIEW: {S.OFFER, S.REJECTED, S.WITHDRAWN},
    S.OFFER: {S.WITHDRAWN},
    S.REJECTED: set(),
    S.WITHDRAWN: set(),
}

# Statuts qu'une candidature peut avoir à sa création.
INITIAL_STATUSES = {S.NOT_APPLIED, S.PREPARING}

# Seul l'endpoint /submit (confirmation explicite) peut passer une candidature à SUBMITTED.
SUBMIT_ONLY = {S.SUBMITTED}

# Événements externes que n8n peut signaler.
N8N_ALLOWED_TARGETS = {S.FOLLOW_UP, S.INTERVIEW, S.OFFER, S.REJECTED}

# Nombre de jours avant la relance proposée après l'envoi.
FOLLOW_UP_AFTER_DAYS = 7


def can_transition(current: ApplicationStatus, target: ApplicationStatus) -> bool:
    return target in ALLOWED_TRANSITIONS[current]


def actor_may_set(actor: ActorType, target: ApplicationStatus) -> bool:
    if target in SUBMIT_ONLY:
        return False
    if actor == ActorType.N8N:
        return target in N8N_ALLOWED_TARGETS
    return True
