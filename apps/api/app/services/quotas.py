"""Compteurs d'usage et quotas.

Le principe posé au modèle de données : `usage_event` est un journal append-only,
et `plan_quota` est éditable en base sans redéploiement. Un quota `hard` bloque ;
un quota souple laisse passer en signalant le dépassement dans la réponse.
"""
from datetime import datetime, timezone

from app.core.db import execute, fetch_all, fetch_one
from app.core.errors import QuotaExceeded

# Fenêtres de comptage, exprimées en SQL pour être évaluées par la base.
_PERIOD_SQL = {
    "day": "at >= date_trunc('day', now())",
    "month": "at >= date_trunc('month', now())",
    "total": "true",
}

# Message adapté au compteur : dire ce qui est atteint et quoi faire ensuite.
_MESSAGES = {
    "agent_question": "Vous avez posé toutes vos questions du jour ({max}). "
                      "Elles se rechargent demain, ou passez à Ascension pour ne plus compter.",
    "doc_uploaded": "L'import de vos propres documents fait partie d'Ascension.",
    "ocr_pages": "Le traitement des documents scannés fait partie d'Ascension.",
    "quiz_generated": "Les quiz à la demande font partie d'Ascension. "
                      "Les quiz déjà préparés pour cet ouvrage restent accessibles.",
    "synthesis_generated": "Les synthèses à la demande font partie d'Ascension.",
    "chronogram_active": "L'offre Découverte permet un chronogramme à la fois. "
                         "Terminez ou archivez le vôtre, ou passez à Ascension.",
    "export_pdf": "L'export PDF fait partie d'Ascension.",
}


async def quota_for(plan: str, kind: str) -> dict | None:
    """Les plafonds appliqués, qui ne sont pas toujours ceux de la formule.

    Pendant la période de lancement, tout le monde reçoit les plafonds
    d'Ascension sans que son plan change. Le passage se fait ici, en un seul
    endroit, parce que c'est le seul endroit que toutes les routes traversent.
    """
    from app.services import exploitation

    return await fetch_one(
        "select period, max_value, hard from plan_quota where plan = %s and type = %s",
        (await exploitation.plan_effectif(plan), kind),
    )


async def consumed(user_id: str, kind: str, period: str) -> int:
    where = _PERIOD_SQL.get(period, "true")
    row = await fetch_one(
        f"""select coalesce(sum(quantity), 0) as n from usage_event
            where user_id = %s and type = %s and {where}""",
        (user_id, kind),
    )
    return int(row["n"]) if row else 0


async def check(user: dict, kind: str, quantity: int = 1) -> dict:
    """Vérifie avant d'agir. Lève QuotaExceeded si le plafond est dur.

    Retourne l'état du compteur pour que la route puisse le renvoyer au client :
    l'application affiche « 12 questions restantes aujourd'hui » sans second appel.
    """
    quota = await quota_for(user["plan"], kind)
    if quota is None or quota["max_value"] is None:
        return {"type": kind, "limite": None, "utilise": None, "restant": None}

    used = await consumed(user["id"], kind, quota["period"])
    limite = int(quota["max_value"])
    if used + quantity > limite:
        message = _MESSAGES.get(kind, "Vous avez atteint la limite de votre formule.").format(
            max=limite
        )
        if quota["hard"]:
            raise QuotaExceeded(
                message,
                {"type": kind, "limite": limite, "utilise": used, "periode": quota["period"]},
            )
    return {
        "type": kind,
        "limite": limite,
        "utilise": used,
        "restant": max(0, limite - used),
        "periode": quota["period"],
    }


async def record(user_id: str, kind: str, quantity: int = 1, cost_tokens: int = 0) -> None:
    await execute(
        """insert into usage_event (user_id, type, quantity, cost_tokens)
           values (%s, %s, %s, %s)""",
        (user_id, kind, quantity, cost_tokens),
    )


async def summary(user: dict) -> list[dict]:
    """État de tous les compteurs du plan : alimente l'écran Compte."""
    from app.services import exploitation

    quotas = await fetch_all(
        "select type, period, max_value, hard from plan_quota where plan = %s order by type",
        (await exploitation.plan_effectif(user["plan"]),),
    )
    out = []
    for q in quotas:
        used = await consumed(user["id"], q["type"], q["period"])
        out.append(
            {
                "type": q["type"],
                "periode": q["period"],
                "limite": q["max_value"],
                "utilise": used,
                "restant": None if q["max_value"] is None else max(0, q["max_value"] - used),
                "bloquant": q["hard"],
            }
        )
    return out
