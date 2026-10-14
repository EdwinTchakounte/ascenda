/**
 * Accès à l'API ASCENDA depuis la vitrine.
 *
 * La vitrine doit rester affichable même si l'API est arrêtée : c'est une page
 * publique, elle ne peut pas dépendre d'un service applicatif pour exister. Les
 * appels tombent donc sur des valeurs de repli issues du corpus réel, et la page
 * se rend malgré tout.
 */

export const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8250";

/**
 * L'adresse que le serveur de la vitrine utilise pour ses propres appels.
 *
 * En production, la vitrine et l'API sont sur le même réseau Docker. Passer par
 * l'adresse publique leur faisait faire le tour par Internet et par le nginx
 * de la machine : un aller-retour inutile, une dépendance au retour réseau vers
 * sa propre adresse, et surtout la limite de trente requêtes par seconde posée
 * pour les visiteurs, qui s'applique alors à la vitrine entière quand elle
 * régénère ses pages. La bibliothèque en ligne affichait zéro ouvrage alors que
 * l'API en servait soixante-dix-huit.
 *
 * Lue à l'exécution et non figée à la construction : elle n'a pas de préfixe
 * NEXT_PUBLIC_, elle ne quitte jamais le serveur.
 */
const API_SERVEUR = process.env.API_INTERNE || API_BASE;

export type Axe = {
  id?: string;
  slug: string;
  label: string;
  description: string | null;
  premium: boolean;
  nb_ouvrages: number;
  nb_pages: number;
  duree_estimee_min: number;
};

export type Ouvrage = {
  id: string;
  titre: string;
  auteurs: string[];
  annee: number | null;
  pages: number | null;
  niveau: string | null;
  type: string | null;
  duree_min: number | null;
  these: string | null;
  axes: { slug: string; label: string }[];
  lecture_integrale: boolean;
};

/** Chiffres du corpus, relevés en base le 14 octobre 2026. Repli seulement. */
export const CORPUS = { ouvrages: 79, pages: 17299, axes: 17, integrale: 7, plafonnes: 72 };

/**
 * Les chiffres du corpus, lus dans l'API plutôt que recopiés.
 *
 * Ils étaient figés dans le code et avaient pris un ouvrage et six axes de
 * retard : la vitrine annonçait soixante-dix-huit ouvrages quand l'application
 * en servait soixante-dix-neuf. Lus ici, ils ne peuvent plus diverger.
 */
export async function leCorpus() {
  const [biblio, axes] = await Promise.all([
    recuperer<{ total: number; ouvrages: Ouvrage[] }>("/bibliotheque?par_page=100", {
      total: 0,
      ouvrages: [],
    }),
    recuperer<Axe[]>("/axes", []),
  ]);
  if (!biblio.total || !axes.length) return CORPUS;
  const pages = biblio.ouvrages.reduce((n, o) => n + (o.pages ?? 0), 0);
  const integrale = biblio.ouvrages.filter((o) => o.lecture_integrale).length;
  return {
    ouvrages: biblio.total,
    pages: pages || CORPUS.pages,
    axes: axes.length,
    integrale,
    plafonnes: biblio.total - integrale,
  };
}

/** Repli : les dix-sept axes avec leurs volumes réels. */
const AXES_REPLI: Axe[] = [
  { slug: "01-ia-fondamentaux-vulgarisation", label: "Fondamentaux de l'IA", description: null, premium: false, nb_ouvrages: 11, nb_pages: 1719, duree_estimee_min: 3577 },
  { slug: "02-ia-technique-academique", label: "IA technique et académique", description: null, premium: false, nb_ouvrages: 7, nb_pages: 2276, duree_estimee_min: 6938 },
  { slug: "03-ia-outils-pratique-prompting", label: "Outils, pratique et prompting", description: null, premium: false, nb_ouvrages: 8, nb_pages: 1351, duree_estimee_min: 2278 },
  { slug: "04-ia-societe-ethique-philosophie", label: "IA, société et éthique", description: null, premium: false, nb_ouvrages: 17, nb_pages: 4015, duree_estimee_min: 10343 },
  { slug: "05-ia-education-pedagogie", label: "IA, éducation et pédagogie", description: null, premium: false, nb_ouvrages: 3, nb_pages: 155, duree_estimee_min: 231 },
  { slug: "06-ia-travail-management-metiers", label: "IA, travail et métiers", description: null, premium: false, nb_ouvrages: 5, nb_pages: 838, duree_estimee_min: 1494 },
  { slug: "07-afrique-histoire-pensee", label: "Afrique, histoire et pensée", description: null, premium: false, nb_ouvrages: 10, nb_pages: 1497, duree_estimee_min: 3342 },
  { slug: "08-litterature-romans", label: "Littérature et romans", description: null, premium: false, nb_ouvrages: 8, nb_pages: 1390, duree_estimee_min: 2860 },
  { slug: "09-developpement-personnel-influence", label: "Développement personnel et influence", description: null, premium: false, nb_ouvrages: 7, nb_pages: 1877, duree_estimee_min: 3766 },
  { slug: "10-economie-entrepreneuriat-finance", label: "Économie, entrepreneuriat et finance", description: null, premium: false, nb_ouvrages: 2, nb_pages: 295, duree_estimee_min: 624 },
  { slug: "11-sciences-environnement", label: "Sciences et environnement", description: null, premium: false, nb_ouvrages: 1, nb_pages: 342, duree_estimee_min: 1568 },
  { slug: "12-1-developpement-rural", label: "Développement rural et filières", description: null, premium: false, nb_ouvrages: 1, nb_pages: 299, duree_estimee_min: 978 },
  { slug: "12-2-agronomie-exploitation", label: "Agronomie et exploitation", description: null, premium: false, nb_ouvrages: 1, nb_pages: 405, duree_estimee_min: 1312 },
  { slug: "12-3-protection-cultures", label: "Protection des cultures", description: null, premium: false, nb_ouvrages: 1, nb_pages: 57, duree_estimee_min: 211 },
  { slug: "12-4-cultures-plantes", label: "Cultures et plantes utiles", description: null, premium: false, nb_ouvrages: 1, nb_pages: 446, duree_estimee_min: 1397 },
  { slug: "12-5-elevage-sante-animale", label: "Élevage et santé animale", description: null, premium: false, nb_ouvrages: 1, nb_pages: 326, duree_estimee_min: 1008 },
  { slug: "12-6-pisciculture-petits-elevages", label: "Pisciculture et petits élevages", description: null, premium: false, nb_ouvrages: 1, nb_pages: 76, duree_estimee_min: 253 },
];

