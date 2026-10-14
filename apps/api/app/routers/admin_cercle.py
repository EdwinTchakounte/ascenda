"""La console : suivre le cercle de lecteurs et traiter les signalements."""
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query
from pydantic import BaseModel

from app.core.db import connection, fetch_all, fetch_one
from app.core.deps import AdminUser
from app.core.errors import NotFound
from app.routers.admin import PAR_PAGE, bornes, enveloppe
from app.services.cercle import prenom

router = APIRouter(prefix="/admin/cercle", tags=["Administration"])


class DecisionIn(BaseModel):
    decision: Literal["masque", "ignore"]


@router.get("", summary="Le cercle en chiffres")
async def vue_ensemble(user: AdminUser):
    chiffres = await fetch_one(
        """select
             (select count(*) from amitie where statut = 'acceptee') as amities,
             (select count(*) from amitie where statut = 'en_attente') as demandes_en_attente,
             (select count(distinct u) from (
                 select demandeur_id as u from amitie where statut = 'acceptee'
                 union select destinataire_id from amitie where statut = 'acceptee') x) as lecteurs_relies,
             (select count(*) from echange where created_at > now() - interval '7 days') as echanges_7j,
             (select count(*) from encouragement where created_at > now() - interval '7 days') as encouragements_7j,
             (select count(*) from signalement where traite_le is null) as signalements_ouverts,
             (select count(*) from blocage) as blocages"""
    )
    jours = await fetch_all(
        """select d::date as jour,
                  (select count(*) from echange e where e.created_at::date = d::date) as echanges,
                  (select count(*) from encouragement g where g.created_at::date = d::date) as encouragements,
                  (select count(*) from amitie a where a.repondu_le::date = d::date
                      and a.statut = 'acceptee') as amities
             from generate_series(current_date - 13, current_date, interval '1 day') d
            order by d"""
    )
    return {**chiffres, "jours": jours}


@router.get("/relations", summary="Les paires de lecteurs qui échangent")
async def relations(
    user: AdminUser,
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=200)] = PAR_PAGE,
):
    """Qui échange avec qui, combien et quand : de quoi repérer un compte qui
    écrit à tout le monde, sans ouvrir aucune conversation."""
    limite, decalage = bornes(page, par_page)
    total = await fetch_one("select count(*) as n from amitie where statut = 'acceptee'")
    lignes = await fetch_all(
        """select a.id, a.repondu_le, ua.id as a_id, ua.display_name as a_nom, ua.email as a_email,
                  ub.id as b_id, ub.display_name as b_nom, ub.email as b_email,
                  (select count(*) from echange e
                    where least(e.auteur_id, e.destinataire_id) = least(a.demandeur_id, a.destinataire_id)
                      and greatest(e.auteur_id, e.destinataire_id) = greatest(a.demandeur_id, a.destinataire_id))
                    as echanges,
                  (select max(e.created_at) from echange e
                    where least(e.auteur_id, e.destinataire_id) = least(a.demandeur_id, a.destinataire_id)
                      and greatest(e.auteur_id, e.destinataire_id) = greatest(a.demandeur_id, a.destinataire_id))
                    as dernier_echange
             from amitie a
             join app_user ua on ua.id = a.demandeur_id
             join app_user ub on ub.id = a.destinataire_id
            where a.statut = 'acceptee'
            order by dernier_echange desc nulls last, a.repondu_le desc
            limit %s offset %s""",
        (limite, decalage),
    )
    return enveloppe(
        [
            {"id": str(l["id"]), "amis_depuis": l["repondu_le"], "echanges": l["echanges"],
             "dernier_echange": l["dernier_echange"],
             "lecteurs": [
                 {"id": str(l["a_id"]), "nom": l["a_nom"], "email": l["a_email"]},
                 {"id": str(l["b_id"]), "nom": l["b_nom"], "email": l["b_email"]},
             ]}
            for l in lignes
        ],
        total["n"], page, par_page,
    )


