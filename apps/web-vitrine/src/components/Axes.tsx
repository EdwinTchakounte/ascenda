import Link from "next/link";
import Apparition from "./Apparition";
import IconeAxe from "./IconesAxes";
import Relief from "./Relief";
import { heures, lesAxes } from "@/lib/api";

export default async function Axes() {
  const axes = await lesAxes();

  return (
    <section id="axes" className="bg-[var(--fond)] py-24">
      <div className="cadre">
        <div className="mx-auto max-w-[62ch] text-center">
          <p className="oeil">Onze parcours</p>
          <h2 className="mt-3 text-[2.1rem] font-semibold leading-tight sm:text-[2.5rem]">
            Un axe, ce n&apos;est pas un thème
          </h2>
          <p className="mt-4 text-[1.02rem] leading-[1.72] text-[var(--texte-doux)]">
            C&apos;est un centre d&apos;intérêt, un objectif et une contrainte de temps. Ce
            triplet suffit à composer un plan : les ouvrages s&apos;ordonnent du plus
            accessible au plus exigeant, et le rythme s&apos;ajuste à ce que vous avez.
          </p>
        </div>

        <ul className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {axes.map((axe, i) => (
            <li key={axe.slug}>
             {/* Le décalage suit l'ordre de lecture : les cartes se posent
                 l'une après l'autre plutôt que toutes d'un bloc. */}
             <Apparition delai={Math.min(i, 5) * 60} className="h-full">
              <Relief className="h-full">
              <Link
                href={`/bibliotheque?axe=${axe.slug}`}
                className="group flex h-full flex-col rounded-[var(--radius-carte)] border border-[var(--trait)] bg-[var(--surface)] p-6 transition-[border-color,box-shadow] duration-200 hover:border-[rgba(212,162,63,0.42)] hover:shadow-[var(--shadow-flottante)]"
              >
                {/* L'icône dans un jeton teinté plutôt que posée à nu : c'est la
                    même anatomie que les tuiles de la console, et une grille de
                    onze symboles isolés se lit moins bien qu'une grille de
                    onze objets. */}
                <span className="grid h-11 w-11 place-items-center rounded-[14px] bg-[var(--fond-creux)] transition-colors group-hover:bg-[rgba(212,162,63,0.16)]">
                  <IconeAxe
                    slug={axe.slug}
                    className="h-[22px] w-[22px] text-[var(--accent-texte)] transition-colors group-hover:text-[var(--color-or)]"
                  />
                </span>
                <h3 className="en-avant mt-4 text-[1.06rem] font-semibold leading-snug">{axe.label}</h3>
                <p className="mt-auto pt-5 text-[0.84rem] text-[var(--texte-doux)]">
                  {axe.nb_ouvrages} ouvrage{axe.nb_ouvrages > 1 ? "s" : ""}
                  <span className="mx-1.5 opacity-40">·</span>
                  {axe.nb_pages.toLocaleString("fr-FR")} pages
                  <span className="mx-1.5 opacity-40">·</span>
                  {heures(axe.duree_estimee_min)} de lecture
                </p>
              </Link>
              </Relief>
             </Apparition>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
