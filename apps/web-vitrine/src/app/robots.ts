import type { MetadataRoute } from "next";

const BASE = process.env.NEXT_PUBLIC_SITE_URL ?? "https://ascenda.app";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: {
      userAgent: "*",
      allow: "/",
      // Rien à cacher, mais rien à faire indexer non plus sur ces deux-là :
      // l'une renvoie vers l'application, l'autre n'est qu'un aiguillage.
      disallow: ["/connexion"],
    },
    sitemap: `${BASE}/sitemap.xml`,
  };
}
