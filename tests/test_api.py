"""Audit : chaque route de l'API est appelée, et le résultat comparé à l'attendu."""
import json, random, string, sys, time, urllib.error, urllib.request

import os
BASE = os.getenv("ASCENDA_API", "http://127.0.0.1:8250")
resultats = []

def appel(methode, chemin, corps=None, tok=None, brut=False, delai=60):
    d = corps if brut else (json.dumps(corps).encode() if corps is not None else None)
    r = urllib.request.Request(BASE + chemin, data=d, method=methode)
    r.add_header("Content-Type", "application/json")
    if tok:
        r.add_header("Authorization", f"Bearer {tok}")
    t0 = time.time()
    try:
        with urllib.request.urlopen(r, timeout=delai) as x:
            b = x.read()
            corps_rep = None
            if b:
                try:
                    corps_rep = json.loads(b)
                except Exception:
                    corps_rep = {"_binaire": len(b)}
            return x.status, corps_rep, time.time() - t0
    except urllib.error.HTTPError as e:
        b = e.read()
        try:
            return e.code, json.loads(b), time.time() - t0
        except Exception:
            return e.code, None, time.time() - t0
    except Exception as e:
        return 0, {"_erreur": str(e)[:90]}, time.time() - t0

def v(nom, methode, chemin, attendu, corps=None, tok=None, brut=False, verif=None):
    s, r, ms = appel(methode, chemin, corps, tok, brut)
    ok = s in (attendu if isinstance(attendu, (list, tuple)) else [attendu])
    detail = ""
    if ok and verif:
        try:
            ok2 = verif(r)
            if ok2 is not True:
                ok, detail = False, str(ok2)[:70]
        except Exception as e:
            ok, detail = False, f"vérif: {type(e).__name__} {e}"[:70]
    if not ok and not detail:
        detail = (str(r)[:80] if r else f"HTTP {s}")
    resultats.append((ok, f"{methode:6} {chemin[:52]:52}", f"{s:>3}", f"{ms*1000:5.0f}ms", nom, detail))
    return r

sfx = "".join(random.choices(string.ascii_lowercase, k=7))

print("\n=== SERVICE ===")
v("santé", "GET", "/sante", 200, verif=lambda r: r["base"] == "ok" or "base non ok")
v("openapi", "GET", "/openapi.json", 200, verif=lambda r: len(r["paths"]) > 40 or "trop peu de routes")
v("docs", "GET", "/docs", 200)

print("=== PUBLIC, sans compte ===")
v("axes", "GET", "/v1/axes", 200, verif=lambda r: len(r) == 17 or f"{len(r)} axes")  # 11 axes et les 6 sous-axes du pôle Agriculture
v("axe inexistant", "GET", "/v1/axes/inconnu", 404)
v("détail axe", "GET", "/v1/axes/07-afrique-histoire-pensee", 200,
  verif=lambda r: len(r["ouvrages"]) == 10 or f"{len(r['ouvrages'])} ouvrages")
v("bibliothèque", "GET", "/v1/bibliotheque?par_page=5", 200, verif=lambda r: r["total"] == 79 or r["total"])
v("filtres", "GET", "/v1/bibliotheque/filtres", 200)
v("filtre niveau", "GET", "/v1/bibliotheque?niveau=debutant&par_page=3", 200,
  verif=lambda r: all(o["niveau"] == "debutant" for o in r["ouvrages"]) or "niveau non filtré")
v("recherche texte", "GET", "/v1/bibliotheque?q=Cheikh&par_page=5", 200,
  verif=lambda r: r["total"] >= 1 or "aucun résultat")
v("recherche corpus", "GET", "/v1/recherche?q=biais%20algorithmique&limite=3", 200,
  verif=lambda r: len(r["resultats"]) == 3 or f"{len(r['resultats'])} résultats")
v("suggestions", "GET", "/v1/recherche/suggestions?q=intel", 200)
v("glossaire", "GET", "/v1/concepts?limite=5", 200, verif=lambda r: len(r) == 5 or len(r))
v("tarifs", "GET", "/v1/paiements/tarifs", 200, verif=lambda r: len(r["formules"]) == 3 or len(r["formules"]))
v("formules", "GET", "/v1/compte/formules", 200)
v("diagnostic", "GET", "/v1/diagnostic?axe=04-ia-societe-ethique-philosophie", 200,
  verif=lambda r: r["total"] >= 6 or r["total"])

