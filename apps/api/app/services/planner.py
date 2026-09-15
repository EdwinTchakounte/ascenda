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
from app.services.titres import est_appareil, est_repli

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


# Une page presque vide (diapositive, proverbe, illustration) se regarde quand
# même : on compte au moins l'équivalent de 60 jetons par page, soit une
# quinzaine de secondes. Sans ce plancher, seize pages de proverbes faisaient
# une séance de deux minutes. Plus haut, il gonflait ces mêmes livres : le
# texte y est complet, simplement court.
JETONS_PAR_PAGE_PLANCHER = 60


def minutes_de(tokens: int | None, wpm: int, pages: int | None = None) -> int:
    t = tokens or 0
    if pages and pages > 0 and t < pages * JETONS_PAR_PAGE_PLANCHER:
        t = pages * JETONS_PAR_PAGE_PLANCHER
    if not t:
        return 0
    return max(1, round(t * MOTS_PAR_TOKEN / max(80, wpm)))


def minutes_estimees(jetons: int | None, pages: int | None, wpm: int = VITESSE_DEFAUT_WPM) -> int:
    """La durée de lecture d'un ouvrage entier, par la même règle que les séances.

    La fiche et le chronogramme doivent dire la même chose : un livre annoncé
    « 19 min » dont le plan compte trois heures se lit comme une erreur.
    """
    return minutes_de(jetons, wpm, pages)


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
                    where c.document_id = d.id and coalesce(c.token_count, 0) >= %s
                      and (not exists (select 1 from axis_chapter ac join chapter c2 on c2.id = ac.chapter_id
                                        where ac.axis_id = da.axis_id and c2.document_id = d.id)
                           or exists (select 1 from axis_chapter ac
                                       where ac.axis_id = da.axis_id and ac.chapter_id = c.id))) as nb_chapitres
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


async def chapitres_de_plusieurs(document_ids: list[str], axis_id: str | None = None) -> dict[str, list[dict]]:
    """Les chapitres de plusieurs ouvrages en une seule requête.

    Avec `axis_id`, un ouvrage borné à certains chapitres pour cet axe
    (`axis_chapter`) ne donne que ceux-là : le Mémento de l'agronome nourrit six
    sous-axes, chacun avec sa part du livre. Un ouvrage sans bornes pour l'axe
    donne tous ses chapitres, comme avant.

    Charger ouvrage par ouvrage faisait dix-huit allers-retours pour un axe de
    dix-sept titres. Avec 3 870 chapitres exploitables au corpus, cela chiffrait
    à une seconde et demie pour composer un plan.
    """
    if not document_ids:
        return {}
    lignes = await fetch_all(
        """select c.document_id, c.id, c.ord, c.title, c.page_start, c.page_end,
                  c.token_count,
                  (%s::uuid is not null and exists (
                      select 1 from axis_chapter ac join chapter c2 on c2.id = ac.chapter_id
                       where ac.axis_id = %s::uuid and c2.document_id = c.document_id)) as borne,
                  (select dv.id from derivative dv
                    where dv.chapter_id = c.id and dv.kind = 'quiz'
                      and dv.superseded_by is null
                      and jsonb_array_length(dv.content->'questions') > 0
                    limit 1) as quiz_id
             from chapter c
            where c.document_id = any(%s)
              and coalesce(c.token_count, 0) >= %s
              and (%s::uuid is null
                   or not exists (select 1 from axis_chapter ac join chapter c2 on c2.id = ac.chapter_id
                                   where ac.axis_id = %s::uuid and c2.document_id = c.document_id)
                   or exists (select 1 from axis_chapter ac where ac.axis_id = %s::uuid and ac.chapter_id = c.id))
              and not exists (
                    select 1 from derivative dv
                     where dv.chapter_id = c.id and dv.kind = 'quiz'
                       and dv.superseded_by is null
                       and jsonb_array_length(dv.content->'questions') = 0
                       and dv.content ? 'motif')
            order by c.document_id, c.ord""",
        (axis_id, axis_id, document_ids, TOKENS_MIN_CHAPITRE, axis_id, axis_id, axis_id),
    )
    par_doc: dict[str, list[dict]] = {d: [] for d in document_ids}
    for l in lignes:
        # Couverture, copyright, sommaire : repérés par leur titre quand la
        # campagne des quiz ne les a pas déjà marqués.
        if est_appareil(l["title"]):
            continue
        par_doc.setdefault(str(l["document_id"]), []).append(l)
    return par_doc


