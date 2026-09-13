"""Le cercle de lecteurs : amitiés, encouragements, échanges, fil d'activité.

Trois règles tiennent l'ensemble, et elles sont vérifiées ici plutôt que dans
chaque route :

- on n'écrit qu'à un ami, c'est-à-dire une amitié acceptée des deux côtés ;
- un blocage, dans un sens ou dans l'autre, coupe tout : demande, message,
  encouragement, et l'amitié elle-même ;
- un lecteur qui ne partage pas son activité n'apparaît dans aucun fil.

On trouve un lecteur par son code ASCENDA, jamais par son nom ni son adresse :
personne ne peut parcourir les comptes.
"""
from datetime import datetime, timedelta, timezone

from app.core.db import connection, execute, fetch_all, fetch_one
from app.core.errors import ApiError, Conflict, NotFound
from app.services import codes

# Des plafonds larges pour un usage normal, bas pour un robot. Au-delà, un
# refus poli : on ne coupe pas le compte.
PLAFONDS = {
    "amitie": (30, "demandes d'ami"),
    "encouragement": (60, "encouragements"),
    "echange": (300, "messages"),
}

GENRES = {
    "bravo": "Bravo pour ta lecture !",
    "courage": "Courage, tu tiens le bon rythme.",
    "defi": "On lit la même chose cette semaine ?",
    "merci": "Merci pour l'encouragement !",
}


class TropDeMessages(ApiError):
    def __init__(self, detail: str):
        super().__init__(detail, 429, "trop_de_requetes")


def prenom(nom: str | None) -> str:
    return ((nom or "").strip().split(" ") or [""])[0] or "Un lecteur"


async def _plafond(table: str, colonne: str, user_id: str) -> None:
    limite, quoi = PLAFONDS[table]
    n = await fetch_one(
        f"select count(*) as n from {table} where {colonne} = %s and created_at > now() - interval '1 day'",
        (user_id,),
    )
    if n["n"] >= limite:
        raise TropDeMessages(
            f"Vous avez atteint la limite de {limite} {quoi} par jour. Reprenez demain."
        )


async def bloque(a: str, b: str) -> bool:
    return bool(await fetch_one(
        "select 1 from blocage where (user_id = %s and bloque_id = %s) or (user_id = %s and bloque_id = %s)",
        (a, b, b, a),
    ))


async def relation(a: str, b: str) -> dict | None:
    return await fetch_one(
        """select * from amitie
            where least(demandeur_id, destinataire_id) = least(%s::uuid, %s::uuid)
              and greatest(demandeur_id, destinataire_id) = greatest(%s::uuid, %s::uuid)""",
        (a, b, a, b),
    )


async def exiger_ami(user_id: str, ami_id: str) -> dict:
    """L'ami, s'il l'est vraiment. Un identifiant quelconque ne donne rien : on
    répond « introuvable » plutôt que « interdit », pour ne pas confirmer qu'un
    compte existe."""
    r = await relation(user_id, ami_id)
    if not r or r["statut"] != "acceptee" or await bloque(user_id, ami_id):
        raise NotFound("Ce lecteur ne fait pas partie de votre cercle.")
    ami = await fetch_one(
        "select id, display_name, partage_activite from app_user where id = %s and is_active", (ami_id,))
    if not ami:
        raise NotFound("Ce lecteur ne fait pas partie de votre cercle.")
    return ami


# ----------------------------------------------------------------- amitiés

