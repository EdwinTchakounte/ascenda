"""L'état de production d'un ouvrage, et du corpus entier."""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg  # noqa: E402

ATTENDUS = {
    "fiche_lecture":   "ouvrage",
    "resume_executif": "ouvrage",
    "synthese":        "ouvrage",
    "quiz":            "chapitre",
    "citation":        "chapitre",
    "compte_rendu":    "chapitre",
}

TOKENS_MIN = 300


def etat_document(conn, doc_id: str) -> dict:
    with conn.cursor() as cur:
        cur.execute(
            """select d.id, coalesce(d.title_clean, d.title_raw) as titre,
                      d.page_count, d.redistributable,
                      (select count(*) from chapter c where c.document_id = d.id) as chapitres,
                      (select count(*) from chapter c
                        where c.document_id = d.id and coalesce(c.token_count,0) >= %s) as utiles,
                      (select count(*) from chunk k where k.document_id = d.id) as chunks,
                      (select count(*) from chunk k
                        where k.document_id = d.id and k.embedding is not null) as vectorises
                 from document d where d.id = %s""",
            (TOKENS_MIN, doc_id),
        )
        d = cur.fetchone()
        if not d:
            return {}
        cur.execute(
            """select kind, count(*) as lots, count(distinct chapter_id) as chapitres
                 from derivative
                where document_id = %s and superseded_by is null
                group by kind""",
            (doc_id,),
        )
        produits = {k: {"lots": l, "chapitres": c} for k, l, c in cur.fetchall()}

    utiles = d[5]
    manques = {}
    for kind, portee in ATTENDUS.items():
        fait = produits.get(kind, {"lots": 0, "chapitres": 0})
        if portee == "ouvrage":
            manques[kind] = 0 if fait["lots"] else 1
        else:
            manques[kind] = max(0, utiles - fait["chapitres"])

    return {
        "id": str(d[0]), "titre": d[1], "pages": d[2], "redistribuable": d[3],
        "chapitres": d[4], "utiles": utiles, "chunks": d[6], "vectorises": d[7],
        "produits": produits, "manques": manques,
        "complet": all(v == 0 for v in manques.values()) and d[7] == d[6],
    }


def main() -> None:
    p = argparse.ArgumentParser(description="État de production du corpus.")
    p.add_argument("--doc", help="préfixe d'identifiant")
    p.add_argument("--incomplets", action="store_true", help="n'afficher que ce qui manque")
    a = p.parse_args()

    conn = pg()
    with conn.cursor() as cur:
        if a.doc:
            cur.execute("select id from document where id::text like %s", (a.doc + "%",))
        else:
            cur.execute("select id from document where takedown_status = 'none' order by title_clean")
        ids = [r[0] for r in cur.fetchall()]

    if a.doc and len(ids) == 1:
        e = etat_document(conn, ids[0])
        print(f"\n{e['titre']}")
        print(f"  {e['pages']} pages · {e['chapitres']} chapitres dont {e['utiles']} exploitables")
        print(f"  {e['chunks']} passages, {e['vectorises']} vectorisés")
        print(f"  lecture intégrale : {'oui' if e['redistribuable'] else 'non, extraits seulement'}")
        print("\n  Dérivés")
        for kind, portee in ATTENDUS.items():
            fait = e["produits"].get(kind, {"lots": 0, "chapitres": 0})
            manque = e["manques"][kind]
            cible = 1 if portee == "ouvrage" else e["utiles"]
            etat = "complet" if manque == 0 else f"il manque {manque}"
            couverture = fait["lots"] if portee == "ouvrage" else fait["chapitres"]
            print(f"    {kind:16} {couverture:>4} / {cible:<4}  {etat}")
        print(f"\n  {'Complet.' if e['complet'] else 'Incomplet.'}")
        return

    lignes = [etat_document(conn, i) for i in ids]
    lignes = [l for l in lignes if l]
    if a.incomplets:
        lignes = [l for l in lignes if not l["complet"]]

    print(f"\n{'ouvrage':46} {'chap':>5} {'vect':>6} {'fiche':>6} {'quiz':>6} "
          f"{'citat':>6} {'cr':>5} {'synth':>6}")
    print("-" * 96)
    for l in lignes:
        vect = f"{l['vectorises']}/{l['chunks']}" if l["chunks"] else "0/0"
        def part(kind):
            fait = l["produits"].get(kind, {"lots": 0, "chapitres": 0})
            return str(fait["lots"] if ATTENDUS[kind] == "ouvrage" else fait["chapitres"])
        print(f"{(l['titre'] or '')[:46]:46} {l['utiles']:>5} {vect:>6} "
              f"{part('fiche_lecture'):>6} {part('quiz'):>6} {part('citation'):>6} "
              f"{part('compte_rendu'):>5} {part('synthese'):>6}")

    complets = sum(1 for l in lignes if l["complet"])
    print(f"\n{len(lignes)} ouvrages, {complets} complets.")
    total_manques = {}
    for l in lignes:
        for k, v in l["manques"].items():
            total_manques[k] = total_manques.get(k, 0) + v
    print("Reste à produire : " + " · ".join(
        f"{k} {v}" for k, v in sorted(total_manques.items(), key=lambda x: -x[1]) if v))


if __name__ == "__main__":
    main()
