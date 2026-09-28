"""Le tableau de bord d'exploitation.

Ce qu'on veut savoir chaque matin : combien de comptes ouverts hier, combien de
paiements passés, lesquels sont restés en chemin, combien d'abonnements
arrivent à échéance, et si les courriels partent.

Tout est déjà en base : `payment_event` trace chaque étape de chaque paiement,
`email_log` chaque message, `progress_event` chaque action de lecture. Ces
routes ne calculent rien de neuf, elles rassemblent.

Le tableau de bord tient en **un seul appel**. Une page qui en fait douze met
douze fois plus de temps à dire la même chose, et échoue douze fois plus
souvent.
"""
from datetime import datetime, timezone
from typing import Annotated, Literal

from pathlib import Path

from fastapi import APIRouter, File, Form, Query, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

import logging

from app.core.config import settings
from app.core.db import execute, fetch_all, fetch_one
from app.core.deps import AdminUser
from app.core.errors import Conflict, NotFound
from app.services import exploitation, travaux

log = logging.getLogger("ascenda.admin")

router = APIRouter(prefix="/admin", tags=["Administration"])

# Les listes de la console sont paginées, comme celles du produit. Sans cela,
# le corpus renvoyait ses deux cents lignes et le journal des courriels les
# siennes à chaque ouverture : le temps de chargement grandit avec le succès,
# ce qui est exactement le mauvais sens.
PAR_PAGE = 40


def bornes(page: int, par_page: int) -> tuple[int, int]:
    return par_page, (page - 1) * par_page


