import Link from "next/link";
import Apparition from "./Apparition";
import IconeAxe from "./IconesAxes";
import Relief from "./Relief";
import { Carreaux, Voile } from "./Formes";
import { heures, lesAxes, lesOuvrages, type Axe } from "@/lib/api";

/**
 * Les onze pôles d'apprentissage.
 *
 * Onze rectangles blancs identiques ne disaient rien : le pôle qui porte dix-sept
 * ouvrages avait exactement le même poids visuel que celui qui en porte un. La
 * carte montre donc d'abord son volume, en grand, et chaque pôle a sa teinte,
 * la même que le dos de ses volumes sur l'étagère.
 *
 * Le premier pôle occupe deux colonnes. Ce n'est pas qu'un effet : onze cartes
 * dans une grille de trois laissent un trou en fin de rangée, et une grille qui
 * ne tombe pas juste se voit plus qu'on ne le croit.
 */

function Carte({
  axe,
  part,
  large,
  apercu = [],
}: {
  axe: Axe;
  part: number;
  large?: boolean;
  apercu?: string[];
}) {
  const teinte = `axe-${axe.slug.slice(0, 2)}`;
  return (
    <Relief className="h-full">
      <Link
        href={`/bibliotheque?axe=${axe.slug}`}
        className={`${teinte} group relative flex h-full flex-col rounded-none border border-[var(--trait)] bg-[var(--surface)] p-6 transition-[border-color,box-shadow] duration-300 hover:border-[color-mix(in_srgb,var(--teinte)_45%,transparent)] hover:shadow-[0_24px_48px_color-mix(in_srgb,var(--teinte)_18%,transparent)] sm:p-7`}
      >
        {/* Le voile de teinte, très bas, qui distingue les pôles sans les crier. */}
        <span
          aria-hidden
          className="pointer-events-none absolute inset-0 rounded-none opacity-[0.055] transition-opacity duration-300 group-hover:opacity-[0.1]"
          style={{
            background:
              "radial-gradient(120% 100% at 100% 0%, var(--teinte) 0%, transparent 62%)",
          }}
        />

        <div className="en-avant relative flex items-start gap-4">
          <span
            className="grid h-12 w-12 flex-none place-items-center rounded-none transition-colors duration-300"
            style={{
              background: "color-mix(in srgb, var(--teinte) 13%, transparent)",
              color: "var(--teinte)",
            }}
          >
            <IconeAxe slug={axe.slug} className="h-[23px] w-[23px]" />
          </span>
          <span className="ml-auto text-right">
            <b
              className="block font-[family-name:var(--font-titre)] text-[1.9rem] font-semibold leading-none tabular-nums"
              style={{ color: "var(--teinte)" }}
            >
              {axe.nb_ouvrages}
            </b>
            <span className="mt-1 block text-[0.7rem] uppercase tracking-[0.09em] text-[var(--texte-doux)]">
              {axe.nb_ouvrages > 1 ? "ouvrages" : "ouvrage"}
            </span>
          </span>
        </div>

        {/* Le titre se centre dans la place qui reste. Une carte étirée par sa
            voisine laissait sinon un trou entre son titre et sa barre. */}
        <div className={large ? "relative" : "relative flex flex-1 flex-col justify-center"}>
          <h3
            className={`en-avant relative font-semibold leading-snug ${
              large ? "mt-5 text-[1.35rem] sm:text-[1.5rem]" : "mt-5 text-[1.08rem]"
            }`}
          >
            {axe.label}
          </h3>
        </div>

        {large ? (
          <div className="relative mt-3">
            {axe.description ? (
              <p className="max-w-[48ch] text-[0.92rem] leading-[1.68] text-[var(--texte-doux)]">
                {axe.description}
              </p>
            ) : null}
            {/* Trois titres du pôle. Un nom de pôle ne dit pas ce qu'on va lire ;
                trois couvertures, si. */}
            {apercu.length ? (
              <ul className="mt-3 space-y-1.5">
                {apercu.map((t) => (
                  <li
                    key={t}
                    className="flex items-start gap-2.5 text-[0.88rem] leading-snug text-[var(--texte-doux)]"
                  >
                    <span
                      aria-hidden
                      className="mt-[7px] h-[5px] w-[5px] flex-none rounded-none"
                      style={{ background: "var(--teinte)" }}
                    />
                    <span className="line-clamp-1">{t}</span>
                  </li>
                ))}
              </ul>
            ) : null}
            <p
              className="mt-4 text-[0.84rem] font-semibold"
              style={{ color: "var(--teinte)" }}
            >
              Explorer ce parcours
              <span
                aria-hidden
                className="ml-1.5 inline-block transition-transform duration-300 group-hover:translate-x-1"
              >
                →
              </span>
            </p>
          </div>
        ) : null}

        <div className="relative pt-6">
          {/* La part du corpus, en barre. « 17 ouvrages » ne dit rien tant qu'on
              ne sait pas ce que pèsent les autres. */}
          <span className="block h-[5px] w-full overflow-hidden rounded-none bg-[var(--fond-creux)]">
            <span
              className="block h-full rounded-none transition-[width] duration-500"
              style={{
                width: `${Math.max(part * 100, 6)}%`,
                background:
                  "linear-gradient(90deg, color-mix(in srgb, var(--teinte) 55%, transparent), var(--teinte))",
              }}
            />
          </span>
          <p className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-[0.82rem] text-[var(--texte-doux)]">
            <span className="tabular-nums">{axe.nb_pages.toLocaleString("fr-FR")} pages</span>
            <span className="opacity-40">·</span>
            <span className="tabular-nums">{heures(axe.duree_estimee_min)} de lecture</span>
            <span
              aria-hidden
              className="ml-auto translate-x-[-6px] opacity-0 transition-all duration-300 group-hover:translate-x-0 group-hover:opacity-100"
              style={{ color: "var(--teinte)" }}
            >
              →
            </span>
          </p>
        </div>
      </Link>
    </Relief>
  );
}

