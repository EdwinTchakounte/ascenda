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
from typing import Annotated

from fastapi import APIRouter, Query
from pydantic import BaseModel

from app.core.db import execute, fetch_all, fetch_one
from app.core.deps import AdminUser
from app.core.errors import NotFound
from app.services import exploitation

router = APIRouter(prefix="/admin", tags=["Administration"])


class ReglageIn(BaseModel):
    valeur: dict


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