def enveloppe(lignes: list, total: int, page: int, par_page: int) -> dict:
    """Toujours la même forme : le client sait s'il reste quelque chose sans
    avoir à deviner. `pages` évite de le faire recalculer partout."""
    return {
        "total": total,
        "page": page,
        "par_page": par_page,
        "pages": max(1, -(-total // par_page)),
        "lignes": lignes,
    }


class ReglageIn(BaseModel):
    valeur: dict


class DroitsIn(BaseModel):
    """Ce qu'on peut changer sur un ouvrage depuis le tableau de bord.

    Uniquement ses droits. Le titre, les auteurs et le texte viennent du
    pipeline et de `data/` : les corriger ici les ferait diverger de leur
    source, et le prochain import les écraserait sans prévenir.
    """

    redistributable: bool | None = None
    max_excerpt_chars: int | None = Field(default=None, ge=0, le=1_000_000)
    takedown_status: Literal["none", "pending", "removed"] | None = None
    # Lisible en entier dans l'application seulement, par un abonné (migration 019).
    lecture_application: bool | None = None


class GabaritIn(BaseModel):
    objet: str | None = Field(default=None, min_length=1, max_length=300)
    corps_html: str | None = None
    corps_texte: str | None = None
    actif: bool | None = None


class CompteIn(BaseModel):
    is_active: bool | None = None
    est_admin: bool | None = None


class AxeIn(BaseModel):
    # Le raccourci sert d'adresse publique : il ne porte ni majuscule, ni
    # accent, ni espace, et il ne change plus une fois posé.
    slug: str = Field(min_length=3, max_length=80, pattern=r"^[a-z0-9][a-z0-9-]*$")
    label: str = Field(min_length=2, max_length=120)
    description: str | None = None
    ordre: int | None = None
    premium: bool = False


class AxePatch(BaseModel):
    label: str | None = Field(default=None, min_length=2, max_length=120)
    description: str | None = None
    ordre: int | None = None
    premium: bool | None = None


class TravailIn(BaseModel):
    type: Literal["ingestion", "structure", "passages", "vecteurs", "derive", "import_data"]
    charge: dict = Field(default_factory=dict)
    document_id: str | None = None


@router.get("/tableau-de-bord", summary="Tout ce qu'il faut voir le matin")
async def tableau_de_bord(user: AdminUser, jours: Annotated[int, Query(ge=1, le=365)] = 30):
    comptes = await fetch_one(
        """select
             count(*) as total,
             count(*) filter (where created_at >= date_trunc('day', now())) as aujourdhui,
             count(*) filter (where created_at >= date_trunc('day', now()) - make_interval(days => %s - 1)) as periode,
             -- La période précédente de même longueur. Un chiffre seul ne dit
             -- pas s'il monte : c'est la comparaison qui informe.
             count(*) filter (where created_at >= date_trunc('day', now()) - make_interval(days => %s * 2 - 1)
                                and created_at <  date_trunc('day', now()) - make_interval(days => %s - 1)) as precedent,
             count(*) filter (where plan <> 'free') as abonnes,
             count(*) filter (where not is_active) as desactives
           from app_user""",
        (jours, jours, jours),
    )
    # Un compte actif est un compte qui a fait quelque chose, pas un compte qui
    # existe. La différence est tout l'intérêt de la mesure.
    actifs = await fetch_one(
        """select
             count(distinct user_id) filter (where at >= now() - interval '1 day') as jour,
             count(distinct user_id) filter (where at >= now() - interval '7 days') as semaine,
             count(distinct user_id) filter (where at >= now() - interval '30 days') as mois
           from progress_event""",
    )
    paiements = await fetch_one(
        """select
             count(*) as total,
             count(*) filter (where statut = 'valide') as valides,
             count(*) filter (where statut = 'en_attente') as en_attente,
             count(*) filter (where statut = 'rejete') as rejetes,
             coalesce(sum(montant) filter (where statut = 'valide'), 0) as encaisse,
             coalesce(sum(montant) filter (where statut = 'valide'
                and created_at >= date_trunc('day', now()) - make_interval(days => %s - 1)), 0) as encaisse_periode,
             coalesce(sum(montant) filter (where statut = 'valide'
                and created_at >= date_trunc('day', now()) - make_interval(days => %s * 2 - 1)
                and created_at <  date_trunc('day', now()) - make_interval(days => %s - 1)), 0) as encaisse_precedent,
             coalesce(round(avg(montant) filter (where statut = 'valide')), 0) as panier_moyen
           from payment""",
        (jours, jours, jours),
    )
    # Un webhook arrivé sans paiement à qui le rattacher. C'est la première
    # chose à regarder quand quelqu'un affirme avoir payé.
    orphelins = await fetch_one(
        """select count(*) as n from payment_event
            where payment_id is null and type in ('webhook_orphelin', 'webhook_illisible')""",
    )
    abonnements = await fetch_one(
        """select
             count(*) filter (where status = 'active' and current_end > now()) as actifs,
             count(*) filter (where status = 'active' and current_end > now()
                and current_end <= now() + interval '7 days') as bientot_echus,
             count(*) filter (where status = 'expired') as expires
           from subscription""",
    )
    courriels = await fetch_one(
        """select
             count(*) filter (where statut = 'envoye') as envoyes,
             count(*) filter (where statut = 'simule') as simules,
             count(*) filter (where statut = 'echec') as echecs,
             count(*) filter (where created_at >= date_trunc('day', now()) - make_interval(days => %s - 1)) as periode
           from email_log""",
        (jours,),
    )
    # La courbe des inscriptions, un point par jour. `generate_series` remplit
    # les jours vides : une courbe qui saute les zéros ment sur la pente.
    # Deux sous-requêtes par jour, et non deux jointures.
    #
    # Joindre `app_user` et `payment` sur le même jour produit leur produit
    # cartésien : un jour à 116 comptes et 42 paiements donnait 4 872 comptes.
    # La courbe annonçait 106 731 inscriptions là où la base en portait 789.
    courbe = await fetch_all(
        """select d::date as jour,
                  (select count(*) from app_user u
                    where date_trunc('day', u.created_at) = d) as comptes,
                  (select count(*) from payment p
                    where date_trunc('day', p.created_at) = d
                      and p.statut = 'valide') as paiements,
                  (select coalesce(sum(p.montant), 0) from payment p
                    where date_trunc('day', p.created_at) = d
                      and p.statut = 'valide') as encaisse,
                  (select count(distinct e.user_id) from progress_event e
                    where date_trunc('day', e.at) = d) as actifs
             from generate_series(
                    date_trunc('day', now()) - make_interval(days => %s - 1),
                    date_trunc('day', now()), interval '1 day') d
            order by d""",
        (jours,),
    )
    # Ce que les gens font, et non seulement combien ils sont. Cinq types
    # d'événements suffisent à dire si la plateforme est lue ou seulement
    # ouverte.
    activite = await fetch_all(
        """select type, count(*) as n, count(distinct user_id) as personnes
             from progress_event
            where at >= now() - make_interval(days => %s)
            group by type order by n desc""",
        (jours,),
    )
    # Les ouvrages les plus programmés. C'est la mesure la plus honnête de ce
    # qui sert : un ouvrage qu'on ouvre une fois pèse moins qu'un ouvrage que
    # le planificateur place dans des dizaines de parcours.
    ouvrages = await fetch_all(
        """select coalesce(nullif(d.title_clean, ''), d.title_raw) as titre,
                  count(*) as seances,
                  count(*) filter (where s.status = 'fait') as faites,
                  count(distinct c.user_axis_id) as parcours
             from session s
             join chronogram c on c.id = s.chronogram_id
             join document d on d.id = s.document_id
            where c.generated_at >= now() - make_interval(days => %s)
            group by d.id, titre
            order by seances desc limit 8""",
        (jours,),
    )
    axes_choisis = await fetch_all(
        """select a.label, a.slug,
                  count(*) as choix,
                  count(*) filter (where ua.created_at >= date_trunc('day', now()) - make_interval(days => %s - 1)) as periode
             from user_axis ua join axis a on a.id = ua.axis_id
            group by a.id, a.label, a.slug
            order by choix desc limit 8""",
        (jours,),
    )
    # L'entonnoir. Chaque marche perdue est une marche à réparer, et on ne sait
    # laquelle qu'en les voyant côte à côte.
    entonnoir = await fetch_one(
        """select
             (select count(*) from app_user) as comptes,
             (select count(distinct user_id) from user_axis) as diagnostiques,
             (select count(distinct ua.user_id)
                from chronogram c join user_axis ua on ua.id = c.user_axis_id) as plans,
             (select count(distinct ua.user_id)
                from session s
                join chronogram c on c.id = s.chronogram_id
                join user_axis ua on ua.id = c.user_axis_id
               where s.status = 'fait') as en_marche,
             (select count(*) from app_user where plan <> 'free') as abonnes""",
    )
    plans = await fetch_all(
        """select plan, count(*) as n from app_user group by plan order by n desc""",
    )
    corpus = await fetch_one(
        """select
             (select count(*) from document where takedown_status = 'none') as ouvrages,
             (select count(*) from chunk) as passages,
             (select count(*) filter (where embedding is not null) from chunk) as vectorises,
             (select count(*) from derivative where kind = 'quiz' and superseded_by is null) as quiz""",
    )
    return {
        "periode_jours": jours,
        "comptes": dict(comptes or {}),
        "actifs": dict(actifs or {}),
        "paiements": {**dict(paiements or {}), "orphelins": (orphelins or {}).get("n", 0)},
        "abonnements": dict(abonnements or {}),
        "courriels": dict(courriels or {}),
        "corpus": dict(corpus or {}),
        "courbe": [
            {"jour": str(c["jour"]), "comptes": c["comptes"], "paiements": c["paiements"],
             "encaisse": int(c["encaisse"] or 0), "actifs": c["actifs"]}
            for c in courbe
        ],
        "activite": [dict(a) for a in activite],
        "ouvrages": [dict(o) for o in ouvrages],
        "axes_choisis": [dict(a) for a in axes_choisis],
        "entonnoir": dict(entonnoir or {}),
        "plans": [dict(p) for p in plans],
        "exploitation": await exploitation.etat(),
    }


@router.get("/paiements", summary="Les paiements, du plus récent")
async def paiements(
    user: AdminUser,
    statut: Annotated[str | None, Query(pattern="^(en_attente|valide|rejete)$")] = None,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=200)] = PAR_PAGE,
):
    where, params = ["true"], []
    if statut:
        where.append("p.statut = %s")
        params.append(statut)
    compte = await fetch_one(
        f"select count(*) as n from payment p where {' and '.join(where)}", params
    )
    limite, saut = bornes(page, par_page)
    lignes = await fetch_all(
        f"""select p.id, p.statut, p.montant, p.devise, p.periode_mois, p.telephone,
                   p.reseau, p.reference_externe, p.motif_rejet, p.created_at,
                   p.date_validation, u.email
              from payment p join app_user u on u.id = p.user_id
             where {' and '.join(where)}
             order by p.created_at desc limit %s offset %s""",
        params + [limite, saut],
    )
    return enveloppe([
        {
            "id": str(l["id"]),
            "email": l["email"],
            "statut": l["statut"],
            "montant": l["montant"],
            "devise": l["devise"],
            "periode_mois": l["periode_mois"],
            "telephone": l["telephone"],
            "reseau": l["reseau"],
            "reference": l["reference_externe"],
            "motif_rejet": l["motif_rejet"],
            "cree_le": l["created_at"],
            "valide_le": l["date_validation"],
        }
        for l in lignes
    ], compte["n"], page, par_page)


