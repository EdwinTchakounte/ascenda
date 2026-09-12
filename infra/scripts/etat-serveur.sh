#!/usr/bin/env bash
# À lancer sur le serveur AVANT de déployer ASCENDA, quand la machine héberge
# déjà d'autres projets.
#
# Ce script ne modifie rien. Il répond aux quatre questions dont dépend toute la
# suite : quels ports sont libres, comment le nginx en place est configuré, où
# il range ses certificats, et si la machine a de quoi construire les images.
#
#   ./etat-serveur.sh
set -uo pipefail

NGINX="${NGINX:-backend-nginx-1}"

echo "════════ Ressources ════════"
free -h 2>/dev/null | head -2
echo
df -h / 2>/dev/null | head -2
echo
echo "charge : $(uptime | sed 's/.*load average/moyenne/')"
echo "conteneurs en marche : $(docker ps -q | wc -l)"

echo
echo "════════ Ports déjà pris sur la machine ════════"
ss -lntH 2>/dev/null | awk '{print $4}' | sed 's/.*://' | sort -n -u | tr '\n' ' '
echo
echo
echo "── les ports dont ASCENDA a besoin ──"
for p in 8260 3260 5450 9250 9251 6379; do
  if ss -lntH "sport = :$p" 2>/dev/null | grep -q .; then
    echo "  $p : PRIS → $(ss -lntpH "sport = :$p" 2>/dev/null | head -1 | sed 's/.*users://')"
  else
    echo "  $p : libre"
  fi
done

echo
echo "════════ Le nginx en place ════════"
if docker ps --format '{{.Names}}' | grep -qx "$NGINX"; then
  echo "conteneur : $NGINX"
  echo
  echo "── ses montages, c'est là qu'on ajoutera la configuration ──"
  docker inspect "$NGINX" --format '{{range .Mounts}}  {{.Source}} → {{.Destination}} ({{.Mode}}){{println}}{{end}}'
  echo "── où il cherche ses fichiers de site ──"
  docker exec "$NGINX" sh -c 'grep -rhE "include .*(conf\.d|sites)" /etc/nginx/nginx.conf 2>/dev/null; ls /etc/nginx/conf.d 2>/dev/null' | head -10
  echo
  echo "── les noms qu'il sert déjà ──"
  docker exec "$NGINX" sh -c 'grep -rhE "^\s*server_name" /etc/nginx/conf.d /etc/nginx/sites-enabled 2>/dev/null' | sort -u | head -20
  echo
  echo "── ses certificats ──"
  docker exec "$NGINX" sh -c 'ls /etc/letsencrypt/live 2>/dev/null || echo "pas de /etc/letsencrypt dans le conteneur"'
else
  echo "Aucun conteneur nommé $NGINX."
  echo "Relancez avec : NGINX=le-vrai-nom ./etat-serveur.sh"
  docker ps --format '  {{.Names}}  {{.Ports}}' | grep -E ":80->|:443->" || echo "  aucun conteneur ne tient 80 ou 443"
fi

echo
echo "════════ Certbot ════════"
command -v certbot > /dev/null && echo "certbot installé sur l'hôte : $(certbot --version 2>&1)" \
  || echo "pas de certbot sur l'hôte"
docker ps -a --format '{{.Names}} {{.Image}}' | grep -i certbot || echo "pas de conteneur certbot"
ls -d /etc/letsencrypt/live/* 2>/dev/null | sed 's|.*/|  certificat déjà émis : |' || echo "  /etc/letsencrypt absent de l'hôte"

echo
echo "════════ Ce que le DNS dit ════════"
for n in ascenda-books.online www.ascenda-books.online api.ascenda-books.online; do
  printf "  %-32s %s\n" "$n" "$(getent hosts "$n" 2>/dev/null | head -1 | awk '{print $1}' || echo 'ne résout pas')"
done
echo
echo "  cette machine se voit comme : $(curl -s --max-time 6 https://api.ipify.org 2>/dev/null || echo '?')"
