#!/usr/bin/env bash
# À lancer sur le serveur, avant de monter la pile.
#
# Chaque ligne vérifie une chose qui, si elle manque, fait échouer le
# déploiement plus loin et plus obscurément : Caddy qui ne démarre pas parce
# qu'un nom ne résout pas, l'API qui refuse de partir sur un JWT_SECRET par
# défaut, un port 80 déjà pris par un Apache oublié.
#
#   ./infra/scripts/preparatifs.sh
set -uo pipefail

RACINE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$RACINE"
NOMS=(ascenda-books.online www.ascenda-books.online api.ascenda-books.online)
souci=0

ok()   { printf "  \033[32m✓\033[0m %s\n" "$1"; }
non()  { printf "  \033[31m✗\033[0m %s\n" "$1"; souci=1; }
note() { printf "    %s\n" "$1"; }

echo
echo "· La machine"
command -v docker > /dev/null && ok "Docker : $(docker --version | cut -d' ' -f3 | tr -d ,)" || non "Docker absent"
docker compose version > /dev/null 2>&1 && ok "Compose : $(docker compose version --short)" || non "Docker Compose absent"

memoire=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')
if [ -n "$memoire" ]; then
  [ "$memoire" -ge 3500 ] && ok "Mémoire : ${memoire} Mo" || non "Mémoire : ${memoire} Mo, c'est juste"
  [ "$memoire" -lt 3500 ] && note "La construction de l'image de l'API demande environ 2 Go. En dessous de 4 Go, ajoutez du swap."
fi

libre=$(df -BG --output=avail "$RACINE" 2>/dev/null | tail -1 | tr -dc '0-9')
if [ -n "$libre" ]; then
  [ "$libre" -ge 15 ] && ok "Disque libre : ${libre} Go" || non "Disque libre : ${libre} Go"
  [ "$libre" -lt 15 ] && note "Images, volumes et sauvegardes demandent une quinzaine de gigaoctets."
fi

echo
echo "· Les noms"
mienne=$(curl -s --max-time 6 https://api.ipify.org 2>/dev/null || true)
[ -n "$mienne" ] && note "Adresse publique vue de l'extérieur : $mienne"
for n in "${NOMS[@]}"; do
  ip=$(getent hosts "$n" 2>/dev/null | head -1 | awk '{print $1}')
  if [ -z "$ip" ]; then
    non "$n ne résout pas encore"
  elif [ -n "$mienne" ] && [ "$ip" != "$mienne" ]; then
    non "$n résout vers $ip, pas vers cette machine"
  else
    ok "$n → $ip"
  fi
done
[ "$souci" -eq 1 ] && note "Caddy refuse de démarrer tant qu'un nom ne résout pas : attendez la propagation."

echo
echo "· Les ports"
for p in 80 443; do
  if ss -lntH "sport = :$p" 2>/dev/null | grep -q .; then
    non "Port $p déjà occupé"
    note "$(ss -lntpH "sport = :$p" 2>/dev/null | head -1)"
  else
    ok "Port $p libre"
  fi
done

echo
echo "· Le fichier d'environnement"
if [ ! -f .env ]; then
  non ".env absent"
  note "cp .env.example .env, puis posez les valeurs."
else
  ok ".env présent"
  # On lit sans exporter : ce fichier porte des mots de passe, il n'a rien à
  # faire dans l'environnement d'un script de vérification.
  valeur() { grep -E "^$1=" .env | head -1 | cut -d= -f2- ; }
  for v in POSTGRES_PASSWORD JWT_SECRET TARA_API_KEY TARA_BUSINESS_ID BREVO_API_KEY; do
    x=$(valeur "$v")
    if [ -z "$x" ]; then non "$v vide"; else ok "$v posée (${#x} caractères)"; fi
  done
  [ "$(valeur API_ENV)" = "prod" ] && ok "API_ENV=prod" || non "API_ENV n'est pas à prod"
  case "$(valeur JWT_SECRET)" in
    dev-secret-a-remplacer|"") non "JWT_SECRET est resté la valeur de développement" ;;
  esac
  case "$(valeur PAIEMENT_TEST_AUTO_VALIDE)" in
    true|True|1) non "PAIEMENT_TEST_AUTO_VALIDE est actif : la caisse valide sans encaisser" ;;
    *) ok "PAIEMENT_TEST_AUTO_VALIDE hors service" ;;
  esac
  for v in PUBLIC_BASE_URL SITE_BASE_URL API_CORS_ORIGINS; do
    x=$(valeur "$v")
    case "$x" in
      https://*) ok "$v = $x" ;;
      "") non "$v vide" ;;
      *) non "$v n'est pas en https : $x" ;;
    esac
  done
fi

echo
echo "· Le dépôt"
ok "commit $(git rev-parse --short HEAD 2>/dev/null || echo '?')"
[ -z "$(git status --porcelain 2>/dev/null)" ] && ok "aucune modification locale" || non "des fichiers sont modifiés sur le serveur"
[ -d data ] && ok "data/ présent ($(find data -name '*.json' | wc -l) fichiers)" || non "data/ absent : le corpus ne pourra pas être importé"

echo
if [ "$souci" -eq 0 ]; then
  echo "Tout est en place. Vous pouvez monter la pile."
else
  echo "Corrigez ce qui est marqué avant de monter la pile."
fi
exit "$souci"
