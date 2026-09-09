"""Construction du chronogramme.

Le principe : un axe n'est pas un thème, c'est un thème + un objectif + une
contrainte de temps. Le planificateur part de cette contrainte et non du corpus.
Il choisit les ouvrages, découpe leurs chapitres en séances de durée à peu près
constante, puis pose ces séances sur des dates réelles.

Ce qu'il ne fait pas : appeler un modèle de langage. Le plan doit être
reproductible, explicable et gratuit. Un LLM sert à rédiger, pas à ordonnancer.
"""
from datetime import date, timedelta

from app.core.db import fetch_all

# Un token vaut environ 0,75 mot. La vitesse par défaut est prudente : mieux vaut
# un plan tenu qu'un plan flatteur.
MOTS_PAR_TOKEN = 0.75
VITESSE_DEFAUT_WPM = 200
DUREE_SEANCE_DEFAUT = 30
TOKENS_MIN_CHAPITRE = 300  # en deçà, c'est de l'appareil : sommaire, colophon, index

ORDRE_NIVEAU = {"debutant": 0, "intermediaire": 1, "avance": 2, None: 1}

# En deçà de ce seuil, une unité de lecture ne mérite pas une séance à elle seule :
# on l'agrège au chapitre suivant du même ouvrage.
SEANCE_MIN_RATIO = 0.5


def minutes_de(tokens: int | None, wpm: int) -> int:
    if not tokens:
        return 0
    return max(1, round(tokens * MOTS_PAR_TOKEN / max(80, wpm)))


async def ouvrages_de_l_axe(axis_id: str, niveau: str | None) -> list[dict]:
    """Ordonne les ouvrages : d'abord le niveau de l'utilisateur, puis ce qui monte.

    Un lecteur qui se déclare débutant ne commence pas par Bostrom. On accepte
    toutefois de le mener plus haut dans le même parcours : c'est l'intérêt d'un
    chronogramme sur douze semaines.
    """
    lignes = await fetch_all(
        """select d.id, coalesce(d.title_clean, d.title_raw) as titre, d.authors,
                  d.page_count, d.redistributable,
                  p.level, p.doc_type_norm, p.reading_time_min, p.central_thesis,
                  da.weight,
                  (select count(*) from chapter c
                    where c.document_id = d.id and coalesce(c.token_count, 0) >= %s) as nb_chapitres
           from document_axis da
           join document d on d.id = da.document_id
           left join document_pedagogy p on p.document_id = d.id
           where da.axis_id = %s and d.takedown_status = 'none'
           order by da.weight desc""",
        (TOKENS_MIN_CHAPITRE, axis_id),
    )
    depart = ORDRE_NIVEAU.get(niveau, 1)

    def cle(o: dict) -> tuple:
        n = ORDRE_NIVEAU.get(o["level"], 1)
        # Les ouvrages du niveau visé passent devant ; en dessous ensuite (révision),
        # au-dessus à la fin (progression).
        rang = 0 if n == depart else (1 if n < depart else 2)
        return (rang, -float(o["weight"] or 1), o["titre"] or "")

    return [o for o in sorted(lignes, key=cle) if o["nb_chapitres"] > 0]


async def chapitres_de_plusieurs(document_ids: list[str]) -> dict[str, list[dict]]:
    """Les chapitres de plusieurs ouvrages en une seule requête.

    Charger ouvrage par ouvrage faisait dix-huit allers-retours pour un axe de
    dix-sept titres. Avec 3 870 chapitres exploitables au corpus, cela chiffrait
    à une seconde et demie pour composer un plan.
    """
    if not document_ids:
        return {}
    lignes = await fetch_all(
        """select c.document_id, c.id, c.ord, c.title, c.page_start, c.page_end,
                  c.token_count,
                  (select dv.id from derivative dv
                    where dv.chapter_id = c.id and dv.kind = 'quiz'
                      and dv.superseded_by is null
                      and jsonb_array_length(dv.content->'questions') > 0
                    limit 1) as quiz_id
             from chapter c
            where c.document_id = any(%s)
              and coalesce(c.token_count, 0) >= %s
              and not exists (
                    select 1 from derivative dv
                     where dv.chapter_id = c.id and dv.kind = 'quiz'
                       and dv.superseded_by is null
                       and jsonb_array_length(dv.content->'questions') = 0
                       and dv.content ? 'motif')
            order by c.document_id, c.ord""",
        (document_ids, TOKENS_MIN_CHAPITRE),
    )
    par_doc: dict[str, list[dict]] = {d: [] for d in document_ids}
    for l in lignes:
        par_doc.setdefault(str(l["document_id"]), []).append(l)
    return par_doc


