import type { MetadataRoute } from "next";

import { lesAxes, lesOuvrages } from "@/lib/api";

const BASE = process.env.NEXT_PUBLIC_SITE_URL ?? "https://ascenda.app";

/**
 * Les pages du site, avec leur priorité relative. La bibliothèque change quand
 * le corpus change ; les pages légales, presque jamais.
 */
const PAGES: { chemin: string; frequence: MetadataRoute.Sitemap[number]["changeFrequency"]; priorite: number }[] = [
  { chemin: "/", frequence: "weekly", priorite: 1 },
  { chemin: "/bibliotheque", frequence: "weekly", priorite: 0.9 },
  { chemin: "/commencer", frequence: "monthly", priorite: 0.8 },
  { chemin: "/a-propos", frequence: "monthly", priorite: 0.6 },
  { chemin: "/droits", frequence: "yearly", priorite: 0.5 },
  { chemin: "/retrait", frequence: "yearly", priorite: 0.5 },
  { chemin: "/contact", frequence: "yearly", priorite: 0.4 },
  { chemin: "/mentions-legales", frequence: "yearly", priorite: 0.3 },
  { chemin: "/confidentialite", frequence: "yearly", priorite: 0.3 },
];

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const maintenant = new Date();
  const fixes = PAGES.map((p) => ({
    url: `${BASE}${p.chemin}`,
    lastModified: maintenant,
    changeFrequency: p.frequence,
    priority: p.priorite,
  }));

  // Chaque ouvrage et chaque axe est une porte d'entrée depuis un moteur de
  // recherche. Deux pages indexées ne captent personne ; quatre-vingt-dix en
  // captent, et chacune arrive sur ce que le lecteur cherchait vraiment.
  //
  // Si l'API ne répond pas à la construction, les listes reviennent vides et
  // le plan du site se réduit aux pages fixes. Un plan incomplet vaut mieux
  // qu'une construction en échec.
  // Cent est le maximum que l'API accepte par page, et le corpus tient dessous.
  // Le jour où il le dépassera, ce plan de site devra paginer : la limite est
  // rappelée ici pour qu'on s'en souvienne à ce moment là.
  const [axes, catalogue] = await Promise.all([
    lesAxes(),
    lesOuvrages({ par_page: "100" }),
  ]);

  return [
    ...fixes,
    ...axes.map((a) => ({
      url: `${BASE}/axe/${a.slug}`,
      lastModified: maintenant,
      changeFrequency: "monthly" as const,
      priority: 0.7,
    })),
    ...catalogue.ouvrages.map((o) => ({
      url: `${BASE}/ouvrage/${o.id}`,
      lastModified: maintenant,
      changeFrequency: "monthly" as const,
      priority: 0.6,
    })),
  ];
}
