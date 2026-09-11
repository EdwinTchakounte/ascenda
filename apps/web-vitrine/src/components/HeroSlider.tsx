"use client";

import Image from "next/image";
import { useCallback, useEffect, useRef, useState } from "react";

import Bouton from "./Bouton";
import { CadreDore, Halo, Trame, Voile } from "./Formes";
import Poussiere3D from "./Poussiere3D";
import Relief from "./Relief";

/**
 * Le hero en trois temps.
 *
 * Chaque diapositive dit une chose et une seule, et montre le produit plutôt
 * qu'une promesse. Le défilement s'arrête au survol, au focus clavier, et
 * quand le système demande moins d'animation : une page qui bouge toute seule
 * pendant qu'on lit est une page qu'on quitte.
 */

type Diapositive = {
  oeil: string;
  titre: React.ReactNode;
  texte: string;
  image: string;
  alt: string;
};

const DIAPOSITIVES: Diapositive[] = [
  {
    oeil: "Learn. Grow. Become.",
    titre: (
      <>
        Vous n&apos;avez pas besoin
        <br />
        de plus de livres.
        <br />
        <span className="text-[var(--color-or-clair)]">Vous avez besoin d&apos;un plan.</span>
      </>
    ),
    texte:
      "Dites où vous en êtes et combien de temps vous avez vraiment. ASCENDA découpe la bibliothèque en séances datées que vous pouvez tenir.",
    image: "/images/lecture.jpg",
    alt: "Un livre ouvert posé près d'une fenêtre",
  },
  {
    oeil: "Un agent qui cite ses sources",
    titre: (
      <>
        Il répond en donnant
        <br />
        <span className="text-[var(--color-or-clair)]">le livre et la page.</span>
      </>
    ),
    texte:
      "L'agent ne répond que sur les ouvrages du corpus. S'il ne trouve rien, il le dit au lieu d'inventer. Chaque réponse porte ses références.",
    image: "/images/bibliotheque.jpg",
    alt: "Rayonnages d'une bibliothèque",
  },
  {
    oeil: "Le plan s'adapte",
    titre: (
      <>
        Vous prenez du retard ?
        <br />
        <span className="text-[var(--color-or-clair)]">Le plan se recompose.</span>
      </>
    ),
    texte:
      "Un quiz après chaque séance, corrigé avec l'extrait du livre qui le justifie. Ce que vous ratez revient en révision espacée.",
    image: "/images/etudier.jpg",
    alt: "Une personne qui lit et prend des notes",
  },
];

const DUREE = 7000;

