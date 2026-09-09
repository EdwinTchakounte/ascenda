"""Le parcours complet d'un utilisateur, du compte au contenu.

On ne vérifie pas des routes : on vérifie qu'une personne peut faire ce que le
produit lui promet, dans l'ordre où elle le fera.
"""
import json, random, string, sys, urllib.error, urllib.request

import os
BASE = os.getenv("ASCENDA_API", "http://127.0.0.1:8250")
etapes, bloquants = [], []
_resultats = etapes

def call(m, p, b=None, tok=None, brut=False):
    d = b if brut else (json.dumps(b).encode() if b is not None else None)
    r = urllib.request.Request(BASE + p, data=d, method=m)
    r.add_header("Content-Type", "application/json")
    if tok: r.add_header("Authorization", f"Bearer {tok}")
    try:
        with urllib.request.urlopen(r, timeout=90) as x:
            body = x.read()
            if not body: return x.status, None
            try: return x.status, json.loads(body)
            except Exception: return x.status, {"_octets": len(body)}
    except urllib.error.HTTPError as e:
        body = e.read()
        try: return e.code, json.loads(body)
        except Exception: return e.code, None
    except Exception as e:
        return 0, {"_erreur": str(e)[:80]}

def etape(n, ok, detail="", bloquant=True):
    etapes.append((ok, n, detail))
    if not ok and bloquant: bloquants.append(n)
    print(("  OUI  " if ok else "  NON  ") + f"{n:46} {detail}")

sfx = "".join(random.choices(string.ascii_lowercase, k=6))
email = f"parcours-{sfx}@example.com"

print("\n1. OUVRIR UN COMPTE")
s, r = call("POST", "/v1/auth/inscription",
            {"email": email, "mot_de_passe": "lecture-guidee-2026", "nom": "Nouvel utilisateur"})
etape("créer le compte", s == 201, f"plan {r['utilisateur']['plan']}" if s == 201 else str(r)[:60])
if s != 201: sys.exit(1)
TOK, REF = r["jetons"]["access_token"], r["jetons"]["refresh_token"]
s, r2 = call("POST", "/v1/auth/connexion", {"email": email, "mot_de_passe": "lecture-guidee-2026"})
etape("se reconnecter plus tard", s == 200)
s, r3 = call("POST", "/v1/auth/rafraichir", {"refresh_token": REF})
etape("rester connecté sans ressaisir", s == 200)
TOK = r3["access_token"]

print("\n2. DIRE OÙ L'ON EN EST")
s, d = call("GET", "/v1/diagnostic?axe=04-ia-societe-ethique-philosophie")
sondes = [q for q in d["questions"] if q["cle"].startswith("sonde_")]
etape("répondre au questionnaire", s == 200 and d["total"] >= 6,
      f"{d['total']} questions dont {len(sondes)} tirées de vrais quiz")
rep = {"familiarite": 1, "objectif": "professionnel", "minutes_semaine": 150,
       "duree_seance": 30, "aisance_lecture": 2, "echeance": 84}
for q in sondes: rep[q["cle"]] = 0
s, prof = call("POST", "/v1/diagnostic", {"axe": "04-ia-societe-ethique-philosophie", "reponses": rep}, TOK)
etape("obtenir un niveau", s == 200, f"niveau {prof['niveau']}")

print("\n3. RECEVOIR UN PLAN")
s, ch = call("POST", "/v1/chronogrammes",
             {"axe": "04-ia-societe-ethique-philosophie", "date_cible": "2026-11-30"}, TOK)
etape("générer le chronogramme", s == 201 and len(ch["seances"]) > 10,
      f"{len(ch['seances'])} séances" if s == 201 else str(ch)[:60])
if s != 201: sys.exit(1)
durees = [x["duree_min"] for x in ch["seances"]]
etape("des séances tenables", min(durees) >= 8 and max(durees) <= 70,
      f"de {min(durees)} à {max(durees)} min")
avec_pages = sum(1 for x in ch["seances"] if x["page_debut"])
etape("des pages précises à lire", avec_pages == len(ch["seances"]),
      f"{avec_pages}/{len(ch['seances'])} séances avec une plage de pages")