DOC = None
r = appel("GET", "/v1/bibliotheque?axe=04-ia-societe-ethique-philosophie&par_page=1")[1]
DOC = r["ouvrages"][0]["id"]
v("fiche ouvrage", "GET", f"/v1/bibliotheque/{DOC}", 200, verif=lambda r: bool(r["titre"]) or "sans titre")
v("ouvrage inexistant", "GET", "/v1/bibliotheque/00000000-0000-0000-0000-000000000000", 404)
v("ouvrage id invalide", "GET", "/v1/bibliotheque/pas-un-uuid", [404, 422, 500])
som = v("sommaire", "GET", f"/v1/bibliotheque/{DOC}/sommaire", 200, verif=lambda r: len(r) > 0 or "vide")
v("pack", "GET", f"/v1/bibliotheque/{DOC}/pack", 200,
  verif=lambda r: r["compteurs"]["questions"] > 0 or "pack sans question")
v("export pdf", "GET", f"/v1/bibliotheque/{DOC}/export.pdf", 200,
  verif=lambda r: r.get("_binaire", 0) > 20000 or f"pdf {r}")
v("citations", "GET", f"/v1/lecteur/{DOC}/citations", 200)
CH = som[0]["id"]
v("lecture chapitre", "GET", f"/v1/lecteur/{DOC}/chapitre/{CH}", 200,
  verif=lambda r: "droits" in r or "droits absents")
v("lecture pages", "GET", f"/v1/lecteur/{DOC}/pages?debut=10&fin=14", [200, 404])

print("=== ACCÈS REFUSÉ SANS JETON ===")
for c in ["/v1/aujourdhui", "/v1/progression", "/v1/compte", "/v1/notes",
          "/v1/chronogrammes", "/v1/agent/conversations", "/v1/concepts/a-reviser",
          "/v1/paiements", "/v1/paiements/abonnement/etat"]:
    v("protégée", "GET", c, 401)
v("jeton bidon", "GET", "/v1/aujourdhui", 401, tok="pas.un.jeton")

print("=== COMPTE ===")
email = f"audit-{sfx}@example.com"
r = v("inscription", "POST", "/v1/auth/inscription", 201,
      {"email": email, "mot_de_passe": "motdepasse-solide-2026", "nom": "Audit"},
      verif=lambda r: r["utilisateur"]["plan"] == "free" or r["utilisateur"]["plan"])
TOK, REFRESH = r["jetons"]["access_token"], r["jetons"]["refresh_token"]
v("email déjà pris", "POST", "/v1/auth/inscription", 409,
  {"email": email, "mot_de_passe": "motdepasse-solide-2026"})
v("mot de passe court", "POST", "/v1/auth/inscription", 422,
  {"email": f"court-{sfx}@example.com", "mot_de_passe": "court"})
v("email invalide", "POST", "/v1/auth/inscription", 422,
  {"email": "pas-un-email", "mot_de_passe": "motdepasse-solide-2026"})
v("connexion", "POST", "/v1/auth/connexion", 200, {"email": email, "mot_de_passe": "motdepasse-solide-2026"})
v("mauvais mot de passe", "POST", "/v1/auth/connexion", 401, {"email": email, "mot_de_passe": "faux"})
v("compte inexistant", "POST", "/v1/auth/connexion", 401,
  {"email": f"jamais-{sfx}@example.com", "mot_de_passe": "motdepasse-solide-2026"})
v("moi", "GET", "/v1/auth/moi", 200, tok=TOK, verif=lambda r: r["email"] == email or r["email"])
v("rafraîchir", "POST", "/v1/auth/rafraichir", 200, {"refresh_token": REFRESH})
v("refresh rejoué", "POST", "/v1/auth/rafraichir", 401, {"refresh_token": REFRESH})

r = appel("POST", "/v1/auth/connexion", {"email": email, "mot_de_passe": "motdepasse-solide-2026"})[1]
TOK = r["jetons"]["access_token"]

print("=== PARCOURS ===")
v("diagnostic enregistré", "POST", "/v1/diagnostic", 200,
  {"axe": "04-ia-societe-ethique-philosophie",
   "reponses": {"familiarite": 1, "objectif": "curiosite", "minutes_semaine": 150,
                "duree_seance": 30, "aisance_lecture": 2, "echeance": 0}}, tok=TOK,
  verif=lambda r: r["niveau"] in ("debutant", "intermediaire", "avance") or r["niveau"])
v("tous les axes ont un parcours", "GET", "/v1/axes", 200,
  verif=lambda r: all(a["parcours_possible"] for a in r)
  or ", ".join(a["slug"] for a in r if not a["parcours_possible"]))
