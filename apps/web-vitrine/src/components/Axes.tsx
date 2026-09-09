import Link from "next/link";
import IconeAxe from "./IconesAxes";
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
          {axes.map((axe) => (
            <li key={axe.slug}>
              <Link
                href={`/bibliotheque?axe=${axe.slug}`}
                className="group flex h-full flex-col rounded-[var(--radius-carte)] border border-[var(--trait)] bg-[var(--surface)] p-6 transition-all duration-200 hover:-translate-y-0.5 hover:border-[rgba(212,162,63,0.42)] hover:shadow-[var(--shadow-flottante)]"
              >
                <IconeAxe
                  slug={axe.slug}
                  className="h-9 w-9 text-[var(--accent-texte)] transition-colors group-hover:text-[var(--color-or)]"
                />
                <h3 className="mt-4 text-[1.06rem] font-semibold leading-snug">{axe.label}</h3>
                <p className="mt-auto pt-5 text-[0.84rem] text-[var(--texte-doux)]">
                  {axe.nb_ouvrages} ouvrage{axe.nb_ouvrages > 1 ? "s" : ""}
                  <span className="mx-1.5 opacity-40">·</span>
                  {axe.nb_pages.toLocaleString("fr-FR")} pages
                  <span className="mx-1.5 opacity-40">·</span>
                  {heures(axe.duree_estimee_min)} de lecture
                </p>
              </Link>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
