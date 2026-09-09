# Modules `mail` + `paiement` — extraction réutilisable

Deux modules Django **autonomes** extraits verbatim de GATHE Finance, prêts à
être greffés dans un nouveau projet Django/DRF. Ils encapsulent deux briques
qui ont déjà été éprouvées en production :

| Module | App Django | Rôle |
|--------|-----------|------|
| [`mail/`](./mail/README.md) | `notifications` | E-mails transactionnels via **Brevo HTTP API** (django-anymail), templates en base, moteur d'événements, kill-switch, logs d'envoi, notifications in-app, annonces broadcast. |
| [`paiement/`](./paiement/README.md) | `payments` | Encaissements/décaissements **mobile money via Tara**, webhook idempotent, **réconciliation (suivi)** par cron, matching à 3 stratégies — la logique anti-« compensation » corrigée en prod. |
| [`_shared/`](./_shared/) | — | Le petit socle commun (`common.py`) dont les deux apps dépendent : `TimestampedModel`, `money_field`, `ZERO`, `parse_pagination`. À copier tel quel. |

> Le code des deux apps est **copié à l'identique** depuis le projet source
> (`backend/apps_coop/notifications` et `backend/apps_coop/payments`). Rien n'a
> été simplifié : tu récupères exactement le comportement validé, y compris les
> correctifs de suivi/réconciliation Tara.

---

## Ce que tu dois savoir avant d'intégrer

Ces apps proviennent d'un monorepo où elles vivaient sous le package
`apps_coop`. Tous les imports internes sont de la forme `apps_coop.<app>`.
Deux stratégies au choix :

### Option A — garder le namespace `apps_coop` (le plus rapide)
Recrée un package `apps_coop/` dans ton nouveau projet et dépose les apps
dedans :

```
ton_projet/
  apps_coop/
    __init__.py
    common.py              ← copié depuis _shared/common.py
    notifications/         ← copié depuis mail/notifications/
    payments/              ← copié depuis paiement/payments/  (uniquement si tu prends le paiement)
    audit/                 ← À FOURNIR (voir « Dépendances à fournir »)
    members/               ← À FOURNIR ou adapter (modèle Member + permissions)
```

Avec cette option **aucun import n'est à modifier**. C'est l'intégration
recommandée.

### Option B — renommer le namespace
Si tu préfères `apps/notifications`, fais un rechercher-remplacer global
`apps_coop.` → `apps.` (ou ton préfixe) dans les `.py` des deux apps, puis
ajuste les `name = "apps_coop.xxx"` dans les `apps.py`.

---

## Dépendances à fournir dans le nouveau projet

Les deux modules s'appuient sur quelques briques transverses du projet source.
Elles sont **petites et documentées** — tu les recrées une fois.

| Dépendance | Utilisée par | Quoi faire |
|-----------|--------------|-----------|
| `apps_coop.common` | mail + paiement | Fourni dans `_shared/common.py`. Copier tel quel. |
| `apps_coop.audit.services` (`record`, `client_ip`, `get_int_setting`, `get_str_setting`) | mail + paiement | Module d'audit + AppSettings tunables. Voir le contrat exact dans chaque README. Tu peux fournir un stub minimal (cf. README paiement). |
| `apps_coop.members.models.Member` | paiement (FK `Payment.member`) | Ton modèle « utilisateur métier ». Le `Payment` pointe dessus. Adapte la FK à ton modèle. |
| `apps_coop.members.permissions` (`IsMember`, `IsStaff`, `IsAdmin`) | mail + paiement (vues DRF) | Classes de permission DRF basées sur les rôles. Fournis les tiennes. |
| Modèles métier (`loans`, `savings`, `BookletOrder`…) | paiement (business hooks) | **Point d'adaptation principal du module paiement** — voir README paiement §« Business hooks ». |

---

## Démarrage rapide

1. Copie `_shared/common.py` → `apps_coop/common.py`.
2. Copie l'app voulue (`mail/notifications` et/ou `paiement/payments`) sous `apps_coop/`.
3. Ajoute-les à `INSTALLED_APPS` + `anymail`.
4. Renseigne les variables d'environnement (voir README de chaque module).
5. `python manage.py migrate`
6. `python manage.py seed_email_templates` (mail) / `seed_fees` + `seed_rates` (paiement).
7. Branche les URLs dans ton routeur `/api/v1/`.

Détails complets et points de vigilance dans les deux READMEs dédiés.

---

## Pourquoi c'est « optimal » et sans rejouer les bugs de compensation

Le module paiement embarque telle quelle la mécanique de **suivi** qui a été
durcie en prod (voir README paiement) :

- **`idempotency_key` (UUID)** envoyée à Tara comme `productId` → dédup côté provider.
- **Webhook atomique + idempotent** : `handle_webhook_event()` peut être rejoué sans double-créditer.
- **Matching à 3 stratégies** (UUID → `reference_externe` → téléphone+récence) : récupère les paiements même quand Tara ne renvoie pas notre `productId`.
- **Cron de réconciliation** : repêche les `EN_ATTENTE`, valide/rejette via `check_status`, timeout à 24h.
- **Hooks métier garantis idempotents** : un même `Payment` validé deux fois ne crédite qu'une fois.

C'est exactement ce qui évite les problèmes de « compensation »/double-comptage.
