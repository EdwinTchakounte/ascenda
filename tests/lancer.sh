#!/usr/bin/env bash
# Lance toutes les suites de vérification. L'API doit tourner.
#
#   ./tests/lancer.sh
#   ASCENDA_API=https://api.exemple.com ./tests/lancer.sh
set -u
cd "$(dirname "$0")/.."
PYTHON="${PYTHON:-.venv/bin/python}"
API="${ASCENDA_API:-http://127.0.0.1:8250}"

if ! curl -sf --max-time 10 "$API/sante" > /dev/null; then
  echo "L'API ne répond pas sur $API."
  echo "  cd apps/api && PYTHONPATH=. ../../.venv/bin/python -m uvicorn app.main:app --port 8250"
  exit 1
fi

echec=0

# La base d'abord : si le schéma ne se reconstruit pas, aucun déploiement neuf
# ne tiendra, et le reste des suites ne dirait rien de ce défaut là.
echo "################  reconstruction de la base  ################"
./db/verifier.sh || echec=1

# Le contrat ensuite : inutile de dérouler cinq suites si une application
# appelle une route qui n'existe plus.
echo
echo "################  contrat d'API  ################"
"$PYTHON" packages/shared/verifier_contrat.py --vif || echec=1

for suite in test_api test_parcours test_revision test_axes test_paiement test_tara test_courriel test_mot_de_passe test_enrichissement test_exploitation test_admin test_import test_codes test_cercle test_pdf test_qualite test_resilience; do
  echo
  echo "################  $suite  ################"
  ASCENDA_API="$API" "$PYTHON" "tests/$suite.py" || echec=1
done

# L'application, si Flutter est installé. Ses vérifications ne touchent ni à la
# base ni à l'API : elles montent des écrans et mesurent. Sur une machine sans
# Flutter, on le dit et on continue plutôt que d'échouer.
echo
echo "################  application mobile  ################"
if command -v flutter > /dev/null 2>&1; then
  (cd apps/mobile && flutter test) || echec=1
else
  echo "Flutter absent : suites de l'application non exécutées."
fi

echo
if [ "$echec" -eq 0 ]; then
  echo "Toutes les suites passent."
else
  echo "Au moins une suite a échoué."
fi
exit $echec
