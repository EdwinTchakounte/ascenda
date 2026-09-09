import Axes from "@/components/Axes";
import Entete from "@/components/Entete";
import HeroSlider from "@/components/HeroSlider";
import Methode from "@/components/Methode";
import Pied from "@/components/Pied";
import Preuve from "@/components/Preuve";
import Produit from "@/components/Produit";
import Tarifs from "@/components/Tarifs";

export default function Accueil() {
  return (
    <>
      <Entete />
      <main>
        <HeroSlider />
        <Axes />
        <Methode />
        <Produit />
        <Tarifs />
        <Preuve />
      </main>
      <Pied />
    </>
  );
}
