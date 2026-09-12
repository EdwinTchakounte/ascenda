"""Encaissement, rattachement, réconciliation, abonnement.

La discipline vient du module `mail+paiement`, où elle a été durcie en
production. Les quatre points qui comptent :

1. **Une clé d'idempotence par paiement.** Rejouer un webhook ne crédite jamais
   deux fois.
2. **Un rattachement en cascade.** Tara ne renvoie pas toujours notre
   `productId`. Sans repli, un membre paie et rien ne se passe.
3. **Une réconciliation périodique.** Un webhook peut se perdre. On interroge
   alors le fournisseur, et on abandonne au bout de 24 heures plutôt que de
   laisser un paiement en attente indéfiniment.
4. **Un webhook qui répond toujours 200.** Sinon Tara rejoue en boucle. L'échec
   est journalisé, pas renvoyé.

Tout ce qui touche un paiement laisse une ligne dans `payment_event`. C'est ce
qui permet de répondre à « pourquoi ce paiement a-t-il été validé ».
"""
import json
import logging
from datetime import datetime, timedelta, timezone

from app.core.config import settings
from app.core.db import connection, fetch_all, fetch_one
from app.core.errors import Conflict, NotFound

from .base import ErreurFournisseur, EvenementWebhook
from .tara import Tara, normaliser_telephone

log = logging.getLogger("ascenda.paiement")

# Fenêtre du rattachement par téléphone. Au-delà, le risque d'attribuer le
# paiement d'un membre à un autre dépasse le bénéfice.
FENETRE_TELEPHONE = timedelta(minutes=30)

FOURNISSEURS = {"tara": Tara}


def fournisseur(code: str = "tara"):
    if code not in FOURNISSEURS:
        raise NotFound(f"Fournisseur de paiement inconnu : {code}.")
    return FOURNISSEURS[code]()


async def tracer(payment_id: str | None, type_: str, source: str,
                 payload: dict | None = None, strategie: str | None = None) -> None:
    """Le journal. Append-only, jamais modifié."""
    async with connection() as conn:
        await conn.execute(
            """insert into payment_event (payment_id, type, source, strategie, payload)
               values (%s, %s, %s, %s, %s::jsonb)""",
            (payment_id, type_, source, strategie, json.dumps(payload or {}, default=str)),
        )


# --------------------------------------------------------------------- achat

async def tarifs(plan: str = "premium") -> list[dict]:
    return await fetch_all(
        """select id, plan, periode_mois, montant, devise, libelle
           from plan_tarif where plan = %s and actif order by periode_mois""",
        (plan,),
    )


async def creer(user: dict, periode_mois: int, plan: str = "premium") -> dict:
    tarif = await fetch_one(
        """select montant, devise, libelle from plan_tarif
           where plan = %s and periode_mois = %s and actif""",
        (plan, periode_mois),
    )
    if not tarif:
        raise NotFound("Cette formule n'est pas proposée.")

    # Un paiement déjà en attente pour le même utilisateur est réutilisé plutôt
    # que dupliqué : deux popups de paiement sur un téléphone, c'est un débit
    # de trop.
    en_cours = await fetch_one(
        """select * from payment
           where user_id = %s and statut = 'en_attente'
             and created_at > now() - interval '30 minutes'
           order by created_at desc limit 1""",
        (user["id"],),
    )
    if en_cours and en_cours["periode_mois"] == periode_mois:
        return en_cours

    paiement = await fetch_one(
        """insert into payment (user_id, plan_cible, periode_mois, montant, devise)
           values (%s, %s, %s, %s, %s) returning *""",
        (user["id"], plan, periode_mois, tarif["montant"], tarif["devise"]),
    )
    await tracer(str(paiement["id"]), "cree", "api",
                 {"periode_mois": periode_mois, "montant": tarif["montant"]})
    return paiement


