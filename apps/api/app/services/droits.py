"""Le garde-fou de droits, en un seul endroit.

Sur 78 ouvrages, 7 seulement sont redistribuables. Pour les 71 autres, servir le
texte intégral exposerait directement le projet. La règle, posée à la couche 7 du
modèle de données : on cite un extrait court avec sa référence, on ne restitue
pas l'œuvre. Tout ce qui renvoie du texte de livre passe par ici.
"""
from dataclasses import dataclass

from app.core.db import fetch_one
from app.core.errors import NotFound


@dataclass(frozen=True)
class Droits:
    document_id: str
    redistributable: bool
    statut: str
    plafond_extrait: int
    takedown: str

    @property
    def texte_integral(self) -> bool:
        return self.redistributable and self.takedown == "none"

    @property
    def retire(self) -> bool:
        return self.takedown != "none"

    def budget(self) -> int:
        """Nombre de caractères de texte d'œuvre servables en une réponse."""
        if self.retire:
            return 0
        return 10_000_000 if self.redistributable else max(0, self.plafond_extrait)

    def message(self) -> str | None:
        if self.retire:
            return "Cet ouvrage a été retiré de la bibliothèque à la demande de son ayant droit."
        if self.texte_integral:
            return None
        if self.plafond_extrait <= 0:
            return (
                "Le texte de cet ouvrage ne peut pas être affiché ici. "
                "ASCENDA vous en donne la fiche, les idées-force, les quiz et le plan de lecture ; "
                "la lecture se fait sur votre exemplaire."
            )
        return (
            "Cet ouvrage n'est pas redistribuable : ASCENDA en cite des extraits courts "
            "avec leur page, sans afficher le texte intégral."
        )


async def droits(document_id: str) -> Droits:
    row = await fetch_one(
        """select id, redistributable, copyright_status, max_excerpt_chars, takedown_status
           from document where id = %s""",
        (document_id,),
    )
    if not row:
        raise NotFound("Cet ouvrage n'existe pas dans la bibliothèque.")
    return Droits(
        document_id=str(row["id"]),
        redistributable=bool(row["redistributable"]),
        statut=row["copyright_status"],
        plafond_extrait=int(row["max_excerpt_chars"] or 0),
        takedown=row["takedown_status"],
    )


def tronquer(texte: str, budget: int) -> tuple[str, bool]:
    """Coupe sur une frontière de phrase quand c'est possible, jamais au milieu d'un mot."""
    if budget <= 0:
        return "", True
    if len(texte) <= budget:
        return texte, False
    coupe = texte[:budget]
    for sep in (". ", " ! ", " ? ", "\n"):
        i = coupe.rfind(sep)
        if i > budget * 0.6:
            return coupe[: i + 1].strip(), True
    i = coupe.rfind(" ")
    return (coupe[:i] if i > 0 else coupe).strip() + "…", True


def repartir(budget: int, morceaux: list[str]) -> list[str]:
    """Répartit un budget d'extrait sur plusieurs passages, du plus court au plus long,
    pour qu'un passage bref ne soit pas sacrifié au profit d'un long."""
    if budget <= 0:
        return ["" for _ in morceaux]
    restant, reste_n = budget, len(morceaux)
    resultat: dict[int, str] = {}
    for idx, txt in sorted(enumerate(morceaux), key=lambda p: len(p[1])):
        part = restant // max(1, reste_n)
        gardé, _ = tronquer(txt, part)
        resultat[idx] = gardé
        restant -= len(gardé)
        reste_n -= 1
    return [resultat[i] for i in range(len(morceaux))]