async def chapitres_de(document_id: str) -> list[dict]:
    """Les chapitres réellement lisibles d'un ouvrage.

    On écarte l'appareil : sommaire, bibliographie, index, colophon, quatrième de
    couverture. La campagne de génération des quiz les a déjà identifiés un par un
    et enregistrés comme lots vides motivés : 178 chapitres à ce jour. Plutôt que
    de redécouvrir la même chose par heuristique, on relit ce marquage.
    """
    lignes = await fetch_all(
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
    return [l for l in lignes if not est_appareil(l["title"])]


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
    """Regroupe les chapitres voisins d'un même ouvrage en séances pleines.

    Un chronogramme qui propose « 2 min » puis « 3 min » puis « 11 min » n'est pas
    un plan de travail : c'est le découpage interne du livre exposé tel quel. On
    remplit donc chaque séance avec les chapitres suivants tant qu'on reste près de
    la durée visée, puis on rattache à la séance précédente la queue trop courte
    d'un ouvrage (un épilogue de deux minutes ne fait pas une séance).
    """
    plancher = max(5, round(duree_seance * SEANCE_MIN_RATIO))

    def contigus(a: dict, b: dict) -> bool:
        """Deux unités qui se suivent dans le livre. Un axe borné à certains
        chapitres (le Mémento de l'agronome) laisse des trous : fusionner par-dessus
        ferait lire « p. 713 à 1206 » pour une demi-heure."""
        # Seuls les ouvrages bornés ont des trous. Ailleurs, l'ordre des chapitres
        # ne suit pas toujours celui des pages, et la fusion reste celle d'avant.
        if not (a.get("borne") and b.get("borne")):
            return True
        if a["page_end"] is None or b["page_start"] is None:
            return True
        return a["page_start"] - 3 <= b["page_start"] <= a["page_end"] + 3

    def absorber(cible: dict, u: dict) -> None:
        cible["minutes"] += u["minutes"]
        cible["page_end"] = u["page_end"] or cible["page_end"]
        cible["chapitres_groupes"] = cible.get("chapitres_groupes", 1) + 1
        cible["repli"] = cible.get("repli") or est_repli(u["chapitre"]) or est_repli(cible["chapitre"])
        # Le quiz du chapitre le plus substantiel devient le livrable de la séance.
        if u["quiz_id"] and not cible["quiz_id"]:
            cible["quiz_id"] = u["quiz_id"]
            cible["chapter_id"] = u["chapter_id"]

    fusionnees: list[dict] = []
    for u in unites:
        precedente = fusionnees[-1] if fusionnees else None
        meme_livre = (precedente is not None and precedente["document_id"] == u["document_id"]
                      and contigus(precedente, u))
        entiers = precedente is not None and not precedente.get("fraction") and not u.get("fraction")
        if meme_livre and entiers and (
            precedente["minutes"] + u["minutes"] <= duree_seance * 1.15
            or (precedente["minutes"] < plancher and precedente["minutes"] + u["minutes"] <= duree_seance * 1.3)
        ):
            absorber(precedente, u)
        else:
            fusionnees.append(dict(u))

    # Une séance d'ouverture trop courte (une préface avant un long chapitre
    # découpé) rejoint la séance qui la suit.
    avant: list[dict] = []
    i = 0
    while i < len(fusionnees):
        u = fusionnees[i]
        suivante = fusionnees[i + 1] if i + 1 < len(fusionnees) else None
        if (
            u["minutes"] < plancher and suivante is not None
            and suivante["document_id"] == u["document_id"] and contigus(u, suivante)
            and u["minutes"] + suivante["minutes"] <= duree_seance * 1.7
        ):
            fusion = dict(u)
            if u.get("fraction") or suivante.get("fraction"):
                fusion.pop("fraction", None)
                fusion["repli"] = True
            absorber(fusion, suivante)
            avant.append(fusion)
            i += 2
            continue
        avant.append(u)
        i += 1
    fusionnees = avant

    # La queue d'un ouvrage : trop courte, elle rejoint la séance d'avant.
    resultat: list[dict] = []
    for i, u in enumerate(fusionnees):
        suivante = fusionnees[i + 1] if i + 1 < len(fusionnees) else None
        fin_de_livre = suivante is None or suivante["document_id"] != u["document_id"]
        precedente = resultat[-1] if resultat else None
        if (
            fin_de_livre and u["minutes"] < plancher and precedente is not None
            and precedente["document_id"] == u["document_id"] and contigus(precedente, u)
            and precedente["minutes"] + u["minutes"] <= duree_seance * 1.5
        ):
            if precedente.get("fraction") or u.get("fraction"):
                precedente.pop("fraction", None)
                precedente["repli"] = True  # on nomme alors la séance par ses pages
            absorber(precedente, u)
        else:
            resultat.append(u)
    return resultat


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
            pages = (ch["page_end"] - ch["page_start"] + 1) if ch["page_start"] and ch["page_end"] else None
            m = minutes_de(ch["token_count"], wpm, pages)
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
                        "borne": bool(ch.get("borne")),
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
        objectif = libelle_seance(u)
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

    return seances, justification_plan(
        seances, jours, duree_seance=duree_seance, wpm=wpm,
        candidats=len(ouvrages), tronque=tronque,
    )


def libelle_seance(u: dict) -> str:
    """Ce que dit la carte de séance. Il ne doit jamais contredire ses pages.

    Un chapitre sans vrai titre porte le nom de ses pages : regroupé avec le
    suivant, « Pages 2 à 66 et 1 chapitre suivant » pour une séance qui va de la
    page 2 à la page 197 se lisait comme une erreur. On nomme alors la séance par
    ses pages réelles.
    """
    ouvrage = u["ouvrage"]
    titre = u["chapitre"]
    pages = (
        f"pages {u['page_start']} à {u['page_end']}"
        if u.get("page_start") and u.get("page_end") and u["page_end"] != u["page_start"]
        else (f"page {u['page_start']}" if u.get("page_start") else None)
    )
    groupes = u.get("chapitres_groupes", 1)
    fraction = u.get("fraction")
    if not titre or est_repli(titre) or u.get("repli"):
        return f"{ouvrage} : {pages}" if pages else ouvrage
    # Quand le chapitre porte le titre de l'ouvrage (fréquent sur les pages de
    # garde), l'énoncer deux fois n'apprend rien au lecteur.
    base = ouvrage if _meme_titre(titre, ouvrage) else f"{ouvrage} : {titre}"
    if fraction:
        return f"{base} ({fraction[0]}/{fraction[1]})"
    if groupes > 1:
        n = groupes - 1
        return f"{base}, et le chapitre suivant" if n == 1 else f"{base}, et les {n} chapitres suivants"
    return base


JOURS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]