ch = v("chronogramme", "POST", "/v1/chronogrammes", 201,
       {"axe": "04-ia-societe-ethique-philosophie"}, tok=TOK,
       verif=lambda r: len(r["seances"]) > 10 or f"{len(r['seances'])} séances")
CHRONO, SEANCE = ch["id"], ch["seances"][0]["id"]
v("2e chronogramme bloqué", "POST", "/v1/chronogrammes", 402,
  {"axe": "03-ia-outils-pratique-prompting"}, tok=TOK)
v("liste chronogrammes", "GET", "/v1/chronogrammes", 200, tok=TOK, verif=lambda r: len(r) == 1 or len(r))
v("détail chronogramme", "GET", f"/v1/chronogrammes/{CHRONO}", 200, tok=TOK)
v("chronogramme d'autrui", "GET", "/v1/chronogrammes/00000000-0000-0000-0000-000000000000", 404, tok=TOK)
v("aujourd'hui", "GET", "/v1/aujourdhui", 200, tok=TOK, verif=lambda r: r["seance"] is not None or "pas de séance")
v("marquer séance", "PATCH", f"/v1/seances/{SEANCE}", 200, {"statut": "fait", "duree_reelle_min": 25}, tok=TOK)
v("statut invalide", "PATCH", f"/v1/seances/{SEANCE}", 422, {"statut": "n_importe_quoi"}, tok=TOK)
v("replanifier sans Ascension", "POST", f"/v1/chronogrammes/{CHRONO}/replanifier", 403, tok=TOK)

print("=== QUIZ ===")
qz = v("quiz d'un ouvrage", "GET", f"/v1/quiz/document/{DOC}", 200, tok=TOK)
lot = next((c for c in qz["chapitres"] if c["nb_questions"] > 0), None)
if lot:
    q = v("passer un quiz", "GET", f"/v1/quiz/{lot['quiz_id']}", 200, tok=TOK,
          verif=lambda r: all("reponse" not in x for x in r["questions"]) or "réponse divulguée")
    v("corriger", "POST", f"/v1/quiz/{lot['quiz_id']}/corriger", 200,
      {"reponses": {"0": 0}, "duree_sec": 30}, tok=TOK,
      verif=lambda r: "details" in r and r["details"][0].get("bonne_reponse") is not None or "sans corrigé")
v("historique quiz", "GET", f"/v1/quiz/document/{DOC}/historique", 200, tok=TOK)
v("quiz inexistant", "GET", "/v1/quiz/00000000-0000-0000-0000-000000000000", 404, tok=TOK)

print("=== AGENT ===")
a = v("question", "POST", "/v1/agent/questions", 201,
      {"question": "Qu'est-ce que le biais algorithmique ?"}, tok=TOK,
      verif=lambda r: len(r["citations"]) > 0 or "aucune citation")
v("conversations", "GET", "/v1/agent/conversations", 200, tok=TOK, verif=lambda r: len(r) >= 1 or len(r))
v("une conversation", "GET", f"/v1/agent/conversations/{a['conversation_id']}", 200, tok=TOK,
  verif=lambda r: len(r["messages"]) == 2 or f"{len(r['messages'])} messages")
v("suggestions agent", "GET", f"/v1/agent/suggestions?document_id={DOC}", 200, tok=TOK)
v("question trop courte", "POST", "/v1/agent/questions", 422, {"question": "a"}, tok=TOK)

print("=== NOTES ET CONCEPTS ===")
n = v("créer note", "POST", "/v1/notes", 201, {"document_id": DOC, "page": 12, "texte": "Note d'audit"}, tok=TOK)
v("lister notes", "GET", "/v1/notes", 200, tok=TOK, verif=lambda r: len(r) == 1 or len(r))
v("modifier note", "PATCH", f"/v1/notes/{n['id']}", 200, {"texte": "Note corrigée"}, tok=TOK)
v("supprimer note", "DELETE", f"/v1/notes/{n['id']}", 204, tok=TOK)
v("note supprimée", "DELETE", f"/v1/notes/{n['id']}", 404, tok=TOK)
h = v("surligner", "POST", "/v1/surlignages", 201,
      {"document_id": DOC, "page": 12, "citation": "un extrait", "couleur": "or"}, tok=TOK)
v("lister surlignages", "GET", "/v1/surlignages", 200, tok=TOK)
v("supprimer surlignage", "DELETE", f"/v1/surlignages/{h['id']}", 204, tok=TOK)
v("à réviser", "GET", "/v1/concepts/a-reviser", 200, tok=TOK)
c = appel("GET", "/v1/concepts?limite=1")[1]
v("détail concept", "GET", f"/v1/concepts/{c[0]['id']}", 200)
v("réviser", "POST", "/v1/concepts/revision", 200, {"concept_id": c[0]["id"], "reussi": True}, tok=TOK)

