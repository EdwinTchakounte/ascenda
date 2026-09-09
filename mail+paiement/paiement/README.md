# Module `paiement` — mobile money Tara (app Django `payments`)

Encaissements (payin) et décaissements (payout) **mobile money via Tara**, avec
la mécanique de **suivi / réconciliation** durcie en production. C'est cette
brique qui élimine les problèmes de « compensation » / double-comptage.

## Garanties anti-compensation (le cœur du module)

| Garantie | Implémentation |
|----------|---------------|
| **Dédup côté provider** | `Payment.idempotency_key` (UUID) envoyée à Tara comme `productId`. |
| **Webhook atomique + idempotent** | `services.handle_webhook_event()` : transaction atomique, rejouable sans double-créditer. |
| **Matching à 3 stratégies** | 1) UUID `idempotency_key` → 2) `reference_externe` → 3) téléphone normalisé + `EN_ATTENTE` récent (< 30 min). Récupère les paiements même quand Tara ne renvoie pas notre `productId`. |
| **Réconciliation par cron** | `tasks.reconcile_pending_payments()` repêche les `EN_ATTENTE`, interroge `check_status`, valide/rejette, **timeout 24h**. |
| **Hooks métier idempotents** | chaque `_hook_*` se garde via `payment.statut` + timestamps : un `Payment` validé 2× ne produit l'effet qu'une fois. |
| **Webhook tolérant** | renvoie toujours 200 (même si le hook échoue) pour éviter les retries Tara en boucle ; l'erreur est auditée. |
| **Récupération manuelle** | `manage.py reconcile_payments --payment-id N --force-valide` quand le MoMo a débité mais que Tara n'a jamais notifié. |

> ⚠️ `PAYMENTS_TEST_AUTO_VALIDATE` et `PAYMENTS_TEST_ALLOW_ANY_AMOUNT` ne doivent
> **JAMAIS** être à `True` en prod (ils valident les paiements sans Tara / sans
> contrôle de montant). Garde-les à `False` par défaut.

## Contenu de l'app (`payments/`)

| Fichier | Rôle |
|--------|------|
| `models.py` | `Payment` (entité centrale, statut/idempotency/reference_externe), `FeeType` (frais éditables), `RateParam` (taux), `PaymentProof` |
| `providers/base.py` | Interface abstraite `PaymentProviderBase` (`init_payin`, `check_status`, `init_payout`, `verify_webhook`) + `InitPayinResult`, `PayoutResult`, `WebhookEvent`, `ProviderError` |
| `providers/tara.py` | **`TaraProvider`** : appels HTTP Tara (`/api/tara/mobilepay`, `/transactions/status`, `/paypout/create`), mapping de statuts, normalisation téléphone CM, mode mock si pas de creds |
| `services.py` | `init_payin_for_payment()`, **`handle_webhook_event()`**, `notify_payment_initiated()`, et les **business hooks** (effets de bord par type de paiement) |
| `views.py` | Endpoints DRF : init, détail, historique, **webhook Tara**, cash-in admin, config frais/taux |
| `urls.py` | Routes (montées sous `/api/v1/payments/`) |
| `tasks.py` | `reconcile_pending_payments_scheduled()` (cron) + `alert_stuck_payments()` |
| `rates.py`, `serializers.py`, `admin.py` | Helpers taux, serializers DRF, admin Django |
| `management/commands/` | `reconcile_payments` (réconciliation manuelle), `seed_fees`, `seed_rates` |

## Dépendances Python

```
Django>=5.2
djangorestframework>=3.15
requests>=2.32        # client HTTP des appels Tara
django-q2>=1.7        # ordonnanceur du cron de réconciliation
croniter>=2.0         # expressions cron
psycopg[binary]>=3.2  # PostgreSQL (transactions atomiques)
```

## Variables d'environnement

