"""La veille : ce qui reste en panne se signale, une fois."""
import logging
import time
from dataclasses import dataclass
from datetime import datetime, timezone

from app.core.config import settings
from app.core.db import connection, execute, fetch_all, fetch_one
from app.services.resilience import DISJONCTEURS, OUVERT

log = logging.getLogger("ascenda.veille")

# Ce que l'ordonnanceur a fait, et quand
PASSAGES: dict[str, float] = {}
DEMARRAGE = time.monotonic()

TRAVAIL_ORPHELIN_MIN = 3
REPRISES_MAX = 2


@dataclass
class Constat:
    cle: str
    gravite: str  # info, attention, critique
    titre: str
    explication: str
    detail: dict


# ------------------------------------------------------------------ contrôles

async def _paiements_bloques() -> list[Constat]:
    l = await fetch_one(
        """select count(*) as n, min(gateway_initiated_at) as plus_ancien from payment
            where statut = 'en_attente' and gateway_initiated_at < now() - interval '2 hours'""")
    if not l["n"]:
        return []
    return [Constat("paiements_bloques", "critique", f"{l['n']} paiement(s) en attente depuis plus de 2 h",
                    "La réconciliation devrait les avoir tranchés. Vérifiez l'accès à Tara et la vue Paiements.",
                    {"nombre": l["n"], "plus_ancien": l["plus_ancien"]})]


async def _webhooks_orphelins() -> list[Constat]:
    l = await fetch_one(
        """select count(*) as n from payment_event
            where type = 'webhook_orphelin' and at > now() - interval '24 hours'""")
    if not l["n"]:
        return []
    return [Constat("webhooks_orphelins", "attention", f"{l['n']} notification(s) de paiement non rattachée(s)",
                    "Un lecteur a peut-être payé sans que son paiement soit retrouvé. Voir Webhooks orphelins.",
                    {"nombre": l["n"]})]


async def _courriels() -> list[Constat]:
    l = await fetch_one(
        """select count(*) filter (where statut = 'abandonne' and created_at > now() - interval '24 hours') as abandonnes,
                  count(*) filter (where statut = 'echec' and prochaine_tentative is not null) as en_file
             from email_log""")
    constats = []
    if l["abandonnes"]:
        constats.append(Constat("courriels_abandonnes", "attention",
                                f"{l['abandonnes']} courriel(s) abandonné(s) après cinq renvois",
                                "Des lecteurs n'ont pas reçu un message. Voir le journal des envois.",
                                {"nombre": l["abandonnes"]}))
    if l["en_file"] >= 20:
        constats.append(Constat("courriels_en_file", "attention", f"{l['en_file']} courriels en attente de renvoi",
                                "Brevo refuse ou ralentit les envois. La file se videra quand il répondra.",
                                {"nombre": l["en_file"]}))
    return constats


async def _disjoncteurs() -> list[Constat]:
    constats = []
    for nom, d in DISJONCTEURS.items():
        v = d.vue()
        if v["etat"] == OUVERT:
            gravite = "critique" if nom == "tara" else "attention"
            constats.append(Constat(f"disjoncteur_{nom}", gravite, f"{nom.capitalize()} jugé indisponible",
                                    f"Le disjoncteur s'est ouvert après plusieurs échecs : {v['dernier_echec']}",
                                    v))
    return constats


async def _travaux_orphelins() -> list[Constat]:
    """Remet en file les travaux dont l'ouvrier ne bat plus, et signale les autres."""
    async with connection() as conn:
        cur = await conn.execute(
            """update travail
                  set etat = case when reprises < %s then 'en_attente' else 'echec' end,
                      reprises = reprises + 1,
                      erreur = case when reprises < %s then null
                                    else 'Interrompu : l''ouvrier ne répond plus.' end,
                      journal = coalesce(journal, '') || E'\\n[veille] travail orphelin, '
                                || case when reprises < %s then 'remis en file.' else 'abandonné.' end,
                      finished_at = case when reprises < %s then null else now() end
                where etat = 'en_cours'
                  and coalesce(battement, started_at) < now() - make_interval(mins => %s)
            returning id, type, etat""",
            (REPRISES_MAX, REPRISES_MAX, REPRISES_MAX, REPRISES_MAX, TRAVAIL_ORPHELIN_MIN),
        )
        lignes = await cur.fetchall()
    abandonnes = [l for l in lignes if l["etat"] == "echec"]
    if lignes:
        log.warning("Travaux orphelins : %s", [(str(l["id"])[:8], l["type"], l["etat"]) for l in lignes])
    recents = await fetch_one(
        """select count(*) as n from travail
            where etat = 'echec' and erreur like 'Interrompu%%' and finished_at > now() - interval '24 hours'""")
    if not recents["n"]:
        return []
    return [Constat("travaux_interrompus", "attention", f"{recents['n']} travail(aux) abandonné(s) après reprises",
                    "L'ouvrier s'est arrêté plusieurs fois sur le même travail. Voir la vue Travaux.",
                    {"nombre": recents["n"], "a_l_instant": len(abandonnes)})]


async def _sauvegarde() -> list[Constat]:
    l = await fetch_one("select max(fini_le) as derniere from sauvegarde")
    if l["derniere"] is None:
        if not settings.is_prod:
            return []
        return [Constat("sauvegarde_absente", "critique", "Aucune sauvegarde enregistrée",
                        "La base n'a jamais été sauvegardée par le script. Programmez-le chaque nuit.", {})]
    age_h = (datetime.now(timezone.utc) - l["derniere"]).total_seconds() / 3600
    if age_h <= 26:
        return []
    return [Constat("sauvegarde_ancienne", "critique", f"Dernière sauvegarde il y a {round(age_h)} h",
                    "La sauvegarde de la nuit n'a pas tourné. Vérifiez la tâche programmée et l'espace disque.",
                    {"derniere": l["derniere"], "age_heures": round(age_h, 1)})]


