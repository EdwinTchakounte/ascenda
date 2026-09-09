# Contrat partagé

Le contrat entre l'API et ses deux clients n'est écrit nulle part ailleurs : la
vitrine et l'application composent leurs URL dans le code. Renommer une route
casse donc un écran sans que rien ne le signale, jusqu'à ce qu'un utilisateur
tombe dessus.

| Fichier | Rôle |
|---|---|
| `openapi.json` | Le schéma de l'API, figé et versionné. C'est la référence à laquelle on compare. |
| `verifier_contrat.py` | Relève les chemins appelés dans le code Dart et TypeScript, et les confronte au schéma. |

```bash
python3 packages/shared/verifier_contrat.py           # comparer au contrat figé
python3 packages/shared/verifier_contrat.py --vif     # comparer à l'API qui tourne
python3 packages/shared/verifier_contrat.py --figer   # mettre le contrat à jour
```

Après avoir changé une route, deux gestes : `--figer` pour enregistrer le
nouveau contrat, et une relecture du écart que `git diff` fait apparaître sur
`openapi.json`. Un chemin qui disparaît de ce fichier est un écran qui va
tomber.

## Ce que ce n'est pas

Ce n'est pas de la génération de types. Les modèles Dart et TypeScript restent
écrits à la main, parce qu'ils portent des choix que le schéma ne dit pas :
quel champ vaut zéro plutôt que nul, comment nommer une chose en français, ce
qu'on affiche quand la valeur manque.

Ce vérificateur attrape la panne la plus fréquente, pas toutes. Un champ
renommé dans une réponse passe au travers ; seule une route disparue est
détectée.
