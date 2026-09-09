# `_shared/` — socle commun

`common.py` est le seul utilitaire transverse dont dépendent les deux modules.
Copie-le tel quel dans `apps_coop/common.py` de ton nouveau projet.

Il fournit :

- `TimestampedModel` — mixin abstrait `created_at` / `updated_at`.
- `money_field(**kwargs)` — colonne `DecimalField` monétaire standard (14,2).
- `ZERO` — `Decimal("0.00")`.
- `parse_pagination(request, default_limit, max_limit)` — pagination défensive
  `?limit=&offset=` pour les endpoints de liste admin.

Aucune dépendance externe (volontairement, pour éviter les cycles d'import).

> L'autre dépendance transverse — `apps_coop.audit.services` — n'est pas
> fournie ici car elle est propre au projet source. Voir le stub minimal dans
> `paiement/README.md` (§ « Dépendances inter-apps à fournir »).
