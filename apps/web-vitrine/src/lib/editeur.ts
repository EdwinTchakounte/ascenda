/**
 * Les informations de l'éditeur, rassemblées ici plutôt que dispersées dans les
 * pages légales.
 *
 * Certaines ne sont connues que de vous : forme juridique, numéro
 * d'immatriculation, adresse, hébergeur. Elles sont laissées à `null` et les
 * pages affichent alors, en clair, qu'elles restent à compléter. Une mention
 * légale inventée est pire qu'une mention légale absente : elle donne
 * l'apparence de la conformité tout en étant fausse, et c'est ce qu'un ayant
 * droit ou une autorité verra en premier.
 */
export const EDITEUR = {
  nom: "ASCENDA",
  responsable: "Tchamba Tchakounte Edwin",
  courriel: process.env.NEXT_PUBLIC_CONTACT_EMAIL ?? "contact@ascenda-books.online",
  pays: "Cameroun",

  /** À compléter avant la mise en ligne publique. */
  formeJuridique: process.env.NEXT_PUBLIC_FORME_JURIDIQUE ?? null,
  immatriculation: process.env.NEXT_PUBLIC_IMMATRICULATION ?? null,
  adresse: process.env.NEXT_PUBLIC_ADRESSE ?? null,
  telephone: process.env.NEXT_PUBLIC_TELEPHONE ?? null,
  hebergeur: process.env.NEXT_PUBLIC_HEBERGEUR ?? null,
} as const;

/** Où l'on envoie quelqu'un qui veut réellement utiliser ASCENDA. */
export const APPLICATION = {
  /** L'application web, si elle est déployée quelque part. */
  web: process.env.NEXT_PUBLIC_APP_URL ?? null,
  /** L'APK Android, si elle est publiée quelque part. */
  android: process.env.NEXT_PUBLIC_APK_URL ?? null,
} as const;

/** Les chiffres des droits, relevés en base le 29 août 2026. */
export const DROITS = {
  ouvrages: 78,
  integraux: 7,
  extraits: 71,
  plafondCourant: 1200,
  plafondMax: 3000,
} as const;
