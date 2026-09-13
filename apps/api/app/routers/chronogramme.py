"""Diagnostic d'entrée, génération du chronogramme, replanification."""
import json
from datetime import date, datetime, timedelta, timezone
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel, Field

from app.core.auteurs import auteurs
from app.core.db import connection, execute, fetch_all, fetch_one
from app.core.deps import CurrentUser, exige
from app.core.errors import Conflict, Forbidden, NotFound
from app.services import planner, quotas

router = APIRouter(tags=["Chronogramme"])

# ---------------------------------------------------------------- diagnostic

QUESTIONS_PROFIL = [
    {
        "cle": "familiarite",
        "question": "Où en êtes-vous avec le sujet que vous voulez travailler ?",
        "choix": [
            {"valeur": 0, "libelle": "Je pars de zéro, le vocabulaire m'est étranger"},
            {"valeur": 1, "libelle": "J'en ai lu des articles, jamais un livre entier"},
            {"valeur": 2, "libelle": "J'ai déjà lu un ou deux ouvrages sur le sujet"},
            {"valeur": 3, "libelle": "Je le pratique ou je l'enseigne"},
        ],
    },
    {
        "cle": "objectif",
        "question": "Qu'attendez-vous de cette lecture ?",
        "choix": [
            {"valeur": "curiosite", "libelle": "Comprendre, sans autre but que de savoir"},
            {"valeur": "professionnel", "libelle": "M'en servir dans mon travail"},
            {"valeur": "examen", "libelle": "Préparer un examen ou un concours"},
            {"valeur": "culture", "libelle": "Me constituer une culture solide et durable"},
        ],
    },
    {
        "cle": "minutes_semaine",
        "question": "Combien de temps pouvez-vous vraiment y consacrer chaque semaine ?",
        "choix": [
            {"valeur": 60, "libelle": "Une heure, quelques minutes par jour"},
            {"valeur": 150, "libelle": "Deux à trois heures"},
            {"valeur": 300, "libelle": "Cinq heures, je m'y tiens sérieusement"},
            {"valeur": 600, "libelle": "Dix heures ou plus, c'est une priorité"},
        ],
    },
    {
        "cle": "duree_seance",
        "question": "Une séance de lecture, pour vous, cela dure combien de temps ?",
        "choix": [
            {"valeur": 15, "libelle": "Un quart d'heure, dans les temps morts"},
            {"valeur": 30, "libelle": "Une demi-heure"},
            {"valeur": 45, "libelle": "Trois quarts d'heure"},
            {"valeur": 60, "libelle": "Une heure d'affilée"},
        ],
    },
    {
        "cle": "aisance_lecture",
        "question": "Devant un texte d'idées d'une vingtaine de pages, vous vous sentez :",
        "choix": [
            {"valeur": 0, "libelle": "Vite découragé, je décroche"},
            {"valeur": 1, "libelle": "À l'aise si le style est simple"},
            {"valeur": 2, "libelle": "À l'aise, même quand c'est dense"},
            {"valeur": 3, "libelle": "J'aime justement les textes exigeants"},
        ],
    },
    {
        "cle": "echeance",
        "question": "Avez-vous une échéance ?",
        "choix": [
            {"valeur": 0, "libelle": "Non, je prends le temps qu'il faut"},
            {"valeur": 84, "libelle": "Environ trois mois"},
            {"valeur": 168, "libelle": "Environ six mois"},
            {"valeur": 28, "libelle": "Un mois, c'est pressé"},
        ],
    },
]


@router.get("/diagnostic", summary="Le questionnaire d'entrée")
async def diagnostic(axe: Annotated[str | None, Query(description="slug d'axe")] = None):
    """Six questions de profil, puis jusqu'à quatre questions tirées des quiz
    réels de l'axe choisi. Sonder la connaissance sur le corpus lui-même vaut
    mieux que la faire déclarer : le lecteur se surestime ou se sous-estime.
    """
    sondage = []
    if axe:
        lignes = await fetch_all(
            """select dv.content, dv.document_id, coalesce(d.title_clean, d.title_raw) as ouvrage
               from derivative dv
               join document d on d.id = dv.document_id
               join document_axis da on da.document_id = d.id
               join axis a on a.id = da.axis_id
               where a.slug = %s and dv.kind = 'quiz' and dv.superseded_by is null
                 and jsonb_array_length(dv.content->'questions') > 0
               order by random() limit 12""",
            (axe,),
        )
        vu_niveaux: set[str] = set()
        for l in lignes:
            for q in (l["content"] or {}).get("questions", []):
                niv = q.get("niveau") or "comprehension"
                if niv in vu_niveaux and len(sondage) >= 2:
                    continue
                vu_niveaux.add(niv)
                sondage.append(
                    {
                        "cle": f"sonde_{len(sondage)}",
                        "question": q["q"],
                        "niveau": niv,
                        "ouvrage": l["ouvrage"],
                        "choix": [{"valeur": i, "libelle": c} for i, c in enumerate(q["choix"])],
                        "_reponse": q.get("reponse"),
                    }
                )
                break
            if len(sondage) >= 4:
                break
        for s in sondage:
            s.pop("_reponse", None)

    return {
        "axe": axe,
        "total": len(QUESTIONS_PROFIL) + len(sondage),
        "questions": QUESTIONS_PROFIL + sondage,
    }