export default async function Axes() {
  const axes = await lesAxes();
  const plusGros = Math.max(1, ...axes.map((a) => a.nb_ouvrages));
  // Le pôle le mieux fourni ouvre la grille. C'est aussi celui par lequel on a
  // le plus de chances de commencer.
  const tete = axes.reduce((a, b) => (b.nb_ouvrages > a.nb_ouvrages ? b : a), axes[0]);
  const suite = axes.filter((a) => a.slug !== tete?.slug);
  // Trois titres du pôle de tête. Si l'API ne répond pas, la carte se rend sans,
  // comme le reste de la vitrine.
  const apercu = tete
    ? (await lesOuvrages({ axe: tete.slug, par_page: "3" })).ouvrages
        .slice(0, 3)
        .map((o) => o.titre)
    : [];

  return (
    <section id="axes" className="relative overflow-hidden bg-[var(--fond)] py-24">
      {/* Le fond de la section : une grille très pâle, et trois voiles de
          couleur pris dans la palette des pôles. Une bande unie de la même
          valeur que la précédente se lit comme une page qui s'arrête. */}
      <Carreaux />
      <Voile teinte="#d4a23f" opacite={0.14} className="-top-32 left-1/2 h-[460px] w-[820px] -translate-x-1/2" />
      <Voile teinte="#8a7f9e" opacite={0.1} className="right-[-8%] top-[38%] h-[420px] w-[520px]" />
      <Voile teinte="#6f8f57" opacite={0.09} className="bottom-[-10%] left-[-6%] h-[380px] w-[520px]" />

      <div className="cadre relative">
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

        <ul className="mt-14 grid gap-4 sm:grid-cols-2 sm:gap-5 lg:grid-cols-3">
          {tete ? (
            <li className="sm:col-span-2">
              <Apparition className="h-full">
                <Carte axe={tete} part={tete.nb_ouvrages / plusGros} large apercu={apercu} />
              </Apparition>
            </li>
          ) : null}
          {suite.map((axe, i) => (
            <li key={axe.slug}>
              {/* Le décalage suit l'ordre de lecture : les cartes se posent
                  l'une après l'autre plutôt que toutes d'un bloc. */}
              <Apparition delai={Math.min(i + 1, 5) * 55} className="h-full">
                <Carte axe={axe} part={axe.nb_ouvrages / plusGros} />
              </Apparition>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