@router.get("/webhooks-orphelins", summary="Les notifications qu'on n'a pas su rattacher")
async def orphelins(
    user: AdminUser,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=200)] = PAR_PAGE,
):
    """Le premier endroit à regarder quand quelqu'un affirme avoir payé.

    Un webhook qui n'a trouvé aucun paiement est conservé avec un identifiant
    nul plutôt que jeté : c'est la seule trace de l'argent de quelqu'un.
    """
    compte = await fetch_one(
        "select count(*) as n from payment_event where payment_id is null")
    limite, saut = bornes(page, par_page)
    lignes = await fetch_all(
        """select id, type, source, strategie, payload, at from payment_event
            where payment_id is null order by at desc limit %s offset %s""",
        (limite, saut),
    )
    return enveloppe([
        {"id": str(l["id"]), "type": l["type"], "source": l["source"],
         "strategie": l["strategie"], "details": l["payload"], "le": l["at"]}
        for l in lignes
    ], compte["n"], page, par_page)


@router.get("/utilisateurs", summary="Chercher un compte")
async def utilisateurs(
    user: AdminUser,
    q: Annotated[str | None, Query(min_length=2)] = None,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=200)] = PAR_PAGE,
):
    where, params = ["true"], []
    if q:
        where.append("(u.email ilike %s or u.display_name ilike %s)")
        params += [f"%{q}%", f"%{q}%"]
    compte = await fetch_one(
        f"select count(*) as n from app_user u where {' and '.join(where)}", params)
    limite, saut = bornes(page, par_page)
    lignes = await fetch_all(
        f"""select u.id, u.email, u.display_name, u.plan, u.plan_until, u.is_active,
                   u.created_at, u.last_login_at,
                   (select count(*) from payment p
                     where p.user_id = u.id and p.statut = 'valide') as paiements,
                   (select count(*) from progress_event pe where pe.user_id = u.id) as actions
              from app_user u
             where {' and '.join(where)}
             order by u.created_at desc limit %s offset %s""",
        params + [limite, saut],
    )
    return enveloppe([
        {
            "id": str(l["id"]),
            "email": l["email"],
            "nom": l["display_name"],
            "plan": l["plan"],
            "plan_jusqu_au": l["plan_until"],
            "actif": l["is_active"],
            "inscrit_le": l["created_at"],
            "derniere_connexion": l["last_login_at"],
            "paiements": l["paiements"],
            "actions": l["actions"],
        }
        for l in lignes
    ], compte["n"], page, par_page)


@router.get("/courriels", summary="Le journal des envois")
async def courriels(
    user: AdminUser,
    statut: Annotated[str | None, Query(pattern="^(en_attente|envoye|simule|echec)$")] = None,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=200)] = PAR_PAGE,
):
    where, params = ["true"], []
    if statut:
        where.append("statut = %s")
        params.append(statut)
    compte = await fetch_one(
        f"select count(*) as n from email_log where {' and '.join(where)}", params)
    limite, saut = bornes(page, par_page)
    lignes = await fetch_all(
        f"""select template, destinataire, objet, statut, erreur, created_at
              from email_log where {' and '.join(where)}
             order by created_at desc limit %s offset %s""",
        params + [limite, saut],
    )
    return enveloppe([
        {"gabarit": l["template"], "destinataire": l["destinataire"], "objet": l["objet"],
         "statut": l["statut"], "erreur": l["erreur"], "le": l["created_at"]}
        for l in lignes
    ], compte["n"], page, par_page)


@router.get("/reglages", summary="Les trois interrupteurs")
async def lire_reglages(user: AdminUser):
    lignes = await fetch_all("select cle, valeur, description, updated_at from reglage order by cle")
    return [
        {"cle": l["cle"], "valeur": l["valeur"], "description": l["description"],
         "modifie_le": l["updated_at"]}
        for l in lignes
    ]


@router.post("/reglages/{cle}", summary="Actionner un interrupteur")
async def poser_reglage(cle: str, data: ReglageIn, user: AdminUser):
    """Bascule un réglage sans passer par SQL.

    C'est tout l'intérêt du tableau de bord : ouvrir une période de lancement ou
    lever une maintenance depuis un téléphone, à l'heure où l'on n'a pas de
    terminal sous la main.
    """
    ligne = await fetch_one("select 1 from reglage where cle = %s", (cle,))
    if not ligne:
        raise NotFound("Ce réglage n'existe pas.")
    if cle == "parrainage":
        v = data.valeur
        try:
            pourcent, validite = int(v.get("pourcent")), int(v.get("validite_jours"))
        except (TypeError, ValueError):
            pourcent = validite = 0
        if not (1 <= pourcent <= 90 and 1 <= validite <= 730):
            raise Conflict("Réduction entre 1 et 90 %, validité entre 1 et 730 jours.")
        data.valeur = {"actif": bool(v.get("actif")), "pourcent": pourcent, "validite_jours": validite}
    import json as _json

    await execute(
        "update reglage set valeur = %s::jsonb, updated_at = now() where cle = %s",
        (_json.dumps(data.valeur), cle),
    )
    exploitation.oublier()
    return {"cle": cle, "valeur": data.valeur}