class DiagnosticIn(BaseModel):
    axe: str
    reponses: dict[str, str | int]


@router.post("/diagnostic", summary="Enregistrer le diagnostic et en déduire un niveau")
async def enregistrer_diagnostic(data: DiagnosticIn, user: CurrentUser):
    r = data.reponses
    familiarite = int(r.get("familiarite", 1) or 0)
    aisance = int(r.get("aisance_lecture", 1) or 0)
    sondes = [v for k, v in r.items() if k.startswith("sonde_")]

    # Le déclaratif pèse deux tiers, les sondes un tiers : quatre questions ne
    # suffisent pas à établir un niveau, elles corrigent une auto-évaluation.
    base = (familiarite + aisance) / 6.0
    score = base * 0.66 + (0.34 if not sondes else 0.34 * (sum(1 for s in sondes if s != -1) / len(sondes)))
    niveau = "debutant" if score < 0.4 else ("intermediaire" if score < 0.72 else "avance")

    minutes = int(r.get("minutes_semaine", 150) or 150)
    duree = int(r.get("duree_seance", 30) or 30)
    objectif = str(r.get("objectif", "curiosite"))
    jours_echeance = int(r.get("echeance", 0) or 0)

    await execute(
        """insert into assessment (user_id, answers, level, score)
           values (%s, %s::jsonb, %s, %s)""",
        (user["id"], json.dumps(r), niveau, round(score, 3)),
    )
    # reading_speed_wpm : on part d'une valeur prudente, mesurée ensuite à l'usage.
    await execute(
        """insert into user_profile (user_id, level_assessed, assessed_at, goal,
                                     weekly_minutes, reading_speed_wpm, language)
           values (%s, %s, now(), %s, %s, %s, 'fr')
           on conflict (user_id) do update
             set level_assessed = excluded.level_assessed, assessed_at = now(),
                 goal = excluded.goal, weekly_minutes = excluded.weekly_minutes""",
        (user["id"], niveau, objectif, minutes, planner.VITESSE_DEFAUT_WPM),
    )
    return {
        "niveau": niveau,
        "score": round(score, 3),
        "objectif": objectif,
        "minutes_semaine": minutes,
        "duree_seance": duree,
        "echeance_jours": jours_echeance or None,
        "message": {
            "debutant": "Nous partons des ouvrages d'introduction et nous montons progressivement.",
            "intermediaire": "Vous avez des bases : le parcours commence au niveau intermédiaire.",
            "avance": "Le parcours vous mène directement aux ouvrages exigeants de l'axe.",
        }[niveau],
    }


# ---------------------------------------------------------------- chronogramme


class ChronogrammeIn(BaseModel):
    axe: str = Field(description="slug de l'axe")
    objectif: str | None = None
    date_debut: date | None = None
    date_cible: date | None = None
    minutes_semaine: int | None = Field(default=None, ge=15, le=2000)
    duree_seance: int | None = Field(default=None, ge=10, le=120)
    adaptatif: bool = False


async def _profil(user_id: str) -> dict:
    p = await fetch_one("select * from user_profile where user_id = %s", (user_id,))
    return p or {"level_assessed": None, "weekly_minutes": 150, "reading_speed_wpm": planner.VITESSE_DEFAUT_WPM}