async def _ordonnanceur() -> list[Constat]:
    # Au démarrage, laisser le temps au premier tour de passer.
    if time.monotonic() - DEMARRAGE < 45 * 60:
        return []
    dernier = PASSAGES.get("reconciliation")
    if dernier is not None and time.monotonic() - dernier < 45 * 60:
        return []
    return [Constat("reconciliation_arretee", "critique", "La réconciliation des paiements ne tourne plus",
                    "Aucun passage depuis 45 min. Redémarrez l'API et lisez ses journaux.",
                    {"dernier_passage_il_y_a_s": None if dernier is None else round(time.monotonic() - dernier)})]


CONTROLES = [_paiements_bloques, _webhooks_orphelins, _courriels, _disjoncteurs,
             _travaux_orphelins, _sauvegarde, _ordonnanceur]


# ----------------------------------------------------------------- incidents

async def _administrateurs() -> list[str]:
    return [l["email"] for l in await fetch_all(
        "select email from app_user where est_admin and is_active and email is not null")]


def _duree(debut: datetime, fin: datetime) -> str:
    minutes = int((fin - debut).total_seconds() // 60)
    heures, minutes = divmod(minutes, 60)
    return f"{heures} h {minutes:02d}" if heures else f"{minutes} min"


async def passer() -> dict:
    """Un passage de veille. Retourne ce qui a été ouvert, gardé et refermé."""
    import json

    from app.services.courriel import service as courriel

    constats: list[Constat] = []
    incomplet = False
    for controle in CONTROLES:
        try:
            constats += await controle()
        except Exception:  # noqa: BLE001 - un contrôle cassé ne doit pas masquer les autres
            incomplet = True
            log.exception("Contrôle de veille %s en échec.", controle.__name__)

    ouverts, gardes = [], []
    admins = await _administrateurs()
    for c in constats:
        ligne = await fetch_one(
            """insert into incident (cle, gravite, titre, detail)
               values (%s, %s, %s, %s::jsonb)
               on conflict (cle) where clos_le is null
               do update set vu_le = now(), titre = excluded.titre, detail = excluded.detail,
                             gravite = excluded.gravite
               returning id, ouvert_le, alerte_envoyee_le, (xmax = 0) as nouveau""",
            (c.cle, c.gravite, c.titre, json.dumps(c.detail, default=str, ensure_ascii=False)),
        )
        (ouverts if ligne["nouveau"] else gardes).append(c.cle)
        if ligne["alerte_envoyee_le"] is None and c.gravite in ("attention", "critique") and admins:
            for email in admins:
                await courriel.envoyer("alerte_exploitation", destinataire=email, contexte={
                    "gravite": c.gravite, "titre": c.titre, "explication": c.explication,
                    "ouvert_le": ligne["ouvert_le"].astimezone().strftime("%d/%m/%Y à %H:%M"),
                })
            await execute("update incident set alerte_envoyee_le = now() where id = %s", (ligne["id"],))

    if incomplet:
        return {"ouverts": ouverts, "gardes": gardes, "refermes": [], "incomplet": True}
    actifs = [c.cle for c in constats]
    refermes = await fetch_all(
        """update incident set clos_le = now()
            where clos_le is null and not (cle = any(%s))
        returning cle, titre, ouvert_le, clos_le, alerte_envoyee_le""",
        (actifs,),
    )
    for r in refermes:
        if r["alerte_envoyee_le"] is not None:
            for email in admins:
                await courriel.envoyer("alerte_resolue", destinataire=email, contexte={
                    "titre": r["titre"],
                    "ouvert_le": r["ouvert_le"].astimezone().strftime("%d/%m/%Y à %H:%M"),
                    "clos_le": r["clos_le"].astimezone().strftime("%d/%m/%Y à %H:%M"),
                    "duree": _duree(r["ouvert_le"], r["clos_le"]),
                })
    if ouverts or refermes:
        log.warning("Veille : ouverts %s, refermés %s", ouverts, [r["cle"] for r in refermes])
    return {"ouverts": ouverts, "gardes": gardes, "refermes": [r["cle"] for r in refermes]}


async def etat() -> dict:
    """Ce que montre la vue Santé de la console."""
    incidents = await fetch_all(
        """select id, cle, gravite, titre, detail, ouvert_le, vu_le, clos_le, alerte_envoyee_le
             from incident where clos_le is null or clos_le > now() - interval '7 days'
            order by clos_le is not null, ouvert_le desc limit 50""")
    file = await fetch_one(
        """select count(*) filter (where statut = 'echec' and prochaine_tentative is not null) as en_file,
                  count(*) filter (where statut = 'abandonne' and created_at > now() - interval '7 days') as abandonnes_7j,
                  count(*) filter (where statut in ('envoye', 'simule') and tentatives > 1
                                     and created_at > now() - interval '7 days') as rattrapes_7j
             from email_log""")
    travaux = await fetch_one(
        """select count(*) filter (where etat = 'en_cours') as en_cours,
                  count(*) filter (where etat = 'en_attente') as en_attente,
                  count(*) filter (where reprises > 0 and created_at > now() - interval '7 days') as repris_7j
             from travail""")
    sauvegarde = await fetch_one("select fichier, octets, fini_le from sauvegarde order by fini_le desc limit 1")
    maintenant = time.monotonic()
    return {
        "incidents": incidents,
        "disjoncteurs": [d.vue() for d in DISJONCTEURS.values()],
        "courriels": file,
        "travaux": travaux,
        "sauvegarde": sauvegarde,
        "ordonnanceur": {k: round(maintenant - v) for k, v in PASSAGES.items()},
    }