# --------------------------------------------------------------- le corpus

@router.get("/corpus", summary="Les ouvrages et leur état de production")
async def corpus(
    user: AdminUser,
    q: Annotated[str | None, Query(min_length=2)] = None,
    axe: Annotated[str | None, Query()] = None,
    manque: Annotated[bool, Query()] = False,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=200)] = PAR_PAGE,
):
    """L'état de chaque ouvrage, en une requête.

    Ce qu'on veut voir : ce qui est entré, ce qui est vectorisé, ce qui est
    dérivé, et ce qui manque. `manque=true` ne garde que les ouvrages
    incomplets, qui sont ceux sur lesquels il reste de l'argent à dépenser.
    """
    where, params = ["true"], []
    if q:
        where.append("(coalesce(d.title_clean, d.title_raw) ilike %s or d.authors::text ilike %s)")
        params += [f"%{q}%", f"%{q}%"]
    if axe:
        where.append(
            "exists (select 1 from document_axis da join axis a on a.id = da.axis_id "
            "where da.document_id = d.id and a.slug = %s)"
        )
        params.append(axe)

    # Le filtre des incomplets vit dans le WHERE, pas en Python : filtrer après
    # la pagination ne rendrait jamais une page pleine, et le total serait faux.
    if manque:
        where.append(
            """(select count(*) from derivative v where v.document_id = d.id
                  and v.kind = 'quiz' and v.superseded_by is null)
               < (select count(*) from chapter c where c.document_id = d.id
                    and coalesce(c.token_count,0) >= 300)
             or (select count(*) from derivative v where v.document_id = d.id
                   and v.kind = 'citation' and v.superseded_by is null)
                < (select count(*) from chapter c where c.document_id = d.id
                     and coalesce(c.token_count,0) >= 300)
             or not exists (select 1 from derivative v where v.document_id = d.id
                              and v.kind = 'fiche_lecture' and v.superseded_by is null)"""
        )
    compte = await fetch_one(
        f"select count(*) as n from document d where {' and '.join(where)}", params
    )
    limite, saut = bornes(page, par_page)
    lignes = await fetch_all(
        f"""select d.id, coalesce(d.title_clean, d.title_raw) as titre, d.authors, d.year,
                   d.page_count, d.language, d.redistributable, d.max_excerpt_chars,
                   d.takedown_status, d.ocr_status, d.has_text_layer, d.added_at,
                   (select count(*) from chapter c where c.document_id = d.id) as chapitres,
                   (select count(*) from chapter c where c.document_id = d.id
                      and coalesce(c.token_count,0) >= 300) as chapitres_utiles,
                   (select count(*) from chunk k where k.document_id = d.id) as passages,
                   (select count(*) from chunk k where k.document_id = d.id
                      and k.embedding is not null) as vectorises,
                   (select count(*) from derivative v where v.document_id = d.id
                      and v.kind = 'quiz' and v.superseded_by is null) as quiz,
                   (select count(*) from derivative v where v.document_id = d.id
                      and v.kind = 'citation' and v.superseded_by is null) as citations,
                   (select count(*) from derivative v where v.document_id = d.id
                      and v.kind = 'fiche_lecture' and v.superseded_by is null) as fiches,
                   (select coalesce(string_agg(a.label, ', ' order by da.weight desc), '')
                      from document_axis da join axis a on a.id = da.axis_id
                     where da.document_id = d.id) as axes
              from document d
             where {' and '.join(where)}
             order by coalesce(d.title_clean, d.title_raw) limit %s offset %s""",
        params + [limite, saut],
    )
    sortie = []
    for l in lignes:
        utiles = l["chapitres_utiles"] or 0
        incomplet = (l["quiz"] or 0) < utiles or (l["citations"] or 0) < utiles or not l["fiches"]
        sortie.append(
            {
                "id": str(l["id"]),
                "titre": l["titre"],
                "auteurs": l["authors"] or [],
                "annee": l["year"],
                "pages": l["page_count"],
                "langue": l["language"],
                "axes": l["axes"],
                "lecture_integrale": l["redistributable"],
                "plafond_extrait": l["max_excerpt_chars"],
                "retrait": l["takedown_status"],
                "ocr": l["ocr_status"],
                "chapitres": l["chapitres"],
                "chapitres_utiles": utiles,
                "passages": l["passages"],
                "vectorises": l["vectorises"],
                "quiz": l["quiz"],
                "citations": l["citations"],
                "fiches": l["fiches"],
                "complet": not incomplet,
                "entre_le": l["added_at"],
            }
        )
    return enveloppe(sortie, compte["n"], page, par_page)