```dotenv
TARA_API_KEY=...                 # clé API Tara (sandbox/prod)
TARA_BUSINESS_ID=...             # identifiant marchand Tara
TARA_WEBHOOK_SECRET=             # actuellement inutilisé (Tara ne signe pas ses webhooks)
PUBLIC_BASE_URL=https://api.mondomaine.com   # sert à construire l'URL de webhook
# Modes test — À LAISSER FALSE EN PROD :
PAYMENTS_TEST_AUTO_VALIDATE=false
PAYMENTS_TEST_ALLOW_ANY_AMOUNT=false
```

Le webhook envoyé à Tara est construit comme :
`{PUBLIC_BASE_URL}/api/v1/payments/webhook/tara/`

> Sans `TARA_API_KEY`/`TARA_BUSINESS_ID`, `TaraProvider` passe en **mode mock**
> (référence factice) — pratique en dev, jamais en prod.

## Réglages `settings.py`

```python
INSTALLED_APPS = [
    # ...
    "rest_framework",
    "apps_coop.payments",
]

TARA_API_KEY = env("TARA_API_KEY", default="")
TARA_BUSINESS_ID = env("TARA_BUSINESS_ID", default="")
TARA_WEBHOOK_SECRET = env("TARA_WEBHOOK_SECRET", default="")
PUBLIC_BASE_URL = env("PUBLIC_BASE_URL", default="http://localhost:8000")
PAYMENTS_TEST_AUTO_VALIDATE = env.bool("PAYMENTS_TEST_AUTO_VALIDATE", default=False)
PAYMENTS_TEST_ALLOW_ANY_AMOUNT = env.bool("PAYMENTS_TEST_ALLOW_ANY_AMOUNT", default=False)
```

URLs :

```python
path("payments/", include("apps_coop.payments.urls")),
```

Cron (django-q2) — planifie la réconciliation :

```python
# via un Schedule django-q2 ou ton ordonnanceur :
#   apps_coop.payments.tasks.reconcile_pending_payments_scheduled  → toutes les 5–15 min
#   apps_coop.payments.tasks.alert_stuck_payments                  → toutes les heures
```

## Dépendances inter-apps à fournir

| Import | Où | Contrat attendu |
|--------|-----|----------------|
| `apps_coop.common` (`TimestampedModel`, `ZERO`, `money_field`, `parse_pagination`) | models, views | Fourni dans `_shared/common.py`. |
| `apps_coop.members.models.Member` | `models.py` (FK `Payment.member`) | Ton modèle métier utilisateur. Adapte la FK. |
| `apps_coop.members.permissions` (`IsMember`, `IsStaff`, `IsAdmin`) | `views.py` | Permissions DRF. |
| `apps_coop.audit.services` (`record`, `client_ip`, `get_int_setting`, `get_str_setting`) | services, views, tasks | Audit + AppSettings tunables. Stub minimal possible ⤵ |

Stub minimal d'audit si tu n'as pas d'app dédiée (à mettre dans
`apps_coop/audit/services.py`) :

```python
def record(*, action, entite_type="", entite_id=None, user=None, details=None, ip=None, user_agent=""):
    return None  # no-op : l'audit ne doit jamais casser un flux

def client_ip(request):
    xff = request.META.get("HTTP_X_FORWARDED_FOR", "")
    return xff.split(",")[0].strip() if xff else request.META.get("REMOTE_ADDR")

def get_int_setting(key, default): return default   # remplace par une vraie lecture si tu veux des tunables
def get_str_setting(key, default): return default
```

## Business hooks — **principal point d'adaptation**

`services.py` mappe chaque **type de paiement** vers un effet de bord métier :

```python
_BUSINESS_HOOKS = {
    Payment.Type.FRAIS_ADHESION:       _hook_adhesion,            # activer le membre
    Payment.Type.EPARGNE:              _hook_savings_deposit,     # créditer l'épargne
    Payment.Type.EPARGNE_CLASSIQUE:    _hook_classic_savings_deposit,
    Payment.Type.FRAIS_DEMANDE_CREDIT: _hook_loan_request_fees,
    Payment.Type.REMBOURSEMENT:        _hook_loan_repayment,      # imputation FIFO
    Payment.Type.FRAIS_CARNET:         _hook_carnet_fees,
    Payment.Type.DECAISSEMENT:         _hook_decaissement,        # activer le prêt + payout
}
```

