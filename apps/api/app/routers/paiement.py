"""Paiement mobile money et abonnement."""
from typing import Annotated, Literal

from fastapi import APIRouter, Query, Request, status
from pydantic import BaseModel, Field

from app.core.config import settings
from app.core.db import fetch_all, fetch_one
from app.core.deps import CurrentUser
from app.core.errors import Forbidden, NotFound
from app.services.paiement import service

router = APIRouter(prefix="/paiements", tags=["Paiement"])


class AchatIn(BaseModel):
    periode_mois: Literal[1, 3, 12] = 1
    telephone: str = Field(min_length=8, max_length=20)
    reseau: Literal["MTN", "ORANGE"]


@router.get("/tarifs", summary="La grille tarifaire")
async def grille():
    """Lue en base : la page de tarifs ne peut pas diverger de ce qui est
    réellement facturé."""
    lignes = await service.tarifs()
    return {
        "moyens": [
            {"code": "mtn", "libelle": "MTN Mobile Money", "operateur": "MTN Cameroun"},
            {"code": "orange", "libelle": "Orange Money", "operateur": "Orange Cameroun"},
        ],
        "formules": [
            {
                "periode_mois": t["periode_mois"],
                "montant": t["montant"],
                "devise": t["devise"],
                "libelle": t["libelle"],
                "par_mois": round(t["montant"] / t["periode_mois"]),
            }
            for t in lignes
        ],
    }


@router.post("", status_code=status.HTTP_201_CREATED, summary="Payer un abonnement")
async def payer(data: AchatIn, user: CurrentUser):
    """Crée le paiement puis déclenche la demande sur le téléphone.

    Le membre valide avec son code mobile money. La confirmation arrive ensuite
    par notification du fournisseur, ou à défaut par la réconciliation.
    """
    paiement = await service.creer(user, data.periode_mois)
    paiement = await service.initier(paiement, data.telephone, data.reseau)
    return _vue(paiement)


@router.get("", summary="Vos paiements")
async def historique(user: CurrentUser, limite: Annotated[int, Query(le=100)] = 30):
    lignes = await fetch_all(
        """select * from payment where user_id = %s order by created_at desc limit %s""",
        (user["id"], limite),
    )
    return [_vue(p) for p in lignes]


@router.get("/{paiement_id}", summary="Suivre un paiement")
async def suivre(paiement_id: str, user: CurrentUser):
    p = await fetch_one(
        "select * from payment where id = %s and user_id = %s", (paiement_id, user["id"])
    )
    if not p:
        raise NotFound("Ce paiement n'existe pas ou ne vous appartient pas.")
    evenements = await fetch_all(
        """select type, source, strategie, at from payment_event
           where payment_id = %s order by at""",
        (paiement_id,),
    )
    return {
        **_vue(p),
        "journal": [
            {"type": e["type"], "source": e["source"], "strategie": e["strategie"], "le": e["at"]}
            for e in evenements
        ],
    }


@router.post("/webhook/tara", summary="Notification de Tara")
async def webhook(request: Request):
    """Répond toujours 200.

    Un code d'erreur ferait rejouer Tara en boucle sans rien résoudre. Ce qui ne
    passe pas est journalisé dans `payment_event`, avec un paiement nul quand le
    rattachement a échoué.
    """
    return await service.traiter_webhook(await request.body(), "tara")


@router.get("/abonnement/etat", summary="Votre abonnement")
async def etat(user: CurrentUser):
    a = await fetch_one(
        """select * from subscription where user_id = %s
           order by current_end desc nulls last limit 1""",
        (user["id"],),
    )
    if not a:
        return {"actif": False, "plan": user["plan"], "message": "Aucun abonnement."}
    from datetime import datetime, timezone

    reste = None
    if a["current_end"]:
        reste = max(0, (a["current_end"] - datetime.now(timezone.utc)).days)
    return {
        "actif": a["status"] == "active" and (a["current_end"] or datetime.now(timezone.utc))
                 > datetime.now(timezone.utc),
        "plan": a["plan"],
        "statut": a["status"],
        "debut": a["current_start"],
        "fin": a["current_end"],
        "jours_restants": reste,
        "periode_mois": a["periode_mois"],
        "montant": a["amount_cents"],
        "devise": a["currency"],
    }


@router.post("/dev/{paiement_id}/confirmer", summary="Confirmer un paiement (développement)")
async def confirmer_dev(paiement_id: str, user: CurrentUser):
    """Simule la notification du fournisseur. Refusée hors développement."""
    if settings.is_prod:
        raise Forbidden("Cette route n'existe qu'en développement.")
    p = await fetch_one(
        "select * from payment where id = %s and user_id = %s", (paiement_id, user["id"])
    )
    if not p:
        raise NotFound("Ce paiement n'existe pas ou ne vous appartient pas.")
    await service.appliquer(p, "valide", source="admin", strategie="confirmation_dev")
    return _vue(await fetch_one("select * from payment where id = %s", (paiement_id,)))


def _vue(p: dict) -> dict:
    return {
        "id": str(p["id"]),
        "montant": p["montant"],
        "devise": p["devise"],
        "periode_mois": p["periode_mois"],
        "plan": p["plan_cible"],
        "statut": p["statut"],
        "motif_rejet": p["motif_rejet"],
        "telephone": p["telephone"],
        "reseau": p["reseau"],
        "reference": p["reference_externe"],
        "url_paiement": (p.get("gateway_reponse") or {}).get("authUrl"),
        "cree_le": p["created_at"],
        "valide_le": p["date_validation"],
        "message": _message(p),
    }


def _message(p: dict) -> str:
    return {
        "en_attente": "Validez la demande sur votre téléphone avec votre code mobile money. "
                      "La confirmation arrive en général en moins d'une minute.",
        "valide": "Paiement confirmé. Votre abonnement est actif.",
        "rejete": p["motif_rejet"] or "Le paiement n'a pas abouti. Vous pouvez réessayer.",
    }[p["statut"]]