@router.get("/corpus/{document_id}", summary="Un ouvrage en détail")
async def un_ouvrage(document_id: str, user: AdminUser):
    d = await fetch_one(
        """select d.*, coalesce(d.title_clean, d.title_raw) as titre from document d
            where d.id = %s""",
        (document_id,),
    )
    if not d:
        raise NotFound("Cet ouvrage n'existe pas.")
    axes = await fetch_all(
        """select a.slug, a.label, da.weight, da.assigned_by
             from document_axis da join axis a on a.id = da.axis_id
            where da.document_id = %s order by da.weight desc""",
        (document_id,),
    )
    derives = await fetch_all(
        """select kind, count(*) as lots, max(generated_at) as dernier,
                  coalesce(sum(cost_tokens_in), 0) as jetons_entree,
                  coalesce(sum(cost_tokens_out), 0) as jetons_sortie
             from derivative where document_id = %s and superseded_by is null
            group by kind order by kind""",
        (document_id,),
    )
    chapitres = await fetch_all(
        """select c.id, c.ord, c.title, c.page_start, c.page_end, c.token_count,
                  (select count(*) from derivative v where v.chapter_id = c.id
                     and v.kind = 'quiz' and v.superseded_by is null) as quiz,
                  (select count(*) from derivative v where v.chapter_id = c.id
                     and v.kind = 'citation' and v.superseded_by is null) as citations
             from chapter c where c.document_id = %s order by c.ord limit 200""",
        (document_id,),
    )
    return {
        "id": str(d["id"]),
        "titre": d["titre"],
        "sous_titre": d["subtitle"],
        "auteurs": d["authors"] or [],
        "annee": d["year"],
        "editeur": d["publisher"],
        "isbn": d["isbn"],
        "pages": d["page_count"],
        "langue": d["language"],
        "fichier": d["filename_original"],
        "entre_le": d["added_at"],
        "droits": {
            "lecture_integrale": d["redistributable"],
            "plafond_extrait": d["max_excerpt_chars"],
            "retrait": d["takedown_status"],
        },
        "axes": [
            {"slug": a["slug"], "label": a["label"], "poids": a["weight"], "source": a["assigned_by"]}
            for a in axes
        ],
        "derives": [
            {"type": v["kind"], "lots": v["lots"], "dernier": v["dernier"],
             "jetons_entree": v["jetons_entree"], "jetons_sortie": v["jetons_sortie"]}
            for v in derives
        ],
        "chapitres": [
            {"id": str(c["id"]), "ordre": c["ord"], "titre": c["title"],
             "page_debut": c["page_start"], "page_fin": c["page_end"],
             "tokens": c["token_count"], "quiz": c["quiz"], "citations": c["citations"]}
            for c in chapitres
        ],
    }


@router.patch("/corpus/{document_id}", summary="Changer les droits d'un ouvrage")
async def changer_droits(document_id: str, data: DroitsIn, user: AdminUser):
    """Seuls les droits se changent ici.

    Le titre, les auteurs et le texte viennent du pipeline et de `data/` : les
    corriger depuis cette page les ferait diverger de leur source, et le
    prochain import les écraserait sans prévenir.

    Poser `takedown_status` à autre chose que `none` retire immédiatement
    l'ouvrage de partout : bibliothèque, recherche, réponses de l'agent, plans
    de lecture déjà construits. C'est le geste qu'on fait quand un ayant droit
    écrit, et il n'a pas besoin d'être réversible pour être utile.
    """
    champs = {k: v for k, v in data.model_dump(exclude_none=True).items()}
    if not champs:
        raise NotFound("Rien à changer.")
    if not await fetch_one("select 1 from document where id = %s", (document_id,)):
        raise NotFound("Cet ouvrage n'existe pas.")
    colonnes = ", ".join(f"{c} = %s" for c in champs)
    await execute(
        f"update document set {colonnes} where id = %s",
        list(champs.values()) + [document_id],
    )
    return {"id": document_id, **champs}


# ------------------------------------------------------------- les comptes

@router.get("/utilisateurs/{user_id}", summary="Un compte en détail")
async def un_compte(user_id: str, user: AdminUser):
    """Tout ce qu'on veut sous les yeux quand quelqu'un écrit au support."""
    u = await fetch_one(
        """select id, email, display_name, plan, plan_since, plan_until, is_active,
                  est_admin, email_verified, locale, created_at, last_login_at
             from app_user where id = %s""",
        (user_id,),
    )
    if not u:
        raise NotFound("Ce compte n'existe pas.")
    paiements = await fetch_all(
        """select id, statut, montant, devise, periode_mois, telephone, reseau,
                  motif_rejet, created_at, date_validation
             from payment where user_id = %s order by created_at desc limit 20""",
        (user_id,),
    )
    abonnements = await fetch_all(
        """select id, plan, status, current_start, current_end, amount_cents, periode_mois
             from subscription where user_id = %s order by current_end desc nulls last limit 10""",
        (user_id,),
    )
    courriels = await fetch_all(
        """select template, objet, statut, erreur, created_at from email_log
            where user_id = %s order by created_at desc limit 20""",
        (user_id,),
    )
    activite = await fetch_all(
        """select pe.type, pe.at, coalesce(d.title_clean, d.title_raw) as ouvrage
             from progress_event pe left join document d on d.id = pe.document_id
            where pe.user_id = %s order by pe.at desc limit 30""",
        (user_id,),
    )
    from app.services import acces as service_acces

    parrainage = await fetch_one(
        """select a.code_parrainage, p.email as parrain,
                  (select count(*) from app_user f where f.parrain_id = a.id) as filleuls,
                  (select count(*) from bon_reduction b where b.user_id = a.id
                      and b.utilise_le is null and b.expire_le > now()) as bons_disponibles,
                  (select count(*) from bon_reduction b where b.user_id = a.id
                      and b.utilise_le is not null) as bons_utilises
             from app_user a left join app_user p on p.id = a.parrain_id where a.id = %s""",
        (user_id,),
    )
    codes_utilises = await fetch_all(
        """select c.code, c.niveau, u.active_le, least(u.fin, c.fin) as fin, c.actif
             from code_acces_utilisation u join code_acces c on c.id = u.code_id
            where u.user_id = %s order by u.active_le desc""",
        (user_id,),
    )
    etat_acces = await service_acces.etat(u)
    return {
        "acces": {"complet": etat_acces["complet"], "source": etat_acces["source"],
                  "fonctions": etat_acces["fonctions"], "jusqu_au": etat_acces["jusqu_au"]},
        "parrainage": parrainage,
        "codes": [
            {"code": c["code"], "niveau": c["niveau"], "active_le": c["active_le"], "fin": c["fin"],
             "en_cours": c["actif"] and c["fin"] > datetime.now(timezone.utc)}
            for c in codes_utilises
        ],
        "compte": {
            "id": str(u["id"]), "email": u["email"], "nom": u["display_name"],
            "plan": u["plan"], "plan_depuis": u["plan_since"], "plan_jusqu_au": u["plan_until"],
            "actif": u["is_active"], "administrateur": u["est_admin"],
            "adresse_verifiee": u["email_verified"], "inscrit_le": u["created_at"],
            "derniere_connexion": u["last_login_at"],
        },
        "paiements": [
            {"id": str(p["id"]), "statut": p["statut"], "montant": p["montant"],
             "devise": p["devise"], "periode_mois": p["periode_mois"],
             "telephone": p["telephone"], "reseau": p["reseau"],
             "motif_rejet": p["motif_rejet"], "cree_le": p["created_at"],
             "valide_le": p["date_validation"]}
            for p in paiements
        ],
        "abonnements": [
            {"id": str(a["id"]), "plan": a["plan"], "statut": a["status"],
             "debut": a["current_start"], "fin": a["current_end"],
             "montant": a["amount_cents"], "periode_mois": a["periode_mois"]}
            for a in abonnements
        ],
        "courriels": [
            {"gabarit": c["template"], "objet": c["objet"], "statut": c["statut"],
             "erreur": c["erreur"], "le": c["created_at"]}
            for c in courriels
        ],
        "activite": [
            {"type": a["type"], "ouvrage": a["ouvrage"], "le": a["at"]} for a in activite
        ],
    }


