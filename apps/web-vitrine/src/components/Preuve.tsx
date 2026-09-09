import Bouton from "./Bouton";
import { CORPUS } from "@/lib/api";

const CHIFFRES = [
  { valeur: CORPUS.ouvrages.toString(), libelle: "ouvrages" },
  { valeur: CORPUS.pages.toLocaleString("fr-FR"), libelle: "pages indexées" },
  { valeur: CORPUS.axes.toString(), libelle: "parcours" },
];

export default function Preuve() {
  return (
    <section className="relative overflow-hidden bg-[var(--color-nuit-profond)] py-24">
      <div
        aria-hidden
        className="pointer-events-none absolute bottom-[-30%] left-1/2 h-[480px] w-[820px] -translate-x-1/2 rounded-full opacity-[0.14] blur-[110px]"
        style={{ background: "radial-gradient(circle, #d4a23f 0%, transparent 70%)" }}
      />

      <div className="cadre relative">
        <ul className="grid gap-10 sm:grid-cols-3">
          {CHIFFRES.map((c) => (
            <li key={c.libelle} className="text-center">
              <p className="font-[family-name:var(--font-titre)] text-[3.1rem] font-semibold leading-none text-[var(--color-or-clair)] tabular-nums">
                {c.valeur}
              </p>
              <p className="mt-2.5 text-[0.88rem] uppercase tracking-[0.14em] text-[#8590aa]">
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
            Commencez par une question : où en êtes-vous ?
          </h2>
          <p className="mx-auto mt-4 max-w-[54ch] text-[1.02rem] leading-[1.7] text-[#b9c1d6]">
            Dix minutes de diagnostic, et vous repartez avec un plan de lecture daté.
            Vous pouvez l&apos;abandonner, le refaire, le ralentir. Il s&apos;ajuste.
          </p>
          <div className="mt-8 flex flex-wrap justify-center gap-3.5">
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
