"""Le pack d'un ouvrage : tout ce qu'ASCENDA en sait, en un seul objet.

Deux usages, une seule source.

- **Hors ligne.** L'application rapatrie le pack et le garde sur le téléphone.
  Fiche, idées-force, citations avec leurs pages, quiz jouables, plan de
  lecture : tout reste utilisable sans réseau. Sur une connexion intermittente,
  c'est cette fonction qui décide de l'usage réel.
- **Export PDF.** Le même pack, mis en page pour être imprimé ou partagé.

Les droits s'appliquent ici comme partout : sur un ouvrage non redistribuable,
le pack contient la fiche, les citations et les quiz, jamais le texte intégral.
"""
from app.core.db import fetch_all, fetch_one
from app.core.errors import NotFound
from app.services.droits import droits


async def construire(document_id: str, *, avec_reponses: bool = False) -> dict:
    """Assemble le pack. `avec_reponses` n'est vrai que pour l'usage hors ligne :
    sans elles, l'application ne pourrait pas corriger un quiz sans réseau."""
    d = await fetch_one(
        """select d.id, coalesce(d.title_clean, d.title_raw) as titre, d.subtitle,
                  d.authors, d.year, d.publisher, d.page_count, d.language,
                  p.level, p.doc_type_norm, p.reading_time_min,
                  p.central_thesis, p.key_ideas, p.target_audience
             from document d
             left join document_pedagogy p on p.document_id = d.id
            where d.id = %s""",
        (document_id,),
    )
    if not d:
        raise NotFound("Cet ouvrage n'existe pas dans la bibliothèque.")

    dr = await droits(document_id)
    axes = await fetch_all(
        """select a.slug, a.label from document_axis da
             join axis a on a.id = da.axis_id
            where da.document_id = %s order by da.weight desc""",
        (document_id,),
    )
    fiche = await fetch_one(
        """select content from derivative
            where document_id = %s and kind = 'fiche_lecture' and superseded_by is null
            limit 1""",
        (document_id,),
    )
    chapitres = await fetch_all(
        """select c.id, c.ord, c.title, c.page_start, c.page_end, c.token_count
             from chapter c
            where c.document_id = %s and coalesce(c.token_count, 0) >= 300
            order by c.ord""",
        (document_id,),
    )
    lots_citations = await fetch_all(
        """select dv.chapter_id, dv.content, c.ord
             from derivative dv left join chapter c on c.id = dv.chapter_id
            where dv.document_id = %s and dv.kind = 'citation' and dv.superseded_by is null
            order by c.ord nulls last""",
        (document_id,),
    )
    lots_quiz = await fetch_all(
        """select dv.id, dv.chapter_id, dv.content, c.ord, c.title
             from derivative dv left join chapter c on c.id = dv.chapter_id
            where dv.document_id = %s and dv.kind = 'quiz' and dv.superseded_by is null
              and jsonb_array_length(dv.content->'questions') > 0
            order by c.ord nulls last""",
        (document_id,),
    )

    citations = [
        {
            "chapitre_id": str(l["chapter_id"]) if l["chapter_id"] else None,
            "texte": c.get("texte"),
            "page": c.get("page"),
            "theme": c.get("theme"),
            "portee": c.get("portee"),
        }
        for l in lots_citations
        for c in (l["content"] or {}).get("citations", [])
    ]

    quiz = []
    for l in lots_quiz:
        questions = []
        for i, q in enumerate((l["content"] or {}).get("questions", [])):
            question = {
                "index": i,
                "question": q.get("q"),
                "choix": q.get("choix", []),
                "niveau": q.get("niveau"),
                "page": q.get("page"),
            }
            if avec_reponses:
                # Sans la réponse et l'explication, un quiz hors ligne ne se
                # corrige pas. On les livre donc, en assumant qu'un lecteur qui
                # ouvre le fichier peut les lire : c'est un outil de travail,
                # pas un examen surveillé.
                question["reponse"] = q.get("reponse")
                question["explication"] = q.get("explication")
            questions.append(question)
        quiz.append(
            {
                "quiz_id": str(l["id"]),
                "chapitre_id": str(l["chapter_id"]) if l["chapter_id"] else None,
                "chapitre": l["title"],
                "questions": questions,
            }
        )

    return {
        "version": 1,
        "ouvrage": {
            "id": str(d["id"]),
            "titre": d["titre"],
            "sous_titre": d["subtitle"],
            "auteurs": d["authors"] or [],
            "annee": d["year"],
            "editeur": d["publisher"],
            "pages": d["page_count"],
            "langue": d["language"],
            "niveau": d["level"],
            "type": d["doc_type_norm"],
            "duree_min": d["reading_time_min"],
            "public": d["target_audience"],
            "these_centrale": d["central_thesis"],
            "idees_force": d["key_ideas"] or [],
            "axes": [{"slug": a["slug"], "label": a["label"]} for a in axes],
        },
        "droits": {
            "lecture_integrale": dr.texte_integral,
            "statut": dr.statut,
            "message": dr.message(),
        },
        "fiche_lecture": fiche["content"] if fiche else None,
        "sommaire": [
            {
                "id": str(c["id"]),
                "ordre": c["ord"],
                "titre": c["title"],
                "page_debut": c["page_start"],
                "page_fin": c["page_end"],
                "duree_min": max(1, round((c["token_count"] or 0) * 0.75 / 200)),
            }
            for c in chapitres
        ],
        "citations": citations,
        "quiz": quiz,
        "compteurs": {
            "chapitres": len(chapitres),
            "citations": len(citations),
            "questions": sum(len(q["questions"]) for q in quiz),
        },
    }
