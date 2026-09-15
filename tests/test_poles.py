"""Vérifie les pôles d'axes et les périmètres de chapitres (migration 018).

Le Mémento de l'agronome nourrit six sous-axes du pôle Agriculture et élevage,
chacun avec sa seule part du livre. On vérifie :

- le pôle n'est pas proposé comme parcours, ses sous-axes le nomment ;
- chaque sous-axe ne compte que ses chapitres ;
- un chronogramme sur « Protection des cultures » ne fait lire que ses pages ;
- les ouvrages sans périmètre donnent les mêmes chapitres qu'avant ;
- la structure du livre : hiérarchie, droits, pages imprimées.
"""
import asyncio, json, os, random, string, sys, urllib.error, urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "apps" / "api"))
from app.core.db import open_pool, close_pool, fetch_all, fetch_one  # noqa: E402
from app.services import planner  # noqa: E402

BASE = os.getenv("ASCENDA_API", "http://127.0.0.1:8250")
STRUCTURE = json.loads((Path(__file__).resolve().parents[1] / "pipeline/ingest/structures/memento-agronome.json").read_text())

_resultats = []
def ok(l, c, e=""):
    _resultats.append((bool(c), l, str(e)))
    print(("  OUI  " if c else "  NON  ") + l + ("  " + str(e) if e != "" else ""))

def call(m, p, b=None, tok=None):
    r = urllib.request.Request(BASE + p, data=json.dumps(b).encode() if b is not None else None, method=m)
    r.add_header("Content-Type", "application/json")
    if tok:
        r.add_header("Authorization", f"Bearer {tok}")
    try:
        with urllib.request.urlopen(r, timeout=90) as x:
            b2 = x.read(); return x.status, (json.loads(b2) if b2 else None)
    except urllib.error.HTTPError as e:
        b2 = e.read(); return e.code, (json.loads(b2) if b2 else None)


