"""Les règles qui rendent le corpus lisible : titres, passages, séances.

Chaque cas vient d'un défaut constaté dans l'application :

- « Pages 2 à 66 et 1 chapitre suivant » pour une séance allant de la page 2 à 197 ;
- « 60 séances d'environ 30 min » et « 22 h 08 au total » dans le même en-tête ;
- une séance de 2 minutes pour 16 pages d'un livre au texte mal extrait ;
- un chapitre ouvert sur la fin du précédent, au milieu d'un mot ;
- des titres « suite de la page précédente », « -7- », « PIA3_Страница_177_1L ».

Fonctions pures : pas d'API ni de base.
"""
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "apps" / "api"))

from app.services import planner  # noqa: E402
from app.services.passages import extrait, lisibles, replier, sans_reprise  # noqa: E402
from app.services.titres import est_appareil, est_titre_casse, titre_lisible  # noqa: E402

_resultats = []


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + repr(detail) if detail else ""))


print("\n· Titres")
for casse in ["suite de la page précédente", "chapitre", "-7-", "12", "PIA3_Страница_177_1L",
              "Que pouvons-nous attendre du développement de l’in-", "BIOGRAPHIE - DAVID GRUSON -", ""]:
    ok(f"« {casse} » est reconnu cassé", est_titre_casse(casse))
for sain in ["Introduction", "Chapitre 3 : l'IA en pratique", "Pages 66 à 197", "GPT-3.5 et GPT-4",
             "Qu'est-ce que l'IA ?"]:
    ok(f"« {sain} » est sain", not est_titre_casse(sain))
ok("un bandeau prend le titre du chapitre précédent, suivi de (suite)",
   titre_lisible("suite de la page précédente", page_start=4, page_end=5, precedent="INTRODUCTION")
   == "INTRODUCTION (suite)")
ok("sans titre précédent, un numéro de page devient une plage de pages",
   titre_lisible("-7-", page_start=11, page_end=12) == "Pages 11 à 12")
ok("une seule page se dit au singulier", titre_lisible("-7-", page_start=11, page_end=11) == "Page 11")
ok("un séparateur final est retiré",
   titre_lisible("BIOGRAPHIE - DAVID GRUSON -", page_start=1, page_end=2) == "BIOGRAPHIE - DAVID GRUSON")
ok("un mot coupé est complété par le texte du chapitre",
   titre_lisible("Que pouvons-nous attendre du développement de l’in-", page_start=1, page_end=3,
                 texte="Que pouvons-nous attendre du développement de l’in-\ntelligence artificielle ?")
   == "Que pouvons-nous attendre du développement de l’intelligence")
ok("sans le texte, le fragment est remplacé par des points de suspension",
   titre_lisible("Que pouvons-nous attendre du développement de l’in-", page_start=1, page_end=3)
   == "Que pouvons-nous attendre du développement de…")
ok("couverture et copyright sont de l'appareil", est_appareil("Couverture") and est_appareil("Page de copyright"))
ok("une préface n'en est pas", not est_appareil("Préface"))

print("\n· Passages")
prec = "Fin du chapitre précédent sur la vision.\nIl parle de l'avenir numérique et de l'intelli"
suiv = "l'avenir numérique et de l'intelli\nLes textes générés par l'IA peuvent-ils être recon-\nnus ?"
ok("la reprise du passage précédent est retirée",
   sans_reprise(prec, suiv).startswith("Les textes générés"), sans_reprise(prec, suiv)[:30])
ok("un passage qui n'était que la reprise devient vide", sans_reprise(prec, "l'avenir numérique et de l'intelli") == "")
ok("une vraie suite de phrase n'est pas amputée",
   sans_reprise("…la critique de la", "raison instrumentale. L'école") == "raison instrumentale. L'école")
ok("les lignes de la mise en page sont recollées, les mots coupés aussi",
   replier("des designs d'amé-\nnagement intérieur pour\nles logos.\nNouvelle phrase.")
   == "des designs d'aménagement intérieur pour les logos.\nNouvelle phrase.")
ok("un numéro de page imprimé n'est pas lu comme du texte",
   replier("fin de la page.\n– 161 –\nEt il rejoignit") == "fin de la page.\nEt il rejoignit", replier("fin de la page.\n– 161 –\nEt il rejoignit"))
ok("les paragraphes restent séparés", replier("Un.\n\nDeux.") == "Un.\n\nDeux.")
ok("une suite de passages se lit d'un tenant",
   lisibles([suiv, "être recon-\nnus ?\nOui, parfois."], prec)[1] == "Oui, parfois.",
   lisibles([suiv, "être recon-\nnus ?\nOui, parfois."], prec))
ok("un paragraphe resté en allemand dans un livre traduit est retiré",
   lisibles(["Les modèles apprennent.\nDen Durchbruch zur Lösung dieses Problems brachten die sogenannten Transformer, die mit dem Text arbeiten und nicht nur ein Wort sehen.\nLa suite est en français."])[0]
   == "Les modèles apprennent.\nLa suite est en français.")
ok("un extrait isolé qui commence en cours de phrase est signalé", extrait("de la page").startswith("…"))