async def demander(user: dict, code_brut: str) -> dict:
    """Envoie une demande d'ami à partir d'un code ASCENDA.

    Si l'autre lecteur nous avait déjà envoyé une demande, on l'accepte : deux
    personnes qui veulent être amies n'ont pas à attendre l'une l'autre.
    """
    code = codes.normaliser(code_brut)
    cible = await fetch_one(
        "select id, display_name from app_user where code_parrainage = %s and is_active", (code,))
    uid = str(user["id"])
    if not cible:
        raise codes.CodeRefuse("Aucun lecteur ne porte ce code. Vérifiez qu'il est bien recopié.")
    cid = str(cible["id"])
    if cid == uid:
        raise codes.CodeRefuse("C'est votre propre code : partagez-le pour qu'on vous ajoute.")
    if await bloque(uid, cid):
        # Même message qu'un code inconnu : un blocage ne se révèle pas.
        raise codes.CodeRefuse("Aucun lecteur ne porte ce code. Vérifiez qu'il est bien recopié.")

    existante = await relation(uid, cid)
    if existante:
        if existante["statut"] == "acceptee":
            raise Conflict(f"{prenom(cible['display_name'])} fait déjà partie de votre cercle.")
        if existante["statut"] == "en_attente" and str(existante["demandeur_id"]) == uid:
            raise Conflict("Votre demande est déjà envoyée. Elle attend une réponse.")
        if existante["statut"] == "en_attente":
            return await repondre(user, str(existante["id"]), accepter=True)
        # Une demande refusée peut être renouvelée, mais pas plus d'une fois
        # par semaine : un refus doit rester un refus.
        if existante["repondu_le"] and existante["repondu_le"] > datetime.now(timezone.utc) - timedelta(days=7):
            raise Conflict("Cette demande a reçu une réponse récemment. Réessayez plus tard.")
        await _plafond("amitie", "demandeur_id", uid)
        await execute(
            """update amitie set demandeur_id = %s, destinataire_id = %s, statut = 'en_attente',
                      created_at = now(), repondu_le = null where id = %s""",
            (uid, cid, existante["id"]),
        )
        return {"statut": "en_attente", "ami": {"id": cid, "nom": prenom(cible["display_name"])}}

    await _plafond("amitie", "demandeur_id", uid)
    try:
        await execute(
            "insert into amitie (demandeur_id, destinataire_id) values (%s, %s)", (uid, cid))
    except Exception as exc:  # noqa: BLE001 - deux demandes croisées à la même seconde
        if "ux_amitie_paire" in str(exc):
            raise Conflict("Une demande existe déjà entre vous. Rafraîchissez le cercle.") from exc
        raise
    return {"statut": "en_attente", "ami": {"id": cid, "nom": prenom(cible["display_name"])}}


async def repondre(user: dict, demande_id: str, *, accepter: bool) -> dict:
    uid = str(user["id"])
    async with connection() as conn:
        cur = await conn.execute(
            """update amitie set statut = %s, repondu_le = now()
                where id = %s and destinataire_id = %s and statut = 'en_attente'
            returning demandeur_id""",
            ("acceptee" if accepter else "refusee", demande_id, uid),
        )
        ligne = await cur.fetchone()
    if not ligne:
        raise NotFound("Cette demande n'existe plus.")
    autre = await fetch_one("select id, display_name from app_user where id = %s", (ligne["demandeur_id"],))
    return {"statut": "acceptee" if accepter else "refusee",
            "ami": {"id": str(autre["id"]), "nom": prenom(autre["display_name"])}}


async def retirer(user: dict, ami_id: str) -> None:
    n = await execute(
        """delete from amitie
            where least(demandeur_id, destinataire_id) = least(%s::uuid, %s::uuid)
              and greatest(demandeur_id, destinataire_id) = greatest(%s::uuid, %s::uuid)""",
        (user["id"], ami_id, user["id"], ami_id),
    )
    if not n:
        raise NotFound("Ce lecteur ne fait pas partie de votre cercle.")


async def bloquer(user: dict, autre_id: str) -> None:
    """Bloquer retire l'amitié et empêche toute nouvelle demande. Les messages
    passés restent en base pour la modération, mais ne se montrent plus."""
    uid = str(user["id"])
    if uid == autre_id:
        raise Conflict("Vous ne pouvez pas vous bloquer vous-même.")
    if not await fetch_one("select 1 from app_user where id = %s", (autre_id,)):
        raise NotFound("Ce lecteur n'existe pas.")
    await execute(
        "insert into blocage (user_id, bloque_id) values (%s, %s) on conflict do nothing", (uid, autre_id))
    await execute(
        """delete from amitie
            where least(demandeur_id, destinataire_id) = least(%s::uuid, %s::uuid)
              and greatest(demandeur_id, destinataire_id) = greatest(%s::uuid, %s::uuid)""",
        (uid, autre_id, uid, autre_id),
    )


# ------------------------------------------------------------- lectures