async function recuperer<T>(chemin: string, repli: T, revalider = 3600): Promise<T> {
  try {
    const r = await fetch(`${API_SERVEUR}/v1${chemin}`, { next: { revalidate: revalider } });
    if (!r.ok) return repli;
    return (await r.json()) as T;
  } catch {
    return repli;
  }
}

export async function lesAxes(): Promise<Axe[]> {
  const axes = await recuperer<Axe[]>("/axes", AXES_REPLI);
  return axes.length ? axes : AXES_REPLI;
}

export async function lesOuvrages(params: Record<string, string> = {}) {
  const q = new URLSearchParams({ par_page: "60", ...params }).toString();
  return recuperer<{ total: number; ouvrages: Ouvrage[] }>(
    `/bibliotheque?${q}`,
    { total: 0, ouvrages: [] },
  );
}

export type Fiche = {
  id: string;
  titre: string;
  sous_titre: string | null;
  auteurs: string[];
  annee: number | null;
  editeur: string | null;
  isbn: string | null;
  pages: number | null;
  langue: string | null;
  axes: { slug: string; label: string }[];
  pedagogie: {
    niveau: string | null;
    type: string | null;
    public: string | null;
    duree_min: number | null;
    these_centrale: string | null;
    idees_force: unknown[];
  };
  droits: { lecture_integrale: boolean; plafond_extrait: number | null; message: string };
  contenu: { chapitres: number; lots_quiz: number; questions: number; citations: number };
};

/**
 * Une fiche d'ouvrage. Retourne null si l'API ne la connaît pas ou ne répond
 * pas : la page appelle alors notFound(), plutôt que d'afficher un gabarit
 * vide qui serait indexé tel quel.
 */
export async function laFiche(id: string): Promise<Fiche | null> {
  try {
    const r = await fetch(`${API_SERVEUR}/v1/bibliotheque/${id}`, { next: { revalidate: 3600 } });
    if (!r.ok) return null;
    return (await r.json()) as Fiche;
  } catch {
    return null;
  }
}

export type FicheAxe = {
  slug: string;
  label: string;
  description: string | null;
  ouvrages: Ouvrage[];
};

export async function laFicheAxe(slug: string): Promise<FicheAxe | null> {
  try {
    const r = await fetch(`${API_SERVEUR}/v1/axes/${slug}`, { next: { revalidate: 3600 } });
    if (!r.ok) return null;
    return (await r.json()) as FicheAxe;
  } catch {
    return null;
  }
}

/** Du plus accessible au plus exigeant : l'ordre que suit le chronogramme. */
export function parNiveau(ouvrages: Ouvrage[]): Ouvrage[] {
  const rang: Record<string, number> = { debutant: 0, intermediaire: 1, avance: 2 };
  return [...ouvrages].sort((a, b) => {
    const ra = rang[a.niveau ?? ""] ?? 1;
    const rb = rang[b.niveau ?? ""] ?? 1;
    return ra !== rb ? ra - rb : (a.pages ?? 0) - (b.pages ?? 0);
  });
}

export const NIVEAUX: Record<string, string> = {
  debutant: "Débutant",
  intermediaire: "Intermédiaire",
  avance: "Avancé",
};

export function heures(minutes: number): string {
  const h = Math.round(minutes / 60);
  if (h < 1) return `${minutes} min`;
  return `${h} h`;
}

export type Moyen = { code: string; libelle: string; operateur: string };
export type Formule = {
  periode_mois: number;
  montant: number;
  devise: string;
  libelle: string;
  par_mois: number;
};

/** Repli : la grille réellement posée en base au 29 août 2026. */
const TARIFS_REPLI = {
  moyens: [
    { code: "mtn", libelle: "MTN Mobile Money", operateur: "MTN Cameroun" },
    { code: "orange", libelle: "Orange Money", operateur: "Orange Cameroun" },
  ] as Moyen[],
  formules: [
    { periode_mois: 1, montant: 3000, devise: "XAF", libelle: "Ascension, un mois", par_mois: 3000 },
    { periode_mois: 3, montant: 8000, devise: "XAF", libelle: "Ascension, trois mois", par_mois: 2667 },
    { periode_mois: 12, montant: 28000, devise: "XAF", libelle: "Ascension, un an", par_mois: 2333 },
  ] as Formule[],
};

/** La grille tarifaire, lue en base : la page ne peut pas mentir sur le prix. */
export async function lesTarifs() {
  return recuperer<{ moyens: Moyen[]; formules: Formule[] }>("/paiements/tarifs", TARIFS_REPLI);
}

export function montant(n: number, devise = "XAF"): string {
  return `${n.toLocaleString("fr-FR")} ${devise}`;
}