export default function HeroSlider() {
  const [index, setIndex] = useState(0);
  const [enPause, setEnPause] = useState(false);
  const minuterie = useRef<ReturnType<typeof setInterval> | null>(null);

  const aller = useCallback((i: number) => setIndex(((i % DIAPOSITIVES.length) + DIAPOSITIVES.length) % DIAPOSITIVES.length), []);

  useEffect(() => {
    const moinsDAnimation = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (moinsDAnimation || enPause) return;
    minuterie.current = setInterval(() => setIndex((i) => (i + 1) % DIAPOSITIVES.length), DUREE);
    return () => {
      if (minuterie.current) clearInterval(minuterie.current);
    };
  }, [enPause]);

  const d = DIAPOSITIVES[index];

  return (
    <section
      className="relative overflow-hidden bg-[var(--color-nuit-profond)]"
      onMouseEnter={() => setEnPause(true)}
      onMouseLeave={() => setEnPause(false)}
      onFocusCapture={() => setEnPause(true)}
      onBlurCapture={() => setEnPause(false)}
      aria-roledescription="carrousel"
      aria-label="Présentation d'ASCENDA"
    >
      <Halo className="-top-40 left-1/2 h-[560px] w-[900px] -translate-x-1/2" />
      {/* Deux voiles froids sous le halo doré : le bleu creuse le fond, le
          violet l'empêche de virer au gris. */}
      <Voile teinte="#4a6fa5" opacite={0.34} className="bottom-[-24%] left-[-10%] h-[560px] w-[720px]" />
      <Voile teinte="#8a7f9e" opacite={0.22} className="right-[-12%] top-[18%] h-[460px] w-[560px]" />
      <Trame />
      {/* La profondeur derrière tout le reste : des grains projetés en vraie
          perspective, qui répondent au pointeur en déplaçant la caméra. */}
      <Poussiere3D densite={0.00014} />

      <div className="cadre relative grid gap-12 py-16 sm:py-20 lg:grid-cols-[1.02fr_0.98fr] lg:items-center lg:gap-16 lg:py-28">
        {/* Le texte */}
        <div className="min-h-[340px] sm:min-h-[380px]">
          <p className="oeil mb-4 transition-opacity duration-500">{d.oeil}</p>
          <h1
            key={`t-${index}`}
            className="animate-[apparition_.55s_ease-out] text-[2.15rem] font-semibold leading-[1.1] text-[#f7f4ec] sm:text-[2.9rem] lg:text-[3.5rem]"
          >
            {d.titre}
          </h1>
          <p
            key={`p-${index}`}
            className="mt-5 max-w-[52ch] animate-[apparition_.65s_ease-out] text-[0.98rem] leading-[1.72] text-[#b9c1d6] sm:text-[1.06rem]"
          >
            {d.texte}
          </p>

          <div className="mt-8 flex flex-wrap items-center gap-3">
            <Bouton href="/commencer" taille="grand">
              Commencer gratuitement
            </Bouton>
            <Bouton href="/bibliotheque" variante="contour" taille="grand">
              Voir la bibliothèque
            </Bouton>
          </div>

          <p className="mt-5 text-[0.82rem] text-[#8590aa]">
            Sans carte bancaire. Paiement par MTN Mobile Money et Orange Money.
          </p>

          {/* Pagination du carrousel */}
          <div className="mt-8 flex items-center gap-3">
            {DIAPOSITIVES.map((s, i) => (
              <button
                key={i}
                onClick={() => aller(i)}
                aria-label={`Diapositive ${i + 1} sur ${DIAPOSITIVES.length}`}
                aria-current={i === index}
                className="group py-2"
              >
                <span
                  className={`block h-[3px] rounded-none transition-all duration-500 ${
                    i === index
                      ? "w-10 bg-[var(--color-or)]"
                      : "w-5 bg-[rgba(255,255,255,0.18)] group-hover:bg-[rgba(232,192,112,0.5)]"
                  }`}
                />
              </button>
            ))}
            <span className="ml-1 text-[0.75rem] tabular-nums text-[#6b7591]">
              {index + 1} / {DIAPOSITIVES.length}
            </span>
          </div>
        </div>

        {/* L'image, et la carte de chronogramme par-dessus. L'ensemble est un
            diorama : la photo au fond, la carte en avant, et le tout s'incline
            sous le pointeur. */}
        <Relief intensite={9} className="relative">
          <CadreDore>
            <div className="relative aspect-[4/3] w-full sm:aspect-[16/11]">
              {DIAPOSITIVES.map((s, i) => (
                <Image
                  key={s.image}
                  src={s.image}
                  alt={s.alt}
                  fill
                  sizes="(max-width: 1024px) 92vw, 46vw"
                  priority={i === 0}
                  className={`object-cover transition-opacity duration-700 ${
                    i === index ? "opacity-100" : "opacity-0"
                  }`}
                />
              ))}
              <div
                aria-hidden
                className="absolute inset-0"
                style={{
                  background:
                    "linear-gradient(180deg, rgba(5,13,34,0.15) 0%, rgba(5,13,34,0.82) 100%)",
                }}
              />
            </div>
          </CadreDore>

          {/* Carte flottante : une vraie séance issue d'un plan généré. */}
          <div className="en-avant relative mx-auto -mt-16 w-[92%] rounded-none border border-[rgba(232,192,112,0.18)] bg-[rgba(11,20,53,0.92)] p-4 shadow-[0_24px_48px_rgba(0,0,0,0.45)] backdrop-blur-md sm:absolute sm:-bottom-8 sm:-left-6 sm:mt-0 sm:w-[290px] sm:p-5">
            <p className="oeil text-[0.66rem]">Séance du jour</p>
            <p className="mt-1.5 font-[family-name:var(--font-titre)] text-[1.02rem] leading-snug text-[#f4f1e8]">
              La guerre des intelligences
            </p>
            <p className="mt-1 text-[0.78rem] text-[#8590aa]">
              ch. 2, p. 46 à 55 · 28 min
            </p>
            <div className="mt-3 flex items-center gap-2.5">
              <div className="h-1.5 flex-1 overflow-hidden rounded-none bg-[rgba(255,255,255,0.08)]">
                <div className="h-full w-[38%] rounded-none bg-[var(--color-or)]" />
              </div>
              <span className="text-[0.7rem] tabular-nums text-[#8590aa]">38 %</span>
            </div>
          </div>
        </Relief>
      </div>

      <style>{`
        @keyframes apparition {
          from { opacity: 0; transform: translateY(10px); }
          to   { opacity: 1; transform: none; }
        }
        @media (prefers-reduced-motion: reduce) {
          .animate-\\[apparition_\\.55s_ease-out\\],
          .animate-\\[apparition_\\.65s_ease-out\\] { animation: none !important; }
        }
      `}</style>
    </section>
  );
}