print("=== PROGRESSION ET COMPTE ===")
v("progression", "GET", "/v1/progression", 200, tok=TOK, verif=lambda r: r["seances"]["total"] > 0 or "aucune séance")
v("régularité", "GET", "/v1/progression/regularite?jours=14", 200, tok=TOK,
  verif=lambda r: len(r["points"]) == 15 or f"{len(r['points'])} points")
v("maîtrise", "GET", "/v1/progression/maitrise", 200, tok=TOK)
v("journal", "GET", "/v1/progression/journal", 200, tok=TOK, verif=lambda r: len(r) > 3 or len(r))
v("compte", "GET", "/v1/compte", 200, tok=TOK)
v("modifier profil", "PATCH", "/v1/compte", 200, {"nom": "Audit modifié", "minutes_semaine": 200}, tok=TOK)
v("usage", "GET", "/v1/compte/usage", 200, tok=TOK,
  verif=lambda r: any(c["utilise"] > 0 for c in r["compteurs"]) or "aucun compteur")

print("=== PAIEMENT ===")
p = v("payer sans choisir d'opérateur", "POST", "/v1/paiements", 201,
      {"periode_mois": 1, "telephone": "699000123"}, tok=TOK,
      verif=lambda r: r["telephone"] == "237699000123" or r["telephone"])
v("période invalide", "POST", "/v1/paiements", 422,
  {"periode_mois": 7, "telephone": "699000123", "reseau": "MTN"}, tok=TOK)
v("réseau invalide", "POST", "/v1/paiements", 422,
  {"periode_mois": 1, "telephone": "699000123", "reseau": "MOOV"}, tok=TOK)
v("historique paiements", "GET", "/v1/paiements", 200, tok=TOK, verif=lambda r: len(r) >= 1 or len(r))
v("suivre paiement", "GET", f"/v1/paiements/{p['id']}", 200, tok=TOK,
  verif=lambda r: len(r["journal"]) >= 3 or f"{len(r['journal'])} événements")
v("abonnement", "GET", "/v1/paiements/abonnement/etat", 200, tok=TOK,
  verif=lambda r: r["actif"] is True or "abonnement inactif")
v("plan devenu premium", "GET", "/v1/auth/moi", 200, tok=TOK,
  verif=lambda r: r["plan"] == "premium" or r["plan"])
v("webhook orphelin", "POST", "/v1/paiements/webhook/tara", 200,
  json.dumps({"productId": "x", "status": "SUCCESS"}).encode(), brut=True)
v("webhook illisible", "POST", "/v1/paiements/webhook/tara", 200, b"pas du json", brut=True)
v("replanifier en Ascension", "POST", f"/v1/chronogrammes/{CHRONO}/replanifier", [200, 409], tok=TOK)

print("=== DÉCONNEXION ===")
r = appel("POST", "/v1/auth/connexion", {"email": email, "mot_de_passe": "motdepasse-solide-2026"})[1]
T2, R2 = r["jetons"]["access_token"], r["jetons"]["refresh_token"]
v("déconnexion", "POST", "/v1/auth/deconnexion", 204, {"refresh_token": R2}, tok=T2)
v("refresh révoqué", "POST", "/v1/auth/rafraichir", 401, {"refresh_token": R2})
v("changer mot de passe", "POST", "/v1/auth/mot-de-passe", 204,
  {"ancien": "motdepasse-solide-2026", "nouveau": "un-autre-mot-de-passe-2026"}, tok=T2)
v("ancien mot de passe refusé", "POST", "/v1/auth/connexion", 401,
  {"email": email, "mot_de_passe": "motdepasse-solide-2026"})
v("nouveau mot de passe", "POST", "/v1/auth/connexion", 200,
  {"email": email, "mot_de_passe": "un-autre-mot-de-passe-2026"})

# ---------- rapport
echecs = [r for r in resultats if not r[0]]
lents = [r for r in resultats if float(r[3].replace("ms", "")) > 1500]
print("\n" + "=" * 100)
print(f"{len(resultats)} appels, {len(resultats) - len(echecs)} conformes, {len(echecs)} écarts")
if echecs:
    print("\nÉCARTS")
    for _, route, code, ms, nom, detail in echecs:
        print(f"  {route} {code}  {nom}\n      {detail}")
if lents:
    print("\nLENTS (> 1,5 s)")
    for _, route, code, ms, nom, _ in lents:
        print(f"  {route} {ms}  {nom}")
sys.exit(1 if echecs else 0)