def _duree(minutes: int) -> str:
    h, m = divmod(minutes, 60)
    return f"{m} min" if not h else (f"{h} h" if not m else f"{h} h {m:02d}")


def justification_plan(
    seances: list[dict], jours: list[int], *, duree_seance: int, wpm: int, candidats: int, tronque: bool
) -> str:
    """L'en-tête du plan, en chiffres qui se recoupent.

    L'ancien texte annonçait « 60 séances d'environ 30 min » et « 22 h 08 au
    total » : 60 fois 30 minutes font 30 heures. La durée annoncée est désormais
    la moyenne réelle des séances, et le total la somme de ces mêmes séances.
    """
    if not seances:
        return "Aucune séance n'a pu être composée avec ce temps disponible."
    n = len(seances)
    total = sum(s["duration_min"] for s in seances)
    moyenne = round(total / n)
    semaines = max(1, -(-n // len(jours)))
    touches = len({s["document_id"] for s in seances})
    noms = ", ".join(JOURS[j] for j in jours[:-1]) + (" et " if len(jours) > 1 else "") + JOURS[jours[-1]]
    texte = (
        f"{n} séances sur {semaines} semaine{'s' if semaines > 1 else ''}, chaque {noms}. "
        f"Chaque séance dure {moyenne} min en moyenne, pour {_duree(total)} de lecture au total, "
        f"estimées à {wpm} mots par minute. "
        f"Le plan parcourt {touches} ouvrage{'s' if touches > 1 else ''}"
        + (f" sur les {candidats} de l'axe." if candidats > touches else ".")
    )
    if tronque:
        texte += (
            " Il s'arrête à votre échéance : repoussez-la pour couvrir la suite du parcours."
        )
    return texte
