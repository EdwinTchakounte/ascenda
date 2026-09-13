"""Le cercle de lecteurs, côté lecteur : amis, encouragements, échanges."""
from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Query, status
from pydantic import BaseModel, Field

from app.core.db import execute, fetch_one
from app.core.deps import CurrentUser
from app.services import cercle, codes

router = APIRouter(prefix="/cercle", tags=["Cercle de lecteurs"])


class DemandeIn(BaseModel):
    code: str = Field(min_length=3, max_length=40, description="Le code ASCENDA du lecteur à ajouter")


class EncouragementIn(BaseModel):
    ami_id: UUID
    genre: Literal["bravo", "courage", "defi", "merci"]
    message: str | None = Field(default=None, max_length=280)
    evenement_id: UUID | None = Field(default=None, description="L'activité du fil qu'on encourage")


class EchangeIn(BaseModel):
    texte: str = Field(min_length=1, max_length=2000)


class SignalementIn(BaseModel):
    echange_id: UUID | None = None
    encouragement_id: UUID | None = None
    motif: str = Field(min_length=3, max_length=500)


class PreferencesIn(BaseModel):
    partage_activite: bool


@router.get("/moi", summary="Votre code, vos compteurs et vos préférences")
async def moi(user: CurrentUser):
    code = await codes.code_ambassadeur(user)
    pref = await fetch_one("select partage_activite from app_user where id = %s", (user["id"],))
    return {
        "code": code,
        "partage_activite": pref["partage_activite"],
        "compteurs": await cercle.compteurs(user),
        "message_partage": (
            f"Rejoins mon cercle de lecture sur ASCENDA : ajoute-moi avec le code {code}."
        ),
    }


@router.patch("/preferences", summary="Partager ou non son activité")
async def preferences(data: PreferencesIn, user: CurrentUser):
    await execute("update app_user set partage_activite = %s where id = %s",
                  (data.partage_activite, user["id"]))
    return {"partage_activite": data.partage_activite}


@router.get("/amis", summary="Vos amis et leur semaine de lecture")
async def amis(user: CurrentUser):
    return await cercle.amis(user)


@router.post("/amis", status_code=status.HTTP_201_CREATED, summary="Ajouter un ami par son code")
async def ajouter(data: DemandeIn, user: CurrentUser):
    return await cercle.demander(user, data.code)


@router.delete("/amis/{ami_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Retirer un ami")
async def retirer(ami_id: UUID, user: CurrentUser):
    await cercle.retirer(user, str(ami_id))


@router.post("/bloquer/{lecteur_id}", status_code=status.HTTP_204_NO_CONTENT, summary="Bloquer un lecteur")
async def bloquer(lecteur_id: UUID, user: CurrentUser):
    await cercle.bloquer(user, str(lecteur_id))


@router.get("/demandes", summary="Demandes d'ami reçues et envoyées")
async def demandes(user: CurrentUser):
    return await cercle.demandes(user)


@router.post("/demandes/{demande_id}/accepter", summary="Accepter une demande")
async def accepter(demande_id: UUID, user: CurrentUser):
    return await cercle.repondre(user, str(demande_id), accepter=True)


@router.post("/demandes/{demande_id}/refuser", summary="Refuser une demande")
async def refuser(demande_id: UUID, user: CurrentUser):
    return await cercle.repondre(user, str(demande_id), accepter=False)


@router.get("/fil", summary="Ce que vos amis ont lu ces derniers jours")
async def fil(user: CurrentUser, jours: Annotated[int, Query(ge=1, le=60)] = 14):
    return await cercle.fil(user, jours)


@router.post("/encouragements", status_code=status.HTTP_201_CREATED, summary="Encourager un ami")
async def encourager(data: EncouragementIn, user: CurrentUser):
    return await cercle.encourager(user, str(data.ami_id), data.genre, data.message,
                                   str(data.evenement_id) if data.evenement_id else None)


@router.get("/encouragements", summary="Les encouragements reçus")
async def encouragements(user: CurrentUser):
    return await cercle.encouragements_recus(user)


@router.post("/encouragements/vus", status_code=status.HTTP_204_NO_CONTENT,
             summary="Marquer les encouragements comme vus")
async def encouragements_vus(user: CurrentUser):
    await execute("update encouragement set vu_le = now() where destinataire_id = %s and vu_le is null",
                  (user["id"],))


@router.get("/echanges/{ami_id}", summary="La conversation avec un ami")
async def conversation(ami_id: UUID, user: CurrentUser, avant: datetime | None = None):
    return await cercle.conversation(user, str(ami_id), avant)


@router.post("/echanges/{ami_id}", status_code=status.HTTP_201_CREATED, summary="Écrire à un ami")
async def ecrire(ami_id: UUID, data: EchangeIn, user: CurrentUser):
    return await cercle.ecrire(user, str(ami_id), data.texte)


@router.post("/echanges/{ami_id}/lus", summary="Marquer la conversation comme lue")
async def lus(ami_id: UUID, user: CurrentUser):
    return {"marques": await cercle.marquer_lus(user, str(ami_id))}


@router.post("/signalements", status_code=status.HTTP_201_CREATED, summary="Signaler un message reçu")
async def signaler(data: SignalementIn, user: CurrentUser):
    return await cercle.signaler(
        user,
        echange_id=str(data.echange_id) if data.echange_id else None,
        encouragement_id=str(data.encouragement_id) if data.encouragement_id else None,
        motif=data.motif,
    )
