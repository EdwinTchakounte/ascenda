"""Codes d'accès et programme ambassadeur, de bout en bout."""
import asyncio
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "apps" / "api"))
sys.path.insert(0, str(RACINE / "tests"))

from commun import appel, suffixe  # noqa: E402

from app.core.db import close_pool, execute, fetch_one, open_pool  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.services.paiement import service as paiement  # noqa: E402

_resultats = []
MDP = "lecture-guidee-2026"


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + str(detail) if detail else ""))


def dans(jours: float) -> str:
    return (datetime.now(timezone.utc) + timedelta(days=jours)).isoformat()


def inscrire(nom="Lecteur", code=None):
    email = f"codes-{suffixe()}-{uuid.uuid4().hex[:4]}@example.com"
    corps = {"email": email, "mot_de_passe": MDP, "nom": nom}
    if code is not None:
        corps["code"] = code
    statut, r, _ = appel("POST", "/v1/auth/inscription", corps)
    jeton = (r or {}).get("jetons", {}).get("access_token") if statut == 201 else None
    return statut, r, email, jeton


def plafond(jeton, compteur):
    _, u, _ = appel("GET", "/v1/compte/usage", jeton=jeton)
    for c in (u or {}).get("compteurs", []):
        if c["type"] == compteur:
            return c["limite"]
    return "absent"


async def admin():
    email = f"codes-adm-{suffixe()}@example.com"
    await execute(
        """insert into app_user (email, display_name, password_hash, plan, est_admin)
           values (%s, 'Console', %s, 'free', true)""",
        (email, hash_password(MDP)),
    )
    _, r, _ = appel("POST", "/v1/auth/connexion", {"email": email, "mot_de_passe": MDP})
    return r["jetons"]["access_token"]


