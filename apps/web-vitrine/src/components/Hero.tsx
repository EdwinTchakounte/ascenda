import Bouton from "./Bouton";
import { CORPUS } from "@/lib/api";

/* Les trois séances de la carte flottante viennent d'un vrai chronogramme
   généré par l'API sur l'axe « IA, société et éthique ». */
const SEANCES = [
  { jour: "Sam. 29", duree: "21 min", ouvrage: "Comment l'IA transformera notre avenir", detail: "p. 7-27", etat: "fait" },
  { jour: "Lun. 31", duree: "28 min", ouvrage: "La guerre des intelligences", detail: "ch. 2, p. 46-55", etat: "aujourd'hui" },
  { jour: "Mar. 1", duree: "25 min", ouvrage: "L'intelligence artificielle n'existe pas", detail: "p. 36-45", etat: "a_venir" },
];

export default function Hero() {
  return (
    <section className="relative overflow-hidden bg-[var(--color-nuit-profond)]">
      {/* Halo doré très diffus : l'or comme lumière, jamais comme aplat. */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-40 left-1/2 h-[560px] w-[900px] -translate-x-1/2 rounded-full opacity-[0.16] blur-[120px]"
        style={{ background: "radial-gradient(circle, #d4a23f 0%, transparent 68%)" }}
      />

      <div className="cadre relative grid gap-14 py-20 md:py-28 lg:grid-cols-[1.05fr_0.95fr] lg:items-center lg:gap-20">
        <div>
          <p className="oeil mb-5">Learn. Grow. Become.</p>
          <h1 className="text-[2.6rem] font-semibold leading-[1.08] text-[#f7f4ec] sm:text-[3.3rem] lg:text-[3.65rem]">
            Vous n&apos;avez pas besoin de plus de livres.
            <br />
            <span className="text-[var(--color-or-clair)]">Vous avez besoin d&apos;un plan.</span>
          </h1>
          <p className="mt-6 max-w-[52ch] text-[1.06rem] leading-[1.72] text-[#b9c1d6]">
            Dites où vous en êtes et combien de temps vous avez vraiment. ASCENDA
            découpe {CORPUS.ouvrages} ouvrages en séances datées que vous pouvez tenir,
            vous interroge sur ce que vous lisez, et répond à vos questions en citant
            toujours le livre et la page.
          </p>

          <div className="mt-9 flex flex-wrap items-center gap-3.5">
            <Bouton href="/commencer" taille="grand">Commencer gratuitement</Bouton>
            <Bouton href="/bibliotheque" variante="contour" taille="grand">
              Voir la bibliothèque
            </Bouton>
          </div>

          <p className="mt-6 text-[0.85rem] text-[#8590aa]">
            Sans carte bancaire. L&apos;offre Découverte reste gratuite.
          </p>
        </div>

        {/* Aperçu du produit : une semaine de chronogramme. */}
        <div className="relative">
          <div
            className="rounded-[var(--radius-carte)] border border-[rgba(232,192,112,0.16)] bg-[rgba(16,28,61,0.72)] p-6 backdrop-blur-sm"
            style={{ boxShadow: "0 32px 64px rgba(0,0,0,0.42)" }}
          >
            <div className="mb-5 flex items-baseline justify-between">
              <div>
                <p className="oeil">Votre semaine</p>
                <p className="mt-1.5 font-[family-name:var(--font-titre)] text-[1.22rem] text-[#f4f1e8]">
                  IA, société et éthique
                </p>
              </div>
              <span className="rounded-full bg-[rgba(212,162,63,0.14)] px-3 py-1 text-[0.72rem] font-medium text-[var(--color-or-clair)]">
                Semaine 1 / 12
              </span>
            </div>

            <ul className="space-y-2.5">
              {SEANCES.map((s) => {
                const actif = s.etat === "aujourd'hui";
                const fait = s.etat === "fait";
                return (
                  <li
                    key={s.jour}
                    className={`flex items-start gap-3.5 rounded-[var(--radius-douce)] border p-3.5 transition-colors ${
                      actif
                        ? "border-[rgba(212,162,63,0.45)] bg-[rgba(212,162,63,0.09)]"
                        : "border-[rgba(255,255,255,0.06)] bg-[rgba(255,255,255,0.02)]"
                    }`}
                  >
                    <span
                      className={`mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-[0.68rem] font-semibold ${
                        fait
                          ? "bg-[rgba(124,154,130,0.2)] text-[#a8c4ad]"
                          : actif
                            ? "bg-[var(--color-or)] text-[#1a1400]"
                            : "bg-[rgba(255,255,255,0.05)] text-[#8590aa]"
                      }`}
                    >
                      {fait ? "✓" : s.jour.split(".")[0].slice(0, 2)}
                    </span>
                    <div className="min-w-0 flex-1">
                      <p
                        className={`truncate text-[0.9rem] font-medium ${
                          fait ? "text-[#7d879e] line-through decoration-1" : "text-[#e6e9f2]"
                        }`}
                      >
                        {s.ouvrage}
                      </p>
                      <p className="mt-0.5 text-[0.78rem] text-[#8590aa]">
                        {s.detail} · {s.duree}
                      </p>
                    </div>
                  </li>
                );
              })}
            </ul>

            <div className="mt-5 flex items-center gap-3 border-t border-[rgba(255,255,255,0.06)] pt-4">
              <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-[rgba(255,255,255,0.07)]">
                <div className="h-full w-[34%] rounded-full bg-[var(--color-or)]" />
              </div>
              <span className="text-[0.76rem] text-[#8590aa]">4 notions à revoir</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
