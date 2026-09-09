"""Le fournisseur Tara, sans réseau et sans identifiants.

Les autres suites appellent l'API par HTTP sur des données réelles. Celle-ci
fait l'inverse : elle isole le seul morceau du système que nous ne pourrons pas
essayer en vrai avant d'avoir un compte marchand ouvert.

Ce qui est vérifié ici tient en une phrase : le jour où Tara appellera notre
webhook, saurons-nous lire ce qu'il envoie. Les charges utiles reproduisent
celles observées en production sur l'implémentation dont ce fournisseur est
porté, y compris les cas tordus (pas de `productId`, statut inconnu, corps
illisible), parce que ce sont eux qui font perdre de l'argent.
"""
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "apps" / "api"))

from app.services.paiement.base import ErreurFournisseur  # noqa: E402
from app.services.paiement.tara import STATUTS, Tara, normaliser_telephone  # noqa: E402

_resultats = []


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + str(detail) if detail else ""))


def leve(libelle, fonction):
    try:
        fonction()
    except ErreurFournisseur as exc:
        ok(libelle, True, exc.message)
    except Exception as exc:  # noqa: BLE001
        ok(libelle, False, f"mauvaise exception : {type(exc).__name__} {exc}")
    else:
        ok(libelle, False, "aucune exception")


def corps(charge: dict) -> bytes:
    import json as _json
    return _json.dumps(charge).encode("utf-8")


print("\n· Le numéro, mis au format que Tara accepte")
for brut, attendu in [
    ("677889900", "237677889900"),
    ("0677889900", "237677889900"),
    ("+237 677 88 99 00", "237677889900"),
    ("237677889900", "237677889900"),
    ("(237) 6-77-88-99-00", "237677889900"),
]:
    obtenu = normaliser_telephone(brut)
    ok(f"{brut!r} donne {attendu}", obtenu == attendu, obtenu)

leve("numéro vide refusé", lambda: normaliser_telephone(""))
leve("numéro sans chiffre refusé", lambda: normaliser_telephone("appelle-moi"))

print("\n· La table des statuts")
for brut in ["SUCCESS", "VALIDATED", "COMPLETED", "PAID"]:
    ok(f"{brut} vaut valide", STATUTS.get(brut) == "valide")
for brut in ["PENDING", "INITIATED"]:
    ok(f"{brut} vaut en attente", STATUTS.get(brut) == "en_attente")
for brut in ["FAILED", "REJECTED", "CANCELLED", "ERROR"]:
    ok(f"{brut} vaut rejete", STATUTS.get(brut) == "rejete")

t = Tara()

print("\n· Le webhook, tel que Tara l'envoie")
e = t.lire_webhook(corps({
    "productId": "cle-a-nous", "status": "SUCCESS",
    "paymentId": "TARA-77", "phoneNumber": "237677889900",
}))
ok("productId devient notre clé", e.cle_idempotence == "cle-a-nous", e.cle_idempotence)
ok("le statut est traduit", e.statut == "valide", e.statut)
ok("la référence Tara est gardée", e.reference_fournisseur == "TARA-77", e.reference_fournisseur)
ok("le téléphone est gardé", e.telephone == "237677889900", e.telephone)

e = t.lire_webhook(corps({"collectionId": "COL-9", "status": "SUCCESS"}))
ok("sans productId, on retombe sur collectionId", e.cle_idempotence == "COL-9", e.cle_idempotence)

e = t.lire_webhook(corps({"productId": "x", "status": "FAILED"}))
ok("un échec reste un rejet", e.statut == "rejete", e.statut)

# Un statut que Tara inventerait demain ne doit surtout pas valider un paiement.
e = t.lire_webhook(corps({"productId": "x", "status": "QUANTUM"}))
ok("un statut inconnu reste en attente", e.statut == "en_attente", e.statut)

e = t.lire_webhook(corps({}))
ok("un corps vide donne une clé vide", e.cle_idempotence == "", repr(e.cle_idempotence))

leve("un corps illisible est refusé", lambda: t.lire_webhook(b"ceci n'est pas du json"))

print("\n· Le contrôle du marchand, seul rempart faute de signature")
t.business_id = "ASCENDA-42"
e = t.lire_webhook(corps({"productId": "x", "status": "SUCCESS", "businessId": "ASCENDA-42"}))
ok("notre businessId passe", e.statut == "valide")
leve("un autre businessId est refusé",
     lambda: t.lire_webhook(corps({"productId": "x", "businessId": "QUELQU-UN-DAUTRE"})))
# Tara n'a pas toujours propagé le champ : l'absence ne doit pas tout bloquer.
e = t.lire_webhook(corps({"productId": "x", "status": "SUCCESS"}))
ok("un webhook sans businessId reste lisible", e.statut == "valide")

print("\n· Le mode simulé, qui est notre état par défaut aujourd'hui")
vide = Tara()
vide.cle = ""
vide.business_id = ""
ok("sans identifiants, Tara est simulé", vide.simule is True)
plein = Tara()
plein.cle = "k"
plein.business_id = "b"
ok("avec identifiants, Tara appelle le réseau", plein.simule is False)

import asyncio  # noqa: E402

