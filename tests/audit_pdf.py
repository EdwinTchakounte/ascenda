"""Audit des PDF lisibles dans l'application."""
import os
import re
import subprocess
import sys
import tempfile
import urllib.request

import pymupdf

API = os.getenv("ASCENDA_API", "http://127.0.0.1:8250")


RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RACINE, "pipeline"))
from common import pg  # noqa: E402

_connexion = pg()


def psql(sql: str) -> list[tuple]:
    with _connexion.cursor() as cur:
        cur.execute(sql)
        return cur.fetchall()


def net(t: str) -> str:
    return re.sub(r"[^a-zà-ÿ0-9]", "", t.lower())


def main() -> int:
    echecs = 0
    ouvrages = psql("select id, page_count, coalesce(title_clean, title_raw) from document "
                    "where redistributable and takedown_status = 'none' order by 3")
    with tempfile.TemporaryDirectory() as dossier:
        for doc_id, pages_base, titre in ouvrages:
            doc_id, pages_base = str(doc_id), str(pages_base)
            chemin = os.path.join(dossier, f"{doc_id}.pdf")
            try:
                urllib.request.urlretrieve(f"{API}/v1/lecteur/{doc_id}/pdf", chemin)
                d = pymupdf.open(chemin)
            except Exception as exc:  # noqa: BLE001
                print(f"NON  {titre} : illisible ({exc})")
                echecs += 1
                continue
            n = d.page_count
            textes = [net(p.get_text()) for p in d]
            sans_texte = [i + 1 for i, t in enumerate(textes) if len(t) < 15]

            passages = psql(f"select page_start, page_end, text from chunk "
                            f"where document_id = '{doc_id}' order by random() limit 25")
            alignes, verifies, ecarts = 0, 0, []
            for debut, fin, texte in passages:
                morceaux = [net(x) for x in re.split(r"\n", texte) if len(net(x)) >= 35]
                if not morceaux:
                    continue
                frag = morceaux[len(morceaux) // 2][:40]
                verifies += 1
                trouve = [i + 1 for i, t in enumerate(textes) if frag in t]
                if trouve and int(debut) - 1 <= trouve[0] <= int(fin) + 1:
                    alignes += 1
                elif trouve:
                    ecarts.append(trouve[0] - int(debut))
                else:
                    ecarts.append("absent")

            probleme = []
            if str(n) != pages_base:
                probleme.append(f"{n} pages dans le PDF, {pages_base} en base")
            if verifies and alignes < verifies * 0.9:
                probleme.append(f"pages décalées : {alignes}/{verifies} passages à leur page, écarts {ecarts[:6]}")
            etat = "NON " if probleme else "OUI "
            echecs += bool(probleme)
            print(f"{etat} {titre[:70]}")
            print(f"      {n} pages, {len(sans_texte)} sans texte {sans_texte[:10]}, "
                  f"{alignes}/{verifies} passages retrouvés à leur page")
            for p in probleme:
                print(f"      {p}")
    print(f"\n{len(ouvrages) - echecs} PDF conformes sur {len(ouvrages)}")
    return 1 if echecs else 0


sys.exit(main())
