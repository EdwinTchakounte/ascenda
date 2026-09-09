import { ImageResponse } from "next/og";

import { laFiche } from "@/lib/api";

export const alt = "Fiche d'ouvrage ASCENDA";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

/**
 * L'image de partage d'un ouvrage.
 *
 * Pendant une campagne, tous les liens partagés remontaient la même
 * illustration générique : trente publications, une seule vignette. Ici chaque
 * ouvrage porte la sienne, avec son titre et ses auteurs, ce qui rend le lien
 * reconnaissable avant même d'être ouvert.
 *
 * Aucune police n'est chargée depuis le réseau : la génération se ferait alors
 * en silence avec une police de repli si l'appel échouait, et le résultat
 * n'apparaîtrait qu'au partage, quand il est trop tard pour le voir.
 */
export default async function Image({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const f = await laFiche(id);
  const titre = f?.titre ?? "ASCENDA";
  const auteurs = f?.auteurs.join(", ") ?? "";
  const axe = f?.axes?.[0]?.label ?? "Lecture guidée";
  // Un titre très long doit rétrécir plutôt que déborder de la vignette.
  const taille = titre.length > 90 ? 46 : titre.length > 55 ? 56 : 68;

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
        <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <div
            style={{
              fontSize: 22,
              letterSpacing: 8,
              fontWeight: 700,
              color: "#e8c070",
            }}
          >
            ASCENDA
          </div>
          <div style={{ fontSize: 22, color: "#8590aa" }}>{axe}</div>
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 22 }}>
          <div
            style={{
              fontSize: taille,
              lineHeight: 1.12,
              fontWeight: 700,
              color: "#f7f4ec",
              display: "flex",
            }}
          >
            {titre.length > 130 ? titre.slice(0, 127) + "..." : titre}
          </div>
          {auteurs ? (
            <div style={{ fontSize: 30, color: "#e8c070", display: "flex" }}>
              {auteurs.length > 70 ? auteurs.slice(0, 67) + "..." : auteurs}
            </div>
          ) : null}
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: 22 }}>
          <div style={{ width: 120, height: 6, background: "#d4a23f" }} />
          <div style={{ fontSize: 22, color: "#8590aa" }}>
            {f?.droits.lecture_integrale ? "Lecture intégrale" : "Extraits cités avec leur page"}
          </div>
        </div>
      </div>
    ),
    size,
  );
}