async def initier(paiement: dict, telephone: str, reseau: str) -> dict:
    """Déclenche la demande de paiement sur le téléphone du membre."""
    f = fournisseur(paiement["provider_code"])

    # En production, un fournisseur sans identifiants renvoie une référence
    # factice : le lecteur voit une demande partir, n'est jamais débité, et son
    # paiement reste en attente pour toujours. Une caisse qui fait semblant de
    # fonctionner est pire qu'une caisse fermée, parce qu'elle ne se signale
    # pas. On refuse donc d'initier, et on le dit.
    #
    # Le commentaire de `Tara.simule` affirmait que l'API refusait de démarrer
    # dans ce cas. C'était faux : rien ne le vérifiait. Refuser le démarrage
    # serait d'ailleurs excessif, une mise en ligne sans encaissement est un
    # état légitime le temps d'obtenir les clés.
    if settings.is_prod and f.simule:
        raise Conflict(
            "Le paiement n'est pas encore ouvert. Les abonnements seront "
            "disponibles très bientôt, et votre compte reste utilisable en "
            "attendant."
        )

    tel = normaliser_telephone(telephone)

    libelle = await fetch_one(
        "select libelle from plan_tarif where plan = %s and periode_mois = %s",
        (paiement["plan_cible"], paiement["periode_mois"]),
    )
    try:
        resultat = await f.initier(
            {**paiement, "libelle": (libelle or {}).get("libelle")},
            telephone=tel, reseau=reseau,
        )
    except ErreurFournisseur as exc:
        await tracer(str(paiement["id"]), "initiation_echouee", "api",
                     {"message": exc.message, "rejouable": exc.rejouable, "brut": exc.brut})
        raise Conflict(
            "La demande de paiement n'a pas pu être envoyée. "
            + ("Réessayez dans un instant." if exc.rejouable else exc.message)
        ) from exc

    async with connection() as conn:
        cur = await conn.execute(
            """update payment
                  set telephone = %s, reseau = %s, reference_externe = %s,
                      gateway_initiated_at = now(), gateway_reponse = %s::jsonb,
                      updated_at = now()
                where id = %s returning *""",
            (tel, reseau, resultat.reference_fournisseur,
             json.dumps(resultat.brut, default=str), paiement["id"]),
        )
        maj = await cur.fetchone()

    await tracer(str(paiement["id"]), "initie", "api",
                 {"telephone": tel, "reseau": reseau, "simule": f.simule})

    # En développement, sans identifiants Tara, on valide immédiatement : sinon
    # aucun parcours d'abonnement n'est testable en local.
    if settings.paiement_test_auto_valide and f.simule:
        log.warning("Validation automatique (mode test) du paiement %s", paiement["id"])
        await appliquer(maj, "valide", source="systeme", strategie="mode_test")
        maj = await fetch_one("select * from payment where id = %s", (paiement["id"],))

    return maj


# -------------------------------------------------------------- rattachement

async def rattacher(evenement: EvenementWebhook) -> tuple[dict | None, str | None]:
    """Retrouve le paiement visé par une notification.

    Trois stratégies en cascade, dans cet ordre. La troisième n'est pas un
    raffinement : c'est la seule qui fonctionne quand Tara ne propage pas notre
    `productId`, ce qui arrive en pratique.
    """
    # 1. Notre clé d'idempotence, renvoyée sous `productId`.
    cle = (evenement.cle_idempotence or "").strip()
    if len(cle) == 36 and cle.count("-") == 4:
        p = await fetch_one("select * from payment where idempotency_key = %s", (cle,))
        if p:
            return p, "cle_idempotence"

    # 2. La référence du fournisseur, si nous l'avions déjà enregistrée.
    for reference in (cle, evenement.reference_fournisseur):
        if not reference:
            continue
        p = await fetch_one(
            """select * from payment where reference_externe = %s
               order by (statut = 'en_attente') desc, created_at desc limit 1""",
            (reference,),
        )
        if p:
            return p, "reference_externe"

    # 3. Le téléphone, sur un paiement en attente de moins de trente minutes.
    if evenement.telephone:
        try:
            tel = normaliser_telephone(evenement.telephone)
        except ErreurFournisseur:
            tel = None
        if tel:
            p = await fetch_one(
                """select * from payment
                   where telephone = %s and statut = 'en_attente'
                     and created_at > now() - %s::interval
                   order by created_at desc limit 1""",
                (tel, f"{int(FENETRE_TELEPHONE.total_seconds())} seconds"),
            )
            if p:
                return p, "telephone_recent"

    return None, None


async def appliquer(paiement: dict, statut: str, *, source: str,
                    strategie: str | None = None, motif: str | None = None) -> bool:
    """Pose le statut d'un paiement. Idempotent : un paiement déjà validé ne
    l'est pas deux fois, et n'ouvre donc pas deux fois l'abonnement.

    Retourne True si quelque chose a changé.
    """
    if paiement["statut"] == statut:
        await tracer(str(paiement["id"]), f"deja_{statut}", source, strategie=strategie)
        return False
    if paiement["statut"] == "valide":
        # Un paiement validé ne redevient pas en attente ni rejeté sur la foi
        # d'une notification tardive.
        await tracer(str(paiement["id"]), "changement_refuse", source,
                     {"vers": statut}, strategie=strategie)
        return False

    async with connection() as conn:
        await conn.execute(
            """update payment
                  set statut = %s, motif_rejet = %s,
                      date_validation = case when %s = 'valide' then now() else null end,
                      updated_at = now()
                where id = %s""",
            (statut, motif, statut, paiement["id"]),
        )

    await tracer(str(paiement["id"]), statut, source, {"motif": motif}, strategie=strategie)

    if statut == "valide":
        abonnement = await ouvrir_abonnement(paiement)
        await _prevenir("paiement_confirme", paiement, abonnement)
    elif statut == "rejete":
        await _prevenir("paiement_rejete", {**paiement, "motif_rejet": motif}, None)
    return True


