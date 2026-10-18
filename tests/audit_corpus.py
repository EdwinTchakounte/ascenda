"""Audit de qualité du corpus et des chronogrammes qu'il produit."""
import asyncio
import re
import sys
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "apps" / "api"))

from app.core.db import close_pool, fetch_all, open_pool  # noqa: E402
from app.services import planner  # noqa: E402
from app.services.titres import est_appareil, est_repli, est_titre_casse  # noqa: E402

DENSITE_MIN = planner.JETONS_PAR_PAGE_PLANCHER


async def main(ecrire: bool) -> int:
    await open_pool()
    lignes: list[str] = []
    bloquants = 0

    def dire(texte=""):
        print(texte)
        lignes.append(texte)

    docs = await fetch_all(
        """select d.id, coalesce(d.title_clean, d.title_raw) as titre, d.page_count, d.authors, d.year,
                  p.reading_time_min,
                  (select coalesce(sum(token_count), 0) from chunk k where k.document_id = d.id) as jetons
             from document d left join document_pedagogy p on p.document_id = d.id
            where d.takedown_status = 'none' order by 2"""
    )
    chapitres = await fetch_all(
        "select document_id, ord, title, page_start, page_end, token_count from chapter order by document_id, ord")
    par_doc = defaultdict(list)
    for c in chapitres:
        par_doc[c["document_id"]].append(c)

    dire("# Audit du corpus")
    dire()
    dire(f"{len(docs)} ouvrages, {len(chapitres)} chapitres.")
    dire()

    # ------------------------------------------------------------ ouvrages
    incomplets, durees, sans_auteur = [], [], []
    for d in docs:
        pages, jetons = d["page_count"] or 0, d["jetons"] or 0
        if pages and jetons / pages < DENSITE_MIN:
            incomplets.append((d["titre"], pages, round(jetons / pages)))
        estime = planner.minutes_estimees(jetons, pages)
        rt = d["reading_time_min"]
        if rt is None or (estime and abs(rt - estime) / estime > 0.25):
            durees.append((d["titre"], rt, estime))
        if not d["authors"] or str(d["authors"]) in ("[]", "{}"):
            sans_auteur.append(d["titre"])

    dire("## Ouvrages")
    dire()
    dire(f"- Pages peu remplies (moins de {DENSITE_MIN} jetons par page : diapositives, proverbes) : **{len(incomplets)}**")
    for t, p, dens in incomplets:
        dire(f"  - {t} : {p} pages, {dens} jetons par page")
    dire(f"- Durée de lecture affichée incohérente avec le texte (écart de plus de 25 %) : **{len(durees)}**")
    for t, rt, e in durees[:15]:
        dire(f"  - {t} : fiche {rt} min, texte {e} min")
    bloquants += len(durees)
    dire(f"- Sans auteur renseigné : **{len(sans_auteur)}**")
    for t in sans_auteur:
        dire(f"  - {t}")

    # Doublons probables : titres voisins une fois la ponctuation retirée.
    def cle(t):
        return re.sub(r"[^a-z0-9]", "", re.sub(r"\(.*?\)", "", (t or "").lower()))
    groupes = defaultdict(list)
    for d in docs:
        groupes[cle(d["titre"])].append(d["titre"])
    doublons = [g for g in groupes.values() if len(g) > 1]
    dire(f"- Doublons probables : **{len(doublons)}**")
    for g in doublons:
        dire(f"  - {' / '.join(g)}")
    dire()

    # ---------------------------------------------------------------- quiz
    rangs = await fetch_all(
        """select q->>'reponse' as rang, count(*) as n
             from derivative d, jsonb_array_elements(d.content->'questions') q
            where d.kind = 'quiz' and d.superseded_by is null group by 1""")
    total_q = sum(r["n"] for r in rangs) or 1
    dominant = max(rangs, key=lambda r: r["n"]) if rangs else None
    part = (dominant["n"] / total_q) if dominant else 0
    dire("## Quiz")
    dire()
    dire(f"- Position de la bonne réponse : " + ", ".join(
        f"choix {int(r['rang']) + 1} {round(100 * r['n'] / total_q)} %" for r in sorted(rangs, key=lambda r: r["rang"])))
    if part > 0.4:
        # Au-delà, cocher toujours la même case suffit à réussir : le quiz ne mesure plus rien.
        dire(f"- **Bonne réponse trop souvent au même rang** ({round(100 * part)} %) : lancer app.outils.melanger_choix")
        bloquants += 1
    dire()

    # ----------------------------------------------------------- chapitres
    casses, replis, appareil = [], Counter(), []
    for c in chapitres:
        if est_titre_casse(c["title"]):
            casses.append(c["title"])
        if est_repli(c["title"]):
            replis[c["document_id"]] += 1
        if est_appareil(c["title"]) and (c["token_count"] or 0) >= planner.TOKENS_MIN_CHAPITRE:
            appareil.append(c["title"])
    titres = {d["id"]: d["titre"] for d in docs}
    dire("## Chapitres")
    dire()
    dire(f"- Titres cassés (fragment, numéro de page, « suite de la page précédente », mot coupé) : **{len(casses)}**")
    for t, n in Counter(casses).most_common(12):
        dire(f"  - « {t} » × {n}")
    bloquants += len(casses)
    dire(f"- Chapitres sans titre, nommés par leurs pages : **{sum(replis.values())}**, "
         f"dans {len(replis)} ouvrages")
    for doc_id, n in replis.most_common(8):
        dire(f"  - {titres.get(doc_id, '?')} : {n} sur {len(par_doc[doc_id])}")
    dire(f"- Pages d'appareil assez longues pour entrer dans un plan (couverture, copyright…) : **{len(appareil)}**")
    dire()

    # --------------------------------------------------------- chronogrammes
    dire("## Chronogrammes simulés")
    dire()
    dire("Un plan par axe, pour un lecteur de niveau intermédiaire : 150 min par semaine, "
         "séances de 30 min, sans échéance.")
    dire()
    densite = {str(d["id"]): (d["jetons"] or 0) / max(1, d["page_count"] or 1) for d in docs}
    # Un pôle regroupe des sous-axes et n'est pas un parcours
    axes = await fetch_all("""select id, slug, label from axis a where slug not like '\\_%%'
                                 and not exists (select 1 from axis e where e.parent_id = a.id)
                               order by sort_order""")
    for a in axes:
        ouvrages = await planner.ouvrages_de_l_axe(str(a["id"]), "intermediaire")
        chaps = await planner.chapitres_de_plusieurs([str(o["id"]) for o in ouvrages], str(a["id"]))
        seances, justification = planner.construire(
            ouvrages, chaps, debut=date(2026, 9, 14), fin=None, minutes_semaine=150, duree_seance=30)
        defauts = Counter()
        exemples = []
        for s in seances:
            pages = (s["page_end"] or 0) - (s["page_start"] or 0) + 1
            m = s["duration_min"]
            probleme = None
            if m < 10:
                probleme = "séance de moins de 10 min"
            elif pages > 0 and pages / m > 4 and densite.get(s["document_id"], 0) >= 150:
                # Seul un livre au texte dense se lit trop vite à ce rythme
                probleme = "plus de 4 pages par minute sur un texte dense"
            elif re.search(r"Pages \d+ à \d+ et \d+ chapitre", s["objective"]):
                probleme = "libellé contradictoire avec les pages"
            elif est_titre_casse(s["objective"].split(" : ", 1)[-1]):
                probleme = "titre cassé dans l'objectif"
            if probleme:
                defauts[probleme] += 1
                if len(exemples) < 3:
                    exemples.append(f"{s['objective']} ({m} min, p. {s['page_start']} à {s['page_end']})")
        n = len(seances)
        dire(f"### {a['label']} : {n} séances, {sum(defauts.values())} défauts")
        dire()
        dire(f"> {justification}")
        for p, k in defauts.items():
            dire(f"- {p} : {k}")
        for e in exemples:
            dire(f"  - {e}")
        dire()
        bloquants += sum(defauts.values())

    dire(f"**Anomalies bloquantes : {bloquants}**")
    await close_pool()
    if ecrire:
        f = RACINE / "docs" / "qualite" / "audit-corpus.md"
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text("\n".join(lignes) + "\n", encoding="utf-8")
        print(f"\nRapport écrit : {f.relative_to(RACINE)}")
    return 1 if bloquants else 0


sys.exit(asyncio.run(main("--rapport" in sys.argv)))
