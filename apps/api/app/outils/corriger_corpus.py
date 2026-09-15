"""Corrige ce que le lecteur voit du corpus, sans toucher au texte des livres.

Trois corrections, toutes rejouables :

1. Les titres de chapitre cassés deviennent lisibles (voir `services/titres.py`).
   L'original est gardé dans `chapter.title_source`.
2. La durée de lecture d'une fiche est recalculée par la même règle que les
   séances du chronogramme (`planner.minutes_estimees`).
3. Les séances déjà planifiées reprennent un libellé fidèle à leurs pages, et
   chaque plan un en-tête dont les chiffres se recoupent.

    python -m app.outils.corriger_corpus            # applique
    python -m app.outils.corriger_corpus --essai    # montre sans écrire
"""
import asyncio
import json
import re
import sys
from pathlib import Path

from app.core.db import close_pool, execute, fetch_all, open_pool
from app.services import planner
from app.services.titres import est_appareil, titre_lisible


async def titres(essai: bool) -> int:
    chapitres = await fetch_all(
        """select c.id, c.document_id, c.ord, c.title, c.title_source, c.page_start, c.page_end,
                  (select k.text from chunk k where k.chapter_id = c.id order by k.ord limit 1) as texte
             from chapter c order by c.document_id, c.ord"""
    )
    # Les traductions de titres restés dans la langue d'origine, relues à la main.
    traduits = json.loads((Path(__file__).parent / "titres_traduits.json").read_text(encoding="utf-8"))
    noms = {str(l["id"]): l["titre"] for l in await fetch_all(
        "select id, coalesce(title_clean, title_raw) as titre from document")}
    changes = 0
    precedent, doc, suites = None, None, 0
    for c in chapitres:
        if c["document_id"] != doc:
            doc, precedent, suites = c["document_id"], None, 0
        # On repart toujours de l'original : rejouer la correction après une
        # amélioration des règles ne corrige pas une correction.
        source = c["title_source"] or c["title"]
        releves = traduits.get(noms.get(str(c["document_id"]), ""), {})
        traduction = releves.get(str(c["ord"]))
        neuf = traduction or titre_lisible(source, page_start=c["page_start"], page_end=c["page_end"],
                                           precedent=precedent, texte=c["texte"])
        # Dans un livre dont on a retrouvé les chapitres, une section nommée par
        # ses pages juste après un chapitre titré en est la suite : « Pages 153
        # à 160 » entre les chapitres XV et XVI, c'est la fin du chapitre XV.
        if (not traduction and releves and re.fullmatch(r"Pages? \d+( à \d+)?", neuf or "")
                and precedent and precedent.startswith("Chapitre") and suites < 3):
            base = re.sub(r"\s*\(suite\)$", "", precedent)
            # « Chapitre V …, puis chapitre VI … » : ce qui suit est la fin du VI.
            if ", puis chapitre " in base:
                base = "Chapitre " + base.split(", puis chapitre ", 1)[1]
            neuf = base + " (suite)"
        # Au-delà de trois sections, ce ne sont plus des suites plausibles d'un
        # chapitre (annexes, notes de fin) : elles gardent le nom de leurs pages.
        suites = suites + 1 if (neuf or "").endswith("(suite)") and not traduction else 0
        if neuf != c["title"]:
            changes += 1
            if changes <= 15 or essai:
                print(f"  titre : « {source} » → « {neuf} »")
            if not essai:
                await execute(
                    "update chapter set title_source = coalesce(title_source, title), title = %s where id = %s",
                    (neuf, c["id"]),
                )
        precedent = neuf
    return changes


async def durees(essai: bool) -> int:
    if not essai:
        # Un ouvrage sans fiche pédagogique n'avait aucune durée : la fiche
        # affichait un tiret. On pose la ligne, la durée suit.
        await execute(
            """insert into document_pedagogy (document_id)
               select id from document d
                where not exists (select 1 from document_pedagogy p where p.document_id = d.id)""")
    lignes = await fetch_all(
        """select d.id, coalesce(d.title_clean, d.title_raw) as titre, d.page_count, p.reading_time_min,
                  (select coalesce(sum(token_count), 0) from chunk k where k.document_id = d.id) as jetons
             from document d join document_pedagogy p on p.document_id = d.id"""
    )
    changes = 0
    for l in lignes:
        m = planner.minutes_estimees(l["jetons"], l["page_count"])
        if m and m != l["reading_time_min"]:
            changes += 1
            if changes <= 8:
                print(f"  durée : {l['titre'][:60]} : {l['reading_time_min']} → {m} min")
            if not essai:
                await execute("update document_pedagogy set reading_time_min = %s where document_id = %s",
                              (m, l["id"]))
    return changes