async def chapitres_de(document_id: str) -> list[dict]:
    """Les chapitres réellement lisibles d'un ouvrage.

    On écarte l'appareil : sommaire, bibliographie, index, colophon, quatrième de
    couverture. La campagne de génération des quiz les a déjà identifiés un par un
    et enregistrés comme lots vides motivés : 178 chapitres à ce jour. Plutôt que
    de redécouvrir la même chose par heuristique, on relit ce marquage.
    """
    return await fetch_all(
        """select c.id, c.ord, c.title, c.page_start, c.page_end, c.token_count,
                  (select dv.id from derivative dv
                    where dv.chapter_id = c.id and dv.kind = 'quiz'
                      and dv.superseded_by is null
                      and jsonb_array_length(dv.content->'questions') > 0
                    limit 1) as quiz_id
           from chapter c
           where c.document_id = %s
             and coalesce(c.token_count, 0) >= %s
             and not exists (
                   select 1 from derivative dv
                    where dv.chapter_id = c.id and dv.kind = 'quiz'
                      and dv.superseded_by is null
                      and jsonb_array_length(dv.content->'questions') = 0
                      and dv.content ? 'motif')
           order by c.ord""",
        (document_id, TOKENS_MIN_CHAPITRE),
    )


def _decouper(chapitre: dict, minutes: int, duree_seance: int) -> list[dict]:
    """Un chapitre long devient plusieurs séances, découpées par pages.

    On coupe sur les pages plutôt que sur les tokens : « lire p. 47 à 63 » est une
    consigne qu'un lecteur peut suivre sur son exemplaire papier, pas « lire
    1 800 tokens ».
    """
    if minutes <= duree_seance * 1.4:
        return [{"minutes": minutes, "page_start": chapitre["page_start"], "page_end": chapitre["page_end"]}]

    n = max(2, round(minutes / duree_seance))
    p0 = chapitre["page_start"] or 1
    p1 = chapitre["page_end"] or p0
    total_pages = max(1, p1 - p0 + 1)
    parts = []
    for i in range(n):
        debut = p0 + round(i * total_pages / n)
        fin = p0 + round((i + 1) * total_pages / n) - 1
        parts.append(
            {
                "minutes": max(1, round(minutes / n)),
                "page_start": debut,
                "page_end": max(debut, fin),
                "fraction": (i + 1, n),
            }
        )
    return parts


def _jours_de_lecture(minutes_semaine: int, duree_seance: int) -> list[int]:
    """Répartit les séances de la semaine sur des jours espacés.

    Trois séances tombent lundi, mercredi, samedi, pas lundi, mardi, mercredi :
    l'espacement sert la mémorisation autant que le confort.
    """
    n = max(1, min(7, round(minutes_semaine / max(10, duree_seance))))
    grilles = {
        1: [1], 2: [1, 4], 3: [0, 2, 5], 4: [0, 1, 3, 5],
        5: [0, 1, 2, 3, 5], 6: [0, 1, 2, 3, 4, 6], 7: [0, 1, 2, 3, 4, 5, 6],
    }
    return grilles[n]


def _meme_titre(a: str | None, b: str | None) -> bool:
    """Compare deux titres sans se laisser arrêter par la typographie.

    Le corpus mélange apostrophe droite et courbe : sans normalisation,
    « Comment l'IA... » et « Comment l’IA... » passent pour deux titres
    différents et la séance répète le nom de l'ouvrage.
    """
    def net(x: str | None) -> str:
        return (x or "").replace("\u2019", "'").replace("\u00a0", " ").strip().casefold()

    return bool(net(a)) and net(a) == net(b)


def _creneaux(debut: date, jours: list[int], combien: int) -> list[date]:
    """Les dates de séance à partir d'aujourd'hui, sans empiler la semaine entamée.

    Commencer un samedi ne doit pas faire tomber les cinq séances de la semaine
    le jour même : on saute les créneaux déjà passés et on reprend au suivant.
    """
    dates: list[date] = []
    lundi = debut - timedelta(days=debut.weekday())
    semaine = 0
    while len(dates) < combien:
        for j in jours:
            jour = lundi + timedelta(weeks=semaine, days=j)
            if jour < debut:
                continue
            dates.append(jour)
            if len(dates) == combien:
                break
        semaine += 1
        if semaine > 520:  # garde-fou : dix ans de planning suffisent
            break
    return dates


