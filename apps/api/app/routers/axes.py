"""Les axes : la porte d'entrée de la bibliothèque et du chronogramme.

Un axe dont le raccourci commence par un tiret bas est une zone de dépôt, pas
un pôle d'apprentissage : `_a-classer` reçoit les ouvrages déposés par la
console avant qu'un humain ne décide où ils vont. Ces zones restent visibles
dans la console et invisibles partout ailleurs, sans quoi la bibliothèque
afficherait un axe vide au nom de dossier.
"""
from fastapi import APIRouter

from app.core.auteurs import auteurs
from app.core.db import fetch_all, fetch_one
from app.core.deps import OptionalUser
from app.core.errors import NotFound

router = APIRouter(prefix="/axes", tags=["Axes"])

# `chapitres_utiles` conditionne tout : sans structure de chapitres, le
# planificateur n'a rien à découper en séances. On l'expose pour que l'interface
# n'invite pas l'utilisateur dans une impasse.
_AXE_SQL = """
select a.id, a.slug, a.label, a.description, a.sort_order, a.is_premium,
       pa.slug                                as pole_slug,
       pa.label                               as pole_label,
       count(d.id)                            as nb_ouvrages,
       coalesce(sum(coalesce(u.pages, d.page_count)), 0) as nb_pages,
       coalesce(sum(coalesce(u.minutes, p.reading_time_min)), 0) as minutes_lecture,
       coalesce(sum(u.n), 0)                  as chapitres_utiles,
       count(d.id) filter (where u.n > 0)     as ouvrages_exploitables
from axis a
left join axis pa             on pa.id = a.parent_id
left join document_axis da    on da.axis_id = a.id
left join document d          on d.id = da.document_id and d.takedown_status = 'none'
left join document_pedagogy p on p.document_id = d.id
-- Un ouvrage borné à certains chapitres pour cet axe (axis_chapter) ne compte
-- que ceux-là : pages, durée et chapitres. Sans bornes, l'ouvrage entier.
left join lateral (
  select count(*) filter (where coalesce(c.token_count, 0) >= 300) as n,
         case when bool_or(b.borne) then sum(greatest(c.page_end - c.page_start + 1, 0)) end as pages,
         case when bool_or(b.borne) then round(sum(coalesce(c.token_count, 0)) * 0.75 / 200) end as minutes
    from chapter c
    cross join lateral (select exists (select 1 from axis_chapter ac join chapter c2 on c2.id = ac.chapter_id
                                        where ac.axis_id = a.id and c2.document_id = d.id) as borne) b
   where c.document_id = d.id
     and (not b.borne or exists (select 1 from axis_chapter ac where ac.axis_id = a.id and ac.chapter_id = c.id))
) u on true
where a.slug not like '\\_%'
  -- Un pôle regroupe des sous-axes et n'a pas d'ouvrage à lui : il n'est pas un
  -- parcours. Ses sous-axes le nomment dans `pole`.
  and not exists (select 1 from axis enfant where enfant.parent_id = a.id)
group by a.id, pa.slug, pa.label
order by a.sort_order, a.label
"""


@router.get("", summary="Les axes, avec leur pôle")
async def lister_axes(user: OptionalUser):
    lignes = await fetch_all(_AXE_SQL)
    return [
        {
            "id": str(l["id"]),
            "slug": l["slug"],
            "label": l["label"],
            "description": l["description"],
            "premium": l["is_premium"],
            "pole": {"slug": l["pole_slug"], "label": l["pole_label"]} if l["pole_slug"] else None,
            "nb_ouvrages": l["nb_ouvrages"],
            "nb_pages": int(l["nb_pages"] or 0),
            "duree_estimee_min": int(l["minutes_lecture"] or 0),
            "ouvrages_exploitables": l["ouvrages_exploitables"],
            "chapitres_utiles": int(l["chapitres_utiles"] or 0),
            # Un axe sans chapitre découpé ne peut pas donner de chronogramme.
            # Ses ouvrages restent consultables, avec fiche, citations et quiz.
            "parcours_possible": (l["ouvrages_exploitables"] or 0) > 0,
        }
        for l in lignes
    ]


@router.get("/{slug}", summary="Un axe et ses ouvrages")
async def detail_axe(slug: str, user: OptionalUser):
    axe = await fetch_one(
        "select * from axis where slug = %s and slug not like '\\_%%'", (slug,))
    if not axe:
        raise NotFound("Cet axe n'existe pas.")
    ouvrages = await fetch_all(
        """select d.id, coalesce(d.title_clean, d.title_raw) as titre, d.authors, d.year,
                  d.page_count, d.redistributable, p.level, p.doc_type, p.reading_time_min,
                  da.weight
           from document_axis da
           join document d on d.id = da.document_id
           left join document_pedagogy p on p.document_id = d.id
           where da.axis_id = %s and d.takedown_status = 'none'
           order by da.weight desc, p.level nulls last, titre""",
        (axe["id"],),
    )
    return {
        "id": str(axe["id"]),
        "slug": axe["slug"],
        "label": axe["label"],
        "description": axe["description"],
        "premium": axe["is_premium"],
        "ouvrages": [
            {
                "id": str(o["id"]),
                "titre": o["titre"],
                "auteurs": auteurs(o["authors"]),
                "annee": o["year"],
                "pages": o["page_count"],
                "niveau": o["level"],
                "type": o["doc_type"],
                "duree_min": o["reading_time_min"],
                "lecture_integrale": o["redistributable"],
            }
            for o in ouvrages
        ],
    }