@router.post("/chronogrammes", status_code=status.HTTP_201_CREATED, summary="Générer un chronogramme")
async def creer(data: ChronogrammeIn, user: CurrentUser):
    axe = await fetch_one(
        "select id, slug, label, is_premium from axis "
        "where slug = %s and slug not like '\\_%%'", (data.axe,))
    if not axe:
        raise NotFound("Cet axe n'existe pas.")
    from app.services import acces

    if axe["is_premium"] and not await acces.a_droit(user, "axes_reserves"):
        raise Forbidden("Cet axe fait partie de l'offre Ascension.")
    if data.adaptatif and not await acces.a_droit(user, "chronogramme_adaptatif"):
        raise Forbidden(
            "La replanification automatique fait partie d'Ascension. "
            "Votre plan reste utilisable, il ne s'ajustera simplement pas tout seul."
        )
    await quotas.check(user, "chronogram_active")

    profil = await _profil(user["id"])
    niveau = profil.get("level_assessed")
    minutes = data.minutes_semaine or profil.get("weekly_minutes") or 150
    duree = data.duree_seance or planner.DUREE_SEANCE_DEFAUT
    wpm = profil.get("reading_speed_wpm") or planner.VITESSE_DEFAUT_WPM
    debut = data.date_debut or date.today()

    ouvrages = await planner.ouvrages_de_l_axe(str(axe["id"]), niveau)
    if not ouvrages:
        raise NotFound("Aucun ouvrage exploitable dans cet axe pour le moment.")
    chapitres = await planner.chapitres_de_plusieurs([str(o["id"]) for o in ouvrages])

    seances, justification = planner.construire(
        ouvrages, chapitres,
        debut=debut, fin=data.date_cible,
        minutes_semaine=minutes, duree_seance=duree, wpm=wpm,
    )
    if not seances:
        raise Conflict("Le temps disponible ne permet pas de composer une seule séance.")

    async with connection() as conn:
        ua = await (await conn.execute(
            """insert into user_axis (user_id, axis_id, goal, target_date, status)
               values (%s, %s, %s, %s, 'actif') returning id""",
            (user["id"], axe["id"], data.objectif, data.date_cible),
        )).fetchone()
        ch = await (await conn.execute(
            """insert into chronogram (user_axis_id, version, start_date, target_date,
                                       adaptive, status, rationale)
               values (%s, 1, %s, %s, %s, 'actif', %s) returning id""",
            (ua["id"], debut, data.date_cible, data.adaptatif, justification),
        )).fetchone()
        for s in seances:
            await conn.execute(
                """insert into session (chronogram_id, ord, document_id, chapter_id,
                                        page_start, page_end, planned_at, duration_min,
                                        objective, deliverable_kind, deliverable_id)
                   values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                (ch["id"], s["ord"], s["document_id"], s["chapter_id"], s["page_start"],
                 s["page_end"], s["planned_at"], s["duration_min"], s["objective"],
                 s["deliverable_kind"], s["deliverable_id"]),
            )

    await quotas.record(user["id"], "chronogram_active")
    return await detail(str(ch["id"]), user)


@router.get("/chronogrammes", summary="Vos chronogrammes")
async def lister(user: CurrentUser):
    lignes = await fetch_all(
        """select c.id, c.version, c.start_date, c.target_date, c.status, c.adaptive,
                  c.rationale, c.generated_at, a.slug as axe, a.label as axe_label,
                  count(s.id) as nb_seances,
                  count(s.id) filter (where s.status = 'fait') as faites,
                  count(s.id) filter (where s.status = 'a_venir'
                                  and s.planned_at::date < current_date) as en_retard
           from chronogram c
           join user_axis ua on ua.id = c.user_axis_id
           join axis a on a.id = ua.axis_id
           left join session s on s.chronogram_id = c.id
           where ua.user_id = %s
           group by c.id, a.slug, a.label
           order by c.generated_at desc""",
        (user["id"],),
    )
    return [
        {
            "id": str(l["id"]),
            "version": l["version"],
            "axe": l["axe"],
            "axe_label": l["axe_label"],
            "debut": l["start_date"],
            "cible": l["target_date"],
            "statut": l["status"],
            "adaptatif": l["adaptive"],
            "justification": l["rationale"],
            "seances": l["nb_seances"],
            "faites": l["faites"],
            "en_retard": l["en_retard"],
            "avancement": round(l["faites"] / l["nb_seances"], 3) if l["nb_seances"] else 0.0,
        }
        for l in lignes
    ]


@router.get("/chronogrammes/{chronogramme_id}", summary="Un chronogramme et ses séances")
async def detail(chronogramme_id: str, user: CurrentUser):
    c = await fetch_one(
        """select c.*, a.slug as axe, a.label as axe_label
           from chronogram c
           join user_axis ua on ua.id = c.user_axis_id
           join axis a on a.id = ua.axis_id
           where c.id = %s and ua.user_id = %s""",
        (chronogramme_id, user["id"]),
    )
    if not c:
        raise NotFound("Ce chronogramme n'existe pas ou ne vous appartient pas.")
    seances = await fetch_all(
        """select s.*, coalesce(d.title_clean, d.title_raw) as ouvrage, d.authors,
                  d.redistributable, ch.title as chapitre
           from session s
           left join document d on d.id = s.document_id
           left join chapter ch on ch.id = s.chapter_id
           where s.chronogram_id = %s order by s.ord""",
        (chronogramme_id,),
    )
    return {
        "id": str(c["id"]),
        "version": c["version"],
        "axe": c["axe"],
        "axe_label": c["axe_label"],
        "debut": c["start_date"],
        "cible": c["target_date"],
        "statut": c["status"],
        "adaptatif": c["adaptive"],
        "justification": c["rationale"],
        "seances": [
            {
                "id": str(s["id"]),
                "ordre": s["ord"],
                "document_id": str(s["document_id"]) if s["document_id"] else None,
                "ouvrage": s["ouvrage"],
                "auteurs": auteurs(s["authors"]),
                "chapitre_id": str(s["chapter_id"]) if s["chapter_id"] else None,
                "chapitre": s["chapitre"],
                "page_debut": s["page_start"],
                "page_fin": s["page_end"],
                "prevue_le": s["planned_at"],
                "duree_min": s["duration_min"],
                "objectif": s["objective"],
                "livrable": s["deliverable_kind"],
                "livrable_id": s["deliverable_id"],
                "statut": s["status"],
                "faite_le": s["completed_at"],
                "lecture_integrale": s["redistributable"],
            }
            for s in seances
        ],
    }


@router.get("/aujourdhui", summary="La séance du jour")
async def aujourdhui(user: CurrentUser):
    """L'écran d'accueil de l'application : ce qu'il y a à faire maintenant."""
    seance = await fetch_one(
        """select s.*, coalesce(d.title_clean, d.title_raw) as ouvrage, d.authors,
                  d.redistributable, ch.title as chapitre, c.id as chronogramme_id,
                  a.slug as axe, a.label as axe_label
           from session s
           join chronogram c on c.id = s.chronogram_id
           join user_axis ua on ua.id = c.user_axis_id
           join axis a on a.id = ua.axis_id
           left join document d on d.id = s.document_id
           left join chapter ch on ch.id = s.chapter_id
           where ua.user_id = %s and c.status = 'actif' and s.status = 'a_venir'
           order by s.planned_at, s.ord limit 1""",
        (user["id"],),
    )
    semaine = await fetch_all(
        """select date(s.planned_at) as jour, s.status, count(*) as n
           from session s
           join chronogram c on c.id = s.chronogram_id
           join user_axis ua on ua.id = c.user_axis_id
           where ua.user_id = %s and c.status = 'actif'
             and s.planned_at >= date_trunc('week', now())
             and s.planned_at < date_trunc('week', now()) + interval '7 days'
           group by 1, 2 order by 1""",
        (user["id"],),
    )
    a_reviser = await fetch_one(
        """select count(*) as n from concept_mastery
           where user_id = %s and (next_review_at is null or next_review_at <= now())""",
        (user["id"],),
    )
    return {
        "seance": (
            {
                "id": str(seance["id"]),
                "chronogramme_id": str(seance["chronogramme_id"]),
                "axe": seance["axe"],
                "axe_label": seance["axe_label"],
                "document_id": str(seance["document_id"]) if seance["document_id"] else None,
                "ouvrage": seance["ouvrage"],
                "auteurs": auteurs(seance["authors"]),
                "chapitre_id": str(seance["chapter_id"]) if seance["chapter_id"] else None,
                "chapitre": seance["chapitre"],
                "page_debut": seance["page_start"],
                "page_fin": seance["page_end"],
                "duree_min": seance["duration_min"],
                "objectif": seance["objective"],
                "livrable": seance["deliverable_kind"],
                "livrable_id": seance["deliverable_id"],
                "prevue_le": seance["planned_at"],
                "en_retard": seance["planned_at"] is not None
                and seance["planned_at"].date() < datetime.now(timezone.utc).date(),
                "lecture_integrale": seance["redistributable"],
            }
            if seance
            else None
        ),
        "semaine": [
            {"jour": s["jour"], "statut": s["status"], "nb": s["n"]} for s in semaine
        ],
        "notions_a_reviser": a_reviser["n"] if a_reviser else 0,
    }


class SeanceStatutIn(BaseModel):
    statut: Literal["fait", "reporte", "abandonne", "a_venir"]
    duree_reelle_min: int | None = None


@router.patch("/seances/{seance_id}", summary="Marquer une séance")
async def marquer(seance_id: str, data: SeanceStatutIn, user: CurrentUser):
    s = await fetch_one(
        """select s.id, s.document_id, s.duration_min from session s
           join chronogram c on c.id = s.chronogram_id
           join user_axis ua on ua.id = c.user_axis_id
           where s.id = %s and ua.user_id = %s""",
        (seance_id, user["id"]),
    )
    if not s:
        raise NotFound("Cette séance n'existe pas ou ne vous appartient pas.")
    await execute(
        """update session
              set status = %s,
                  completed_at = case when %s = 'fait' then now() else null end,
                  actual_duration_min = coalesce(%s, actual_duration_min)
            where id = %s""",
        (data.statut, data.statut, data.duree_reelle_min, seance_id),
    )
    type_evt = "read_pages" if data.statut == "fait" else "session_skipped"
    await execute(
        """insert into progress_event (user_id, session_id, document_id, type, payload)
           values (%s, %s, %s, %s, %s::jsonb)""",
        (user["id"], seance_id, s["document_id"], type_evt,
         json.dumps({"statut": data.statut, "duree_min": data.duree_reelle_min or s["duration_min"]})),
    )
    return {"id": seance_id, "statut": data.statut}


@router.post("/chronogrammes/{chronogramme_id}/replanifier", summary="Replanifier (Ascension)")
async def replanifier(
    chronogramme_id: str,
    user: Annotated[dict, Depends(exige("chronogramme_adaptatif"))],
):
    """Regénère les séances restantes en une nouvelle version, sans toucher à
    l'historique. Le plan précédent passe en « remplacé » : on garde la trace de
    ce qui avait été promis, ce qui est la condition d'un plan honnête.
    """
    c = await fetch_one(
        """select c.*, ua.id as user_axis_id, ua.axis_id
           from chronogram c join user_axis ua on ua.id = c.user_axis_id
           where c.id = %s and ua.user_id = %s and c.status = 'actif'""",
        (chronogramme_id, user["id"]),
    )
    if not c:
        raise NotFound("Ce chronogramme n'existe pas, ne vous appartient pas, ou n'est plus actif.")

    restantes = await fetch_all(
        """select s.document_id, s.chapter_id, s.page_start, s.page_end, s.duration_min,
                  s.objective, s.deliverable_kind, s.deliverable_id
           from session s
           where s.chronogram_id = %s and s.status in ('a_venir', 'reporte')
           order by s.ord""",
        (chronogramme_id,),
    )
    if not restantes:
        raise Conflict("Toutes les séances de ce plan sont déjà faites ou abandonnées.")

    profil = await _profil(user["id"])
    minutes = profil.get("weekly_minutes") or 150
    duree = max(10, round(sum(r["duration_min"] or 30 for r in restantes) / len(restantes)))
    jours = planner._jours_de_lecture(minutes, duree)
    debut = date.today()
    lundi = debut - timedelta(days=debut.weekday())

    async with connection() as conn:
        await conn.execute(
            "update chronogram set status = 'remplace' where id = %s", (chronogramme_id,)
        )
        neuf = await (await conn.execute(
            """insert into chronogram (user_axis_id, version, supersedes_id, start_date,
                                       target_date, adaptive, status, rationale)
               values (%s, %s, %s, %s, %s, true, 'actif', %s) returning id""",
            (c["user_axis_id"], c["version"] + 1, chronogramme_id, debut, c["target_date"],
             f"Replanification du {debut.isoformat()} : {len(restantes)} séances restantes "
             f"réparties sur {len(jours)} jours par semaine."),
        )).fetchone()
        for i, r in enumerate(restantes):
            semaine, rang = divmod(i, len(jours))
            jour = max(debut, lundi + timedelta(weeks=semaine, days=jours[rang]))
            await conn.execute(
                """insert into session (chronogram_id, ord, document_id, chapter_id,
                                        page_start, page_end, planned_at, duration_min,
                                        objective, deliverable_kind, deliverable_id)
                   values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
                (neuf["id"], i, r["document_id"], r["chapter_id"], r["page_start"],
                 r["page_end"], jour, r["duration_min"], r["objective"],
                 r["deliverable_kind"], r["deliverable_id"]),
            )
    return await detail(str(neuf["id"]), user)