jours = {str(x["prevue_le"])[:10] for x in ch["seances"]}
etape("étalées sur des jours distincts", len(jours) > 20, f"{len(jours)} jours")

print("\n4. SAVOIR QUOI FAIRE AUJOURD'HUI")
s, a = call("GET", "/v1/aujourdhui", tok=TOK)
etape("voir la séance du jour", s == 200 and a["seance"] is not None,
      a["seance"]["ouvrage"][:44] if a.get("seance") else "aucune")
sc = a["seance"]
etape("savoir combien de temps", bool(sc["duree_min"]), f"{sc['duree_min']} min")
etape("savoir quelles pages", bool(sc["page_debut"]), f"p. {sc['page_debut']} à {sc['page_fin']}")

print("\n5. ACCÉDER AU CONTENU")
DOC, CHAP = sc["document_id"], sc["chapitre_id"]
s, lec = call("GET", f"/v1/lecteur/{DOC}/chapitre/{CHAP}")
texte = sum(len(p["texte"]) for p in lec.get("passages", []))
etape("lire le chapitre", s == 200 and texte > 0, f"{texte} caractères servis")
etape("connaître ses droits sur l'ouvrage", "droits" in lec,
      "intégral" if lec["droits"]["lecture_integrale"] else "extraits plafonnés")
s, cit = call("GET", f"/v1/lecteur/{DOC}/citations")
etape("voir les citations vérifiées", s == 200 and cit["total"] > 0, f"{cit['total']} citations")
s, fic = call("GET", f"/v1/bibliotheque/{DOC}")
etape("lire la fiche de l'ouvrage", s == 200 and bool(fic.get("fiche_lecture")),
      f"{len(fic['pedagogie']['idees_force'])} idées-force")
s, som = call("GET", f"/v1/bibliotheque/{DOC}/sommaire")
etape("parcourir le sommaire", s == 200 and len(som) > 0, f"{len(som)} chapitres")

print("\n6. ÊTRE INTERROGÉ")
s, qz = call("GET", f"/v1/quiz/document/{DOC}", tok=TOK)
lot = next((c for c in (qz.get("chapitres") or []) if c["nb_questions"] > 0), None)
etape("trouver un quiz", lot is not None, f"{qz.get('total_questions', 0)} questions sur l'ouvrage")
if lot:
    s, q = call("GET", f"/v1/quiz/{lot['quiz_id']}", tok=TOK)
    etape("passer le quiz", s == 200, f"{len(q['questions'])} questions")
    etape("sans voir les réponses", all("reponse" not in x for x in q["questions"]))
    s, co = call("POST", f"/v1/quiz/{lot['quiz_id']}/corriger",
                 {"reponses": {"0": 0, "1": 1}, "duree_sec": 60}, TOK)
    etape("être corrigé", s == 200, f"score {int(co['score']*100)} %")
    d0 = co["details"][0]
    etape("comprendre pourquoi", bool(d0.get("explication")))
    etape("voir l'extrait qui le prouve", d0.get("extrait") is not None,
          f"p. {(d0.get('extrait') or {}).get('page')}")

print("\n7. POSER UNE QUESTION")
s, ag = call("POST", "/v1/agent/questions", {"question": "Qu'est-ce que le biais algorithmique ?"}, TOK)
etape("obtenir une réponse", s == 201, f"{len(ag['citations'])} sources")
etape("avec le livre et la page",
      all(c.get("ouvrage") and c.get("page") for c in ag["citations"][:3]),
      ", ".join(f"{c['ouvrage'][:22]} p.{c['page']}" for c in ag["citations"][:2]))
etape("rédaction automatique active", not ag["degrade"],
      "NON : ANTHROPIC_API_KEY absente, seules les sources sont renvoyées", bloquant=False)

print("\n8. EMPORTER L'OUVRAGE")
s, pk = call("GET", f"/v1/bibliotheque/{DOC}/pack")
etape("télécharger le pack hors ligne", s == 200 and pk["compteurs"]["questions"] > 0,
      f"{pk['compteurs']['chapitres']} chap., {pk['compteurs']['citations']} cit., "
      f"{pk['compteurs']['questions']} questions")
