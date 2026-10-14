"""Reconstitue la structure des ouvrages dépourvus de table des matières."""
import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import pg  # noqa: E402

TOKENS_CIBLE = 2500     # environ trente minutes de lecture
TOKENS_MIN = 300        # en deçà, une section n'est pas exploitable
TOKENS_MAX = 6000       # au-delà, on redécoupe

# Marqueurs de tête de chapitre. Ancrés en début de ligne, sur un texte propre.
MARQUEURS = re.compile(
    r"^\s*("
    r"CHAPITRE\s+([IVXLC]+|\d+|PREMIER|PREMIÈRE)"
    r"|Chapitre\s+([IVXLC]+|\d+|premier|première)"
    r"|(PREMIÈRE|DEUXIÈME|TROISIÈME|QUATRIÈME|CINQUIÈME|SIXIÈME|SEPTIÈME|HUITIÈME)\s+PARTIE"
    r"|PARTIE\s+([IVXLC]+|\d+)"
    r"|LIVRE\s+([IVXLC]+|\d+)"
    r"|INTRODUCTION|CONCLUSION|PRÉFACE|PREFACE|AVANT-PROPOS|POSTFACE"
    r"|ÉPILOGUE|EPILOGUE|PROLOGUE|ANNEXES?|BIBLIOGRAPHIE|GLOSSAIRE"
    r"|[IVXLC]{1,6}\s*[.\-—]\s+\S{4,}"
    r"|\d{1,2}\s*[.\-—]\s+[A-ZÀÂÉÈÊÎÔÛÇ]\S{3,}"
    r")\s*$",
    re.MULTILINE,
)


def passages(conn, doc_id):
    with conn.cursor() as cur:
        cur.execute(
            """select id, ord, page_start, page_end, token_count, left(text, 900)
                 from chunk where document_id = %s order by ord""",
            (doc_id,),
        )
        return [
            {"id": r[0], "ord": r[1], "page_start": r[2], "page_end": r[3],
             "tokens": r[4] or 0, "tete": r[5] or ""}
            for r in cur.fetchall()
        ]


def titre_detecte(tete: str) -> str | None:
    """Un marqueur en tête de passage, et le titre qui le suit s'il existe."""
    # On ne regarde que le début : un « CHAPITRE » cité au milieu d'un
    # paragraphe n'ouvre pas une section.
    debut = "\n".join(tete.split("\n")[:6])
    m = MARQUEURS.search(debut)
    if not m:
        return None
    marqueur = m.group(1).strip()
    # La ligne suivante fait souvent office de titre.
    apres = debut[m.end():].strip().split("\n")
    suite = next((l.strip() for l in apres if 3 < len(l.strip()) < 90), "")
    if suite and not MARQUEURS.match(suite):
        return f"{marqueur}. {suite}"[:180]
    return marqueur[:180]


def par_marqueurs(morceaux: list[dict]) -> list[dict] | None:
    """Sections délimitées par les marqueurs trouvés. None si trop peu."""
    debuts = [i for i, m in enumerate(morceaux) if titre_detecte(m["tete"])]
    if len(debuts) < 3:
        return None
    if debuts[0] != 0:
        debuts.insert(0, 0)

    sections = []
    for n, i in enumerate(debuts):
        j = debuts[n + 1] if n + 1 < len(debuts) else len(morceaux)
        bloc = morceaux[i:j]
        if not bloc:
            continue
        sections.append({
            "titre": titre_detecte(bloc[0]["tete"]) or f"Section {n + 1}",
            "morceaux": bloc,
        })
    return sections


def marqueurs_credibles(sections: list[dict], morceaux: list[dict]) -> bool:
    """Un découpage par marqueurs n'est retenu que s'il ressemble à un sommaire."""
    if len(sections) < 3:
        return False

    pages = max((m["page_end"] or 0) for m in morceaux) or 1
    # Un chapitre fait rarement moins de cinq pages.
    if len(sections) > max(4, pages / 5):
        return False

    titres = [s["titre"] for s in sections if s["titre"]]
    if len(titres) < len(sections) * 0.8:
        return False
    if len(set(titres)) < len(titres) * 0.8:
        return False
    return True


def par_pages(morceaux: list[dict]) -> list[dict]:
    """Sections d'environ TOKENS_CIBLE jetons, nommées par leur plage de pages."""
    sections, courant, total = [], [], 0
    for m in morceaux:
        courant.append(m)
        total += m["tokens"]
        if total >= TOKENS_CIBLE:
            sections.append({"titre": None, "morceaux": courant})
            courant, total = [], 0
    if courant:
        if sections and total < TOKENS_MIN:
            sections[-1]["morceaux"].extend(courant)
        else:
            sections.append({"titre": None, "morceaux": courant})
    return sections


