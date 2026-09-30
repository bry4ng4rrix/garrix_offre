"""Règles métier du matching (valeurs de référence, pas des poids).

Les POIDS des critères sont configurables (variables MATCHING_*_WEIGHT puis
PUT /matching/settings). Ce fichier regroupe les règles fixes utilisées par
scoring.py ; modifiez-les ici si vous voulez changer le comportement du calcul.
"""

from app.shared.enums import Priority, SkillLevel, SkillRequirement

# Score attribué à un critère quand l'offre ne donne pas l'information (0 à 1).
UNKNOWN_SCORE = 0.5

# Un critère est considéré "correspondant" à partir de ce sous-score.
MATCH_THRESHOLD = 0.6

# Une compétence obligatoire compte double par rapport à une compétence appréciée.
REQUIREMENT_WEIGHTS = {SkillRequirement.REQUIRED: 2.0, SkillRequirement.PREFERRED: 1.0}

# Part de la compétence reconnue selon votre niveau.
SKILL_LEVEL_FACTORS = {
    SkillLevel.BEGINNER: 0.5,
    SkillLevel.INTERMEDIATE: 0.8,
    SkillLevel.ADVANCED: 1.0,
    SkillLevel.EXPERT: 1.0,
}

# Importance d'une technologie recherchée selon sa priorité.
PRIORITY_WEIGHTS = {Priority.LOW: 1.0, Priority.MEDIUM: 2.0, Priority.HIGH: 3.0}

# Si une technologie marquée "obligatoire" est absente de l'offre, le score final est plafonné.
REQUIRED_TECHNOLOGY_MISSING_MAX_SCORE = 50

# Écart de niveau (rang profil - rang offre) -> sous-score.
LEVEL_GAP_SCORES = {0: 1.0, 1: 0.8, -1: 0.6}
LEVEL_OVERQUALIFIED_SCORE = 0.5  # profil nettement plus senior que le poste
LEVEL_UNDERQUALIFIED_SCORE = 0.2  # profil nettement moins senior que le poste

# Localisation : même ville = 1, même pays seulement = 0.6.
SAME_COUNTRY_SCORE = 0.6
# Mode de travail non souhaité (ex: poste sur site alors que vous ne voulez que du remote).
UNWANTED_WORK_MODE_FACTOR = 0.4

# Conversion des salaires en montant annuel pour les comparer.
SALARY_PERIOD_TO_YEAR = {"year": 1, "month": 12, "day": 218, "hour": 1607}

# Titre : synonymes ramenés à une forme commune avant comparaison.
TITLE_SYNONYMS = {
    "developpeur": "developer",
    "developpeuse": "developer",
    "dev": "developer",
    "ingenieur": "engineer",
    "ingenieure": "engineer",
    "fullstack": "full stack",
    "backend": "back end",
    "frontend": "front end",
}
TITLE_STOPWORDS = {
    "h",
    "f",
    "de",
    "du",
    "des",
    "la",
    "le",
    "les",
    "en",
    "et",
    "a",
    "the",
    "and",
    "of",
}