@router.patch("/utilisateurs/{user_id}", summary="Désactiver un compte, ou donner le droit")
async def changer_compte(user_id: str, data: CompteIn, user: AdminUser):
    """Deux leviers, et rien d'autre.

    Désactiver un compte le ferme sans l'effacer : sa progression reste, et on
    peut revenir dessus. Donner le droit d'administration se fait ici ou en
    SQL, mais jamais depuis l'application.

    On ne peut pas se retirer soi-même le droit : c'est le moyen le plus simple
    de se verrouiller dehors un dimanche soir.
    """
    champs = data.model_dump(exclude_none=True)
    if not champs:
        raise NotFound("Rien à changer.")
    if str(user["id"]) == str(user_id) and champs.get("est_admin") is False:
        raise Conflict("Vous ne pouvez pas retirer votre propre droit d'administration.")
    if not await fetch_one("select 1 from app_user where id = %s", (user_id,)):
        raise NotFound("Ce compte n'existe pas.")
    colonnes = ", ".join(f"{c} = %s" for c in champs)
    await execute(
        f"update app_user set {colonnes} where id = %s", list(champs.values()) + [user_id]
    )
    return {"id": user_id, **champs}


# ------------------------------------------------------------ les paiements

@router.get("/paiements/{paiement_id}", summary="Un paiement et son journal")
async def un_paiement(paiement_id: str, user: AdminUser):
    """Le journal est la réponse à « j'ai payé mais rien ne s'est passé ».

    Chaque étape y est : la création, l'envoi au fournisseur, la notification,
    la stratégie qui a permis de la rattacher, ou l'abandon.
    """
    p = await fetch_one(
        """select p.*, u.email from payment p join app_user u on u.id = p.user_id
            where p.id = %s""",
        (paiement_id,),
    )
    if not p:
        raise NotFound("Ce paiement n'existe pas.")
    journal = await fetch_all(
        """select type, source, strategie, payload, at from payment_event
            where payment_id = %s order by at""",
        (paiement_id,),
    )
    return {
        "id": str(p["id"]),
        "email": p["email"],
        "statut": p["statut"],
        "montant": p["montant"],
        "devise": p["devise"],
        "periode_mois": p["periode_mois"],
        "telephone": p["telephone"],
        "reseau": p["reseau"],
        "reference": p["reference_externe"],
        "cle_idempotence": str(p["idempotency_key"]),
        "motif_rejet": p["motif_rejet"],
        "cree_le": p["created_at"],
        "valide_le": p["date_validation"],
        "journal": [
            {"type": e["type"], "source": e["source"], "strategie": e["strategie"],
             "details": e["payload"], "le": e["at"]}
            for e in journal
        ],
    }


# ------------------------------------------------------------ les gabarits

@router.get("/gabarits", summary="Les messages transactionnels")
async def gabarits(user: AdminUser):
    lignes = await fetch_all(
        "select code, objet, corps_html, corps_texte, actif, updated_at from email_template order by code"
    )
    return [
        {"code": l["code"], "objet": l["objet"], "corps_html": l["corps_html"],
         "corps_texte": l["corps_texte"], "actif": l["actif"], "modifie_le": l["updated_at"]}
        for l in lignes
    ]


@router.patch("/gabarits/{code}", summary="Corriger un message")
async def changer_gabarit(code: str, data: GabaritIn, user: AdminUser):
    """Les gabarits vivent en base précisément pour cela : corriger une faute
    dans un message qui part à tous les nouveaux membres ne doit pas demander
    une construction d'image et un redémarrage."""
    champs = data.model_dump(exclude_none=True)
    if not champs:
        raise NotFound("Rien à changer.")
    if not await fetch_one("select 1 from email_template where code = %s", (code,)):
        raise NotFound("Ce message n'existe pas.")
    colonnes = ", ".join(f"{c} = %s" for c in champs)
    await execute(
        f"update email_template set {colonnes}, updated_at = now() where code = %s",
        list(champs.values()) + [code],
    )
    return {"code": code, **champs}


