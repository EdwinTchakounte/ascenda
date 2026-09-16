"""Bibliothèque : liste filtrable, fiche d'ouvrage, sommaire."""
from typing import Annotated, Literal

from fastapi import APIRouter, Query
from fastapi.responses import Response

from app.core.auteurs import auteurs
from app.core.db import execute, fetch_all, fetch_one
from app.core.deps import OptionalUser, ClientApplication
from app.core.errors import NotFound
from app.services import export_pdf, pack as service_pack
from app.services.droits import droits

router = APIRouter(prefix="/bibliotheque", tags=["Bibliothèque"])


@router.get("", summary="Liste des ouvrages, filtrable")
async def lister(
    user: OptionalUser,
    axe: Annotated[str | None, Query(description="slug d'axe")] = None,
    niveau: Annotated[Literal["debutant", "intermediaire", "avance"] | None, Query()] = None,
    type_ouvrage: Annotated[str | None, Query(alias="type")] = None,
    duree_max: Annotated[int | None, Query(description="minutes de lecture")] = None,
    lecture_integrale: Annotated[bool | None, Query()] = None,
    q: Annotated[str | None, Query(description="recherche sur le titre et l'auteur")] = None,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=100)] = 24,
):
    where = ["d.takedown_status = 'none'"]
    params: list = []
    if axe:
        # Un pôle (« Agriculture et élevage ») filtre sur tous ses sous-axes.
        where.append(
            "exists (select 1 from document_axis da join axis a on a.id = da.axis_id "
            "left join axis pa on pa.id = a.parent_id "
            "where da.document_id = d.id and (a.slug = %s or pa.slug = %s))"
        )
        params.extend([axe, axe])
    if niveau:
        where.append("p.level = %s")
        params.append(niveau)
    if type_ouvrage:
        where.append("p.doc_type_norm = %s")
        params.append(type_ouvrage)
    if duree_max:
        where.append("coalesce(p.reading_time_min, 0) <= %s")
        params.append(duree_max)
    if lecture_integrale is not None:
        where.append("d.redistributable = %s")
        params.append(lecture_integrale)
    if q:
        where.append(
            "(unaccent(coalesce(d.title_clean, d.title_raw)) ilike unaccent(%s) "
            "or unaccent(d.authors::text) ilike unaccent(%s))"
        )
        params += [f"%{q}%", f"%{q}%"]

    clause = " and ".join(where)
    total = await fetch_one(
        f"""select count(*) as n from document d
            left join document_pedagogy p on p.document_id = d.id
            where {clause}""",
        params,
    )
    lignes = await fetch_all(
        f"""select d.id, coalesce(d.title_clean, d.title_raw) as titre, d.subtitle, d.authors,
                   d.year, d.publisher, d.page_count, d.language, d.redistributable,
                   p.level, p.doc_type, p.doc_type_norm, p.reading_time_min, p.central_thesis,
                   (select count(*) from chapter c where c.document_id = d.id) as nb_chapitres,
                   (select coalesce(json_agg(json_build_object('slug', a.slug, 'label', a.label)
                                             order by da.weight desc), '[]'::json)
                      from document_axis da join axis a on a.id = da.axis_id
                     where da.document_id = d.id) as axes,
                   exists (select 1 from derivative dv where dv.document_id = d.id
                           and dv.kind = 'fiche_lecture' and dv.superseded_by is null) as a_fiche,
                   exists (select 1 from derivative dv where dv.document_id = d.id
                           and dv.kind = 'quiz' and dv.superseded_by is null
                           and jsonb_array_length(dv.content->'questions') > 0) as a_quiz
            from document d
            left join document_pedagogy p on p.document_id = d.id
            where {clause}
            order by titre
            limit %s offset %s""",
        params + [par_page, (page - 1) * par_page],
    )
    return {
        "total": total["n"],
        "page": page,
        "par_page": par_page,
        "ouvrages": [
            {
                "id": str(l["id"]),
                "titre": l["titre"],
                "sous_titre": l["subtitle"],
                "auteurs": auteurs(l["authors"]),
                "annee": l["year"],
                "editeur": l["publisher"],
                "pages": l["page_count"],
                "langue": l["language"],
                "niveau": l["level"],
                "type": l["doc_type_norm"],
                "type_detaille": l["doc_type"],
                "duree_min": l["reading_time_min"],
                "these": l["central_thesis"],
                "axes": l["axes"],
                "nb_chapitres": l["nb_chapitres"],
                "lecture_integrale": l["redistributable"],
                "a_fiche": l["a_fiche"],
                "a_quiz": l["a_quiz"],
            }
            for l in lignes
        ],
    }


@router.get("/filtres", summary="Valeurs disponibles pour les filtres")
async def filtres():
    niveaux = await fetch_all(
        "select level as v, count(*) as n from document_pedagogy where level is not null group by 1 order by 1"
    )
    types = await fetch_all(
        "select doc_type_norm as v, count(*) as n from document_pedagogy where doc_type_norm is not null group by 1 order by 2 desc"
    )
    axes = await fetch_all(
        """select a.slug as v, a.label, count(da.document_id) as n
           from axis a left join document_axis da on da.axis_id = a.id
           where a.slug not like '\\_%'
           group by a.id order by a.sort_order"""
    )
    return {
        "niveaux": [{"valeur": r["v"], "nb": r["n"]} for r in niveaux],
        "types": [{"valeur": r["v"], "nb": r["n"]} for r in types],
        "axes": [{"valeur": r["v"], "label": r["label"], "nb": r["n"]} for r in axes],
    }


