"""Compteurs d'usage et quotas."""
from datetime import datetime, timezone

from app.core.db import execute, fetch_all, fetch_one
from app.core.errors import QuotaExceeded

# Fenêtres de comptage, exprimées en SQL pour être évaluées par la base.
_PERIOD_SQL = {
    "day": "at >= date_trunc('day', now())",
    "month": "at >= date_trunc('month', now())",
    "total": "true",
}

_EN_JETONS = {"agent_tokens"}

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
    "agent_tokens": "Vous avez atteint le volume de réponses inclus. "
                    "Il se recharge au début du mois, ou passez à Ascension.",
}


async def quota_for(user: dict, kind: str) -> dict | None:
    """Les plafonds appliqués, qui ne sont pas toujours ceux de la formule."""
    from app.services import acces

    quota = await fetch_one(
        "select period, max_value, hard from plan_quota where plan = %s and type = %s",
        (await acces.plan_pour(user, kind), kind),
    )
    if kind != "agent_tokens":
        return quota

    # Un code d'accès peut porter son propre plafond de jetons.
    borne = await acces.plafond_jetons(str(user["id"]))
    if not borne:
        return quota
    du_plan = quota["max_value"] if quota and quota["max_value"] is not None else None
    if du_plan is not None and du_plan <= borne["plafond"]:
        return quota
    return {"period": "total", "max_value": borne["plafond"], "hard": True,
            "depuis": borne["depuis"], "code": borne["code"]}


async def consumed(user_id: str, kind: str, period: str, depuis=None) -> int:
    """Ce qui a déjà été consommé sur la fenêtre."""
    colonne = "cost_tokens" if kind in _EN_JETONS else "quantity"
    if depuis is not None:
        where, params = "at >= %s", (user_id, kind, depuis)
    else:
        where, params = _PERIOD_SQL.get(period, "true"), (user_id, kind)
    row = await fetch_one(
        f"""select coalesce(sum({colonne}), 0) as n from usage_event
            where user_id = %s and type = %s and {where}""",
        params,
    )
    return int(row["n"]) if row else 0


async def check(user: dict, kind: str, quantity: int = 1) -> dict:
    """Vérifie avant d'agir. Lève QuotaExceeded si le plafond est dur."""
    quota = await quota_for(user, kind)
    if quota is None or quota["max_value"] is None:
        return {"type": kind, "limite": None, "utilise": None, "restant": None}

    used = await consumed(user["id"], kind, quota["period"], quota.get("depuis"))
    limite = int(quota["max_value"])
    if used + quantity > limite:
        if quota.get("code"):
            # Un plafond porté par un code ne se recharge pas au mois
            message = (f"Le volume inclus dans le code {quota['code']} est épuisé "
                       f"({limite} jetons).")
        else:
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
    """État de tous les compteurs : alimente l'écran Compte."""
    types = await fetch_all("select distinct type from plan_quota order by type")
    out = []
    for t in types:
        q = await quota_for(user, t["type"])
        if not q:
            continue
        used = await consumed(user["id"], t["type"], q["period"], q.get("depuis"))
        out.append(
            {
                "type": t["type"],
                "periode": q["period"],
                "limite": q["max_value"],
                "utilise": used,
                "restant": None if q["max_value"] is None else max(0, q["max_value"] - used),
                "bloquant": q["hard"],
            }
        )
    return out
