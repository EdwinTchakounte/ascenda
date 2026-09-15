"""Mélanger l'ordre des réponses des quiz.

Les questions ont été rédigées avec la bonne réponse en premier : 11 308 sur
11 540. Rien ne les mélangeait ensuite, ni l'API, ni le pack hors ligne, ni
l'application. Un lecteur qui cochait toujours la première case réussissait
presque tout, et la révision espacée ne voyait jamais ses lacunes.

On mélange une fois, dans la base, les choix et l'indice de la bonne réponse
ensemble. Tout ce qui lit un quiz (correction, diagnostic, export PDF, pack hors
ligne) lit les deux au même endroit et reste donc cohérent. Le texte des
questions ne change pas : une question déjà passée reste la même question.

Le mélange est déterministe (graine tirée de l'identifiant du dérivé et du rang
de la question) et marqué dans le contenu : rejouer l'outil ne remélange rien.
Le contenu d'avant est gardé dans `content_source` s'il n'y est pas déjà.

    python -m app.outils.melanger_choix --essai
    python -m app.outils.melanger_choix
"""
import argparse
import asyncio
import hashlib
import json
import random
from collections import Counter

from app.core.db import close_pool, connection, fetch_all, open_pool

MARQUE = "choix_melanges"


def melanger(questions: list[dict], graine: str) -> list[dict]:
    """Les questions avec leurs choix mélangés, la bonne réponse suivie."""
    sortie = []
    for i, q in enumerate(questions):
        choix = q.get("choix") or []
        bonne = q.get("reponse")
        if len(choix) < 2 or not isinstance(bonne, int) or not 0 <= bonne < len(choix):
            sortie.append(q)
            continue
        ordre = list(range(len(choix)))
        alea = random.Random(int(hashlib.sha256(f"{graine}:{i}".encode()).hexdigest()[:16], 16))
        alea.shuffle(ordre)
        sortie.append({**q, "choix": [choix[k] for k in ordre], "reponse": ordre.index(bonne)})
    return sortie


async def main(essai: bool) -> None:
    await open_pool()
    try:
        lots = await fetch_all(
            """select id, content, content_source from derivative
                where kind = 'quiz' and superseded_by is null
                  and jsonb_array_length(coalesce(content->'questions', '[]'::jsonb)) > 0
                  and not coalesce((content->>%s)::boolean, false)""",
            (MARQUE,),
        )
        avant, apres, touches = Counter(), Counter(), 0
        async with connection() as conn:
            for l in lots:
                questions = l["content"]["questions"]
                nouvelles = melanger(questions, str(l["id"]))
                avant.update(q.get("reponse") for q in questions)
                apres.update(q.get("reponse") for q in nouvelles)
                touches += 1
                if essai:
                    continue
                contenu = {**l["content"], "questions": nouvelles, MARQUE: True}
                await conn.execute(
                    """update derivative set content = %s::jsonb,
                              content_source = coalesce(content_source, content)
                        where id = %s""",
                    (json.dumps(contenu, ensure_ascii=False), l["id"]),
                )
        print(f"{touches} lots de quiz {'à mélanger' if essai else 'mélangés'}.")
        print(f"  rang de la bonne réponse avant : {dict(sorted(avant.items()))}")
        print(f"  rang de la bonne réponse après : {dict(sorted(apres.items()))}")
    finally:
        await close_pool()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--essai", action="store_true", help="montrer sans écrire")
    asyncio.run(main(p.parse_args().essai))