async def accents(essai: bool) -> int:
    """Rend leurs accents aux quiz et aux commentaires de citations écrits sans.

    Seuls les champs rédigés sont retouchés : l'énoncé, les choix et
    l'explication d'une question ; le thème et la portée d'une citation. Le texte
    cité, copié du livre, n'est jamais modifié. L'original est gardé dans
    `derivative.content_source`, et chaque passage repart de cet original.
    """
    from app.outils.accents import Accentueur, sans_accents

    lots = await fetch_all(
        """select id, kind, coalesce(content_source, content) as content, content as actuel,
                  content_source is not null as retouche
             from derivative
            where kind in ('quiz', 'citation') and superseded_by is null""")

    def retoucher(x):
        # Phrase sans aucun accent : restitution au contexte. Phrase déjà en
        # partie accentuée : seulement les mots sans ambiguïté.
        if not isinstance(x, str):
            return x
        return accentueur.accentuer(x) if sans_accents(x) else accentueur.accentuer_sur(x)

    def champs(kind: str, contenu: dict) -> list[str]:
        if kind == "quiz":
            return [x for q in contenu.get("questions", [])
                    for x in [q.get("q"), q.get("explication"), *(q.get("choix") or [])] if isinstance(x, str)]
        return [x for c in contenu.get("citations", []) for x in (c.get("theme"), c.get("portee")) if isinstance(x, str)]

    a_traiter = lots
    accentueur = Accentueur()
    for l in await fetch_all(
            """select k.text from chunk k join document d on d.id = k.document_id
                where coalesce(d.language, 'fr') ilike 'fr%%'"""):
        accentueur.apprendre(l["text"])

    changes = 0
    for l in a_traiter:
        c = json.loads(json.dumps(l["content"]))
        if l["kind"] == "quiz":
            for q in c.get("questions", []):
                for cle in ("q", "explication"):
                    if isinstance(q.get(cle), str):
                        q[cle] = retoucher(q[cle])
                q["choix"] = [retoucher(x) for x in q.get("choix") or []]
        else:
            for cit in c.get("citations", []):
                for cle in ("theme", "portee"):
                    if isinstance(cit.get(cle), str):
                        cit[cle] = retoucher(cit[cle])
        if c != l["actuel"]:
            changes += 1
            if changes <= 6:
                paires = [(x, y) for x, y in zip(champs(l["kind"], l["content"]), champs(l["kind"], c)) if x != y]
                if paires:
                    print(f"  accents : « {paires[0][0][:80]} »\n         → « {paires[0][1][:80]} »")
            if not essai:
                # On repart toujours de l'original : une règle améliorée corrige
                # l'original, pas une retouche précédente.
                await execute(
                    "update derivative set content_source = coalesce(content_source, content), content = %s::jsonb "
                    "where id = %s",
                    (json.dumps(c, ensure_ascii=False), l["id"]))
    return changes


async def metadonnees(essai: bool) -> int:
    """Auteurs, années, éditeurs et langues relevés dans les fichiers eux-mêmes."""
    corrections = json.loads((Path(__file__).parent / "metadonnees.json").read_text(encoding="utf-8"))
    changes = 0
    for titre, champs in corrections.items():
        if titre.startswith("_"):
            continue
        doc = await fetch_all(
            "select id, authors, year, publisher, language from document "
            "where coalesce(title_clean, title_raw) = %s", (titre,))
        if not doc:
            print(f"  métadonnées : ouvrage introuvable « {titre} »")
            continue
        d = doc[0]
        for champ, valeur in champs.items():
            actuel = d[champ]
            if actuel == valeur:
                continue
            changes += 1
            print(f"  {champ} : {titre[:50]} : {actuel!r} → {valeur!r}")
            if not essai:
                valeur_sql = json.dumps(valeur, ensure_ascii=False) if champ == "authors" else valeur
                cast = "::jsonb" if champ == "authors" else ""
                await execute(f"update document set {champ} = %s{cast} where id = %s", (valeur_sql, d["id"]))
    # La fiche de lecture porte sa propre copie des auteurs et de l'année : on
    # l'aligne sur l'ouvrage corrigé, pour qu'aucune donnée n'en contredise une autre.
    for f in await fetch_all(
        """select dv.id, dv.content, d.authors, d.year from derivative dv join document d on d.id = dv.document_id
            where dv.kind = 'fiche_lecture' and dv.superseded_by is null"""):
        contenu = dict(f["content"] or {})
        voulu = {"auteurs": f["authors"] or [], "annee": f["year"]}
        if all(contenu.get(k) == v for k, v in voulu.items()):
            continue
        contenu.update(voulu)
        changes += 1
        if not essai:
            await execute(
                "update derivative set content_source = coalesce(content_source, content), content = %s::jsonb "
                "where id = %s", (json.dumps(contenu, ensure_ascii=False), f["id"]))
    return changes