@router.get("/{document_id}", summary="Fiche d'un ouvrage")
async def fiche(document_id: str, user: OptionalUser, client_app: ClientApplication):
    d = await fetch_one(
        """select d.*, coalesce(d.title_clean, d.title_raw) as titre,
                  p.level, p.doc_type, p.doc_type_norm, p.target_audience, p.reading_time_min,
                  p.concept_density, p.central_thesis, p.key_ideas
           from document d
           left join document_pedagogy p on p.document_id = d.id
           where d.id = %s""",
        (document_id,),
    )
    if not d:
        raise NotFound("Cet ouvrage n'existe pas dans la bibliothèque.")

    dr = await droits(document_id, user, client_app)
    axes = await fetch_all(
        """select a.slug, a.label, da.weight, da.assigned_by
           from document_axis da join axis a on a.id = da.axis_id
           where da.document_id = %s order by da.weight desc""",
        (document_id,),
    )
    # Les trois dérivés d'ouvrage arrivent en une requête. Chargés un par un,
    # c'était trois allers-retours pour une page que le lecteur ouvre souvent.
    lus = await fetch_all(
        """select distinct on (kind) kind, content, generated_at from derivative
           where document_id = %s and superseded_by is null
             and kind in ('fiche_lecture', 'synthese', 'resume_executif')
           order by kind, generated_at desc""",
        (document_id,),
    )
    derives = {l["kind"]: l["content"] for l in lus}
    fiche_lecture = {"content": derives["fiche_lecture"]} if "fiche_lecture" in derives else None
    stats = await fetch_one(
        """select
             (select count(*) from chapter where document_id = %(d)s) as chapitres,
             (select count(*) from derivative where document_id = %(d)s and kind = 'quiz'
                and superseded_by is null) as lots_quiz,
             (select coalesce(sum(jsonb_array_length(content->'questions')), 0)
                from derivative where document_id = %(d)s and kind = 'quiz'
                and superseded_by is null) as questions,
             (select coalesce(sum(jsonb_array_length(content->'citations')), 0)
                from derivative where document_id = %(d)s and kind = 'citation'
                and superseded_by is null) as citations""",
        {"d": document_id},
    )
    # Fait dialoguer avec : les ouvrages qui prennent position sur la même controverse.
    controverses = await fetch_all(
        """select c.id, c.question, cp2.stance, cp2.summary,
                  d2.id as autre_id, coalesce(d2.title_clean, d2.title_raw) as autre_titre
           from controversy_position cp
           join controversy c on c.id = cp.controversy_id
           join controversy_position cp2 on cp2.controversy_id = c.id and cp2.document_id <> cp.document_id
           join document d2 on d2.id = cp2.document_id
           where cp.document_id = %s""",
        (document_id,),
    )
    prerequis = await fetch_all(
        """select d2.id, coalesce(d2.title_clean, d2.title_raw) as titre, dp.strength
           from document_prerequisite dp join document d2 on d2.id = dp.prerequisite_id
           where dp.document_id = %s""",
        (document_id,),
    )

    return {
        "id": str(d["id"]),
        "titre": d["titre"],
        "titre_original": d["title_raw"],
        "sous_titre": d["subtitle"],
        "auteurs": auteurs(d["authors"]),
        "annee": d["year"],
        "editeur": d["publisher"],
        "isbn": d["isbn"],
        "collection": d["collection"],
        "traducteur": d["translator"],
        "pages": d["page_count"],
        "langue": d["language"],
        "biblio_fiable": (d["biblio_confidence"] or 0) >= 0.6 or d["biblio_validated"],
        "axes": [
            {"slug": a["slug"], "label": a["label"], "poids": a["weight"], "source": a["assigned_by"]}
            for a in axes
        ],
        "pedagogie": {
            "niveau": d["level"],
            "type": d["doc_type_norm"],
            "type_detaille": d["doc_type"],
            "public": d["target_audience"],
            "duree_min": d["reading_time_min"],
            "densite": d["concept_density"],
            "these_centrale": d["central_thesis"],
            "idees_force": d["key_ideas"] or [],
        },
        "fiche_lecture": fiche_lecture["content"] if fiche_lecture else None,
        # Nos textes, pas ceux de l'auteur : une synthèse et un résumé exécutif
        # sont des oeuvres dérivées que nous écrivons. Le plafond de citation ne
        # les gouverne pas, il ne gouverne que les extraits littéraux.
        "synthese": derives.get("synthese"),
        "resume_executif": derives.get("resume_executif"),
        "droits": {
            "lecture_integrale": dr.texte_integral,
            # Le PDF d'origine s'ouvre dans l'application, sous la même règle.
            "pdf": dr.texte_integral and bool(d["storage_key"])
                   and (d["mime"] or "application/pdf") == "application/pdf",
            # La taille du fichier : un PDF de 90 Mo ne se télécharge pas sur un
            # forfait mobile sans prévenir.
            "pdf_octets": d["size_bytes"] if dr.texte_integral else None,
            # Lisible en entier dans l'application seulement : pas d'export du
            # livre, et un hors-ligne gardé chiffré par l'application.
            "application_seulement": dr.lecture_application and not dr.redistributable,
            "hors_ligne_integral": dr.hors_ligne_integral,
            "statut": dr.statut,
            "plafond_extrait": dr.plafond_extrait,
            "message": dr.message(),
        },
        "contenu": {
            "chapitres": stats["chapitres"],
            "lots_quiz": stats["lots_quiz"],
            "questions": stats["questions"],
            "citations": stats["citations"],
        },
        "prerequis": [
            {"id": str(p["id"]), "titre": p["titre"], "force": p["strength"]} for p in prerequis
        ],
        "dialogue_avec": [
            {
                "controverse": c["question"],
                "ouvrage_id": str(c["autre_id"]),
                "ouvrage": c["autre_titre"],
                "position": c["stance"],
                "resume": c["summary"],
            }
            for c in controverses
        ],
    }