async def main():
    await open_pool()
    crees = []
    try:
        # Le lancement ouvrirait tout à tout le monde et rendrait chaque
        # vérification d'accès vraie pour une mauvaise raison.
        await execute("update reglage set valeur = valeur || '{\"actif\": false}' where cle = 'lancement'")
        await execute("""update reglage set valeur = '{"actif": true, "pourcent": 20, "validite_jours": 180}'
                         where cle = 'parrainage'""")
        jeton_admin = await admin()
        s = suffixe(4).upper()

        print("\n· La console crée les codes")
        code_complet = f"LANCEMENT-{s}"
        st, c1, _ = appel("POST", "/v1/admin/codes", {
            "code": code_complet.lower(), "libelle": "Lancement", "niveau": "complet",
            "fin": dans(30), "duree_jours": 7}, jeton=jeton_admin)
        ok("code complet créé, saisi en minuscules et rangé en majuscules",
           st == 201 and c1["code"] == code_complet and c1["statut"] == "actif", (st, c1))
        crees.append(c1["id"])

        code_limite = f"QUIZ-{s}"
        st, c2, _ = appel("POST", "/v1/admin/codes", {
            "code": code_limite, "libelle": "Quiz et export", "niveau": "limite",
            "fonctions": ["quiz_generated", "export_pdf"], "fin": dans(30), "max_utilisations": 1},
            jeton=jeton_admin)
        ok("code limité créé avec ses deux fonctions",
           st == 201 and sorted(c2["fonctions"]) == ["export_pdf", "quiz_generated"], (st, c2))
        crees.append(c2["id"])

        st, r, _ = appel("POST", "/v1/admin/codes", {
            "code": code_complet, "libelle": "Doublon", "niveau": "complet", "fin": dans(3)}, jeton=jeton_admin)
        ok("un doublon est refusé", st == 409, st)
        st, r, _ = appel("POST", "/v1/admin/codes", {
            "code": f"VIDE-{s}", "libelle": "Vide", "niveau": "limite", "fonctions": [], "fin": dans(3)},
            jeton=jeton_admin)
        ok("un code limité sans fonction est refusé", st == 422, st)
        st, r, _ = appel("POST", "/v1/admin/codes", {
            "code": f"PASSE-{s}", "libelle": "Passé", "niveau": "complet", "fin": dans(-1)}, jeton=jeton_admin)
        ok("une fin déjà passée est refusée", st == 422, st)
        st, r, _ = appel("POST", "/v1/admin/codes", {
            "code": f"MAUVAIS-{s}", "libelle": "Inconnue", "niveau": "limite",
            "fonctions": ["tout_gratuit"], "fin": dans(3)}, jeton=jeton_admin)
        ok("une fonction hors catalogue est refusée", st == 422, st)
        st, r, _ = appel("POST", "/v1/admin/codes", {
            "code": "A B!", "libelle": "Forme", "niveau": "complet", "fin": dans(3)}, jeton=jeton_admin)
        ok("une forme de code invalide est refusée", st in (422,), st)

        st, _, _, jeton_simple = inscrire()
        st, _, _ = appel("GET", "/v1/admin/codes", jeton=jeton_simple)
        ok("un lecteur ne voit pas la liste des codes", st == 403, st)
        st, _, _ = appel("POST", "/v1/admin/codes", {
            "code": f"PIRATE-{s}", "libelle": "x", "niveau": "complet", "fin": dans(3)}, jeton=jeton_simple)
        ok("ni n'en crée", st == 403, st)

        print("\n· Un code refusé ne crée pas de compte")
        st, r, email_refus, _ = inscrire(code="CODE-QUI-N-EXISTE-PAS")
        ok("inscription refusée avec un code inconnu", st == 404, (st, r))
        compte = await fetch_one("select 1 from app_user where email = %s", (email_refus,))
        ok("et aucun compte n'est resté", compte is None)
        st, r, _, _ = inscrire(code="   ")
        ok("un champ de code vide ne gêne pas l'inscription", st == 201, st)

        print("\n· Code complet à l'inscription")
        st, r, email_a, jeton_a = inscrire("Awa Diallo", code=f" {code_complet.lower()} ")
        acces = r["utilisateur"]["acces"] if st == 201 else {}
        ok("compte créé et code appliqué", st == 201 and r["code_applique"]["type"] == "acces", (st, r and r.get("code_applique")))
        ok("l'accès est complet, venu d'un code", acces.get("complet") and acces.get("source") == "code", acces)
        ok("le plan du compte n'a pas changé", r["utilisateur"]["plan"] == "free")
        fin = datetime.fromisoformat(acces["jusqu_au"].replace("Z", "+00:00"))
        ok("la durée de 7 jours s'applique, et non la fin du code à 30 jours",
           timedelta(days=6.9) < fin - datetime.now(timezone.utc) < timedelta(days=7.1), fin)
        ok("les questions à l'agent ont le plafond d'Ascension", plafond(jeton_a, "agent_question") == 400,
           plafond(jeton_a, "agent_question"))
        ok("l'export PDF est ouvert", plafond(jeton_a, "export_pdf") is None)
        st, r, _ = appel("POST", "/v1/codes/activer", {"code": code_complet}, jeton=jeton_a)
        ok("activer deux fois le même code est refusé", st == 409, st)

        print("\n· Code limité depuis le profil")
        st, _, email_b, jeton_b = inscrire("Bruno")
        ok("sans code, Découverte", plafond(jeton_b, "export_pdf") == 0 and plafond(jeton_b, "agent_question") == 20)
        st, r, _ = appel("POST", "/v1/codes/activer", {"code": code_limite.lower()}, jeton=jeton_b)
        ok("code limité activé depuis le profil", st == 200 and r["niveau"] == "limite", (st, r))
        ok("l'export et les quiz passent au plafond d'Ascension",
           plafond(jeton_b, "export_pdf") is None and plafond(jeton_b, "quiz_generated") is None)
        ok("les questions à l'agent restent au plafond de Découverte", plafond(jeton_b, "agent_question") == 20)
        _, moi_b, _ = appel("GET", "/v1/auth/moi", jeton=jeton_b)
        ok("l'accès décrit les fonctions ouvertes, sans être complet",
           moi_b["acces"]["complet"] is False and sorted(moi_b["acces"]["fonctions"]) == ["export_pdf", "quiz_generated"],
           moi_b["acces"])
        st, _, _ = appel("POST", "/v1/chronogrammes/00000000-0000-0000-0000-000000000000/replanifier",
                         {}, jeton=jeton_b)
        ok("la replanification, non incluse, reste refusée", st == 403, st)
        st, _, _ = appel("POST", "/v1/chronogrammes/00000000-0000-0000-0000-000000000000/replanifier",
                         {}, jeton=jeton_a)
        ok("elle passe le garde avec le code complet (introuvable ensuite, pas interdite)", st == 404, st)

        st, _, _, jeton_c = inscrire("Chloé")
        st, r, _ = appel("POST", "/v1/codes/activer", {"code": code_limite}, jeton=jeton_c)
        ok("le code à usage unique refuse une deuxième personne", st == 422 and "maximal" in r["detail"]["message"], (st, r))

        print("\n· Tout code s'arrête")
        u_a = await fetch_one("select id from app_user where email = %s", (email_a,))
        await execute("update code_acces_utilisation set fin = now() - interval '1 minute' where user_id = %s",
                      (u_a["id"],))
        _, moi_a, _ = appel("GET", "/v1/auth/moi", jeton=jeton_a)
        ok("à la fin de sa durée, l'accès se referme", moi_a["acces"]["complet"] is False
           and moi_a["acces"]["source"] == "aucune", moi_a["acces"])
        ok("et les plafonds reviennent à Découverte", plafond(jeton_a, "agent_question") == 20)

        await execute("update code_acces set fin = now() - interval '1 minute', debut = now() - interval '2 days' where id = %s",
                      (c2["id"],))
        ok("à la date de fin du code, l'accès limité se referme aussi", plafond(jeton_b, "export_pdf") == 0)
        st, _, _, jeton_d = inscrire("Dora")
        st, r, _ = appel("POST", "/v1/codes/activer", {"code": code_complet}, jeton=jeton_d)
        ok("un code encore valable s'active", st == 200, st)
        st, r, _ = appel("PATCH", f"/v1/admin/codes/{c1['id']}", {"actif": False}, jeton=jeton_admin)
        ok("la console désactive le code", st == 200 and r["statut"] == "desactive", (st, r))
        _, moi_d, _ = appel("GET", "/v1/auth/moi", jeton=jeton_d)
        ok("et l'accès qu'il avait ouvert se referme aussitôt", moi_d["acces"]["complet"] is False, moi_d["acces"])
        st, r, _, _ = inscrire(code=code_complet)
        ok("un code désactivé refuse l'inscription", st == 422, (st, r))

        st, c3, _ = appel("POST", "/v1/admin/codes", {
            "code": f"BIENTOT-{s}", "libelle": "Plus tard", "niveau": "complet",
            "debut": dans(2), "fin": dans(10)}, jeton=jeton_admin)
        crees.append(c3["id"])
        st, r, _ = appel("POST", "/v1/codes/activer", {"code": f"BIENTOT-{s}"}, jeton=jeton_d)
        ok("un code programmé n'est pas encore utilisable", st == 422 and c3["statut"] == "programme", (st, c3["statut"]))

        st, detail, _ = appel("GET", f"/v1/admin/codes/{c1['id']}", jeton=jeton_admin)
        ok("la console liste qui a utilisé un code", st == 200 and detail["utilisations"] == 2
           and len(detail["utilisateurs"]) == 2, (st, detail.get("utilisations")))

        print("\n· Programme ambassadeur")
        st, r, email_p, jeton_p = inscrire("Paul Mbarga")
        _, mes, _ = appel("GET", "/v1/codes/moi", jeton=jeton_p)
        code_p = mes["ambassadeur"]["code"]
        ok("chaque lecteur a son code, formé sur son prénom", code_p.startswith("PAUL-") and len(code_p) == 9, code_p)
        _, mes_bis, _ = appel("GET", "/v1/codes/moi", jeton=jeton_p)
        ok("et ce code ne change pas d'un appel à l'autre", mes_bis["ambassadeur"]["code"] == code_p)

        st, r, _ = appel("POST", "/v1/codes/activer", {"code": code_p}, jeton=jeton_p)
        ok("son propre code ne s'active pas sur son compte", st == 422, st)

        st, r, email_f, jeton_f = inscrire("Fanta Sow", code=code_p.lower())
        ok("un filleul s'inscrit avec le code", st == 201 and r["code_applique"]["type"] == "parrainage", (st, r and r.get("code_applique")))
        ok("le message remercie avec le prénom de l'ambassadeur", "Paul" in r["code_applique"]["message"], r["code_applique"])
        f = await fetch_one("select parrain_id from app_user where email = %s", (email_f,))
        p = await fetch_one("select id from app_user where email = %s", (email_p,))
        ok("le filleul est rattaché à son ambassadeur", str(f["parrain_id"]) == str(p["id"]))

        _, mes, _ = appel("GET", "/v1/codes/moi", jeton=jeton_p)
        bon = (mes["bons"] or [{}])[0]
        ok("l'ambassadeur a un bon de 20 %", bon.get("pourcent") == 20 and bon.get("statut") == "disponible", mes["bons"])
        ok("le bon nomme le filleul par son prénom seulement", bon.get("filleul") == "Fanta", bon)
        ok("la notification dans l'application est en attente", mes["nouveaux"] == 1 and bon.get("nouveau"), mes["nouveaux"])
        ok("un filleul compté", mes["ambassadeur"]["filleuls"] == 1)
        courriel = await fetch_one(
            """select objet, statut from email_log where user_id = %s and template = 'parrainage_recompense'""",
            (p["id"],))
        ok("l'ambassadeur est prévenu par courriel", courriel is not None and "Fanta" in courriel["objet"]
           and "20 %" in courriel["objet"], courriel)
        st, _, _ = appel("POST", "/v1/codes/bons/vus", jeton=jeton_p)
        _, mes, _ = appel("GET", "/v1/codes/moi", jeton=jeton_p)
        ok("une fois vue, la notification ne revient pas", st == 204 and mes["nouveaux"] == 0, mes["nouveaux"])

        st, r, _ = appel("POST", "/v1/codes/activer", {"code": code_p}, jeton=jeton_d)
        ok("un code ambassadeur ne s'utilise pas après l'inscription", st == 422, (st, r))

        print("\n· La réduction sur le prochain abonnement")
        _, tarifs, _ = appel("GET", "/v1/paiements/tarifs", jeton=jeton_p)
        mois = next(t for t in tarifs["formules"] if t["periode_mois"] == 1)
        ok("les tarifs montrent la réduction à l'ambassadeur", tarifs["reduction"]["pourcent"] == 20
           and mois["montant_reduit"] == mois["montant"] * 8 // 10, (tarifs["reduction"], mois))
        _, tarifs_anonyme, _ = appel("GET", "/v1/paiements/tarifs")
        ok("mais pas à un visiteur", tarifs_anonyme["reduction"] is None)

        user_p = await fetch_one("select * from app_user where id = %s", (p["id"],))
        p1 = await paiement.creer(user_p, 1)
        ok("le paiement est créé au prix réduit", p1["montant"] == mois["montant_reduit"]
           and p1["montant_brut"] == mois["montant"] and p1["reduction_pourcent"] == 20, (p1["montant"], p1["montant_brut"]))
        p2 = await paiement.creer(user_p, 3)
        ok("un second paiement lancé en parallèle ne profite pas du même bon", p2["bon_id"] is None, p2["montant"])
        await paiement.appliquer(p2, "rejete", source="admin", motif="essai")
        await paiement.appliquer(p1, "rejete", source="admin", motif="essai")
        p3 = await paiement.creer(user_p, 12)
        ok("un paiement rejeté rend le bon", p3["bon_id"] is not None and p3["reduction_pourcent"] == 20, p3["montant"])
        await paiement.appliquer(p3, "valide", source="admin", strategie="essai")
        b = await fetch_one("select utilise_le, payment_id from bon_reduction where id = %s", (p3["bon_id"],))
        ok("le paiement validé consomme le bon", b["utilise_le"] is not None and str(b["payment_id"]) == str(p3["id"]), b)
        p4 = await paiement.creer(user_p, 1)
        ok("le suivant est au plein tarif", p4["bon_id"] is None and p4["montant"] == mois["montant"], p4["montant"])
        await paiement.appliquer(p4, "rejete", source="admin", motif="essai")
        _, mes, _ = appel("GET", "/v1/codes/moi", jeton=jeton_p)
        ok("le bon apparaît comme utilisé", mes["bons"][0]["statut"] == "utilise" and mes["reduction_prochaine"] is None,
           mes["bons"][0])

        print("\n· Chaque filleul rapporte un bon, une seule fois")
        st, r, email_g, _ = inscrire("Grace", code=code_p)
        _, mes, _ = appel("GET", "/v1/codes/moi", jeton=jeton_p)
        ok("un deuxième filleul, un deuxième bon", len(mes["bons"]) == 2 and mes["ambassadeur"]["filleuls"] == 2, len(mes["bons"]))
        g = await fetch_one("select * from app_user where email = %s", (email_g,))
        from app.services import codes as service_codes
        await service_codes._parrainer(g, await fetch_one("select * from app_user where id = %s", (p["id"],)))
        n = await fetch_one("select count(*) as n from bon_reduction where filleul_id = %s", (g["id"],))
        ok("rejouer le parrainage du même filleul ne crée pas de bon", n["n"] == 1, n)
        await execute("update bon_reduction set expire_le = now() - interval '1 minute' where filleul_id = %s", (g["id"],))
        _, tarifs, _ = appel("GET", "/v1/paiements/tarifs", jeton=jeton_p)
        ok("un bon expiré ne réduit plus rien", tarifs["reduction"] is None, tarifs["reduction"])

        print("\n· Réglage du programme")
        st, _, _ = appel("POST", "/v1/admin/reglages/parrainage",
                         {"valeur": {"actif": True, "pourcent": 150, "validite_jours": 30}}, jeton=jeton_admin)
        ok("une réduction au delà de 90 % est refusée", st == 409, st)
        st, _, _ = appel("POST", "/v1/admin/reglages/parrainage",
                         {"valeur": {"actif": False, "pourcent": 25, "validite_jours": 30}}, jeton=jeton_admin)
        st2, r, email_h, _ = inscrire("Hugo", code=code_p)
        ok("programme suspendu : le code ambassadeur est refusé à l'inscription", st == 200 and st2 == 422, (st, st2, r))
        st, _, _ = appel("POST", "/v1/admin/reglages/parrainage",
                         {"valeur": {"actif": True, "pourcent": 25, "validite_jours": 30}}, jeton=jeton_admin)
        st, r, _, _ = inscrire("Ines", code=code_p)
        bon_ines = await fetch_one(
            """select b.pourcent, b.expire_le from bon_reduction b join app_user f on f.id = b.filleul_id
                where f.display_name = 'Ines' and b.user_id = %s""", (p["id"],))
        ok("réactivé à 25 % sur 30 jours, le nouveau bon suit le réglage",
           bon_ines and bon_ines["pourcent"] == 25
           and timedelta(days=29.9) < bon_ines["expire_le"] - datetime.now(timezone.utc) < timedelta(days=30.1), bon_ines)

        st, amb, _ = appel("GET", "/v1/admin/ambassadeurs", jeton=jeton_admin)
        ligne = next((l for l in amb.get("lignes", []) if l["code"] == code_p), None)
        ok("la console suit les ambassadeurs", st == 200 and ligne and ligne["filleuls"] == 3, ligne)
        st, fiche, _ = appel("GET", f"/v1/admin/utilisateurs/{p['id']}", jeton=jeton_admin)
        ok("et la fiche d'un compte montre son code et ses filleuls",
           st == 200 and fiche["parrainage"]["code_parrainage"] == code_p and fiche["parrainage"]["filleuls"] == 3,
           fiche.get("parrainage"))
    finally:
        await execute("""update reglage set valeur = '{"actif": true, "pourcent": 20, "validite_jours": 180}'
                         where cle = 'parrainage'""")
        await execute("delete from app_user where email like 'codes-%%@example.com'")
        await execute("delete from code_acces where code like '%%-' || %s", (s,)) if 's' in dir() else None
        await close_pool()


asyncio.run(main())

print("\n" + "=" * 92)
_echecs = [x for x in _resultats if not x[0]]
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
sys.exit(1 if _echecs else 0)