@router.get("/abonnements", summary="Les abonnements, du plus proche de l'échéance")
async def abonnements(
    user: AdminUser,
    statut: Annotated[str | None, Query(pattern="^(active|expired|canceled)$")] = None,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=200)] = PAR_PAGE,
):
    where, params = ["true"], []
    if statut:
        where.append("s.status = %s")
        params.append(statut)
    compte = await fetch_one(
        f"select count(*) as n from subscription s where {' and '.join(where)}", params)
    limite, saut = bornes(page, par_page)
    lignes = await fetch_all(
        f"""select s.id, s.plan, s.status, s.current_start, s.current_end, s.amount_cents,
                   s.periode_mois, u.email,
                   greatest(0, extract(day from s.current_end - now())::int) as jours_restants
              from subscription s join app_user u on u.id = s.user_id
             where {' and '.join(where)}
             order by s.current_end asc nulls last limit %s offset %s""",
        params + [limite, saut],
    )
    return enveloppe([
        {"id": str(l["id"]), "email": l["email"], "plan": l["plan"], "statut": l["status"],
         "debut": l["current_start"], "fin": l["current_end"], "montant": l["amount_cents"],
         "periode_mois": l["periode_mois"], "jours_restants": l["jours_restants"]}
        for l in lignes
    ], compte["n"], page, par_page)


@router.get("/corpus/{document_id}/derives", summary="Le contenu produit, lisible")
async def derives_lisibles(
    document_id: str,
    user: AdminUser,
    kind: Annotated[str, Query(pattern="^(quiz|citation|fiche_lecture|compte_rendu|synthese|resume_executif|flashcards)$")] = "quiz",
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=50)] = 10,
):
    """Le contenu lui-même, pas son compte.

    La console disait « 97 lots de quiz » sans permettre d'en lire un seul. On
    ne peut pas juger de ce qu'on a payé sans le regarder, et c'est justement
    au moment de lancer une campagne de génération qu'il faut savoir si la
    précédente a produit quelque chose de bon.
    """
    compte = await fetch_one(
        """select count(*) as n from derivative
            where document_id = %s and kind = %s and superseded_by is null""",
        (document_id, kind),
    )
    limite, saut = bornes(page, par_page)
    lignes = await fetch_all(
        """select v.id, v.chapter_id, v.content, v.model_id, v.prompt_version,
                  v.cost_tokens_in, v.cost_tokens_out, v.generated_at,
                  c.ord, c.title as chapitre, c.page_start
             from derivative v left join chapter c on c.id = v.chapter_id
            where v.document_id = %s and v.kind = %s and v.superseded_by is null
            order by c.ord nulls first, v.generated_at
            limit %s offset %s""",
        (document_id, kind, limite, saut),
    )
    return enveloppe(
        [
            {
                "id": str(l["id"]),
                "chapitre": l["chapitre"],
                "ordre": l["ord"],
                "page": l["page_start"],
                "modele": l["model_id"],
                "version_invite": l["prompt_version"],
                "jetons": (l["cost_tokens_in"] or 0) + (l["cost_tokens_out"] or 0),
                "produit_le": l["generated_at"],
                "contenu": l["content"],
            }
            for l in lignes
        ],
        compte["n"], page, par_page,
    )


@router.get("/corpus/{document_id}/fichier", summary="Le PDF d'origine")
async def fichier_source(document_id: str, user: AdminUser):
    """Sert le fichier tel qu'il est entré.

    Le seul moyen de vérifier qu'un découpage douteux vient du pipeline et non
    du PDF lui-même. Servi en flux depuis le stockage objet plutôt que chargé
    en mémoire : certains ouvrages pèsent cent mégaoctets.
    """
    d = await fetch_one(
        """select storage_key, filename_original, mime, size_bytes,
                  coalesce(title_clean, title_raw) as titre
             from document where id = %s""",
        (document_id,),
    )
    if not d or not d["storage_key"]:
        raise NotFound("Cet ouvrage n'a pas de fichier d'origine.")
    from app.services import stockage

    return stockage.servir(
        d["storage_key"],
        nom=d["filename_original"] or f"{d['titre']}.pdf",
        mime=d["mime"],
    )


# --------------------------------------------------------------- les axes

@router.get("/axes", summary="Les pôles d'apprentissage")
async def axes_admin(user: AdminUser):
    lignes = await fetch_all(
        """select a.id, a.slug, a.label, a.description, a.sort_order, a.is_premium,
                  (select count(*) from document_axis da where da.axis_id = a.id) as ouvrages,
                  (a.centroid is not null) as centroide
             from axis a order by a.sort_order nulls last, a.slug"""
    )
    return [
        {"id": str(l["id"]), "slug": l["slug"], "label": l["label"],
         "description": l["description"], "ordre": l["sort_order"],
         "premium": l["is_premium"], "ouvrages": l["ouvrages"],
         "centroide": l["centroide"]}
        for l in lignes
    ]


@router.post("/axes", status_code=201, summary="Ouvrir un pôle d'apprentissage")
async def creer_axe(data: AxeIn, user: AdminUser):
    """Un axe nouveau naît vide, et c'est normal.

    Il se remplit en y rattachant des ouvrages. Son centroïde, qui sert au
    classement automatique des nouveaux entrants, se calcule une fois qu'il en
    porte assez : `pipeline/embed/embed.py --centroides`.
    """
    if await fetch_one("select 1 from axis where slug = %s", (data.slug,)):
        raise Conflict("Un axe porte déjà ce raccourci.")
    ligne = await fetch_one(
        """insert into axis (slug, label, description, sort_order, is_premium)
           values (%s, %s, %s, %s, %s) returning id, slug, label""",
        (data.slug, data.label, data.description, data.ordre, data.premium),
    )
    return {"id": str(ligne["id"]), "slug": ligne["slug"], "label": ligne["label"]}


@router.patch("/axes/{slug}", summary="Renommer ou décrire un axe")
async def changer_axe(slug: str, data: AxePatch, user: AdminUser):
    champs = data.model_dump(exclude_none=True)
    if not champs:
        raise NotFound("Rien à changer.")
    if not await fetch_one("select 1 from axis where slug = %s", (slug,)):
        raise NotFound("Cet axe n'existe pas.")
    colonnes = ", ".join(f"{'sort_order' if c == 'ordre' else ('is_premium' if c == 'premium' else c)} = %s"
                         for c in champs)
    await execute(f"update axis set {colonnes} where slug = %s",
                  list(champs.values()) + [slug])
    return {"slug": slug, **champs}