def _fusionner(unites: list[dict], duree_seance: int) -> list[dict]:
    """Regroupe les unités trop courtes avec la suivante du même ouvrage.

    Un chronogramme qui propose « 2 min » puis « 3 min » puis « 11 min » n'est pas
    un plan de travail : c'est le découpage interne du livre exposé tel quel. On
    agrège tant qu'on reste sous la durée de séance visée.
    """
    plancher = max(5, round(duree_seance * SEANCE_MIN_RATIO))
    fusionnees: list[dict] = []
    for u in unites:
        precedente = fusionnees[-1] if fusionnees else None
        peut_fusionner = (
            precedente is not None
            and precedente["minutes"] < plancher
            and precedente["document_id"] == u["document_id"]
            and precedente["minutes"] + u["minutes"] <= duree_seance * 1.3
            and not precedente.get("fraction")
            and not u.get("fraction")
        )
        if peut_fusionner:
            precedente["minutes"] += u["minutes"]
            precedente["page_end"] = u["page_end"] or precedente["page_end"]
            precedente["chapitres_groupes"] = precedente.get("chapitres_groupes", 1) + 1
            # Le quiz du chapitre le plus substantiel devient le livrable de la séance.
            if u["quiz_id"] and not precedente["quiz_id"]:
                precedente["quiz_id"] = u["quiz_id"]
                precedente["chapter_id"] = u["chapter_id"]
        else:
            fusionnees.append(dict(u))
    return fusionnees


def construire(
    ouvrages: list[dict],
    chapitres_par_doc: dict[str, list[dict]],
    *,
    debut: date,
    fin: date | None,
    minutes_semaine: int,
    duree_seance: int = DUREE_SEANCE_DEFAUT,
    wpm: int = VITESSE_DEFAUT_WPM,
) -> tuple[list[dict], str]:
    """Retourne (séances, justification du plan)."""
    jours = _jours_de_lecture(minutes_semaine, duree_seance)
    seances_par_semaine = len(jours)

    # 1. Aplatir le corpus retenu en unités de séance.
    unites: list[dict] = []
    for o in ouvrages:
        for ch in chapitres_par_doc.get(str(o["id"]), []):
            m = minutes_de(ch["token_count"], wpm)
            if m == 0:
                continue
            for part in _decouper(ch, m, duree_seance):
                unites.append(
                    {
                        "document_id": str(o["id"]),
                        "ouvrage": o["titre"],
                        "chapter_id": str(ch["id"]),
                        "chapitre": ch["title"],
                        "quiz_id": str(ch["quiz_id"]) if ch["quiz_id"] else None,
                        "lecture_integrale": o["redistributable"],
                        **part,
                    }
                )

    # 2. Regrouper ce qui est trop court pour faire une séance.
    unites = _fusionner(unites, duree_seance)

    # 3. Si une échéance est fixée, on tronque plutôt que de promettre l'impossible.
    tronque = False
    if fin:
        semaines = max(1, ((fin - debut).days + 6) // 7)
        capacite = semaines * seances_par_semaine
        if len(unites) > capacite:
            unites = unites[:capacite]
            tronque = True

    # 4. Poser les dates sur les créneaux réellement disponibles.
    seances = []
    dates = _creneaux(debut, jours, len(unites))
    for i, u in enumerate(unites):
        jour = dates[i]
        titre_chap = u["chapitre"] or f"Chapitre {u['chapter_id'][:8]}"
        fraction = u.get("fraction")
        # Quand le chapitre porte le titre de l'ouvrage (fréquent sur les pages
        # de garde), l'énoncer deux fois n'apprend rien au lecteur.
        meme_titre = _meme_titre(titre_chap, u["ouvrage"])
        objectif = u["ouvrage"] if meme_titre else f"{u['ouvrage']} : {titre_chap}"
        if fraction:
            objectif += f" ({fraction[0]}/{fraction[1]})"
        elif u.get("chapitres_groupes", 1) > 1:
            n = u["chapitres_groupes"] - 1
            objectif += f" et {n} chapitre suivant" if n == 1 else f" et {n} chapitres suivants"
        seances.append(
            {
                "ord": i,
                "document_id": u["document_id"],
                "chapter_id": u["chapter_id"],
                "page_start": u["page_start"],
                "page_end": u["page_end"],
                "planned_at": jour,
                "duration_min": u["minutes"],
                "objective": objectif,
                "deliverable_kind": "quiz" if u["quiz_id"] else "note",
                "deliverable_id": u["quiz_id"],
            }
        )

    total_min = sum(s["duration_min"] for s in seances)
    # Les ouvrages effectivement touchés, pas ceux qui étaient candidats :
    # annoncer seize titres pour un plan qui n'en couvre que quatre serait faux.
    touches = len({s["document_id"] for s in seances})
    justification = (
        f"{len(seances)} séances d'environ {duree_seance} min, "
        f"{seances_par_semaine} par semaine, "
        f"sur {touches} ouvrage{'s' if touches > 1 else ''}, "
        f"{total_min // 60} h {total_min % 60:02d} de lecture au total, "
        f"à {wpm} mots par minute."
    )
    if tronque:
        justification += (
            " Le plan a été ramené à ce qui tient avant l'échéance : "
            "il couvre le début du parcours, pas la totalité de l'axe."
        )
    return seances, justification