@router.get("/{document_id}/sommaire", summary="Sommaire par chapitre")
async def sommaire(document_id: str, user: OptionalUser):
    if not await fetch_one("select 1 from document where id = %s", (document_id,)):
        raise NotFound("Cet ouvrage n'existe pas dans la bibliothèque.")
    chapitres = await fetch_all(
        """select c.id, c.ord, c.title, c.page_start, c.page_end, c.token_count,
                  (select count(*) from chunk k where k.chapter_id = c.id) as nb_passages,
                  (select coalesce(sum(jsonb_array_length(dv.content->'questions')), 0)
                     from derivative dv where dv.chapter_id = c.id and dv.kind = 'quiz'
                     and dv.superseded_by is null) as nb_questions
           from chapter c where c.document_id = %s order by c.ord""",
        (document_id,),
    )
    return [
        {
            "id": str(c["id"]),
            "ordre": c["ord"],
            "titre": c["title"],
            "page_debut": c["page_start"],
            "page_fin": c["page_end"],
            "tokens": c["token_count"],
            # ~200 mots/min, un token ≈ 0,75 mot : la durée sert au découpage en séances.
            "duree_min": max(1, round((c["token_count"] or 0) * 0.75 / 200)) if c["token_count"] else None,
            "nb_passages": c["nb_passages"],
            "nb_questions": c["nb_questions"],
        }
        for c in chapitres
    ]


@router.get("/{document_id}/pack", summary="Le pack complet d'un ouvrage")
async def pack_complet(document_id: str, user: OptionalUser, client_app: ClientApplication):
    """Tout ce qu'ASCENDA sait de cet ouvrage, en un seul appel.

    Destiné au téléchargement hors ligne : l'application le garde sur le
    téléphone et reste utilisable sans réseau, y compris pour passer les quiz.
    Les réponses sont donc incluses, sans quoi rien ne se corrige hors ligne.
    """
    # Le texte intégral n'y entre que pour un lecteur qui peut le lire, depuis
    # l'application : c'est elle qui le garde chiffré pour la lecture hors ligne.
    dr = await droits(document_id, user, client_app)
    jusqu = None
    if dr.hors_ligne_integral and user and not dr.redistributable:
        from app.services import acces

        jusqu = (await acces.etat(user)).get("jusqu_au")
    p = await service_pack.construire(document_id, avec_reponses=True, avec_texte=dr.hors_ligne_integral,
                                      acces_jusqu_au=jusqu)
    if user:
        await execute(
            """insert into progress_event (user_id, document_id, type, payload)
               values (%s, %s, 'opened_doc', '{"pack": true}'::jsonb)""",
            (user["id"], document_id),
        )
    return p


@router.get("/{document_id}/export.pdf", summary="Export PDF d'un ouvrage")
async def export(
    document_id: str,
    user: OptionalUser,
    complet: Annotated[bool, Query(description="toutes les citations et questions")] = False,
):
    """Le même pack, mis en page pour être imprimé ou partagé.

    Par défaut, un compagnon de lecture d'une dizaine de pages. `complet=true`
    rend l'intégralité, ce qui peut représenter plus de quarante pages et
    plusieurs secondes de fabrication.
    """
    p = await service_pack.construire(document_id, avec_reponses=True)
    octets = export_pdf.produire(p, complet=complet)
    nom = _nom_fichier(p["ouvrage"]["titre"])
    return Response(
        content=octets,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{nom}"'},
    )


def _nom_fichier(titre: str) -> str:
    import re
    import unicodedata

    sans_accents = unicodedata.normalize("NFKD", titre or "ouvrage")
    sans_accents = sans_accents.encode("ascii", "ignore").decode("ascii")
    propre = re.sub(r"[^A-Za-z0-9]+", "-", sans_accents).strip("-").lower()[:60]
    return f"ascenda-{propre or 'ouvrage'}.pdf"
