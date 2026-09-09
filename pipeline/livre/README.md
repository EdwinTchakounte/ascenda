# Le module par ouvrage

Un seul point d'entrée pour amener un livre de la source au corpus servi.

```bash
.venv/bin/python pipeline/livre/etat.py                      # ce qui manque, ouvrage par ouvrage
.venv/bin/python pipeline/livre/produire.py --doc 753e4ca2 --plan
.venv/bin/python pipeline/derive/derive.py --kinds quiz,citation --estimer
.venv/bin/python pipeline/livre/produire.py --tous --etapes citation
```

## Quatre garanties

**Elle s'appelle.** `produire.py` passe `--doc` et `--kind` à `derive.py`. Ces
deux options n'existaient pas : le moteur sortait en erreur d'argument avant le
premier appel au modèle, et personne ne s'en apercevait parce que le contrôle de
clé s'arrêtait juste avant. Le module n'avait donc jamais rien produit.

**Elle ne refait pas.** La sélection écarte ce qui existe déjà. Sans ce filtre,
relancer pour combler les 1 549 quiz manquants aurait régénéré les 2 304 déjà
produits, au tarif plein. `--refaire` force la reprise quand on veut vraiment
tout reconstruire.

**Elle remplace au lieu d'empiler.** L'ancien dérivé sort de la circulation
avant que le nouveau n'entre, et pointe ensuite vers son remplaçant. L'index
unique partiel garantit qu'il n'y a jamais qu'un dérivé actif par cible et par
type ; l'historique reste consultable.

**Elle annonce son coût.** `--estimer` compte exactement les jetons d'entrée,
estime la sortie, et donne le prix en direct et en batch. Les tarifs sont dans
deux constantes à vérifier chez Anthropic : elles donnent un ordre de grandeur,
pas une facture.

## Ce que le produit lit vraiment

Six des sept types ont désormais un écran :

| type | où il s'affiche |
|---|---|
| `fiche_lecture` | fiche d'ouvrage |
| `resume_executif` | fiche d'ouvrage, bloc « En bref » |
| `synthese` | fiche d'ouvrage, sections et pages |
| `compte_rendu` | lecteur, avant le texte du chapitre |
| `quiz` | après chaque séance |
| `citation` | lecteur et pack hors ligne |

`flashcards` reste sans écran. Elle est donc **sortie du plan par défaut** : la
révision espacée fonctionne déjà sur les notions ancrées dans le texte, et
compter comme manquant ce que personne n'attend rendait tout le corpus
perpétuellement incomplet. Le schéma et la consigne existent, on la produira le
jour où un écran l'attendra :

```bash
produire.py --doc 753e4ca2 --etapes flashcards
```

Compte rendu, synthèse et résumé exécutif sont **nos textes**, pas ceux de
l'auteur : ce sont des oeuvres dérivées. Le plafond de citation ne les gouverne
pas, il ne gouverne que les extraits littéraux.

## Le seuil des 300 jetons

En deçà, un chapitre est de l'appareil : sommaire, colophon, index, quatrième de
couverture. Le planificateur ne les programme jamais en séance. Le moteur les
écarte donc aussi, avec le même seuil, sinon un ouvrage n'atteindrait jamais
l'état « complet » et on paierait pour des quiz sur des tables des matières.