@router.post("/corpus/{document_id}/axes/{slug}", summary="Rattacher un ouvrage à un axe")
async def rattacher(document_id: str, slug: str, user: AdminUser,
                    poids: Annotated[float, Query(ge=0, le=1)] = 1.0):
    axe = await fetch_one("select id from axis where slug = %s", (slug,))
    if not axe or not await fetch_one("select 1 from document where id = %s", (document_id,)):
        raise NotFound("Cet ouvrage ou cet axe n'existe pas.")
    # 'curator' et non 'admin' : la table n'accepte que auto, user et curator,
    # et c'est bien un rattachement décidé par une personne qu'on note ici.
    await execute(
        """insert into document_axis (document_id, axis_id, weight, assigned_by)
           values (%s, %s, %s, 'curator')
           on conflict (document_id, axis_id) do update set weight = excluded.weight,
                                                            assigned_by = 'curator'""",
        (document_id, axe["id"], poids),
    )
    return {"document_id": document_id, "axe": slug, "poids": poids}


@router.delete("/corpus/{document_id}/axes/{slug}", status_code=204,
               summary="Détacher un ouvrage d'un axe")
async def detacher(document_id: str, slug: str, user: AdminUser):
    axe = await fetch_one("select id from axis where slug = %s", (slug,))
    if not axe:
        raise NotFound("Cet axe n'existe pas.")
    await execute(
        "delete from document_axis where document_id = %s and axis_id = %s",
        (document_id, axe["id"]),
    )


# ------------------------------------------------------------ les travaux

@router.get("/travaux", summary="La file des travaux")
async def liste_travaux(
    user: AdminUser,
    etat: Annotated[str | None, Query(pattern="^(en_attente|en_cours|termine|echec|annule)$")] = None,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=100)] = PAR_PAGE,
):
    limite, saut = bornes(page, par_page)
    lignes, total = await travaux.lister(etat, limite, saut)
    return enveloppe(lignes, total, page, par_page)


@router.get("/travaux/{travail_id}", summary="Un travail et son journal")
async def un_travail(travail_id: str, user: AdminUser):
    t = await travaux.un(travail_id)
    if not t:
        raise NotFound("Ce travail n'existe pas.")
    return t


@router.post("/travaux", status_code=201, summary="Mettre un travail dans la file")
async def inscrire_travail(data: TravailIn, user: AdminUser):
    """Lance une étape du pipeline sans ouvrir un terminal.

    Ce n'est pas exécuté ici : l'ouvrier prendra le travail dans les secondes
    qui suivent. Une requête HTTP qui dure dix heures est une requête qui
    échoue.
    """
    try:
        t = await travaux.inscrire(
            data.type, data.charge, data.document_id, str(user["id"])
        )
    except ValueError as exc:
        raise NotFound(str(exc)) from exc
    if t.get("deja"):
        raise Conflict("Ce travail est déjà dans la file ou en cours.")
    return await travaux.un(str(t["id"]))


@router.post("/travaux/{travail_id}/relancer", summary="Remettre un travail échoué dans la file")
async def relancer_travail(travail_id: str, user: AdminUser):
    t = await travaux.relancer(travail_id)
    if not t:
        raise Conflict("Seul un travail en échec ou annulé se relance.")
    return await travaux.un(travail_id)


@router.delete("/travaux/{travail_id}", status_code=204, summary="Annuler un travail en attente")
async def annuler_travail(travail_id: str, user: AdminUser):
    """Un travail en cours ne s'annule pas d'ici : il tourne dans un autre
    processus, et le tuer à mi-parcours laisserait la base à moitié écrite."""
    if not await travaux.annuler(travail_id):
        raise Conflict("Seul un travail encore en attente s'annule.")


@router.post("/corpus/import", status_code=201, summary="Déposer un ouvrage")
async def importer_ouvrage(
    user: AdminUser,
    fichier: Annotated[UploadFile, File()],
    axe: Annotated[str | None, Form()] = None,
):
    """Reçoit un PDF et inscrit son ingestion dans la file.

    Le fichier est écrit dans `livres/` sous l'axe demandé, là où le pipeline
    va le chercher. On l'écrit par morceaux : un ouvrage de cent mégaoctets
    chargé en mémoire ferait tomber un conteneur à deux cents.

    L'envoi n'est pas reprenable. Sur une connexion qui coupe, il faut
    recommencer : c'est une limite assumée, et la console le dit.
    """
    nom = Path(fichier.filename or "sans-nom.pdf").name
    if not nom.lower().endswith(".pdf"):
        raise Conflict("Seuls les fichiers PDF sont acceptés.")

    dossier = Path(settings.dossier_livres) / (axe or "_a-classer")
    try:
        dossier.mkdir(parents=True, exist_ok=True)
        chemin = dossier / nom
        taille = 0
        with chemin.open("wb") as sortie:
            while morceau := await fichier.read(1024 * 1024):
                taille += len(morceau)
                if taille > settings.taille_max_import:
                    sortie.close()
                    chemin.unlink(missing_ok=True)
                    raise Conflict(
                        f"Fichier trop lourd : la limite est de "
                        f"{settings.taille_max_import // (1024 * 1024)} Mo."
                    )
                sortie.write(morceau)
    except Conflict:
        raise
    except OSError as exc:
        log.exception("Dépôt impossible dans %s", dossier)
        raise Conflict(f"Le fichier n'a pas pu être écrit : {exc}") from exc

    t = await travaux.inscrire(
        "ingestion",
        {"fichier": nom, "axe": axe, "octets": taille},
        demande_par=str(user["id"]),
    )
    return {**await travaux.un(str(t["id"])), "fichier": nom, "octets": taille}


@router.get("/sante", summary="Incidents, disjoncteurs, files et sauvegarde")
async def sante_detaillee(user: AdminUser):
    from app.services import veille

    return await veille.etat()


@router.post("/sante/veille", summary="Passer la veille maintenant")
async def passer_veille(user: AdminUser):
    """Utile après une réparation : l'incident se referme sans attendre cinq minutes."""
    from app.services import veille

    return await veille.passer()
