import Bouton from "./Bouton";
import { Voile } from "./Formes";
import { CORPUS } from "@/lib/api";

const CHIFFRES = [
  { valeur: CORPUS.ouvrages.toString(), libelle: "ouvrages" },
  { valeur: CORPUS.pages.toLocaleString("fr-FR"), libelle: "pages indexées" },
  { valeur: CORPUS.axes.toString(), libelle: "parcours" },
];

export default function Preuve() {
  return (
    <section className="relative overflow-hidden bg-[var(--color-nuit-profond)] py-24">
      <Voile teinte="#d4a23f" opacite={0.18} flou={110} className="bottom-[-30%] left-1/2 h-[480px] w-[820px] -translate-x-1/2" />
      <Voile teinte="#4a6fa5" opacite={0.26} className="left-[-12%] top-[-18%] h-[440px] w-[600px]" />
      <Voile teinte="#8a7f9e" opacite={0.2} className="right-[-10%] top-[10%] h-[400px] w-[520px]" />

      <div className="cadre relative">
        {/* Trois colonnes dès le téléphone : empilés, les trois chiffres
            occupaient quatre cent cinquante pixels pour trois mots. */}
        <ul className="grid grid-cols-3 gap-3 sm:gap-10">
          {CHIFFRES.map((c) => (
            <li key={c.libelle} className="text-center">
              <p className="font-[family-name:var(--font-titre)] text-[1.9rem] font-semibold leading-none sm:text-[3.1rem] text-[var(--color-or-clair)] tabular-nums">
                {c.valeur}
              </p>
              <p className="mt-2 text-[0.66rem] uppercase tracking-[0.1em] text-[#8590aa] sm:mt-2.5 sm:text-[0.88rem] sm:tracking-[0.14em]">
                {c.libelle}
              </p>
            </li>
          ))}
        </ul>

        <figure className="mx-auto mt-20 max-w-[62ch] text-center">
          <blockquote className="font-[family-name:var(--font-titre)] text-[1.44rem] leading-[1.55] text-[#f0ede4] sm:text-[1.6rem]">
            « Le plus grand ennemi du savoir n&apos;est pas l&apos;ignorance, mais l&apos;illusion du
            savoir. »
          </blockquote>
          <figcaption className="mt-5 text-[0.86rem] text-[#8590aa]">
            Stephen Hawking, cité dans <em>IA générative et mésinformation</em>,
            Académie des technologies, p. 32.
            <span className="mt-1.5 block text-[0.8rem] opacity-70">
              Une citation du corpus, avec sa page. Comme toutes celles que vous
              lirez ici.
            </span>
          </figcaption>
        </figure>

        <div className="mt-16 text-center">
          <h2 className="text-[2rem] font-semibold leading-tight text-[#f7f4ec] sm:text-[2.3rem]">
            Commencez par une question&nbsp;: où en êtes-vous&nbsp;?
          </h2>
          <p className="mx-auto mt-4 max-w-[54ch] text-[1.02rem] leading-[1.7] text-[#b9c1d6]">
            Dix minutes de diagnostic, et vous repartez avec un plan de lecture daté.
            Vous pouvez l&apos;abandonner, le refaire, le ralentir. Il s&apos;ajuste.
          </p>
          <div className="mx-auto mt-9 grid max-w-[420px] grid-cols-2 gap-2.5 sm:flex sm:max-w-none sm:justify-center sm:gap-3">
            <Bouton href="/commencer" taille="grand">Faire le diagnostic</Bouton>
            <Bouton href="/bibliotheque" variante="contour" taille="grand">
              Parcourir la bibliothèque
            </Bouton>
          </div>
        </div>
      </div>
    </section>
  );
}
