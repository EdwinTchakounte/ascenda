import type { Metadata, Viewport } from "next";
import { Fraunces, Inter } from "next/font/google";
import "./globals.css";

/* Fraunces dit « livre » sans être décorative ; Inter porte l'interface.
   Les deux sont chargées en latin étendu : le corpus est francophone. */
const titre = Fraunces({
  subsets: ["latin", "latin-ext"],
  weight: ["400", "500", "600", "700"],
  variable: "--police-titre",
  display: "swap",
});

const corps = Inter({
  subsets: ["latin", "latin-ext"],
  variable: "--police-corps",
  display: "swap",
});

/* Sans cette base, Next résout l'image de partage sur localhost:3000 et
   l'aperçu du lien reste vide partout où le site est partagé. La variable est
   lue à la construction : elle doit être posée avant `next build`. */
const base = process.env.NEXT_PUBLIC_SITE_URL ?? "https://ascenda-books.online";

export const metadata: Metadata = {
  metadataBase: new URL(base),
  title: "ASCENDA, lecture guidée",
  description:
    "Choisissez un axe, ASCENDA construit votre chronogramme de lecture : des séances datées tirées de 79 ouvrages, une synthèse, un quiz, et un agent qui cite toujours le livre et la page.",
  keywords: [
    "lecture guidée", "chronogramme de lecture", "intelligence artificielle",
    "Afrique", "apprentissage", "bibliothèque", "francophone",
  ],
  authors: [{ name: "Tchamba Tchakounte Edwin" }],
  openGraph: {
    title: "ASCENDA. Learn. Grow. Become.",
    description:
      "79 ouvrages, 17 299 pages, 17 parcours. Un plan de lecture qui tient compte du temps que vous avez vraiment.",
    locale: "fr_FR",
    type: "website",
    images: [
      {
        url: "/images/partage-1200x630.jpg",
        width: 1200,
        height: 630,
        alt: "ASCENDA, lecture guidée",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "ASCENDA. Learn. Grow. Become.",
    description: "79 ouvrages, 17 parcours, un plan de lecture qui tient dans votre semaine.",
    images: ["/images/partage-1200x630.jpg"],
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#faf8f4" },
    { media: "(prefers-color-scheme: dark)", color: "#050d22" },
  ],
};

export default function RacineLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr" className={`${titre.variable} ${corps.variable}`}>
      <body>{children}</body>
    </html>
  );
}
