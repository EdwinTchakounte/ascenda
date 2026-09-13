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
  // Une file par parcours, puis un volume de chaque file à tour de rôle : deux
  // livres voisins sur l'étagère ne viennent jamais du même parcours tant qu'il
  // en reste d'autres. Les ouvrages dont l'auteur est connu passent devant.
  const files = new Map<string, Dos[]>();
  const tries = [...ouvrages].sort((a, b) => Number(b.auteurs.length > 0) - Number(a.auteurs.length > 0));
  for (const o of tries) {
    const axe = o.axes[0];
    if (!axe) continue;
    const file = files.get(axe.slug) ?? [];
    file.push({ id: o.id, titre: o.titre, auteur: o.auteurs[0] ?? "", axe: axe.label, slug: axe.slug });
    files.set(axe.slug, file);
  }
  const choisis: Dos[] = [];
  while (choisis.length < 12 && [...files.values()].some((f) => f.length > 0)) {
    for (const file of files.values()) {
      const o = file.shift();
      if (o && choisis.length < 12) choisis.push(o);
    }
  }
  // L'étagère tourne en boucle : le dernier volume est voisin du premier.
  const n = choisis.length;
  if (n > 2 && choisis[n - 1].slug === choisis[0].slug) {
    const reste = [...files.values()].flat();
    const autre = reste.find((o) => o.slug !== choisis[0].slug && o.slug !== choisis[1].slug && o.slug !== choisis[n - 2].slug);
    if (autre) choisis[n - 1] = autre;
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
