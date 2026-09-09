# Vitrine ASCENDA.
#
# Sortie « standalone » de Next : l'image finale ne contient que le serveur et
# les modules réellement utilisés, pas les cinq cents mégaoctets de node_modules
# de développement.

FROM node:22-alpine AS dependances
WORKDIR /app
COPY apps/web-vitrine/package*.json ./
# Trois cent soixante et onze paquets sur une connexion lente : npm abandonne
# au premier délai dépassé et la construction entière tombe. On lui laisse dix
# minutes par requête et dix reprises, comme pour pip côté API.
RUN npm config set fetch-retries 10 \
 && npm config set fetch-retry-maxtimeout 120000 \
 && npm config set fetch-timeout 600000 \
 && npm ci --no-audit --no-fund

FROM node:22-alpine AS constructeur
WORKDIR /app
COPY --from=dependances /app/node_modules ./node_modules
COPY apps/web-vitrine .
# L'adresse de l'API est figée à la construction : Next l'inline dans les pages
# rendues à l'avance. La changer demande une reconstruction, pas un redémarrage.
ARG NEXT_PUBLIC_API_URL=http://localhost:8250
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL
# Même chose pour l'adresse publique du site : elle résout l'image de partage.
# Laissée à sa valeur locale, l'aperçu du lien reste vide sur les réseaux.
ARG NEXT_PUBLIC_SITE_URL=http://localhost:3251
ENV NEXT_PUBLIC_SITE_URL=$NEXT_PUBLIC_SITE_URL
# Où mène « Commencer », et l'identité qui remplit les pages légales. Les pages
# concernées sont pré-rendues : ces valeurs sont donc figées ici, pas au
# démarrage. Ce qui reste vide s'affiche comme « à renseigner ».
ARG NEXT_PUBLIC_APP_URL=
ARG NEXT_PUBLIC_APK_URL=
ARG NEXT_PUBLIC_CONTACT_EMAIL=
ARG NEXT_PUBLIC_FORME_JURIDIQUE=
ARG NEXT_PUBLIC_IMMATRICULATION=
ARG NEXT_PUBLIC_ADRESSE=
ARG NEXT_PUBLIC_TELEPHONE=
ARG NEXT_PUBLIC_HEBERGEUR=
ENV NEXT_PUBLIC_APP_URL=$NEXT_PUBLIC_APP_URL \
    NEXT_PUBLIC_APK_URL=$NEXT_PUBLIC_APK_URL \
    NEXT_PUBLIC_CONTACT_EMAIL=$NEXT_PUBLIC_CONTACT_EMAIL \
    NEXT_PUBLIC_FORME_JURIDIQUE=$NEXT_PUBLIC_FORME_JURIDIQUE \
    NEXT_PUBLIC_IMMATRICULATION=$NEXT_PUBLIC_IMMATRICULATION \
    NEXT_PUBLIC_ADRESSE=$NEXT_PUBLIC_ADRESSE \
    NEXT_PUBLIC_TELEPHONE=$NEXT_PUBLIC_TELEPHONE \
    NEXT_PUBLIC_HEBERGEUR=$NEXT_PUBLIC_HEBERGEUR
RUN npm run build

FROM node:22-alpine
LABEL org.opencontainers.image.title="ASCENDA vitrine"
WORKDIR /app
RUN addgroup -g 10001 ascenda && adduser -u 10001 -G ascenda -D ascenda

COPY --from=constructeur /app/public ./public
COPY --from=constructeur --chown=ascenda:ascenda /app/.next/standalone ./
COPY --from=constructeur --chown=ascenda:ascenda /app/.next/static ./.next/static

USER ascenda
ENV NODE_ENV=production PORT=3251 HOSTNAME=0.0.0.0
EXPOSE 3251

HEALTHCHECK --interval=30s --timeout=8s --start-period=15s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3251/ > /dev/null || exit 1

CMD ["node", "server.js"]
