#!/usr/bin/env python3
"""Redécoupe les passages d'un ouvrage structuré, au titre près et sur place.

L'ingestion range chaque page entière dans un chapitre. Quand une section
commence au milieu d'une page (« LE RADIS » sous la fin de « Le poireau »), la
fin de la section précédente part dans la suivante, et une fiche courte qui tient
en un tiers de page n'a aucun passage à elle. Sur le Mémento de l'agronome, les
rédacteurs de quiz l'ont signalé presque à chaque lot.

Ce script coupe chaque page à la ligne du titre (champ `ligne` de la structure,
ou début du titre pour les entrées du sommaire), puis reconstruit les passages
avec les mêmes règles que l'ingestion (environ 750 jetons, reprise de 100 jetons
commencée sur un mot, jamais à cheval sur deux chapitres).

Il travaille **sur place** : le document et ses chapitres gardent leurs
identifiants, donc leurs quiz, citations et séances. Seuls les passages sont
remplacés ; leurs vecteurs sont à recalculer ensuite (embed.py --doc).

    python3 pipeline/ingest/redecouper.py pipeline/ingest/structures/memento-agronome.json --plan
    python3 pipeline/ingest/redecouper.py pipeline/ingest/structures/memento-agronome.json
"""
import argparse
import hashlib
import json
import re
import sys
import unicodedata
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import LIVRES, PIPELINE_VERSION, pg, sha256_file  # noqa: E402
import ingest  # noqa: E402

# Une fin de section plus courte ne fait pas un passage : elle rejoint le passage
# précédent du même chapitre. L'ingestion la jetait (seuil de 200 caractères).
COURT = 200


def plier(s: str) -> str:
    s = s.replace("’", " ").replace("'", " ")
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", s)).strip()


def position_du_titre(texte: str, chapitre: dict, apres: int) -> int | None:
    """Décalage (en caractères) de la ligne du titre dans la page, après `apres`."""
    cible = plier(chapitre.get("ligne") or re.sub(r"^[\dA]+[\d.]*\s*", "", chapitre["titre"]))
    if not cible:
        return None
    lignes, decalage = [], 0
    for ligne in texte.splitlines(keepends=True):
        if decalage >= apres:
            lignes.append((decalage, plier(ligne)))
        decalage += len(ligne)
    # La ligne exacte d'abord : « L'élevage bovin » ne doit pas se poser sur
    # « L'élevage bovin laitier », qui le suit dans la même page.
    for pos, p in lignes:
        if p == cible:
            return pos
    # Puis le début d'un titre du sommaire imprimé sur plusieurs lignes
    # (« La protection contre les » / « maladies et les ravageurs »).
    for pos, p in lignes:
        if p and len(p) >= 8 and cible.startswith(p):
            return pos
    return None


def segments(pages: list[str], chapitres: list[dict]) -> tuple[list[tuple[int, int, str]], list[str]]:
    """[(page, rang du chapitre, texte)] dans l'ordre du livre, et les titres introuvables."""
    par_page: dict[int, list[int]] = {}
    for i, c in enumerate(chapitres):
        par_page.setdefault(c["page"], []).append(i)
    sortie, introuvables = [], []
    courant = None
    for num, texte in enumerate(pages, start=1):
        coupes = []  # (décalage, rang)
        apres = 0
        for rang in par_page.get(num, []):
            pos = position_du_titre(texte, chapitres[rang], apres)
            if pos is None:
                introuvables.append(f"p.{num} {chapitres[rang]['titre']}")
                pos = apres  # à défaut, au point où l'on en est dans la page
            coupes.append((pos, rang))
            apres = pos
        debut = 0
        for pos, rang in coupes:
            if pos > debut and courant is not None:
                sortie.append((num, courant, texte[debut:pos]))
            if pos > debut and courant is None:
                sortie.append((num, None, texte[debut:pos]))
            debut, courant = pos, rang
        if texte[debut:].strip():
            sortie.append((num, courant, texte[debut:]))
    return sortie, introuvables


