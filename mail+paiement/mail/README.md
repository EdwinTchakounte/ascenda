# Module `mail` — e-mails transactionnels (app Django `notifications`)

E-mails transactionnels brandés via **Brevo HTTP API** (pas de SMTP), avec :

- templates stockés **en base** (`EmailTemplate`) → éditables sans redéploiement ;
- **kill-switch** par template (`actif=False` coupe l'envoi proprement) ;
- moteur d'**événements** (`EventConfig` + `EventHook`) : le code métier émet un
  événement, le moteur décide quels e-mails partent ;
- **logs d'envoi** (`EmailLog`) + audit ;
- **notifications in-app** (`Notification`) en miroir des e-mails ;
- **annonces broadcast** (`Announcement`) admin → membres ;
- layout HTML brandé réutilisable (`email_blocks.py` + `_wrap_layout`).

## Contenu de l'app (`notifications/`)

| Fichier | Rôle |
|--------|------|
| `models.py` | `EmailTemplate`, `EmailLog`, `Notification`, `EventConfig`, `EventHook`, `Announcement` |
| `services.py` | **`send_template(code, *, to, context, member, attachments)`** ← point d'entrée principal ; `create_notification()`, `broadcast_announcement()`, `_wrap_layout()` |
| `events.py` | **`emit_event(code, *, member, context, attachments, to_email)`** ← façade métier |
| `email_blocks.py` | Blocs HTML inline-CSS (`title`, `hi`, `lead`, `p`, `amount`, `info_card`, `cta`, `callout`, `code_block`, `closing`) |
| `admin.py` | Admin Django (templates, logs, notifications) |
| `serializers.py`, `views.py`, `admin_views.py`, `urls.py` | API DRF : feed notifications membre + CRUD annonces admin |
| `management/commands/seed_email_templates.py` | Seed idempotent des ~50 templates |
| `management/commands/seed_event_catalog.py` | Seed idempotent des événements + hooks (1 hook EMAIL par event) |
| `management/commands/send_email_pack.py` | Utilitaire : rend tous les templates et les envoie à une adresse pour relecture |
| `assets/logo.png` | Logo inline (Content-ID `gathe-logo`) — **remplace-le par le tien** |

## Dépendances Python

```
django-anymail[brevo]>=10.3   # traduit EmailMultiAlternatives → API Brevo
Django>=5.2                   # transaction.on_commit, EmailMultiAlternatives
```

(Optionnel : `reportlab` si tu attaches des PDF générés, comme l'attestation
welcome du projet source.)

## Variables d'environnement

```dotenv
# Backend e-mail : Brevo HTTP API en prod, console en dev
EMAIL_BACKEND=anymail.backends.brevo.EmailBackend
BREVO_API_KEY=xkeysib-...            # clé API transactionnelle Brevo
DEFAULT_FROM_EMAIL=Mon Projet <noreply@mondomaine.com>
CONTACT_NOTIFICATION_EMAIL=contact@mondomaine.com
```

En dev, laisse `EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend`
(les e-mails s'affichent dans les logs, rien n'est envoyé).

## Réglages `settings.py`

```python
INSTALLED_APPS = [
    # ...
    "anymail",
    "apps_coop.notifications",
]

EMAIL_BACKEND = env("EMAIL_BACKEND", default="django.core.mail.backends.console.EmailBackend")
ANYMAIL = {"BREVO_API_KEY": env("BREVO_API_KEY", default="")}
DEFAULT_FROM_EMAIL = env("DEFAULT_FROM_EMAIL", default="Mon Projet <noreply@mondomaine.com>")
CONTACT_NOTIFICATION_EMAIL = env("CONTACT_NOTIFICATION_EMAIL", default="contact@mondomaine.com")
# Optionnel : URL absolue d'un logo hébergé (sinon le PNG inline assets/logo.png est utilisé)
# EMAIL_LOGO_URL = env("EMAIL_LOGO_URL", default="")
```

URLs (dans ton `api_v1.py` / routeur racine) :

```python
path("notifications/", include("apps_coop.notifications.urls")),
```

## Dépendances inter-apps à fournir

| Import | Où | Contrat attendu |
|--------|-----|----------------|
| `apps_coop.common.TimestampedModel` | `models.py` | Fourni dans `_shared/common.py`. |
| `apps_coop.audit.services.record(...)` | `services.py`, `events.py`, `admin_views.py` | Écrit une ligne d'audit ; **ne doit jamais lever**. Stub possible (cf. README paiement). |
| `apps_coop.audit.services.client_ip(request)` | `admin_views.py` | Renvoie l'IP client. |
| `apps_coop.members.permissions.IsStaff` | `admin_views.py` | Permission DRF staff. |
| `apps_coop.members.models.Member` | `services.py` (import différé) | Sert à rattacher la notification in-app à un membre. Si tu n'as pas de `Member`, adapte `send_template` pour rattacher au `User`. |

> Le module mail est **faiblement couplé** : hormis `Member` (pour la
> notification in-app miroir) et l'audit, il ne dépend d'aucune logique métier.
> C'est le plus simple des deux à réutiliser.

## Mise en route

```bash
python manage.py migrate
python manage.py seed_email_templates      # crée les templates en base
python manage.py seed_event_catalog        # crée les events + hooks EMAIL
# relecture optionnelle de tous les rendus :
python manage.py send_email_pack --to toi@exemple.com
```

## Utilisation depuis le code métier

Façade recommandée — passe par le moteur d'événements :

```python
from apps_coop.notifications.events import emit_event

emit_event(
    "member.welcome",
    member=member,
    context={"prenom": member.prenom, "portal_url": "https://app.mondomaine.com"},
    to_email=member.user.email,
)
```

Envoi direct d'un template (sans passer par le catalogue d'events) :

```python
from apps_coop.notifications.services import send_template

send_template(
    "savings.deposit_confirmed",
    to=member.user.email,
    member=member,
    context={"montant": "10 000", "date": "29/06/2026"},
)
```

Déclenchement après commit DB (pattern du projet source pour le welcome) :

```python
from django.db import transaction
transaction.on_commit(lambda: send_template("member.welcome", to=email, member=member, context=ctx))
```

## Points d'adaptation pour ton nouveau projet

1. **Renomme les templates** : les ~50 codes (`member.welcome`, `loan.approved`…)
   sont propres au métier coopératif. Garde le moteur, réécris `seed_email_templates.py`
   et `seed_event_catalog.py` avec **tes** codes et **tes** contenus.
2. **Remplace `assets/logo.png`** et l'identité visuelle dans `services._wrap_layout()`
   (couleurs, footer, mentions « Akwa Bercy / Douala »).
3. **`Member`** : si ton modèle utilisateur diffère, ajuste l'import différé dans
   `services.py` (~ligne 318) et la FK de `Notification` si tu veux le miroir in-app.
4. Le **contexte** d'un template est rendu par `str.format(**context)` : chaque
   clé `{nom}` du HTML doit exister dans le `context`, sinon le rendu est protégé
   mais le placeholder reste brut.