etape("les quiz restent corrigeables hors ligne",
      "reponse" in pk["quiz"][0]["questions"][0])
s, pdf = call("GET", f"/v1/bibliotheque/{DOC}/export.pdf")
etape("exporter en PDF", s == 200 and pdf.get("_octets", 0) > 20000,
      f"{pdf.get('_octets', 0)//1024} Ko")

print("\n9. SUIVRE SA PROGRESSION")
s, _ = call("PATCH", f"/v1/seances/{sc['id']}", {"statut": "fait", "duree_reelle_min": 27}, TOK)
etape("marquer une séance faite", s == 200)
s, pr = call("GET", "/v1/progression", tok=TOK)
etape("voir son avancement", s == 200 and pr["seances"]["faites"] >= 1,
      f"{pr['seances']['faites']}/{pr['seances']['total']} séances, {pr['seances']['minutes_lues']} min")
s, rg = call("GET", "/v1/progression/regularite?jours=14", tok=TOK)
etape("voir sa régularité", s == 200, f"série de {rg['serie_en_cours']} jour(s)")
s, rev = call("GET", "/v1/concepts/a-reviser", tok=TOK)
etape("retrouver les notions ratées", s == 200, f"{rev['total']} notion(s) à revoir")
s, n = call("POST", "/v1/notes", {"document_id": DOC, "page": 12, "texte": "Ma note"}, TOK)
etape("prendre une note", s == 201)

print("\n10. PAYER ET DÉBLOQUER")
s, tf = call("GET", "/v1/paiements/tarifs")
etape("voir les tarifs et moyens de paiement", s == 200 and len(tf["moyens"]) == 2,
      " et ".join(m["libelle"] for m in tf["moyens"]))
s, pay = call("POST", "/v1/paiements",
              {"periode_mois": 3, "telephone": "699112233", "reseau": "MTN"}, TOK)
etape("lancer un paiement mobile money", s == 201, f"{pay['montant']} {pay['devise']}")
s, ab = call("GET", "/v1/paiements/abonnement/etat", tok=TOK)
etape("abonnement ouvert", s == 200 and ab["actif"], f"{ab['jours_restants']} jours")
s, me = call("GET", "/v1/auth/moi", tok=TOK)
etape("compte passé en Ascension", me["plan"] == "premium", me["plan"])
s, c2 = call("POST", "/v1/chronogrammes", {"axe": "03-ia-outils-pratique-prompting"}, TOK)
etape("second axe débloqué", s == 201, f"{len(c2['seances'])} séances" if s == 201 else str(c2)[:50])
s, _ = call("POST", f"/v1/chronogrammes/{ch['id']}/replanifier", tok=TOK)
etape("replanification débloquée", s in (200, 409))
s, jr = call("GET", f"/v1/paiements/{pay['id']}", tok=TOK)
etape("paiement tracé de bout en bout", len(jr["journal"]) >= 4,
      " puis ".join(e["type"] for e in jr["journal"]))

print("\n" + "=" * 92)
oui = sum(1 for ok, _, _ in etapes if ok)
print(f"{oui} étapes franchies sur {len(etapes)}")
if bloquants:
    print("\nBLOQUANTS :")
    for b in bloquants: print(f"  - {b}")
else:
    print("\nAucun blocage : le parcours va du compte au contenu sans interruption.")


# --- verdict
#
# Une étape peut échouer sans que le produit soit inutilisable : la rédaction
# automatique de l'agent demande une clé d'API, et son absence ne casse aucun
# parcours. On la signale, on ne fait pas échouer la suite pour autant.
import sys as _sys
_ecarts = [l for l in _resultats if not l[0]]
print("\n" + "=" * 92)
print(f"{len(_resultats) - len(_ecarts)} sur {len(_resultats)}")
if _ecarts:
    print("\nÉCARTS")
    for _ok, _lib, _det in _ecarts:
        marque = "BLOQUANT" if _lib in bloquants else "signalé"
        print(f"  [{marque}] {_lib}\n      {_det}")
_sys.exit(1 if bloquants else 0)