def passages(segs: list[tuple[int, int, str]]) -> list[dict]:
    tgt = int(ingest.TARGET_TOKENS * ingest.CHARS_PER_TOKEN)
    ovl = int(ingest.OVERLAP_TOKENS * ingest.CHARS_PER_TOKEN)
    sortie: list[dict] = []
    buf: list[str] = []
    pages: list[int] = []
    chap = object()
    reprise = False  # le tampon ne contient que la reprise du passage précédent

    def fermer(fin_de_chapitre: bool):
        nonlocal buf, pages, reprise
        texte = "\n".join(buf).strip()
        if not texte or reprise:
            buf, pages, reprise = [], [], False
            return
        if len(texte) < COURT and fin_de_chapitre:
            precedent = sortie[-1] if sortie and sortie[-1]["rang"] == chap else None
            if precedent:
                precedent["text"] += "\n" + texte
                precedent["page_end"] = max(precedent["page_end"], max(pages))
            elif len(texte) >= 40:
                sortie.append(dict(text=texte, page_start=min(pages), page_end=max(pages), rang=chap))
            buf, pages = [], []
            return
        sortie.append(dict(text=texte, page_start=min(pages), page_end=max(pages), rang=chap))
        queue = texte[-ovl:] if len(texte) > ovl else ""
        espace = queue.find(" ")
        queue = queue[espace + 1:] if 0 <= espace < 40 else queue
        buf, pages = ([queue], [max(pages)]) if queue else ([], [])
        reprise = bool(queue)

    for page, rang, texte in segs:
        if not texte.strip():
            continue
        if rang != chap:
            fermer(True)
            buf, pages, reprise = [], [], False
            chap = rang
        buf.append(texte)
        pages.append(page)
        reprise = False
        if sum(len(x) for x in buf) >= tgt:
            fermer(False)
    fermer(True)
    for s in sortie:
        s["token_count"] = int(len(s["text"]) / ingest.CHARS_PER_TOKEN)
        s["content_hash"] = hashlib.sha256(s["text"].encode()).hexdigest()
    return sortie


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("structure", type=Path)
    ap.add_argument("--plan", action="store_true", help="mesurer sans écrire")
    a = ap.parse_args()
    structure = json.loads(a.structure.read_text())
    fichier = (LIVRES / structure["fichier"]).resolve()
    chapitres = structure["chapitres"]

    conn = pg()
    with conn.cursor() as cur:
        cur.execute("select id from document where sha256 = %s and owner_id is null", (sha256_file(fichier),))
        r = cur.fetchone()
        if not r:
            raise SystemExit("Ouvrage non ingéré : lancer d'abord structure_imposee.py.")
        doc_id = r[0]
        cur.execute("select id, page_start from chapter where document_id = %s order by ord", (doc_id,))
        lignes = cur.fetchall()
    if len(lignes) != len(chapitres) or any(l[1] != c["page"] for l, c in zip(lignes, chapitres)):
        raise SystemExit("Les chapitres en base ne correspondent pas à la structure : rien n'est écrit.")
    ids = [l[0] for l in lignes]

    pages, _toc, _meta, _n = ingest.extract_pdf(fichier)
    segs, introuvables = segments(pages, chapitres)
    nouveaux = passages(segs)

    par_chap: dict[int, dict] = {}
    for p in nouveaux:
        if p["rang"] is None:
            continue
        d = par_chap.setdefault(p["rang"], {"jetons": 0, "fin": 0})
        d["jetons"] += p["token_count"]
        d["fin"] = max(d["fin"], p["page_end"])
    with conn.cursor() as cur:
        cur.execute("""select count(*), count(*) filter (where coalesce(token_count, 0) >= 300)
                         from chapter where document_id = %s""", (doc_id,))
        total, lisibles_avant = cur.fetchone()
        cur.execute("select count(*) from chunk where document_id = %s", (doc_id,))
        passages_avant = cur.fetchone()[0]
    lisibles_apres = sum(1 for d in par_chap.values() if d["jetons"] >= 300)
    print(f"Titres retrouvés dans leur page : {len(chapitres) - len(introuvables)} sur {len(chapitres)}")
    for t in introuvables[:20]:
        print("   introuvable :", t)
    print(f"Passages : {passages_avant} avant, {len(nouveaux)} après")
    print(f"Chapitres assez longs pour un plan (300 jetons) : {lisibles_avant} avant, {lisibles_apres} après")
    sans = [chapitres[i]["titre"] for i in range(len(chapitres)) if i not in par_chap]
    print(f"Chapitres sans aucun passage : {len(sans)}", sans[:12])
    if a.plan:
        return

    with conn.cursor() as cur:
        cur.execute("delete from chunk where document_id = %s", (doc_id,))
        for i, p in enumerate(nouveaux):
            cur.execute("""insert into chunk (document_id, chapter_id, ord, page_start, page_end,
                             text, token_count, content_hash, pipeline_version)
                           values (%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                        (doc_id, ids[p["rang"]] if p["rang"] is not None else None, i, p["page_start"],
                         p["page_end"], p["text"], p["token_count"], p["content_hash"], PIPELINE_VERSION))
        # Un chapitre se termine là où finit son dernier passage : souvent sur la
        # page où commence le suivant.
        for rang, cid in enumerate(ids):
            d = par_chap.get(rang)
            cur.execute("update chapter set token_count = %s, page_end = greatest(page_start, %s) where id = %s",
                        (d["jetons"] if d else 0, d["fin"] if d else chapitres[rang]["page"], cid))
    conn.commit()
    print("Passages remplacés. À faire : pipeline/embed/embed.py --doc", str(doc_id)[:8])


if __name__ == "__main__":
    main()
