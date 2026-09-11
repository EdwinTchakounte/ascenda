import Apparition from "@/components/Apparition";
import Axes from "@/components/Axes";
import Entete from "@/components/Entete";
import Etagere3D, { type Dos } from "@/components/Etagere3D";
import HeroSlider from "@/components/HeroSlider";
import Methode from "@/components/Methode";
import Pied from "@/components/Pied";
import Preuve from "@/components/Preuve";
import Produit from "@/components/Produit";
import Tarifs from "@/components/Tarifs";
import { lesOuvrages } from "@/lib/api";

/**
 * Douze volumes pour l'étagère, pris dans douze pôles différents quand c'est
 * possible. Une étagère où six dos sur douze portent la même couleur ne dit
 * rien de l'étendue de la bibliothèque.
 */
async function pourLEtagere(): Promise<Dos[]> {
  const { ouvrages } = await lesOuvrages({ par_page: "60" });
  const vus = new Set<string>();
  const choisis: Dos[] = [];
  for (const tour of [1, 2, 3]) {
    for (const o of ouvrages) {
      if (choisis.length >= 12 || choisis.some((c) => c.id === o.id)) continue;
      const axe = o.axes[0];
      if (!axe) continue;
      if (tour === 1 && vus.has(axe.slug)) continue;
      vus.add(axe.slug);
      choisis.push({
        id: o.id,
        titre: o.titre,
        auteur: o.auteurs[0] ?? "Auteur inconnu",
        axe: axe.label,
        slug: axe.slug,
      });
    }
  }
  return choisis;
}

export default async function Accueil() {
  const etagere = await pourLEtagere();

  return (
    <>
      <Entete />
      <main>
        <HeroSlider />
        <Axes />
        <Etagere3D ouvrages={etagere} />
        <Apparition>
          <Methode />
        </Apparition>
        <Apparition>
          <Produit />
        </Apparition>
        <Apparition>
          <Tarifs />
        </Apparition>
        <Apparition>
          <Preuve />
        </Apparition>
      </main>
      <Pied />
    </>
  );
}