def consolider(sections: list[dict]) -> list[dict]:
    """Fusionne ce qui est trop court, redécoupe ce qui est trop long."""
    fusionnees = []
    for s in sections:
        t = sum(m["tokens"] for m in s["morceaux"])
        if fusionnees and t < TOKENS_MIN:
            fusionnees[-1]["morceaux"].extend(s["morceaux"])
        else:
            fusionnees.append(s)

    finales = []
    for s in fusionnees:
        t = sum(m["tokens"] for m in s["morceaux"])
        if t <= TOKENS_MAX or len(s["morceaux"]) < 2:
            finales.append(s)
            continue
        # Trop longue : on la coupe en parts égales, en gardant le titre suivi
        # d'un numéro de partie pour que le lecteur s'y retrouve.
        parts = max(2, round(t / TOKENS_CIBLE))
        taille = max(1, len(s["morceaux"]) // parts)
        for k in range(0, len(s["morceaux"]), taille):
            bloc = s["morceaux"][k:k + taille]
            if not bloc:
                continue
            suffixe = f" ({k // taille + 1})" if s["titre"] else None
            finales.append({
                "titre": (s["titre"] + suffixe) if s["titre"] else None,
                "morceaux": bloc,
            })
    return finales


def nommer(section: dict) -> str:
    titre = section["titre"]
    # « Section 4 » ne dit rien de plus qu'une plage de pages, et fait croire à
    # un sommaire qui n'existe pas.
    if titre and not titre.startswith("Section"):
        return titre
    p0 = section["morceaux"][0]["page_start"]
    p1 = section["morceaux"][-1]["page_end"] or p0
    if p0 is None:
        return "Section"
    return f"Pages {p0} à {p1}" if p1 and p1 != p0 else f"Page {p0}"


def traiter(conn, doc_id, titre_doc, ecrire: bool) -> dict:
    morceaux = passages(conn, doc_id)
    if not morceaux:
        return {"titre": titre_doc, "sections": 0, "methode": "aucun passage"}

    sections = par_marqueurs(morceaux)
    methode = "marqueurs"
    if sections and not marqueurs_credibles(sections, morceaux):
        sections = None
    if not sections:
        sections, methode = par_pages(morceaux), "pages"
    sections = consolider(sections)
    exploitables = sum(
        1 for s in sections if sum(m["tokens"] for m in s["morceaux"]) >= TOKENS_MIN
    )

    if ecrire:
        with conn.cursor() as cur:
            cur.execute("update chunk set chapter_id = null where document_id = %s", (doc_id,))
            cur.execute("delete from chapter where document_id = %s", (doc_id,))
            for i, s in enumerate(sections):
                tokens = sum(m["tokens"] for m in s["morceaux"])
                cur.execute(
                    """insert into chapter (document_id, ord, title, page_start, page_end,
                                            token_count)
                       values (%s,%s,%s,%s,%s,%s) returning id""",
                    (doc_id, i, nommer(s), s["morceaux"][0]["page_start"],
                     s["morceaux"][-1]["page_end"], tokens),
                )
                cid = cur.fetchone()[0]
                cur.execute(
                    "update chunk set chapter_id = %s where id = any(%s)",
                    (cid, [m["id"] for m in s["morceaux"]]),
                )
        conn.commit()

    return {"titre": titre_doc, "sections": len(sections),
            "exploitables": exploitables, "methode": methode}


def main() -> None:
    p = argparse.ArgumentParser(description="Reconstitue la structure des ouvrages sans sommaire.")
    p.add_argument("--doc", help="préfixe d'identifiant")
    p.add_argument("--tous", action="store_true", help="tous les ouvrages sans chapitre exploitable")
    p.add_argument("--plan", action="store_true", help="montrer sans écrire")
    a = p.parse_args()
    if not (a.doc or a.tous or a.plan):
        p.error("préciser --doc, --tous ou --plan")

    conn = pg()
    with conn.cursor() as cur:
        if a.doc:
            cur.execute(
                """select id, coalesce(title_clean, title_raw) from document
                    where id::text like %s""", (a.doc + "%",))
        else:
            cur.execute(
                """select d.id, coalesce(d.title_clean, d.title_raw)
                     from document d
                    where d.takedown_status = 'none'
                      and not exists (select 1 from chapter c
                                       where c.document_id = d.id
                                         and coalesce(c.token_count, 0) >= %s)
                    order by d.page_count desc nulls last""", (TOKENS_MIN,))
        cibles = cur.fetchall()

    print(f"{len(cibles)} ouvrage(s) à traiter.\n")
    print(f"{'ouvrage':44} {'méthode':10} {'sections':>9} {'utiles':>7}")
    print("-" * 74)
    total_sections = total_utiles = 0
    for doc_id, titre in cibles:
        r = traiter(conn, doc_id, titre, ecrire=not a.plan)
        total_sections += r.get("sections", 0)
        total_utiles += r.get("exploitables", 0)
        print(f"{(titre or '')[:44]:44} {r['methode']:10} "
              f"{r.get('sections', 0):>9} {r.get('exploitables', 0):>7}")

    print(f"\n{total_sections} sections, dont {total_utiles} exploitables.")
    if a.plan:
        print("Mode plan : rien n'a été écrit.")


if __name__ == "__main__":
    main()
