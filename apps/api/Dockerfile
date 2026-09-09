# API ASCENDA.
#
# Construction en deux temps : les dépendances dans une couche qui ne change
# presque jamais, le code dans une couche qui change à chaque commit. Sur une
# connexion lente, reconstruire l'image après une modification de code ne doit
# pas retélécharger deux cents mégaoctets de paquets.

FROM python:3.12-slim AS dependances
WORKDIR /app
# psycopg[binary] embarque son propre libpq : aucun paquet système à installer.
COPY apps/api/requirements.txt .
# Sur une connexion lente, pip abandonne au bout de quinze secondes sans un
# octet et la construction entière échoue. On lui laisse le temps et on rejoue
# le téléchargement au lieu de repartir de zéro.
RUN pip install --no-cache-dir --prefix=/depot \
      --timeout 120 --retries 10 -r requirements.txt

# La recherche sémantique est optionnelle, et son absence n'est pas une panne :
# l'API bascule en plein texte et l'annonce dans le champ `mode` de la réponse.
# L'activer ajoute deux gigaoctets de dépendances à l'image, et deux de plus au
# premier démarrage pour le modèle. Sur une connexion à trente kilo-octets par
# seconde, c'est une décision, pas un détail.
#
#   docker build --build-arg AVEC_RECHERCHE_SEMANTIQUE=true -f apps/api/Dockerfile .
ARG AVEC_RECHERCHE_SEMANTIQUE=false
COPY apps/api/requirements-recherche.txt .
RUN if [ "$AVEC_RECHERCHE_SEMANTIQUE" = "true" ]; then \
      pip install --no-cache-dir --prefix=/depot \
        --timeout 300 --retries 10 -r requirements-recherche.txt; \
    fi

FROM python:3.12-slim
LABEL org.opencontainers.image.title="ASCENDA API"
LABEL org.opencontainers.image.description="Lecture guidée : chronogramme, agent, paiement"

# L'application ne tourne pas en root : une faille dans une dépendance ne doit
# pas donner la main sur le conteneur.
RUN useradd --create-home --uid 10001 ascenda
WORKDIR /app

COPY --from=dependances /depot /usr/local
COPY apps/api/app ./app
COPY db/migrations ./db/migrations

USER ascenda
ENV PYTHONPATH=/app \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    API_PORT=8250

EXPOSE 8250

# La sonde interroge la base, pas seulement le processus : une API qui répond
# sans sa base n'est pas en bonne santé.
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request,json,sys; \
d=json.loads(urllib.request.urlopen('http://127.0.0.1:8250/sante',timeout=8).read()); \
sys.exit(0 if d.get('base')=='ok' else 1)"

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8250"]
