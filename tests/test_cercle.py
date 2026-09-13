"""Le cercle de lecteurs, de bout en bout.

Ce qui doit tenir :

- on ajoute un lecteur par son code, jamais par son nom, et l'amitié n'existe
  qu'acceptée ; deux demandes croisées se rejoignent ;
- on n'écrit et on n'encourage qu'un ami ; un identifiant quelconque ne dit
  même pas si le compte existe ;
- le fil ne montre que les amis qui partagent leur activité ;
- un blocage coupe tout, et ne se révèle pas ;
- on ne signale que ce qu'on a reçu, et la console ne lit que ce qui est
  signalé ; un message masqué disparaît des deux côtés ;
- les plafonds quotidiens arrêtent un robot sans gêner un lecteur.

Les appels passent par HTTP comme ceux de l'application.
"""
import asyncio
import sys
import uuid
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "apps" / "api"))
sys.path.insert(0, str(RACINE / "tests"))

from commun import appel, suffixe  # noqa: E402

from app.core.db import close_pool, execute, fetch_one, open_pool  # noqa: E402
from app.core.security import hash_password  # noqa: E402

_resultats = []
MDP = "lecture-guidee-2026"


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + str(detail) if detail else ""))


def inscrire(nom):
    email = f"cercle-{suffixe()}-{uuid.uuid4().hex[:4]}@example.com"
    st, r, _ = appel("POST", "/v1/auth/inscription", {"email": email, "mot_de_passe": MDP, "nom": nom})
    assert st == 201, (st, r)
    jeton = r["jetons"]["access_token"]
    _, moi, _ = appel("GET", "/v1/cercle/moi", jeton=jeton)
    return {"id": r["utilisateur"]["id"], "jeton": jeton, "code": moi["code"], "nom": nom}


async def admin():
    email = f"cercle-adm-{suffixe()}@example.com"
    await execute(
        """insert into app_user (email, display_name, password_hash, plan, est_admin)
           values (%s, 'Console', %s, 'free', true)""",
        (email, hash_password(MDP)),
    )
    _, r, _ = appel("POST", "/v1/auth/connexion", {"email": email, "mot_de_passe": MDP})
    return r["jetons"]["access_token"]


async def seance(user_id, duree=25):
    doc = await fetch_one("select id from document order by id limit 1")
    ligne = await fetch_one(
        """insert into progress_event (user_id, document_id, type, payload)
           values (%s, %s, 'read_pages', %s::jsonb) returning id""",
        (user_id, doc["id"], f'{{"statut": "fait", "duree_min": {duree}}}'),
    )
    return str(ligne["id"])