async def main():
    await open_pool()
    try:
        doc = await fetch_one("select * from document where title_clean = %s and owner_id is null", (STRUCTURE["titre"],))
        if not doc:
            ok("le Mémento de l'agronome est ingéré", False, "lancer pipeline/ingest/structure_imposee.py")
            return
        D = str(doc["id"])

        print("\n· Le livre")
        ok("protégé par défaut : pas de texte intégral", doc["copyright_status"] == "restricted" and not doc["redistributable"],
           f"{doc['copyright_status']}, extraits {doc['max_excerpt_chars']} car.")
        n = await fetch_one("select count(*) as n, count(*) filter (where parent_id is null) as racines from chapter where document_id = %s", (D,))
        ok("tous les chapitres décrits sont en base", n["n"] == len(STRUCTURE["chapitres"]), f"{n['n']} sur {len(STRUCTURE['chapitres'])}")
        ok("la hiérarchie tient : 8 parties, l'introduction et les annexes", n["racines"] == 9, n["racines"])
        mais = await fetch_one(
            """select c.page_start, c.token_count, p.title as parent from chapter c join chapter p on p.id = c.parent_id
                where c.document_id = %s and c.title = 'Le maïs'""", (D,))
        ok("la fiche du maïs est sous « Les céréales », page PDF 784", mais and mais["parent"] == "Les céréales" and mais["page_start"] == 784, mais)
        ok("page PDF 784 = page imprimée 780", STRUCTURE["decalage_pages"] == 4)
        orphelins = await fetch_one("select count(*) as n, max(page_end) as fin from chunk where document_id = %s and chapter_id is null", (D,))
        ok("seules les pages de garde n'ont pas de chapitre", (orphelins["fin"] or 0) <= 12, orphelins)

        print("\n· Les axes")
        s, axes = call("GET", "/v1/axes")
        slugs = {a["slug"]: a for a in axes}
        ok("le pôle n'est pas un parcours", "12-agriculture-elevage" not in slugs)
        sous = [a for a in axes if a.get("pole") and a["pole"]["slug"] == "12-agriculture-elevage"]
        ok("six sous-axes nomment leur pôle", len(sous) == 6, [a["slug"] for a in sous])
        ok("les axes existants n'ont pas de pôle", all(a["pole"] is None for a in axes if not a["slug"].startswith("12-")))
        prot = slugs.get("12-3-protection-cultures", {})
        ok("« Protection des cultures » ne compte que sa part du livre", 0 < prot.get("nb_pages", 0) < 100,
           f"{prot.get('nb_pages')} pages sur {doc['page_count']}")
        total = sum(a["nb_pages"] for a in sous)
        ok("les six parts ne dépassent pas le livre", total <= doc["page_count"], f"{total} pages")

        print("\n· Le planificateur")
        ax = await fetch_one("select id from axis where slug = '12-3-protection-cultures'")
        borne = (await planner.chapitres_de_plusieurs([D], str(ax["id"])))[D]
        tout = (await planner.chapitres_de_plusieurs([D]))[D]
        attendus = {c["titre"] for c in STRUCTURE["chapitres"] if c.get("axe") == "12-3-protection-cultures"}
        ok("avec l'axe : seulement ses chapitres", borne and all(c["title"] in attendus for c in borne),
           [c["title"][:30] for c in borne])
        ok("sans axe : tout le livre", len(tout) > len(borne) * 10, f"{len(tout)} contre {len(borne)}")
        index = [c for c in tout if c["title"] in ("Index", "Adresses utiles", "Sommaire des cédéroms")]
        hors = await fetch_one(
            """select count(*) as n from axis_chapter ac join chapter c on c.id = ac.chapter_id
                where c.document_id = %s and c.title in ('Index', 'Adresses utiles', 'Sommaire des cédéroms', 'Glossaire')""", (D,))
        ok("index, adresses et glossaire hors de tout axe", hors["n"] == 0, f"{len(index)} présents sans axe")

        autre = await fetch_one(
            """select da.document_id, da.axis_id from document_axis da
                where not exists (select 1 from axis_chapter ac join chapter c on c.id = ac.chapter_id
                                   where ac.axis_id = da.axis_id and c.document_id = da.document_id)
                limit 1""")
        a1 = (await planner.chapitres_de_plusieurs([str(autre["document_id"])]))[str(autre["document_id"])]
        a2 = (await planner.chapitres_de_plusieurs([str(autre["document_id"])], str(autre["axis_id"])))[str(autre["document_id"])]
        ok("un ouvrage sans périmètre : mêmes chapitres qu'avant", [c["id"] for c in a1] == [c["id"] for c in a2], len(a1))

        print("\n· Un chronogramme sur « Protection des cultures »")
        sfx = "".join(random.choices(string.ascii_lowercase, k=6))
        _, r = call("POST", "/v1/auth/inscription", {"email": f"agro-{sfx}@example.com", "mot_de_passe": "lecture-guidee-2026"})
        tok = r["jetons"]["access_token"]
        call("POST", "/v1/diagnostic", {"axe": "12-3-protection-cultures", "reponses": {"familiarite": 1, "objectif": "pratique",
             "minutes_semaine": 150, "duree_seance": 30, "aisance_lecture": 2, "echeance": 0}}, tok)
        s, ch = call("POST", "/v1/chronogrammes", {"axe": "12-3-protection-cultures"}, tok)
        ok("chronogramme créé", s == 201, f"{len(ch['seances'])} séances" if s == 201 else str(ch)[:90])
        if s == 201:
            print("    ", ch["justification"])
            pages = [(x["page_debut"], x["page_fin"]) for x in ch["seances"]]
            dans = [(667, 720), (1199, 1206)]
            hors_perimetre = [p for p in pages if not any(a <= p[0] and p[1] <= b for a, b in dans)]
            ok("toutes les séances lisent les pages de la protection des cultures", not hors_perimetre, hors_perimetre[:3])
            for x in ch["seances"][:6]:
                print(f"     {x['duree_min']:>2} min  p.{x['page_debut']}-{x['page_fin']}  {x['objectif'][:60]}")
            d = ch["seances"][0]
            s2, lec = call("GET", f"/v1/lecteur/{d['document_id']}/chapitre/{d['chapitre_id']}", tok=tok)
            ok("la première séance se lit", s2 == 200 and lec.get("passages"), s2)
        await fetch_one("delete from app_user where email = %s returning id", (f"agro-{sfx}@example.com",))
    finally:
        await close_pool()


asyncio.run(main())
_echecs = [x for x in _resultats if not x[0]]
print("\n" + "=" * 92)
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
sys.exit(1 if _echecs else 0)