async def _prevenir(evenement: str, paiement: dict, abonnement: dict | None) -> None:
    """Écrit au membre, sans jamais faire tomber ce qui a déclenché l'envoi.

    Cette fonction est appelée depuis le webhook de paiement. Une panne du
    service de courriel ne doit pas empêcher un abonnement de s'ouvrir : le
    membre a payé, le reçu est second.
    """
    try:
        from app.services.courriel import evenements

        if evenement == "paiement_confirme":
            await evenements.paiement_confirme(paiement, abonnement)
        else:
            await evenements.paiement_rejete(paiement)
    except Exception:  # noqa: BLE001
        log.exception("Courriel %s non envoyé pour le paiement %s", evenement, paiement.get("id"))


# ------------------------------------------------------------------ webhook

async def traiter_webhook(corps: bytes, code: str = "tara") -> dict:
    """Toujours renvoyer 200, quoi qu'il arrive.

    Un code d'erreur ferait rejouer Tara en boucle sans rien résoudre. Ce qui ne
    passe pas est journalisé, et un webhook non rattaché est conservé avec un
    `payment_id` nul : c'est la première chose à regarder quand un membre
    affirme avoir payé.
    """
    f = fournisseur(code)
    try:
        evenement = f.lire_webhook(corps)
    except ErreurFournisseur as exc:
        await tracer(None, "webhook_illisible", "webhook",
                     {"message": exc.message, "corps": corps[:500].decode("utf-8", "replace")})
        return {"recu": True, "traite": False, "raison": exc.message}

    paiement, strategie = await rattacher(evenement)
    if not paiement:
        await tracer(None, "webhook_orphelin", "webhook", evenement.brut)
        log.warning("Webhook non rattaché : %s", evenement.brut)
        return {"recu": True, "traite": False, "raison": "paiement introuvable"}

    if evenement.reference_fournisseur and not paiement["reference_externe"]:
        async with connection() as conn:
            await conn.execute(
                "update payment set reference_externe = %s where id = %s",
                (evenement.reference_fournisseur, paiement["id"]),
            )

    change = await appliquer(
        paiement, evenement.statut, source="webhook", strategie=strategie,
        motif=None if evenement.statut != "rejete" else "Refusé par le fournisseur.",
    )
    return {"recu": True, "traite": change, "strategie": strategie, "statut": evenement.statut}


# ----------------------------------------------------------- réconciliation

async def reconcilier(taille: int = 100, pause: float | None = None) -> dict:
    """Repêche les paiements restés en attente.

    Un webhook peut se perdre. On interroge alors le fournisseur. Au bout de
    24 heures sans réponse, on abandonne : laisser un paiement en attente
    indéfiniment empêche le membre d'en relancer un.

    Tara supporte mal les rafales : on espace les appels.
    """
    import asyncio

    limite = datetime.now(timezone.utc) - timedelta(hours=settings.reconciliation_timeout_heures)
    en_attente = await fetch_all(
        """select * from payment
           where statut = 'en_attente' and gateway_initiated_at is not null
           order by gateway_initiated_at limit %s""",
        (taille,),
    )
    bilan = {"examines": len(en_attente), "valides": 0, "rejetes": 0,
             "abandonnes": 0, "inchanges": 0, "erreurs": 0}

    for i, paiement in enumerate(en_attente):
        if paiement["gateway_initiated_at"] and paiement["gateway_initiated_at"] <= limite:
            await appliquer(
                paiement, "rejete", source="reconciliation", strategie="timeout",
                motif=f"Aucune confirmation en {settings.reconciliation_timeout_heures} h.",
            )
            bilan["abandonnes"] += 1
            continue

        if i:
            # Tara supporte mal les rafales : environ trois appels par minute.
            # La pause est paramétrable pour que les vérifications n'aient pas
            # à l'attendre.
            await asyncio.sleep(
                settings.reconciliation_pause_secondes if pause is None else pause
            )
        try:
            statut = await fournisseur(paiement["provider_code"]).statut(paiement)
        except ErreurFournisseur as exc:
            await tracer(str(paiement["id"]), "reconciliation_echouee", "reconciliation",
                         {"message": exc.message})
            bilan["erreurs"] += 1
            continue

        if statut == "en_attente":
            bilan["inchanges"] += 1
            continue
        if await appliquer(paiement, statut, source="reconciliation", strategie="interrogation"):
            bilan["valides" if statut == "valide" else "rejetes"] += 1

    return bilan