Ces hooks importent (en **import différé**, pour éviter les cycles) des modèles
métier propres à la coopérative :

- `apps_coop.savings.models` (SavingsAccount, SavingsTransaction, …)
- `apps_coop.loans.models` (Loan, LoanInstallment, LoanRepayment, LoanRequest)
- `apps_coop.loans.lender_payouts`
- `apps_coop.members.models` (Member, BookletOrder)

**Dans ton nouveau projet :**

1. Garde **toute la mécanique générique** : `Payment`, `TaraProvider`, le webhook,
   la réconciliation, l'`idempotency_key`, le matching 3 stratégies. C'est ça qui
   t'évite les bugs de compensation et c'est **indépendant du métier**.
2. **Réécris uniquement les `_hook_*`** et le dict `_BUSINESS_HOOKS` avec **tes**
   types de paiement et **tes** effets de bord. Respecte les 2 invariants :
   - un hook doit être **idempotent** (rejouable sans doublon) ;
   - un hook ne doit **jamais lever** (loggue/audite et sort proprement).
3. Réduis l'enum `Payment.Type` aux types dont tu as besoin (puis régénère une
   migration). Supprime les hooks et imports métier que tu n'utilises pas.

## Flux complet (rappel)

1. **Init** (membre → API) : `POST /payments/init/` crée un `Payment` `EN_ATTENTE`.
2. **Provider** (API → Tara) : `init_payin()` → `POST /api/tara/mobilepay` (`productId` = UUID).
3. **Action MoMo** (membre saisit son PIN).
4. **Webhook** (Tara → API) : `POST /payments/webhook/tara/` → `handle_webhook_event()` (atomique, idempotent).
5. **Matching** : UUID → `reference_externe` → téléphone+récence.
6. **Confirmation** : passage à `VALIDE` + exécution du hook métier.
7. **Filet cron** : `reconcile_pending_payments()` repêche les `EN_ATTENTE` > N min via `check_status`.
8. **Timeout** : après 24h, rejet auto.
9. **Récupération manuelle** : `manage.py reconcile_payments --payment-id N --force-valide`.

## Mise en route

```bash
python manage.py migrate
python manage.py seed_fees      # types de frais éditables
python manage.py seed_rates     # taux configurables
# planifie le cron reconcile_pending_payments_scheduled via django-q2
```

## Tests

Le module embarque une suite **autonome** (`tests/`) qui valide la brique Tara
pure — celle qui protège des problèmes de compensation — **sans DB ni projet
complet**. Elle couvre : normalisation téléphone, mapping de statut, parsing +
sécurité du webhook (matching `productId`/`collectionId`, garde `businessId`,
payloads cassés), et le mode mock.

```bash
cd paiement/
pip install pytest django requests
pytest            # 30 tests, < 1 s, aucune base requise
```

> Ces tests prouvent que le cœur réutilisable fonctionne en isolation. La
> logique métier branchée sur les `_hook_*` (épargne/crédit) se teste, elle,
> dans ton projet avec ses propres modèles — exactement comme la suite
> d'origine (`test_disburse_tara`, `test_late_payment_cron`,
> `test_multi_jours_prepaye`, `test_payments_auto_validate`, `test_payments_me`)
> qui validait l'intégration complète **41/41 verts**.

## Sécurité webhook (important)

Tara **ne signe pas** ses webhooks (pas de HMAC, pas de header de signature).
La sécurité repose sur : HTTPS + URL de webhook secrète + vérification du
`businessId`. Ne déduis pas un statut « payé » d'un appel non vérifié côté
métier : c'est `handle_webhook_event()` (atomique + matching) qui fait foi, et
le cron de réconciliation qui confirme via `check_status` (source de vérité Tara).