async def resume_lecture(user_ids: list[str]) -> dict[str, dict]:
    """Ce qu'un ami voit de la lecture d'un autre : sa semaine, sa régularité,
    son dernier livre. Rien de plus, et rien pour qui ne partage pas."""
    if not user_ids:
        return {}
    lignes = await fetch_all(
        """select u.id,
                  u.partage_activite,
                  count(*) filter (where e.type = 'read_pages' and e.at > now() - interval '7 days') as seances_semaine,
                  coalesce(sum((e.payload->>'duree_min')::int) filter (
                      where e.type = 'read_pages' and e.at > now() - interval '7 days'), 0) as minutes_semaine,
                  count(distinct (e.at at time zone 'Africa/Douala')::date) filter (
                      where e.at > now() - interval '14 days') as jours_actifs_14,
                  max(e.at) as derniere_activite
             from app_user u
             left join progress_event e on e.user_id = u.id
                  and e.type in ('read_pages', 'quiz_attempt', 'concept_mastered')
            where u.id = any(%s::uuid[])
            group by u.id""",
        (user_ids,),
    )
    derniers = await fetch_all(
        """select distinct on (e.user_id) e.user_id, coalesce(d.title_clean, d.title_raw) as titre
             from progress_event e join document d on d.id = e.document_id
            where e.user_id = any(%s::uuid[]) and e.type in ('read_pages', 'opened_doc', 'quiz_attempt')
            order by e.user_id, e.at desc""",
        (user_ids,),
    )
    titres = {str(d["user_id"]): d["titre"] for d in derniers}
    sortie = {}
    for l in lignes:
        uid = str(l["id"])
        if not l["partage_activite"]:
            sortie[uid] = {"partage": False}
            continue
        sortie[uid] = {
            "partage": True,
            "seances_semaine": l["seances_semaine"],
            "minutes_semaine": l["minutes_semaine"],
            "jours_actifs_14": l["jours_actifs_14"],
            "derniere_activite": l["derniere_activite"],
            "lit": titres.get(uid),
        }
    return sortie


async def amis(user: dict) -> list[dict]:
    lignes = await fetch_all(
        """select u.id, u.display_name, a.repondu_le as amis_depuis,
                  (select count(*) from echange x
                    where x.auteur_id = u.id and x.destinataire_id = %(moi)s
                      and x.lu_le is null and x.masque_le is null) as non_lus
             from amitie a
             join app_user u on u.id = case when a.demandeur_id = %(moi)s then a.destinataire_id
                                            else a.demandeur_id end
            where %(moi)s in (a.demandeur_id, a.destinataire_id) and a.statut = 'acceptee'
              and u.is_active
            order by u.display_name""",
        {"moi": user["id"]},
    )
    lectures = await resume_lecture([str(l["id"]) for l in lignes])
    return [
        {"id": str(l["id"]), "nom": prenom(l["display_name"]), "amis_depuis": l["amis_depuis"],
         "non_lus": l["non_lus"], "lecture": lectures.get(str(l["id"]), {"partage": False})}
        for l in lignes
    ]


async def demandes(user: dict) -> dict:
    recues = await fetch_all(
        """select a.id, a.created_at, u.id as user_id, u.display_name
             from amitie a join app_user u on u.id = a.demandeur_id
            where a.destinataire_id = %s and a.statut = 'en_attente' order by a.created_at desc""",
        (user["id"],),
    )
    envoyees = await fetch_all(
        """select a.id, a.created_at, u.id as user_id, u.display_name
             from amitie a join app_user u on u.id = a.destinataire_id
            where a.demandeur_id = %s and a.statut = 'en_attente' order by a.created_at desc""",
        (user["id"],),
    )

    def vue(l):
        return {"id": str(l["id"]), "le": l["created_at"],
                "lecteur": {"id": str(l["user_id"]), "nom": prenom(l["display_name"])}}

    return {"recues": [vue(l) for l in recues], "envoyees": [vue(l) for l in envoyees]}