# -------------------------------------------------------------- abonnement

async def ouvrir_abonnement(paiement: dict) -> dict:
    """Ouvre ou prolonge l'abonnement, puis passe le compte au plan payé.

    Prolonger plutôt que remplacer : un membre qui paie avant l'échéance ne doit
    pas perdre les jours qui lui restaient.
    """
    mois = int(paiement["periode_mois"] or 1)
    jours = mois * 30

    courant = await fetch_one(
        """select * from subscription
           where user_id = %s and status = 'active' and current_end > now()
           order by current_end desc limit 1""",
        (paiement["user_id"],),
    )
    depart = courant["current_end"] if courant else datetime.now(timezone.utc)
    fin = depart + timedelta(days=jours)

    async with connection() as conn:
        if courant:
            cur = await conn.execute(
                """update subscription
                      set current_end = %s, periode_mois = %s, amount_cents = %s
                    where id = %s returning *""",
                (fin, mois, paiement["montant"], courant["id"]),
            )
        else:
            cur = await conn.execute(
                """insert into subscription (user_id, plan, provider, provider_ref, status,
                                             current_start, current_end, amount_cents,
                                             currency, periode_mois)
                   values (%s, %s, %s, %s, 'active', now(), %s, %s, %s, %s) returning *""",
                (paiement["user_id"], paiement["plan_cible"], paiement["provider_code"],
                 paiement["reference_externe"], fin, paiement["montant"],
                 paiement["devise"], mois),
            )
        abonnement = await cur.fetchone()

        await conn.execute(
            """update payment set subscription_id = %s, nb_jours_couverts = %s where id = %s""",
            (abonnement["id"], jours, paiement["id"]),
        )
        await conn.execute(
            """update app_user set plan = %s, plan_since = coalesce(plan_since, now()),
                                   plan_until = %s
                where id = %s""",
            (paiement["plan_cible"], fin, paiement["user_id"]),
        )

    await tracer(str(paiement["id"]), "abonnement_ouvert", "systeme",
                 {"jusqu_au": fin.isoformat(), "jours": jours})
    return abonnement


async def fermer_echus() -> dict:
    """Ferme les abonnements arrivés à terme.

    Le compte repasse en `free`, et les quotas referment l'accès d'eux-mêmes :
    ils lisent déjà le plan. Il n'y a donc rien d'autre à couper.
    """
    async with connection() as conn:
        cur = await conn.execute(
            """update subscription set status = 'expired', closed_at = now()
                where status = 'active' and current_end <= now()
                returning id, user_id, current_end""",
        )
        echus = await cur.fetchall()

        ferme = 0
        for a in echus:
            # On ne redescend que si aucun autre abonnement ne couvre encore.
            cur = await conn.execute(
                """select 1 from subscription
                   where user_id = %s and status = 'active' and current_end > now() limit 1""",
                (a["user_id"],),
            )
            if await cur.fetchone():
                continue
            await conn.execute(
                "update app_user set plan = 'free', plan_until = null where id = %s",
                (a["user_id"],),
            )
            ferme += 1

    if echus:
        await tracer(None, "abonnements_fermes", "systeme",
                     {"expires": len(echus), "comptes_redescendus": ferme})

    # Prévenir après la transaction, jamais dedans : un envoi lent tiendrait la
    # table `subscription` verrouillée le temps de joindre le fournisseur.
    for a in echus:
        try:
            from app.services.courriel import evenements

            await evenements.abonnement_echu(str(a["user_id"]), a.get("current_end"))
        except Exception:  # noqa: BLE001
            log.exception("Courriel de fin d'abonnement non envoyé pour %s", a["user_id"])

    return {"expires": len(echus), "comptes_redescendus": ferme}


async def bientot_echus(jours: int = 5) -> list[dict]:
    """Les abonnements qui se terminent bientôt, pour la relance par courriel."""
    return await fetch_all(
        """select s.id, s.user_id, s.current_end, u.email, u.display_name
           from subscription s join app_user u on u.id = s.user_id
           where s.status = 'active'
             and s.current_end between now() and now() + %s::interval""",
        (f"{jours} days",),
    )