@router.get("/signalements", summary="Les signalements")
async def signalements(
    user: AdminUser,
    etat: Literal["ouverts", "traites", "tous"] = "ouverts",
    page: Annotated[int, Query(ge=1)] = 1,
    par_page: Annotated[int, Query(ge=1, le=200)] = PAR_PAGE,
):
    limite, decalage = bornes(page, par_page)
    filtre = {"ouverts": "s.traite_le is null", "traites": "s.traite_le is not null", "tous": "true"}[etat]
    total = await fetch_one(f"select count(*) as n from signalement s where {filtre}")
    lignes = await fetch_all(
        f"""select s.id, s.motif, s.created_at, s.traite_le, s.decision,
                   sig.display_name as signale_par, sig.email as signale_par_email,
                   coalesce(e.texte, g.message) as contenu, coalesce(e.created_at, g.created_at) as ecrit_le,
                   case when e.id is not null then 'echange' else 'encouragement' end as nature,
                   aut.id as auteur_id, aut.display_name as auteur, aut.email as auteur_email,
                   (select count(*) from signalement s2
                      left join echange e2 on e2.id = s2.echange_id
                      left join encouragement g2 on g2.id = s2.encouragement_id
                     where coalesce(e2.auteur_id, g2.auteur_id) = aut.id) as signalements_auteur
              from signalement s
              join app_user sig on sig.id = s.auteur_id
              left join echange e on e.id = s.echange_id
              left join encouragement g on g.id = s.encouragement_id
              join app_user aut on aut.id = coalesce(e.auteur_id, g.auteur_id)
             where {filtre}
             order by s.created_at desc limit %s offset %s""",
        (limite, decalage),
    )
    return enveloppe(
        [
            {"id": str(l["id"]), "motif": l["motif"], "le": l["created_at"], "traite_le": l["traite_le"],
             "decision": l["decision"], "nature": l["nature"],
             "contenu": l["contenu"] or "(encouragement sans message)", "ecrit_le": l["ecrit_le"],
             "signale_par": {"nom": l["signale_par"], "email": l["signale_par_email"]},
             "auteur": {"id": str(l["auteur_id"]), "nom": l["auteur"], "email": l["auteur_email"],
                        "signalements": l["signalements_auteur"]}}
            for l in lignes
        ],
        total["n"], page, par_page,
    )


@router.post("/signalements/{signalement_id}", summary="Trancher un signalement")
async def trancher(signalement_id: UUID, data: DecisionIn, user: AdminUser):
    """`masque` retire le message des deux conversations et le garde en base ;
    `ignore` le laisse visible. Dans les deux cas, le signalement est clos."""
    async with connection() as conn:
        cur = await conn.execute(
            """update signalement set traite_le = now(), traite_par = %s, decision = %s
                where id = %s returning echange_id, encouragement_id""",
            (user["id"], data.decision, str(signalement_id)),
        )
        s = await cur.fetchone()
        if not s:
            raise NotFound("Ce signalement n'existe pas.")
        if data.decision == "masque":
            if s["echange_id"]:
                await conn.execute("update echange set masque_le = now() where id = %s", (s["echange_id"],))
            else:
                await conn.execute("update encouragement set masque_le = now() where id = %s",
                                   (s["encouragement_id"],))
            # Les autres signalements du même message sont clos du même geste.
            await conn.execute(
                """update signalement set traite_le = now(), traite_par = %s, decision = 'masque'
                    where traite_le is null
                      and (echange_id = %s or encouragement_id = %s)""",
                (user["id"], s["echange_id"], s["encouragement_id"]),
            )
    return {"decision": data.decision}


@router.get("/lecteurs/{lecteur_id}", summary="Le cercle d'un lecteur")
async def cercle_lecteur(lecteur_id: UUID, user: AdminUser):
    lid = str(lecteur_id)
    if not await fetch_one("select 1 from app_user where id = %s", (lid,)):
        raise NotFound("Ce lecteur n'existe pas.")
    amis = await fetch_all(
        """select u.id, u.display_name, a.statut, a.created_at
             from amitie a
             join app_user u on u.id = case when a.demandeur_id = %(l)s then a.destinataire_id
                                            else a.demandeur_id end
            where %(l)s in (a.demandeur_id, a.destinataire_id)
            order by a.created_at desc""",
        {"l": lid},
    )
    volumes = await fetch_one(
        """select
             (select count(*) from echange where auteur_id = %(l)s) as echanges_ecrits,
             (select count(*) from echange where auteur_id = %(l)s and created_at > now() - interval '1 day')
                as echanges_24h,
             (select count(*) from encouragement where auteur_id = %(l)s) as encouragements_donnes,
             (select count(*) from encouragement where destinataire_id = %(l)s) as encouragements_recus,
             (select count(*) from blocage where bloque_id = %(l)s) as bloque_par,
             (select count(*) from signalement s left join echange e on e.id = s.echange_id
                 left join encouragement g on g.id = s.encouragement_id
               where coalesce(e.auteur_id, g.auteur_id) = %(l)s) as signalements_recus""",
        {"l": lid},
    )
    return {
        **volumes,
        "relations": [
            {"id": str(a["id"]), "nom": prenom(a["display_name"]), "statut": a["statut"], "le": a["created_at"]}
            for a in amis
        ],
    }