async def fil(user: dict, jours: int = 14, limite: int = 60) -> list[dict]:
    """Ce que les amis ont lu ces derniers jours, du plus récent au plus ancien.

    Un événement porte déjà les encouragements qu'on lui a envoyés : l'écran
    montre « encouragé » plutôt que d'inviter à le refaire.
    """
    lignes = await fetch_all(
        """with mes_amis as (
               select case when demandeur_id = %(moi)s then destinataire_id else demandeur_id end as id
                 from amitie
                where %(moi)s in (demandeur_id, destinataire_id) and statut = 'acceptee'
           )
           select e.id, e.type, e.payload, e.at, u.id as user_id, u.display_name,
                  coalesce(d.title_clean, d.title_raw) as titre,
                  exists (select 1 from encouragement g
                           where g.evenement_id = e.id and g.auteur_id = %(moi)s) as encourage
             from progress_event e
             join mes_amis m on m.id = e.user_id
             join app_user u on u.id = e.user_id and u.partage_activite and u.is_active
             left join document d on d.id = e.document_id
            where e.type in ('read_pages', 'quiz_attempt', 'concept_mastered')
              and e.at > now() - make_interval(days => %(jours)s)
              and (e.type <> 'read_pages' or e.payload->>'statut' = 'fait')
              and not exists (select 1 from blocage b
                               where (b.user_id = %(moi)s and b.bloque_id = e.user_id)
                                  or (b.user_id = e.user_id and b.bloque_id = %(moi)s))
            order by e.at desc
            limit %(limite)s""",
        {"moi": user["id"], "jours": jours, "limite": limite},
    )
    sortie = []
    for l in lignes:
        p = l["payload"] or {}
        if l["type"] == "read_pages":
            genre, texte = "seance", (
                f"a terminé une séance de {p['duree_min']} min" if p.get("duree_min") else "a terminé une séance")
        elif l["type"] == "quiz_attempt":
            justes, total = p.get("justes"), p.get("total")
            genre, texte = "quiz", (
                f"a réussi {justes} questions sur {total} à un quiz" if total else "a passé un quiz")
        else:
            genre, texte = "notion", "a acquis une nouvelle notion"
        sortie.append({
            "id": str(l["id"]), "genre": genre, "texte": texte, "ouvrage": l["titre"], "le": l["at"],
            "lecteur": {"id": str(l["user_id"]), "nom": prenom(l["display_name"])},
            "encourage": l["encourage"],
        })
    return sortie


# ------------------------------------------------------- encouragements

async def encourager(user: dict, ami_id: str, genre: str, message: str | None,
                     evenement_id: str | None) -> dict:
    uid = str(user["id"])
    await exiger_ami(uid, ami_id)
    await _plafond("encouragement", "auteur_id", uid)
    if evenement_id:
        ev = await fetch_one("select user_id from progress_event where id = %s", (evenement_id,))
        if not ev or str(ev["user_id"]) != ami_id:
            raise NotFound("Cette activité n'existe pas dans le fil.")
        if await fetch_one(
            "select 1 from encouragement where evenement_id = %s and auteur_id = %s", (evenement_id, uid)):
            raise Conflict("Vous avez déjà encouragé cette lecture.")
    texte = (message or "").strip() or None
    ligne = await fetch_one(
        """insert into encouragement (auteur_id, destinataire_id, genre, message, evenement_id)
           values (%s, %s, %s, %s, %s) returning id, created_at""",
        (uid, ami_id, genre, texte, evenement_id),
    )
    return {"id": str(ligne["id"]), "genre": genre, "message": texte or GENRES[genre],
            "le": ligne["created_at"]}


async def encouragements_recus(user: dict, limite: int = 40) -> list[dict]:
    lignes = await fetch_all(
        """select g.id, g.genre, g.message, g.created_at, g.vu_le, u.id as auteur_id, u.display_name,
                  coalesce(d.title_clean, d.title_raw) as ouvrage
             from encouragement g
             join app_user u on u.id = g.auteur_id
             left join progress_event e on e.id = g.evenement_id
             left join document d on d.id = e.document_id
            where g.destinataire_id = %s and g.masque_le is null
              and not exists (select 1 from blocage b where b.user_id = %s and b.bloque_id = g.auteur_id)
            order by g.created_at desc limit %s""",
        (user["id"], user["id"], limite),
    )
    return [
        {"id": str(l["id"]), "genre": l["genre"], "message": l["message"] or GENRES[l["genre"]],
         "le": l["created_at"], "nouveau": l["vu_le"] is None, "ouvrage": l["ouvrage"],
         "auteur": {"id": str(l["auteur_id"]), "nom": prenom(l["display_name"])}}
        for l in lignes
    ]