async def main():
    await open_pool()
    try:
        awa, ben, chloe, dan = inscrire("Awa Mbarga"), inscrire("Ben"), inscrire("Chloé"), inscrire("Dan")
        jeton_admin = await admin()

        print("\n· Se trouver et devenir amis")
        st, r, _ = appel("GET", "/v1/cercle/moi")
        ok("le cercle exige un compte", st == 401, st)
        ok("chaque lecteur a un code ASCENDA", all(x["code"] for x in (awa, ben, chloe, dan)), awa["code"])
        st, r, _ = appel("POST", "/v1/cercle/amis", {"code": "PERSONNE-ZZZZ"}, jeton=awa["jeton"])
        ok("un code inconnu est refusé avec un message clair", st == 422 and "code" in r["detail"]["message"], (st, r))
        st, r, _ = appel("POST", "/v1/cercle/amis", {"code": awa["code"]}, jeton=awa["jeton"])
        ok("son propre code est refusé", st == 422, st)
        st, r, _ = appel("POST", "/v1/cercle/amis", {"code": " " + ben["code"].lower() + " "}, jeton=awa["jeton"])
        ok("un code recopié en minuscules avec des espaces fonctionne",
           st == 201 and r["statut"] == "en_attente" and r["ami"]["nom"] == "Ben", (st, r))
        st, r, _ = appel("POST", "/v1/cercle/amis", {"code": ben["code"]}, jeton=awa["jeton"])
        ok("une seconde demande identique est refusée", st == 409, st)

        _, moi_ben, _ = appel("GET", "/v1/cercle/moi", jeton=ben["jeton"])
        ok("Ben voit une demande en attente dans ses compteurs", moi_ben["compteurs"]["demandes"] == 1, moi_ben)
        _, dem, _ = appel("GET", "/v1/cercle/demandes", jeton=ben["jeton"])
        ok("la demande reçue porte le prénom, sans l'adresse",
           len(dem["recues"]) == 1 and dem["recues"][0]["lecteur"]["nom"] == "Awa"
           and "email" not in str(dem), dem)
        _, dem_awa, _ = appel("GET", "/v1/cercle/demandes", jeton=awa["jeton"])
        ok("Awa la voit parmi ses demandes envoyées", len(dem_awa["envoyees"]) == 1, dem_awa)

        st, r, _ = appel("POST", f"/v1/cercle/echanges/{ben['id']}", {"texte": "Salut"}, jeton=awa["jeton"])
        ok("avant acceptation, on ne peut pas écrire", st == 404, st)
        st, r, _ = appel("POST", f"/v1/cercle/demandes/{dem['recues'][0]['id']}/accepter", jeton=awa["jeton"])
        ok("seul le destinataire peut accepter", st == 404, st)
        st, r, _ = appel("POST", f"/v1/cercle/demandes/{dem['recues'][0]['id']}/accepter", jeton=ben["jeton"])
        ok("Ben accepte", st == 200 and r["statut"] == "acceptee", (st, r))

        st, r, _ = appel("POST", "/v1/cercle/amis", {"code": chloe["code"]}, jeton=dan["jeton"])
        st, r, _ = appel("POST", "/v1/cercle/amis", {"code": dan["code"]}, jeton=chloe["jeton"])
        ok("deux demandes croisées deviennent une amitié", st == 201 and r["statut"] == "acceptee", (st, r))
        st, r, _ = appel("POST", "/v1/cercle/amis", {"code": awa["code"]}, jeton=chloe["jeton"])
        _, dem_a, _ = appel("GET", "/v1/cercle/demandes", jeton=awa["jeton"])
        st, r, _ = appel("POST", f"/v1/cercle/demandes/{dem_a['recues'][0]['id']}/refuser", jeton=awa["jeton"])
        ok("Awa refuse Chloé", st == 200 and r["statut"] == "refusee", (st, r))
        st, r, _ = appel("POST", "/v1/cercle/amis", {"code": awa["code"]}, jeton=chloe["jeton"])
        ok("un refus ne se contourne pas en redemandant tout de suite", st == 409, (st, r))

        print("\n· Le fil et la semaine des amis")
        ev_ben = await seance(ben["id"], 30)
        await seance(ben["id"], 20)
        await seance(dan["id"], 15)
        _, amis, _ = appel("GET", "/v1/cercle/amis", jeton=awa["jeton"])
        ok("Awa voit Ben et sa semaine : 2 séances, 50 minutes",
           len(amis) == 1 and amis[0]["nom"] == "Ben" and amis[0]["lecture"]["seances_semaine"] == 2
           and amis[0]["lecture"]["minutes_semaine"] == 50, amis)
        _, fil, _ = appel("GET", "/v1/cercle/fil", jeton=awa["jeton"])
        ok("le fil d'Awa montre les séances de Ben, et pas celles de Dan",
           len(fil) == 2 and all(f["lecteur"]["nom"] == "Ben" for f in fil)
           and "30 min" in next(f for f in fil if f["id"] == ev_ben)["texte"], fil)

        appel("PATCH", "/v1/cercle/preferences", {"partage_activite": False}, jeton=ben["jeton"])
        _, fil, _ = appel("GET", "/v1/cercle/fil", jeton=awa["jeton"])
        _, amis, _ = appel("GET", "/v1/cercle/amis", jeton=awa["jeton"])
        ok("Ben cesse de partager : il sort du fil, sa semaine est masquée",
           fil == [] and amis[0]["lecture"] == {"partage": False}, (fil, amis))
        appel("PATCH", "/v1/cercle/preferences", {"partage_activite": True}, jeton=ben["jeton"])

        print("\n· Encourager")
        st, r, _ = appel("POST", "/v1/cercle/encouragements",
                         {"ami_id": ben["id"], "genre": "bravo", "evenement_id": ev_ben}, jeton=awa["jeton"])
        ok("Awa encourage la séance de Ben", st == 201 and r["message"] == "Bravo pour ta lecture !", (st, r))
        st, r, _ = appel("POST", "/v1/cercle/encouragements",
                         {"ami_id": ben["id"], "genre": "bravo", "evenement_id": ev_ben}, jeton=awa["jeton"])
        ok("une même séance ne s'encourage qu'une fois", st == 409, st)
        _, fil, _ = appel("GET", "/v1/cercle/fil", jeton=awa["jeton"])
        ok("le fil marque la séance comme encouragée",
           next(f for f in fil if f["id"] == ev_ben)["encourage"] is True, fil)
        st, r, _ = appel("POST", "/v1/cercle/encouragements",
                         {"ami_id": dan["id"], "genre": "courage"}, jeton=awa["jeton"])
        ok("on n'encourage pas un lecteur hors de son cercle", st == 404, st)
        st, r, _ = appel("POST", "/v1/cercle/encouragements",
                         {"ami_id": ben["id"], "genre": "courage", "evenement_id": await seance(dan["id"])},
                         jeton=awa["jeton"])
        ok("ni l'activité d'un autre lecteur glissée dans la demande", st == 404, st)
        st, r, _ = appel("POST", "/v1/cercle/encouragements",
                         {"ami_id": ben["id"], "genre": "courage", "message": "Tu tiens le rythme, continue."},
                         jeton=awa["jeton"])
        ok("un encouragement peut porter un mot personnel", st == 201 and "rythme" in r["message"], (st, r))
        st, r, _ = appel("POST", "/v1/cercle/encouragements",
                         {"ami_id": ben["id"], "genre": "insulte"}, jeton=awa["jeton"])
        ok("un genre inconnu est refusé", st == 422, st)

        _, moi_ben, _ = appel("GET", "/v1/cercle/moi", jeton=ben["jeton"])
        _, recus, _ = appel("GET", "/v1/cercle/encouragements", jeton=ben["jeton"])
        ok("Ben reçoit 2 encouragements nouveaux, l'un rattaché à son livre",
           moi_ben["compteurs"]["encouragements"] == 2 and len(recus) == 2
           and all(x["nouveau"] for x in recus) and any(x["ouvrage"] for x in recus), (moi_ben, recus))
        appel("POST", "/v1/cercle/encouragements/vus", jeton=ben["jeton"])
        _, moi_ben, _ = appel("GET", "/v1/cercle/moi", jeton=ben["jeton"])
        ok("une fois vus, le compteur retombe", moi_ben["compteurs"]["encouragements"] == 0, moi_ben)

        print("\n· Échanger")
        st, m1, _ = appel("POST", f"/v1/cercle/echanges/{ben['id']}",
                          {"texte": "Tu en es où du chapitre 3 ?"}, jeton=awa["jeton"])
        ok("Awa écrit à Ben", st == 201 and m1["de_moi"] is True, (st, m1))
        st, m2, _ = appel("POST", f"/v1/cercle/echanges/{awa['id']}",
                          {"texte": "Presque fini, il est dense."}, jeton=ben["jeton"])
        st, r, _ = appel("POST", f"/v1/cercle/echanges/{ben['id']}", {"texte": "   "}, jeton=awa["jeton"])
        ok("un message vide est refusé", st == 422, st)
        st, r, _ = appel("POST", f"/v1/cercle/echanges/{ben['id']}", {"texte": "x" * 2001}, jeton=awa["jeton"])
        ok("un message trop long est refusé", st == 422, st)
        st, r, _ = appel("POST", f"/v1/cercle/echanges/{dan['id']}", {"texte": "Bonjour"}, jeton=awa["jeton"])
        ok("écrire hors de son cercle répond « introuvable »", st == 404, st)
        st, r, _ = appel("GET", f"/v1/cercle/echanges/{uuid.uuid4()}", jeton=awa["jeton"])
        ok("un identifiant inventé ne révèle rien", st == 404, st)
        st, r, _ = appel("GET", "/v1/cercle/echanges/pas-un-identifiant", jeton=awa["jeton"])
        ok("un identifiant mal formé est refusé proprement, sans erreur serveur", st == 422, st)

        _, amis_a, _ = appel("GET", "/v1/cercle/amis", jeton=awa["jeton"])
        ok("Awa voit 1 message non lu de Ben", amis_a[0]["non_lus"] == 1, amis_a)
        _, conv, _ = appel("GET", f"/v1/cercle/echanges/{ben['id']}", jeton=awa["jeton"])
        ok("la conversation se lit dans l'ordre, du plus ancien au plus récent",
           [m["texte"] for m in conv["messages"]] == ["Tu en es où du chapitre 3 ?", "Presque fini, il est dense."]
           and conv["messages"][1]["de_moi"] is False, conv)
        st, r, _ = appel("POST", f"/v1/cercle/echanges/{ben['id']}/lus", jeton=awa["jeton"])
        _, moi_a, _ = appel("GET", "/v1/cercle/moi", jeton=awa["jeton"])
        ok("marquée lue, le compteur de messages retombe", r["marques"] == 1 and moi_a["compteurs"]["messages"] == 0,
           (r, moi_a))
        _, conv_b, _ = appel("GET", f"/v1/cercle/echanges/{awa['id']}", jeton=ben["jeton"])
        ok("Ben voit que son message a été lu", conv_b["messages"][1]["lu"] is True, conv_b)
        st, r, _ = appel("GET", f"/v1/cercle/echanges/{ben['id']}", jeton=dan["jeton"])
        ok("un tiers ne lit pas la conversation", st == 404, st)

        print("\n· Signaler et modérer")
        st, r, _ = appel("POST", "/v1/cercle/signalements",
                         {"echange_id": m1["id"], "motif": "Test de signalement"}, jeton=awa["jeton"])
        ok("on ne signale pas son propre message", st == 404, st)
        st, r, _ = appel("POST", "/v1/cercle/signalements",
                         {"echange_id": m2["id"], "motif": "Test"}, jeton=dan["jeton"])
        ok("ni un message d'une conversation où l'on n'est pas", st == 404, st)
        st, sig, _ = appel("POST", "/v1/cercle/signalements",
                           {"echange_id": m1["id"], "motif": "Propos déplacés"}, jeton=ben["jeton"])
        ok("Ben signale le message reçu d'Awa", st == 201, (st, sig))
        st, r, _ = appel("POST", "/v1/cercle/signalements",
                         {"echange_id": m1["id"], "motif": "Encore"}, jeton=ben["jeton"])
        ok("un message ne se signale qu'une fois", st == 409, st)

        st, vue, _ = appel("GET", "/v1/admin/cercle", jeton=awa["jeton"])
        ok("la console du cercle est réservée aux administrateurs", st == 403, st)
        st, vue, _ = appel("GET", "/v1/admin/cercle", jeton=jeton_admin)
        ok("la console compte amitiés, échanges et signalements",
           st == 200 and vue["amities"] >= 2 and vue["echanges_7j"] >= 2 and vue["signalements_ouverts"] >= 1
           and len(vue["jours"]) == 14, vue)
        st, rel, _ = appel("GET", "/v1/admin/cercle/relations?par_page=200", jeton=jeton_admin)
        paire = next((l for l in rel["lignes"] if {x["id"] for x in l["lecteurs"]} == {awa["id"], ben["id"]}), None)
        ok("les relations montrent le volume d'échanges, jamais le contenu",
           paire and paire["echanges"] == 2 and "Presque fini" not in str(rel), paire)
        st, sigs, _ = appel("GET", "/v1/admin/cercle/signalements", jeton=jeton_admin)
        ligne = next((l for l in sigs["lignes"] if l["id"] == sig["id"]), None)
        ok("le message signalé, lui, se lit dans la console avec son auteur",
           ligne and ligne["contenu"] == "Tu en es où du chapitre 3 ?" and ligne["auteur"]["id"] == awa["id"], ligne)
        st, r, _ = appel("POST", f"/v1/admin/cercle/signalements/{sig['id']}", {"decision": "masque"},
                         jeton=jeton_admin)
        _, conv_b, _ = appel("GET", f"/v1/cercle/echanges/{awa['id']}", jeton=ben["jeton"])
        _, conv_a, _ = appel("GET", f"/v1/cercle/echanges/{ben['id']}", jeton=awa["jeton"])
        ok("masqué, le message disparaît des deux côtés",
           st == 200 and len(conv_b["messages"]) == 1 and len(conv_a["messages"]) == 1, (conv_a, conv_b))
        _, sigs, _ = appel("GET", "/v1/admin/cercle/signalements", jeton=jeton_admin)
        ok("et le signalement est clos", all(l["id"] != sig["id"] for l in sigs["lignes"]), sigs["total"])
        st, fiche, _ = appel("GET", f"/v1/admin/cercle/lecteurs/{awa['id']}", jeton=jeton_admin)
        ok("la fiche d'Awa dans la console compte le signalement reçu",
           st == 200 and fiche["signalements_recus"] == 1 and fiche["echanges_ecrits"] == 1, fiche)

        print("\n· Plafonds")
        await execute(
            """insert into echange (auteur_id, destinataire_id, texte)
               select %s, %s, 'rafale' from generate_series(1, 300)""",
            (dan["id"], chloe["id"]),
        )
        st, r, _ = appel("POST", f"/v1/cercle/echanges/{chloe['id']}", {"texte": "une de plus"}, jeton=dan["jeton"])
        ok("au-delà de 300 messages en un jour, un refus poli", st == 429 and "demain" in r["detail"]["message"],
           (st, r))

        print("\n· Retirer et bloquer")
        st, r, _ = appel("POST", f"/v1/cercle/bloquer/{awa['id']}", jeton=ben["jeton"])
        ok("Ben bloque Awa", st == 204, st)
        _, amis_a, _ = appel("GET", "/v1/cercle/amis", jeton=awa["jeton"])
        ok("l'amitié disparaît", amis_a == [], amis_a)
        st, r, _ = appel("POST", "/v1/cercle/amis", {"code": ben["code"]}, jeton=awa["jeton"])
        ok("Awa ne peut plus demander Ben, et le message ne révèle pas le blocage",
           st == 422 and "Aucun lecteur" in r["detail"]["message"], (st, r))
        st, r, _ = appel("POST", f"/v1/cercle/echanges/{awa['id']}", {"texte": "?"}, jeton=ben["jeton"])
        ok("et Ben ne peut plus lui écrire non plus", st == 404, st)
        st, r, _ = appel("DELETE", f"/v1/cercle/amis/{chloe['id']}", jeton=dan["jeton"])
        _, amis_d, _ = appel("GET", "/v1/cercle/amis", jeton=dan["jeton"])
        ok("Dan retire Chloé de son cercle", st == 204 and amis_d == [], (st, amis_d))
        st, r, _ = appel("DELETE", f"/v1/cercle/amis/{chloe['id']}", jeton=dan["jeton"])
        ok("la retirer deux fois répond « introuvable »", st == 404, st)
    finally:
        await execute("delete from app_user where email like 'cercle-%%@example.com'")
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
