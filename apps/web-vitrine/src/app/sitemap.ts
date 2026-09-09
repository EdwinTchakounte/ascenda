import type { MetadataRoute } from "next";

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

export default function sitemap(): MetadataRoute.Sitemap {
  const maintenant = new Date();
  return PAGES.map((p) => ({
    url: `${BASE}${p.chemin}`,
    lastModified: maintenant,
    changeFrequency: p.frequence,
    priority: p.priorite,
  }));
}
