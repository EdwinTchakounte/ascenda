from datetime import datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field


class InscriptionIn(BaseModel):
    email: EmailStr
    mot_de_passe: str = Field(min_length=8, max_length=128)
    nom: str | None = Field(default=None, max_length=120)


class ConnexionIn(BaseModel):
    email: EmailStr
    mot_de_passe: str


class RafraichirIn(BaseModel):
    refresh_token: str


class Jetons(BaseModel):
    access_token: str
    refresh_token: str
    token_type: Literal["bearer"] = "bearer"
    expire_dans: int  # secondes


class Utilisateur(BaseModel):
    id: str
    email: str | None
    nom: str | None
    plan: str
    plan_until: datetime | None = None
    locale: str = "fr"
    cree_le: datetime


class SessionOuverte(BaseModel):
    utilisateur: Utilisateur
    jetons: Jetons


class ChangerMotDePasseIn(BaseModel):
    ancien: str
    nouveau: str = Field(min_length=8, max_length=128)


class MotDePasseOublieIn(BaseModel):
    email: EmailStr


class ReinitialiserIn(BaseModel):
    email: EmailStr
    # Six chiffres, saisis à la main depuis un courriel. On accepte les espaces
    # que les gens ajoutent en recopiant, ils sont retirés côté service.
    code: str = Field(min_length=6, max_length=12)
    nouveau: str = Field(min_length=8, max_length=128)
