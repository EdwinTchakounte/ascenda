"""Schémas JSON des dérivés ASCENDA (structured outputs, additionalProperties=False)."""

FICHE = {
    "type": "object",
    "properties": {
        "titre_normalise": {"type": "string"},
        "auteurs": {"type": "array", "items": {"type": "string"}},
        "annee": {"type": ["integer", "null"]},
        "type_ouvrage": {"type": "string",
            "enum": ["essai", "manuel", "cours", "roman", "rapport", "guide_pratique", "recueil"]},
        "niveau": {"type": "string", "enum": ["debutant", "intermediaire", "avance"]},
        "public_cible": {"type": "string"},
        "these_centrale": {"type": "string",
            "description": "Une à trois phrases. Ce que l'ouvrage soutient, pas ce dont il parle."},
        "idees_force": {
            "type": "array", "minItems": 4, "maxItems": 6,
            "items": {"type": "object", "properties": {
                "titre": {"type": "string"},
                "explication": {"type": "string"},
                "page": {"type": ["integer", "null"]}},
                "required": ["titre", "explication", "page"], "additionalProperties": False}},
        "concepts_cles": {
            "type": "array", "minItems": 5, "maxItems": 12,
            "items": {"type": "object", "properties": {
                "terme": {"type": "string"}, "definition": {"type": "string"}},
                "required": ["terme", "definition"], "additionalProperties": False}},
        "a_lire_si": {"type": "string"},
        "a_eviter_si": {"type": "string"},
        "prerequis": {"type": "array", "items": {"type": "string"},
            "description": "Notions à maîtriser avant d'ouvrir le livre."},
        "controverses": {"type": "array", "items": {"type": "string"},
            "description": "Points où l'auteur prend position et où d'autres le contredisent."},
        "confiance": {"type": "number",
            "description": "0-1 : fiabilité de cette fiche compte tenu du texte fourni."}
    },
    "required": ["titre_normalise", "auteurs", "annee", "type_ouvrage", "niveau",
                 "public_cible", "these_centrale", "idees_force", "concepts_cles",
                 "a_lire_si", "a_eviter_si", "prerequis", "controverses", "confiance"],
    "additionalProperties": False,
}

SYNTHESE = {
    "type": "object",
    "properties": {
        "resume_court": {"type": "string", "description": "3 phrases maximum."},
        "resume_structure": {
            "type": "array", "minItems": 3, "maxItems": 8,
            "items": {"type": "object", "properties": {
                "section": {"type": "string"},
                "contenu": {"type": "string"},
                "pages": {"type": "string"}},
                "required": ["section", "contenu", "pages"], "additionalProperties": False}},
        "a_retenir": {"type": "array", "minItems": 3, "maxItems": 7, "items": {"type": "string"}},
        "questions_ouvertes": {"type": "array", "items": {"type": "string"},
            "description": "Ce que le texte laisse sans réponse — matière à discussion."}
    },
    "required": ["resume_court", "resume_structure", "a_retenir", "questions_ouvertes"],
    "additionalProperties": False,
}

QUIZ = {
    "type": "object",
    "properties": {
        "questions": {
            "type": "array", "minItems": 4, "maxItems": 10,
            "items": {"type": "object", "properties": {
                "question": {"type": "string"},
                "type": {"type": "string", "enum": ["qcm", "vrai_faux", "ouverte"]},
                "difficulte": {"type": "string", "enum": ["rappel", "comprehension", "analyse"]},
                "options": {"type": "array", "items": {"type": "string"},
                            "description": "4 options pour un QCM, 2 pour vrai/faux, [] pour une ouverte."},
                "reponse": {"type": "string"},
                "justification": {"type": "string",
                    "description": "Pourquoi cette réponse, en s'appuyant sur le texte."},
                "extrait_source": {"type": "string",
                    "description": "Citation littérale du livre qui justifie la réponse."},
                "page": {"type": ["integer", "null"]},
                "concept": {"type": "string"}},
                "required": ["question", "type", "difficulte", "options", "reponse",
                             "justification", "extrait_source", "page", "concept"],
                "additionalProperties": False}}
    },
    "required": ["questions"],
    "additionalProperties": False,
}

FLASHCARDS = {
    "type": "object",
    "properties": {
        "cartes": {
            "type": "array", "minItems": 5, "maxItems": 20,
            "items": {"type": "object", "properties": {
                "recto": {"type": "string"}, "verso": {"type": "string"},
                "concept": {"type": "string"}, "page": {"type": ["integer", "null"]}},
                "required": ["recto", "verso", "concept", "page"], "additionalProperties": False}}
    },
    "required": ["cartes"], "additionalProperties": False,
}

SCHEMAS = {"fiche_lecture": FICHE, "synthese": SYNTHESE, "quiz": QUIZ, "flashcards": FLASHCARDS}


# --- Citations : des extraits vérifiés mot à mot contre le texte source.
# `texte` doit être une reprise exacte, sans quoi l'enregistrement échoue.
CITATION = {
    "type": "object",
    "additionalProperties": False,
    "required": ["citations"],
    "properties": {
        "citations": {
            "type": "array",
            "minItems": 1,
            "maxItems": 8,
            "items": {
                "type": "object",
                "additionalProperties": False,
                "required": ["texte", "page", "axe", "theme", "portee"],
                "properties": {
                    "texte": {"type": "string", "minLength": 40, "maxLength": 700},
                    "page": {"type": "integer"},
                    "axe": {"type": "string"},
                    "theme": {"type": "string", "maxLength": 80},
                    "portee": {"type": "string", "maxLength": 400},
                },
            },
        }
    },
}

# --- Compte rendu de chapitre : ce qu'un lecteur doit en retenir, et ce que
# le chapitre laisse de côté ou avance sans le démontrer.
COMPTE_RENDU = {
    "type": "object",
    "additionalProperties": False,
    "required": ["resume", "points_cles", "a_retenir"],
    "properties": {
        "resume": {"type": "string", "minLength": 200, "maxLength": 2000},
        "points_cles": {
            "type": "array", "minItems": 2, "maxItems": 7,
            "items": {"type": "string", "maxLength": 300},
        },
        "a_retenir": {"type": "string", "maxLength": 400},
        "reserves": {
            "type": "array", "maxItems": 4,
            "items": {"type": "string", "maxLength": 300},
            "description": "Ce que le chapitre affirme sans l'établir, ou passe sous silence.",
        },
        "pour_le_lecteur_africain": {"type": "string", "maxLength": 400},
    },
}

# --- Résumé exécutif : l'ouvrage en une page, pour décider de le lire.
RESUME_EXECUTIF = {
    "type": "object",
    "additionalProperties": False,
    "required": ["en_une_phrase", "argument", "structure", "verdict"],
    "properties": {
        "en_une_phrase": {"type": "string", "maxLength": 300},
        "argument": {"type": "string", "minLength": 300, "maxLength": 2500},
        "structure": {
            "type": "array", "minItems": 2, "maxItems": 12,
            "items": {"type": "string", "maxLength": 200},
        },
        "verdict": {"type": "string", "maxLength": 600},
        "temps_de_lecture_min": {"type": "integer"},
    },
}

SCHEMAS.update({
    "citation": CITATION,
    "compte_rendu": COMPTE_RENDU,
    "resume_executif": RESUME_EXECUTIF,
})
