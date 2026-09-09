import json, random, string, urllib.error, urllib.request
import os
BASE = os.getenv("ASCENDA_API", "http://127.0.0.1:8250")
def call(m,p,b=None,tok=None):
    r=urllib.request.Request(BASE+p, data=json.dumps(b).encode() if b is not None else None, method=m)
    r.add_header("Content-Type","application/json")
    if tok: r.add_header("Authorization",f"Bearer {tok}")
    try:
        with urllib.request.urlopen(r, timeout=60) as x:
            b2=x.read(); return x.status,(json.loads(b2) if b2 else None)
    except urllib.error.HTTPError as e:
        b2=e.read(); return e.code,(json.loads(b2) if b2 else None)
_resultats = []
def ok(l,c,e=""):
    _resultats.append((bool(c), l, str(e)))
    print(("  OUI  " if c else "  NON  ") + f"{l:44} {e}")

sfx="".join(random.choices(string.ascii_lowercase,k=6))
_,r = call("POST","/v1/auth/inscription",{"email":f"rev-{sfx}@example.com","mot_de_passe":"lecture-guidee-2026"})
tok = r["jetons"]["access_token"]

# Un ouvrage riche en notions du glossaire
_,b = call("GET","/v1/bibliotheque?axe=04-ia-societe-ethique-philosophie&par_page=20")
trouve = False
for o in b["ouvrages"]:
    s,qz = call("GET",f"/v1/quiz/document/{o['id']}",tok=tok)
    if s != 200: continue
    lots = [c for c in qz["chapitres"] if c["nb_questions"] >= 3]
    if not lots: continue
    for lot in lots[:4]:
        s,q = call("GET",f"/v1/quiz/{lot['quiz_id']}",tok=tok)
        if s != 200: continue
        # On rate tout volontairement : la bonne réponse n'est jamais l'indice 3
        # sur toutes les questions à la fois.
        faux = {str(i): 3 for i in range(len(q["questions"]))}
        s,co = call("POST",f"/v1/quiz/{lot['quiz_id']}/corriger",{"reponses":faux},tok)
        if s == 200 and co["justes"] < co["total"]:
            trouve = True
            print(f"\nQuiz raté volontairement : {co['justes']}/{co['total']} sur « {o['titre'][:44]} »")
            break
    if trouve: break

s,rev = call("GET","/v1/concepts/a-reviser",tok=tok)
ok("des notions sont programmées", rev["total"] > 0,
   ", ".join(n["terme"] for n in rev["notions"][:5]) if rev["total"] else "aucune")
if rev["total"]:
    n = rev["notions"][0]
    ok("la notion porte sa définition", bool(n["definition"]),
       (n["definition"] or "")[:60])
    s,r2 = call("POST","/v1/concepts/revision",{"concept_id":n["concept_id"],"reussi":True},tok)
    ok("réviser l'éloigne dans le temps", s==200 and r2["interval_days"]>=1,
       f"revient dans {r2['interval_days']} jour(s)")
    s,r3 = call("POST","/v1/concepts/revision",{"concept_id":n["concept_id"],"reussi":False},tok)
    ok("échouer la ramène à demain", s==200 and r3["interval_days"]==1)

s,d = call("GET",f"/v1/concepts/{rev['notions'][0]['concept_id']}" if rev["total"] else "/v1/concepts?limite=1")
if rev["total"]:
    ok("la fiche de notion montre des passages", len(d.get("occurrences",[]))>0,
       f"{len(d.get('occurrences',[]))} occurrences dans le corpus")

s,a = call("GET","/v1/aujourdhui",tok=tok)
ok("l'accueil annonce les révisions", a["notions_a_reviser"] > 0, f"{a['notions_a_reviser']} notions")


# --- verdict
import sys as _sys
_echecs = [l for l in _resultats if not l[0]]
print("\n" + "=" * 92)
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
_sys.exit(1 if _echecs else 0)
