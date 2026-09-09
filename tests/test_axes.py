import json, random, string, urllib.error, urllib.request
import os
BASE = os.getenv("ASCENDA_API", "http://127.0.0.1:8250")
def call(m,p,b=None,tok=None):
    r=urllib.request.Request(BASE+p, data=json.dumps(b).encode() if b is not None else None, method=m)
    r.add_header("Content-Type","application/json")
    if tok: r.add_header("Authorization",f"Bearer {tok}")
    try:
        with urllib.request.urlopen(r, timeout=90) as x:
            b2=x.read(); return x.status,(json.loads(b2) if b2 else None)
    except urllib.error.HTTPError as e:
        b2=e.read(); return e.code,(json.loads(b2) if b2 else None)
_resultats = []
def ok(l,c,e=""):
    _resultats.append((bool(c), l, str(e)))
    print(("  OUI  " if c else "  NON  ") + f"{l:44} {e}")

s,axes = call("GET","/v1/axes")
sans = [a for a in axes if not a["parcours_possible"]]
ok("tous les axes proposent un parcours", len(sans)==0,
   "aucun axe bloqué" if not sans else ", ".join(a["label"] for a in sans))
for a in axes:
    print(f"     {a['label'][:38]:38} {a['ouvrages_exploitables']}/{a['nb_ouvrages']} ouvrages, {a['chapitres_utiles']} chapitres")

sfx="".join(random.choices(string.ascii_lowercase,k=6))
_,r = call("POST","/v1/auth/inscription",{"email":f"afr-{sfx}@example.com","mot_de_passe":"lecture-guidee-2026"})
tok=r["jetons"]["access_token"]
call("POST","/v1/diagnostic",{"axe":"07-afrique-histoire-pensee","reponses":{"familiarite":1,"objectif":"culture","minutes_semaine":150,"duree_seance":30,"aisance_lecture":2,"echeance":0}},tok)
s,ch = call("POST","/v1/chronogrammes",{"axe":"07-afrique-histoire-pensee"},tok)
ok("chronogramme sur l'axe Afrique", s==201, f"{len(ch['seances'])} séances" if s==201 else str(ch)[:70])
if s==201:
    print("    ", ch["justification"][:110])
    for x in ch["seances"][:5]:
        print(f"     {x['prevue_le'][:10]}  {x['duree_min']:>2} min  p.{x['page_debut']}-{x['page_fin']}  {x['objectif'][:56]}")
    d = ch["seances"][0]
    s2,lec = call("GET", f"/v1/lecteur/{d['document_id']}/chapitre/{d['chapitre_id']}")
    car = sum(len(p["texte"]) for p in lec.get("passages",[]))
    ok("le contenu de la première séance est lisible", s2==200 and car>0, f"{car} caractères")


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