# ------------------------------------------------------------- échanges

def _vue_echange(l: dict, moi: str) -> dict:
    return {"id": str(l["id"]), "texte": l["texte"], "le": l["created_at"],
            "de_moi": str(l["auteur_id"]) == moi, "lu": l["lu_le"] is not None}


async def conversation(user: dict, ami_id: str, avant: datetime | None = None, limite: int = 50) -> dict:
    uid = str(user["id"])
    ami = await exiger_ami(uid, ami_id)
    lignes = await fetch_all(
        """select id, auteur_id, texte, created_at, lu_le from echange
            where least(auteur_id, destinataire_id) = least(%s::uuid, %s::uuid)
              and greatest(auteur_id, destinataire_id) = greatest(%s::uuid, %s::uuid)
              and masque_le is null
              and (%s::timestamptz is null or created_at < %s::timestamptz)
            order by created_at desc limit %s""",
        (uid, ami_id, uid, ami_id, avant, avant, limite),
    )
    return {
        "ami": {"id": ami_id, "nom": prenom(ami["display_name"])},
        # Du plus ancien au plus récent : l'ordre de lecture d'une conversation.
        "messages": [_vue_echange(l, uid) for l in reversed(lignes)],
        "plus_anciens": len(lignes) == limite,
    }


async def ecrire(user: dict, ami_id: str, texte: str) -> dict:
    uid = str(user["id"])
    await exiger_ami(uid, ami_id)
    texte = texte.strip()
    if not texte:
        raise codes.CodeRefuse("Le message est vide.")
    await _plafond("echange", "auteur_id", uid)
    ligne = await fetch_one(
        """insert into echange (auteur_id, destinataire_id, texte) values (%s, %s, %s)
           returning id, auteur_id, texte, created_at, lu_le""",
        (uid, ami_id, texte),
    )
    return _vue_echange(ligne, uid)


async def marquer_lus(user: dict, ami_id: str) -> int:
    await exiger_ami(str(user["id"]), ami_id)
    return await execute(
        "update echange set lu_le = now() where auteur_id = %s and destinataire_id = %s and lu_le is null",
        (ami_id, user["id"]),
    )


async def signaler(user: dict, *, echange_id: str | None, encouragement_id: str | None, motif: str) -> dict:
    """On ne signale que ce qu'on a reçu : un lecteur ne peut pas faire lire à
    la modération les messages d'une conversation à laquelle il n'a pas part."""
    uid = str(user["id"])
    if bool(echange_id) == bool(encouragement_id):
        raise codes.CodeRefuse("Indiquez le message ou l'encouragement à signaler.")
    if echange_id:
        cible = await fetch_one("select destinataire_id from echange where id = %s", (echange_id,))
    else:
        cible = await fetch_one("select destinataire_id from encouragement where id = %s", (encouragement_id,))
    if not cible or str(cible["destinataire_id"]) != uid:
        raise NotFound("Ce message n'existe pas.")
    ligne = await fetch_one(
        """insert into signalement (auteur_id, echange_id, encouragement_id, motif)
           values (%s, %s, %s, %s) on conflict do nothing returning id""",
        (uid, echange_id, encouragement_id, motif.strip()),
    )
    if not ligne:
        raise Conflict("Vous avez déjà signalé ce message.")
    return {"id": str(ligne["id"])}


async def compteurs(user: dict) -> dict:
    """Les pastilles de l'application, en une requête."""
    l = await fetch_one(
        """select
             (select count(*) from amitie where destinataire_id = %(moi)s and statut = 'en_attente') as demandes,
             (select count(*) from echange where destinataire_id = %(moi)s and lu_le is null
                 and masque_le is null) as messages,
             (select count(*) from encouragement where destinataire_id = %(moi)s and vu_le is null
                 and masque_le is null) as encouragements""",
        {"moi": user["id"]},
    )
    return {**l, "total": l["demandes"] + l["messages"] + l["encouragements"]}