async def tailles(essai: bool) -> int:
    """La taille enregistrée à l'import ne correspond pas toujours au fichier
    stocké (1,7 Mo annoncés pour un PDF de 92 Mo). On relit celle du stockage."""
    from minio import Minio

    from app.core.config import settings

    client = Minio(settings.minio_endpoint, access_key=settings.minio_root_user,
                   secret_key=settings.minio_root_password, secure=settings.minio_secure)
    lignes = await fetch_all(
        "select id, coalesce(title_clean, title_raw) as titre, storage_key, size_bytes from document "
        "where storage_key is not null")
    changes = 0
    for l in lignes:
        try:
            reelle = client.stat_object(settings.minio_bucket, l["storage_key"]).size
        except Exception:  # noqa: BLE001 - fichier absent du stockage : rien à corriger ici
            continue
        if reelle != l["size_bytes"]:
            changes += 1
            print(f"  taille : {l['titre'][:60]} : {l['size_bytes']} → {reelle} octets")
            if not essai:
                await execute("update document set size_bytes = %s where id = %s", (reelle, l["id"]))
    return changes


async def seances(essai: bool) -> tuple[int, int]:
    lignes = await fetch_all(
        """select s.id, s.chronogram_id, s.document_id, s.page_start, s.page_end, s.objective,
                  s.duration_min, s.planned_at,
                  coalesce(d.title_clean, d.title_raw) as ouvrage, c.title as chapitre
             from session s
             join document d on d.id = s.document_id
             left join chapter c on c.id = s.chapter_id
            order by s.chronogram_id, s.ord"""
    )
    # Combien de chapitres une séance couvre : ceux qui commencent dans sa plage.
    chapitres = await fetch_all("select document_id, title, page_start from chapter")
    debuts: dict = {}
    for c in chapitres:
        if not est_appareil(c["title"]) and c["page_start"]:
            debuts.setdefault(c["document_id"], []).append(c["page_start"])

    changes = 0
    par_plan: dict = {}
    for s in lignes:
        par_plan.setdefault(s["chronogram_id"], []).append(s)
        fraction = re.search(r"\((\d+)/(\d+)\)$", s["objective"] or "")
        couverts = sum(
            1 for p in debuts.get(s["document_id"], [])
            if s["page_start"] and s["page_end"] and s["page_start"] < p <= s["page_end"]
        )
        # Seuls les libellés de l'ancien planificateur sont réécrits : un plan
        # composé depuis la correction a déjà le bon, et le recalculer ici (sans
        # le détail du regroupement) le rendrait moins précis.
        ancien = (
            re.search(r" et \d+ chapitres? suivants?$", s["objective"] or "")
            or re.search(r" : Pages \d+ à \d+", s["objective"] or "")
            or (s["chapitre"] is not None and s["chapitre"] not in (s["objective"] or ""))
        )
        if not ancien:
            continue
        neuf = planner.libelle_seance({
            "ouvrage": s["ouvrage"], "chapitre": s["chapitre"],
            "page_start": s["page_start"], "page_end": s["page_end"],
            "chapitres_groupes": 1 + couverts if not fraction else 1,
            "fraction": (int(fraction.group(1)), int(fraction.group(2))) if fraction else None,
        })
        if neuf != s["objective"]:
            changes += 1
            if changes <= 8:
                print(f"  séance : « {s['objective']} » → « {neuf} »")
            if not essai:
                await execute("update session set objective = %s where id = %s", (neuf, s["id"]))

    plans = 0
    for chrono_id, ss in par_plan.items():
        c = (await fetch_all("select rationale from chronogram where id = %s", (chrono_id,)))[0]
        # Idem pour l'en-tête : seul l'ancien texte (« séances d'environ ») est refait.
        if "séances d'environ" not in (c["rationale"] or ""):
            continue
        jours = sorted({s["planned_at"].weekday() for s in ss if s["planned_at"]}) or [0]
        texte = planner.justification_plan(
            [{"duration_min": s["duration_min"] or 0, "document_id": s["document_id"]} for s in ss],
            jours, duree_seance=planner.DUREE_SEANCE_DEFAUT, wpm=planner.VITESSE_DEFAUT_WPM,
            candidats=0, tronque="échéance" in (c["rationale"] or ""),
        )
        if texte != c["rationale"]:
            plans += 1
            if not essai:
                await execute("update chronogram set rationale = %s where id = %s", (texte, chrono_id))
    return changes, plans


async def main() -> None:
    essai = "--essai" in sys.argv
    await open_pool()
    try:
        print("Titres de chapitre")
        t = await titres(essai)
        print("Durées de lecture")
        d = await durees(essai)
        print("Séances et plans")
        s, p = await seances(essai)
        print("Tailles des fichiers")
        o = await tailles(essai)
        print("Métadonnées")
        m = await metadonnees(essai)
        print("Accents des quiz et des citations")
        acc = await accents(essai)
    finally:
        await close_pool()
    verbe = "à corriger" if essai else "corrigés"
    print(f"\n{t} titres, {d} durées, {s} libellés de séance, {p} en-têtes de plan, {o} tailles, {m} métadonnées, {acc} lots réaccentués {verbe}.")


if __name__ == "__main__":
    asyncio.run(main())