print("\n· Accents")
from app.outils.accents import Accentueur, sans_accents  # noqa: E402
acc = Accentueur()
for phrase in [
    "Le modèle présente une difficulté. Il a été entraîné sur des données. Elle présente ses résultats.",
    "La jeunesse invente de nouveaux usages. Il est configuré en fonction du marché. Ça marche très bien.",
    "À partir de là, où va-t-on ? On va à l'école. Il a une préface. Le préfacier a écrit une préface.",
    "Quelle inquiétude exprime-t-il ? Il plagie des passages. Une qualité, une sécurité, un système.",
] * 6:
    acc.apprendre(phrase)
ok("une question écrite sans accents les retrouve",
   acc.accentuer("Quelle inquietude exprime-t-il dans sa preface ?") == "Quelle inquiétude exprime-t-il dans sa préface ?",
   acc.accentuer("Quelle inquietude exprime-t-il dans sa preface ?"))
ok("un verbe inversé reste au présent", "exprime-t-il" in acc.accentuer("Quelle difference exprime-t-il ?"))
ok("après un pronom, pas de participe sans auxiliaire", acc.accentuer("Il plagie des passages") == "Il plagie des passages")
ok("avec un auxiliaire, le participe est rendu", acc.accentuer("Il est configure en fonction") == "Il est configuré en fonction")
ok("le mode sûr ne touche pas un homographe", acc.accentuer_sur("Ça marche, la qualite suit") == "Ça marche, la qualité suit",
   acc.accentuer_sur("Ça marche, la qualite suit"))
ok("une phrase déjà accentuée n'est pas jugée sans accents", not sans_accents("Quelle inquiétude exprime-t-il dans sa préface ?"))

print("\n· Séances")
u = {"ouvrage": "L'Afrique en 200 proverbes", "chapitre": "Pages 2 à 66", "page_start": 2, "page_end": 197,
     "chapitres_groupes": 2, "repli": True}
ok("des chapitres sans titre regroupés se nomment par leurs pages réelles",
   planner.libelle_seance(u) == "L'Afrique en 200 proverbes : pages 2 à 197", planner.libelle_seance(u))
u = {"ouvrage": "Vivre avec ChatGPT", "chapitre": "Introduction", "page_start": 5, "page_end": 20,
     "chapitres_groupes": 3}
ok("des chapitres titrés regroupés gardent le premier titre",
   planner.libelle_seance(u) == "Vivre avec ChatGPT : Introduction, et les 2 chapitres suivants")
ok("une page presque vide compte quinze secondes, un texte complet compte son texte",
   planner.minutes_de(624, 200, pages=16) == 4 and planner.minutes_de(12000, 200, pages=16) == 45,
   (planner.minutes_de(624, 200, pages=16), planner.minutes_de(12000, 200, pages=16)))
seances = [{"duration_min": 30, "document_id": "a"}] * 40 + [{"duration_min": 10, "document_id": "b"}] * 20
j = planner.justification_plan(seances, [0, 2, 4], duree_seance=30, wpm=200, candidats=5, tronque=True)
ok("l'en-tête donne la moyenne réelle et un total qui se recoupent",
   "23 min en moyenne" in j and "23 h 20" in j and "20 semaines" in j and "sur les 5" in j, j)

chapitres = [
    {"id": i, "title": t, "page_start": a, "page_end": b, "token_count": k, "quiz_id": None}
    for i, (t, a, b, k) in enumerate([
        ("Préface", 1, 2, 700), ("Chapitre 1", 3, 40, 12000), ("Chapitre 2", 41, 48, 2500),
        ("Chapitre 3", 49, 55, 2400), ("Épilogue", 56, 57, 400),
    ])
]
s, _ = planner.construire([{"id": "d", "titre": "Livre", "redistributable": False}], {"d": chapitres},
                          debut=planner.date(2026, 9, 14), fin=None, minutes_semaine=150, duree_seance=30)
ok("aucune séance de moins de 10 minutes", all(x["duration_min"] >= 10 for x in s),
   [(x["objective"], x["duration_min"]) for x in s])
ok("les séances tiennent près de la durée visée", all(x["duration_min"] <= 51 for x in s))
ok("le livre est couvert de la première à la dernière page",
   s[0]["page_start"] == 1 and s[-1]["page_end"] == 57, [(x["page_start"], x["page_end"]) for x in s])

print("\n" + "=" * 92)
print("\n· Quiz")
from app.outils.melanger_choix import melanger  # noqa: E402

qs = [{"q": f"Question {i}", "choix": [f"juste {i}", "faux a", "faux b", "faux c"], "reponse": 0} for i in range(200)]
m = melanger(qs, "lot-essai")
ok("la bonne réponse suit son texte", all(x["choix"][x["reponse"]] == f"juste {i}" for i, x in enumerate(m)))
ok("le mélange est reproductible", melanger(qs, "lot-essai") == m)
from collections import Counter as _C  # noqa: E402
rangs = _C(x["reponse"] for x in m)
ok("aucune position ne domine", max(rangs.values()) / len(m) < 0.4, dict(rangs))
ok("les questions et explications ne changent pas", [x["q"] for x in m] == [x["q"] for x in qs])

_echecs = [x for x in _resultats if not x[0]]
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
sys.exit(1 if _echecs else 0)
