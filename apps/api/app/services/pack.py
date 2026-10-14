"""Le pack d'un ouvrage : tout ce qu'ASCENDA en sait, en un seul objet."""
from app.core.auteurs import auteurs
from app.core.db import fetch_all, fetch_one
from app.core.errors import NotFound
from app.services.droits import droits


VALIDITE_HORS_LIGNE_JOURS = 30


async def construire(document_id: str, *, avec_reponses: bool = False, avec_texte: bool = False,
                     acces_jusqu_au=None) -> dict:
    """Assemble le pack. `avec_reponses` n'est vrai que pour l'usage hors ligne : sans elles,
    l'application ne pourrait pas corriger un quiz sans réseau.
    """
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

    lecture = None
    if avec_texte:
        from app.services.passages import lisibles

        passages = await fetch_all(
            """select chapter_id, page_start, page_end, text from chunk
                where document_id = %s and chapter_id is not null order by ord""",
            (document_id,),
        )
        par_chapitre: dict[str, list[dict]] = {}
        for p in passages:
            par_chapitre.setdefault(str(p["chapter_id"]), []).append(p)
        lecture = []
        for cid, ps in par_chapitre.items():
            textes = lisibles([p["text"] for p in ps])
            lecture.append({
                "chapitre_id": cid,
                "passages": [
                    {"page_debut": p["page_start"], "page_fin": p["page_end"], "texte": t}
                    for p, t in zip(ps, textes) if t
                ],
            })

    valable = None
    if lecture is not None:
        from datetime import datetime, timedelta, timezone

        valable = datetime.now(timezone.utc) + timedelta(days=VALIDITE_HORS_LIGNE_JOURS)
        if acces_jusqu_au is not None:
            valable = min(valable, acces_jusqu_au)

    return {
        "version": 1,
        # Le texte des chapitres, quand ce lecteur peut le garder hors ligne.
        "lecture": lecture,
        "lecture_valable_jusqu_au": valable.isoformat() if valable else None,
        "ouvrage": {
            "id": str(d["id"]),
            "titre": d["titre"],
            "sous_titre": d["subtitle"],
            "auteurs": auteurs(d["authors"]),
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
