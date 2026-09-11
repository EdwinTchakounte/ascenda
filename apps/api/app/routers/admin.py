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
from typing import Annotated, Literal

from fastapi import APIRouter, Query
from pydantic import BaseModel, Field

from app.core.db import execute, fetch_all, fetch_one
from app.core.deps import AdminUser
from app.core.errors import Conflict, NotFound
from app.services import exploitation

router = APIRouter(prefix="/admin", tags=["Administration"])


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


class GabaritIn(BaseModel):
    objet: str | None = Field(default=None, min_length=1, max_length=300)
    corps_html: str | None = None
    corps_texte: str | None = None
    actif: bool | None = None


class CompteIn(BaseModel):
    is_active: bool | None = None
    est_admin: bool | None = None


@router.get("/tableau-de-bord", summary="Tout ce qu'il faut voir le matin")
async def tableau_de_bord(user: AdminUser, jours: Annotated[int, Query(ge=1, le=365)] = 30):
    comptes = await fetch_one(
        """select
             count(*) as total,
             count(*) filter (where created_at >= date_trunc('day', now())) as aujourdhui,
             count(*) filter (where created_at >= now() - make_interval(days => %s)) as periode,
             count(*) filter (where plan <> 'free') as abonnes,
             count(*) filter (where not is_active) as desactives
           from app_user""",
        (jours,),
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
                and created_at >= now() - make_interval(days => %s)), 0) as encaisse_periode
           from payment""",
        (jours,),
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
             count(*) filter (where created_at >= now() - make_interval(days => %s)) as periode
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
                      and p.statut = 'valide') as paiements
             from generate_series(
                    date_trunc('day', now()) - make_interval(days => %s - 1),
                    date_trunc('day', now()), interval '1 day') d
            order by d""",
        (jours,),
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
            {"jour": str(c["jour"]), "comptes": c["comptes"], "paiements": c["paiements"]}
            for c in courbe
        ],
        "exploitation": await exploitation.etat(),
    }


@router.get("/paiements", summary="Les paiements, du plus récent")
async def paiements(
    user: AdminUser,
    statut: Annotated[str | None, Query(pattern="^(en_attente|valide|rejete)$")] = None,
    limite: Annotated[int, Query(ge=1, le=200)] = 50,
):
    where, params = ["true"], []
    if statut:
        where.append("p.statut = %s")
        params.append(statut)
    lignes = await fetch_all(
        f"""select p.id, p.statut, p.montant, p.devise, p.periode_mois, p.telephone,
                   p.reseau, p.reference_externe, p.motif_rejet, p.created_at,
                   p.date_validation, u.email
              from payment p join app_user u on u.id = p.user_id
             where {' and '.join(where)}
             order by p.created_at desc limit %s""",
        params + [limite],
    )
    return [
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
    ]


@router.get("/webhooks-orphelins", summary="Les notifications qu'on n'a pas su rattacher")
async def orphelins(user: AdminUser, limite: Annotated[int, Query(ge=1, le=100)] = 30):
    """Le premier endroit à regarder quand quelqu'un affirme avoir payé.

    Un webhook qui n'a trouvé aucun paiement est conservé avec un identifiant
    nul plutôt que jeté : c'est la seule trace de l'argent de quelqu'un.
    """
    lignes = await fetch_all(
        """select id, type, source, strategie, payload, at from payment_event
            where payment_id is null order by at desc limit %s""",
        (limite,),
    )
    return [
        {"id": str(l["id"]), "type": l["type"], "source": l["source"],
         "strategie": l["strategie"], "details": l["payload"], "le": l["at"]}
        for l in lignes
    ]


@router.get("/utilisateurs", summary="Chercher un compte")
async def utilisateurs(
    user: AdminUser,
    q: Annotated[str | None, Query(min_length=2)] = None,
    limite: Annotated[int, Query(ge=1, le=100)] = 30,
):
    where, params = ["true"], []
    if q:
        where.append("(u.email ilike %s or u.display_name ilike %s)")
        params += [f"%{q}%", f"%{q}%"]
    lignes = await fetch_all(
        f"""select u.id, u.email, u.display_name, u.plan, u.plan_until, u.is_active,
                   u.created_at, u.last_login_at,
                   (select count(*) from payment p
                     where p.user_id = u.id and p.statut = 'valide') as paiements,
                   (select count(*) from progress_event pe where pe.user_id = u.id) as actions
              from app_user u
             where {' and '.join(where)}
             order by u.created_at desc limit %s""",
        params + [limite],
    )
    return [
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
    ]


@router.get("/courriels", summary="Le journal des envois")
async def courriels(
    user: AdminUser,
    statut: Annotated[str | None, Query(pattern="^(en_attente|envoye|simule|echec)$")] = None,
    limite: Annotated[int, Query(ge=1, le=200)] = 50,
):
    where, params = ["true"], []
    if statut:
        where.append("statut = %s")
        params.append(statut)
    lignes = await fetch_all(
        f"""select template, destinataire, objet, statut, erreur, created_at
              from email_log where {' and '.join(where)}
             order by created_at desc limit %s""",
        params + [limite],
    )
    return [
        {"gabarit": l["template"], "destinataire": l["destinataire"], "objet": l["objet"],
         "statut": l["statut"], "erreur": l["erreur"], "le": l["created_at"]}
        for l in lignes
    ]


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
    limite: Annotated[int, Query(ge=1, le=200)] = 100,
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
             order by coalesce(d.title_clean, d.title_raw) limit %s""",
        params + [limite],
    )
    sortie = []
    for l in lignes:
        utiles = l["chapitres_utiles"] or 0
        incomplet = (l["quiz"] or 0) < utiles or (l["citations"] or 0) < utiles or not l["fiches"]
        if manque and not incomplet:
            continue
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
    return sortie


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
    return {
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
    limite: Annotated[int, Query(ge=1, le=200)] = 60,
):
    where, params = ["true"], []
    if statut:
        where.append("s.status = %s")
        params.append(statut)
    lignes = await fetch_all(
        f"""select s.id, s.plan, s.status, s.current_start, s.current_end, s.amount_cents,
                   s.periode_mois, u.email,
                   greatest(0, extract(day from s.current_end - now())::int) as jours_restants
              from subscription s join app_user u on u.id = s.user_id
             where {' and '.join(where)}
             order by s.current_end asc nulls last limit %s""",
        params + [limite],
    )
    return [
        {"id": str(l["id"]), "email": l["email"], "plan": l["plan"], "statut": l["status"],
         "debut": l["current_start"], "fin": l["current_end"], "montant": l["amount_cents"],
         "periode_mois": l["periode_mois"], "jours_restants": l["jours_restants"]}
        for l in lignes
    ]