resultat = asyncio.run(vide.initier(
    {"idempotency_key": "abc-123", "montant": 3000, "libelle": "Essai"},
    telephone="677889900", reseau="MTN",
))
ok("le mode simulé ne sort pas sur le réseau", resultat.brut.get("simule") is True)
ok("il rend notre propre clé", resultat.reference_fournisseur == "abc-123",
   resultat.reference_fournisseur)
ok("le mode simulé ne valide jamais de lui-même",
   asyncio.run(vide.statut({"idempotency_key": "abc-123"})) == "en_attente")

print("\n· La requête réellement envoyée, avec un transport bouchonné")

import httpx  # noqa: E402

_vues = []


def _transport(reponse):
    """Un client httpx qui ne sort pas de la machine et note ce qu'on lui donne."""
    def gerer(requete: httpx.Request) -> httpx.Response:
        import json as _json
        _vues.append({"url": str(requete.url), "charge": _json.loads(requete.content)})
        return reponse
    original = httpx.AsyncClient

    def fabrique(*a, **k):
        return original(*a, **{**k, "transport": httpx.MockTransport(gerer)})

    return original, fabrique


def _avec(reponse, action):
    original, fabrique = _transport(reponse)
    httpx.AsyncClient = fabrique
    try:
        return action()
    finally:
        httpx.AsyncClient = original


reel = Tara()
reel.cle = "cle-marchand"
reel.business_id = "ASCENDA-42"
paiement = {"idempotency_key": "id-987", "montant": 8000, "libelle": "Ascension, trois mois"}

_vues.clear()
r = _avec(
    httpx.Response(200, json={"status": "PENDING", "message": "ok"}),
    lambda: asyncio.run(reel.initier(paiement, telephone="0677889900", reseau="MTN")),
)
envoye = _vues[-1]["charge"] if _vues else {}
ok("l'appel part sur dklo.co", _vues and "dklo.co/api/tara/mobilepay" in _vues[-1]["url"],
   _vues[-1]["url"] if _vues else "aucun appel")
ok("productPrice est un entier", isinstance(envoye.get("productPrice"), int),
   repr(envoye.get("productPrice")))
ok("le téléphone part en 2376XXXXXXXX", envoye.get("phoneNumber") == "237677889900",
   envoye.get("phoneNumber"))
ok("network est laissé vide, Tara déduit l'opérateur", envoye.get("network") == "",
   repr(envoye.get("network")))
ok("productId porte notre clé", envoye.get("productId") == "id-987", envoye.get("productId"))
ok("le webhook annoncé est le nôtre",
   str(envoye.get("webHookUrl", "")).endswith("/v1/paiements/webhook/tara"),
   envoye.get("webHookUrl"))
ok("nos identifiants accompagnent la demande",
   envoye.get("apiKey") == "cle-marchand" and envoye.get("businessId") == "ASCENDA-42")
ok("la référence rendue est notre clé", r.reference_fournisseur == "id-987",
   r.reference_fournisseur)

print("\n· Ce que fait le fournisseur quand Tara va mal")


def _echec(reponse):
    return lambda: asyncio.run(reel.initier(paiement, telephone="677889900", reseau="MTN"))


def _attendu(libelle, reponse, rejouable):
    try:
        _avec(reponse, _echec(reponse))
    except ErreurFournisseur as exc:
        ok(libelle, exc.rejouable is rejouable,
           f"rejouable={exc.rejouable} : {exc.message[:70]}")
    except Exception as exc:  # noqa: BLE001
        ok(libelle, False, f"{type(exc).__name__} : {exc}")
    else:
        ok(libelle, False, "aucune exception")


# Une panne serveur se rejoue ; un refus métier, jamais : le rejouer débiterait
# une seconde fois pour la même raison de refus.
_attendu("une erreur 500 est rejouable", httpx.Response(500, text="boom"), True)
_attendu("un refus 400 n'est pas rejouable",
         httpx.Response(400, json={"message": "solde insuffisant"}), False)
_attendu("une page HTML au lieu de JSON est refusée",
         httpx.Response(200, text="<html>maintenance</html>"), False)
# Tara signale parfois une erreur métier avec un code HTTP 200.
_attendu("un statut ERROR en HTTP 200 est refusé",
         httpx.Response(200, json={"status": "ERROR", "message": "compte inconnu"}), False)

print("\n· Le statut interrogé au fournisseur")
_vues.clear()
statut = _avec(
    httpx.Response(200, json={"status": "SUCCESS"}),
    lambda: asyncio.run(reel.statut({"idempotency_key": "id-987"})),
)
ok("SUCCESS remonte comme valide", statut == "valide", statut)
ok("l'interrogation porte notre clé",
   _vues and _vues[-1]["charge"].get("productId") == "id-987")

print("\n· Les adresses annoncées à Tara")
ok("le webhook pointe sur notre route",
   t._url_webhook().endswith("/v1/paiements/webhook/tara"), t._url_webhook())
ok("le retour pointe sur une page à nous",
   t._url_retour().endswith("/paiement/retour"), t._url_retour())

print("\n" + "=" * 92)
_echecs = [x for x in _resultats if not x[0]]
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
sys.exit(1 if _echecs else 0)
