import { ImageResponse } from "next/og";

import { laFicheAxe } from "@/lib/api";

export const alt = "Axe de lecture ASCENDA";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

/** L'image de partage d'un axe : son nom, et ce qu'il contient réellement. */
export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const a = await laFicheAxe(slug);
  const label = a?.label ?? "Axe de lecture";
  const nb = a?.ouvrages.length ?? 0;
  // `toLocaleString("fr-FR")` sépare les milliers par une espace fine
  // insécable, dont la police de repli du générateur d'images n'a pas le
  // glyphe : « 1 497 » s'affichait « 1▯497 ». On sépare donc à la main, par une
  // espace ordinaire, que toute police connaît.
  const pages = (a?.ouvrages ?? [])
    .reduce((s, o) => s + (o.pages ?? 0), 0)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, " ");

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          background: "#0b1435",
          padding: "64px 72px",
          fontFamily: "sans-serif",
        }}
      >
        <div style={{ fontSize: 22, letterSpacing: 8, fontWeight: 700, color: "#e8c070" }}>
          ASCENDA
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
          <div style={{ fontSize: 26, color: "#8590aa", display: "flex" }}>Axe de lecture</div>
          <div
            style={{
              fontSize: label.length > 34 ? 60 : 74,
              lineHeight: 1.1,
              fontWeight: 700,
              color: "#f7f4ec",
              display: "flex",
            }}
          >
            {label}
          </div>
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 26 }}>
          <div style={{ width: 120, height: 6, background: "#d4a23f" }} />
          <div style={{ fontSize: 26, color: "#b9c1d6", display: "flex" }}>
            {nb} ouvrages, {pages} pages, dans l&apos;ordre où les lire
          </div>
        </div>
      </div>
    ),
    size,
  );
}
