"""Construction du chronogramme."""
from datetime import date, timedelta

from app.core.db import fetch_all
from app.services.titres import est_appareil, est_repli

# Un token vaut environ 0,75 mot.
MOTS_PAR_TOKEN = 0.75
VITESSE_DEFAUT_WPM = 200
DUREE_SEANCE_DEFAUT = 30
TOKENS_MIN_CHAPITRE = 300  # en deçà, c'est de l'appareil : sommaire, colophon, index

ORDRE_NIVEAU = {"debutant": 0, "intermediaire": 1, "avance": 2, None: 1}

# En deçà de ce seuil, une unité de lecture ne mérite pas une séance à elle seule
SEANCE_MIN_RATIO = 0.5


JETONS_PAR_PAGE_PLANCHER = 60


def minutes_de(tokens: int | None, wpm: int, pages: int | None = None) -> int:
    t = tokens or 0
    if pages and pages > 0 and t < pages * JETONS_PAR_PAGE_PLANCHER:
        t = pages * JETONS_PAR_PAGE_PLANCHER
    if not t:
        return 0
    return max(1, round(t * MOTS_PAR_TOKEN / max(80, wpm)))


def minutes_estimees(jetons: int | None, pages: int | None, wpm: int = VITESSE_DEFAUT_WPM) -> int:
    """La durée de lecture d'un ouvrage entier, par la même règle que les séances."""
    return minutes_de(jetons, wpm, pages)


async def ouvrages_de_l_axe(axis_id: str, niveau: str | None) -> list[dict]:
    """Ordonne les ouvrages : d'abord le niveau de l'utilisateur, puis ce qui monte."""
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
        # Les ouvrages du niveau visé passent devant
        rang = 0 if n == depart else (1 if n < depart else 2)
        return (rang, -float(o["weight"] or 1), o["titre"] or "")

    return [o for o in sorted(lignes, key=cle) if o["nb_chapitres"] > 0]


async def chapitres_de_plusieurs(document_ids: list[str], axis_id: str | None = None) -> dict[str, list[dict]]:
    """Les chapitres de plusieurs ouvrages en une seule requête."""
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
        # Couverture, copyright, sommaire
        if est_appareil(l["title"]):
            continue
        par_doc.setdefault(str(l["document_id"]), []).append(l)
    return par_doc


async def chapitres_de(document_id: str) -> list[dict]:
    """Les chapitres réellement lisibles d'un ouvrage."""
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
    """Un chapitre long devient plusieurs séances, découpées par pages."""
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
    """Répartit les séances de la semaine sur des jours espacés."""
    n = max(1, min(7, round(minutes_semaine / max(10, duree_seance))))
    grilles = {
        1: [1], 2: [1, 4], 3: [0, 2, 5], 4: [0, 1, 3, 5],
        5: [0, 1, 2, 3, 5], 6: [0, 1, 2, 3, 4, 6], 7: [0, 1, 2, 3, 4, 5, 6],
    }
    return grilles[n]


def _meme_titre(a: str | None, b: str | None) -> bool:
    """Compare deux titres sans se laisser arrêter par la typographie."""
    def net(x: str | None) -> str:
        return (x or "").replace("\u2019", "'").replace("\u00a0", " ").strip().casefold()

    return bool(net(a)) and net(a) == net(b)


def _creneaux(debut: date, jours: list[int], combien: int) -> list[date]:
    """Les dates de séance à partir d'aujourd'hui, sans empiler la semaine entamée."""
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
    """Regroupe les chapitres voisins d'un même ouvrage en séances pleines."""
    plancher = max(5, round(duree_seance * SEANCE_MIN_RATIO))

    def contigus(a: dict, b: dict) -> bool:
        """Deux unités qui se suivent dans le livre."""
        # Seuls les ouvrages bornés ont des trous.
        if not (a.get("borne") and b.get("borne")):
            return True
        if a["page_end"] is None or b["page_start"] is None:
            return True
        return a["page_start"] - 3 <= b["page_start"] <= a["page_end"] + 3

    def absorber(cible: dict, u: dict) -> None:
        for t in u.get("titres") or []:
            if t not in (cible.get("titres") or []):
                cible.setdefault("titres", []).append(t)
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

    # Une séance d'ouverture trop courte (une préface avant un long chapitre découpé)
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
            fusion = dict(u, titres=list(u.get("titres") or []))
            if u.get("fraction") or suivante.get("fraction"):
                fusion.pop("fraction", None)
                fusion["mixte"] = True
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
                precedente["mixte"] = True  # les titres portent alors « (début) » ou « (fin) »
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
                        "titres": [_titre_de_part(ch["title"], part.get("fraction"))],
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


def _titre_de_part(titre: str | None, fraction: tuple | None) -> str | None:
    """Le titre d'un morceau de chapitre, tel qu'il se lit dans une séance groupée."""
    if not titre or not fraction:
        return titre
    i, n = fraction
    return f"{titre} ({'début' if i == 1 else 'fin' if i == n else 'suite'})"


def _enumerer(titres: list[str]) -> str:
    # Le point-virgule plutôt que « et »
    return " ; ".join(titres)


# Au-delà, la liste des titres ne tient plus sur une carte de séance.
TITRES_MAX, SIGNES_MAX = 4, 90


def libelle_seance(u: dict) -> str:
    """Ce que dit la carte de séance. Il ne doit jamais contredire ses pages."""
    ouvrage = u["ouvrage"]
    titre = u["chapitre"]
    pages = (
        f"pages {u['page_start']} à {u['page_end']}"
        if u.get("page_start") and u.get("page_end") and u["page_end"] != u["page_start"]
        else (f"page {u['page_start']}" if u.get("page_start") else None)
    )
    groupes = u.get("chapitres_groupes", 1)
    fraction = u.get("fraction")
    titres = [t for t in (u.get("titres") or []) if t]
    if not titre or est_repli(titre) or u.get("repli"):
        return f"{ouvrage} : {pages}" if pages else ouvrage
    if len(titres) > 1 and not any(est_repli(t) for t in titres):
        # Autant de titres que la carte en tient, puis le compte du reste
        pris: list[str] = []
        for t in titres[:TITRES_MAX]:
            if len(" ; ".join(pris + [t])) > SIGNES_MAX and pris:
                break
            pris.append(t)
        reste = len(titres) - len(pris)
        if not reste:
            return f"{ouvrage} : {_enumerer(pris)}"
        return f"{ouvrage} : {_enumerer(pris)} et {reste} autre{'s' if reste > 1 else ''}"
    if u.get("mixte"):
        return f"{ouvrage} : {pages}" if pages else ouvrage
    # Quand le chapitre porte le titre de l'ouvrage (fréquent sur les pages de garde)
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
    """L'en-tête du plan, en chiffres qui se recoupent."""
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
