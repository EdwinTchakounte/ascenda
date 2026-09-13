"use client";

import Image from "next/image";
import { useCallback, useEffect, useRef, useState } from "react";

import Bouton from "./Bouton";
import { Trame } from "./Formes";
import Poussiere3D from "./Poussiere3D";

/**
 * Le hero : une vidéo de lecture en plein cadre, le message au centre.
 *
 * Trois messages se relaient au-dessus d'une seule vidéo. Le défilement
 * s'arrête au survol, au focus clavier, et quand le système demande moins
 * d'animation : une page qui bouge toute seule pendant qu'on lit est une page
 * qu'on quitte.
 *
 * La vidéo est un bonus, jamais un préalable. L'image d'attente s'affiche
 * d'abord et suffit à elle seule ; la vidéo ne se charge qu'une fois la page
 * interactive, et pas du tout si le visiteur a demandé moins d'animation ou
 * active l'économiseur de données. Deux cadrages : horizontal sur ordinateur,
 * vertical sur téléphone, pour ne jamais rogner un plan large dans un écran
 * étroit. Sources et licences : `public/videos/SOURCES.md`.
 */

type Message = {
  oeil: string;
  titre: React.ReactNode;
  texte: string;
};

const MESSAGES: Message[] = [
  {
    oeil: "Learn. Grow. Become.",
    titre: (
      <>
        Vous n&apos;avez pas besoin de plus de livres.{" "}
        <span className="text-[var(--color-or-clair)]">Vous avez besoin d&apos;un plan.</span>
      </>
    ),
    texte:
      "Dites où vous en êtes et combien de temps vous avez vraiment. ASCENDA découpe la bibliothèque en séances datées que vous pouvez tenir.",
  },
  {
    oeil: "Un agent qui cite ses sources",
    titre: (
      <>
        Il répond en donnant{" "}
        <span className="text-[var(--color-or-clair)]">le livre et la page.</span>
      </>
    ),
    texte:
      "L'agent ne répond que sur les ouvrages du corpus. S'il ne trouve rien, il le dit au lieu d'inventer. Chaque réponse porte ses références.",
  },
  {
    oeil: "Le plan s'adapte",
    titre: (
      <>
        Vous prenez du retard&nbsp;?{" "}
        <span className="text-[var(--color-or-clair)]">Le plan se recompose.</span>
      </>
    ),
    texte:
      "Un quiz après chaque séance, corrigé avec l'extrait du livre qui le justifie. Ce que vous ratez revient en révision espacée.",
  },
];

const DUREE = 7000;

type Connexion = { saveData?: boolean };

export default function HeroSlider() {
  const [index, setIndex] = useState(0);
  const [enPause, setEnPause] = useState(false);
  const [videoPrete, setVideoPrete] = useState(false);
  const [videoArretee, setVideoArretee] = useState(false);
  const video = useRef<HTMLVideoElement | null>(null);

  const aller = useCallback(
    (i: number) => setIndex(((i % MESSAGES.length) + MESSAGES.length) % MESSAGES.length),
    [],
  );

  useEffect(() => {
    const moinsDAnimation = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (moinsDAnimation || enPause) return;
    const minuterie = setInterval(() => setIndex((i) => (i + 1) % MESSAGES.length), DUREE);
    return () => clearInterval(minuterie);
  }, [enPause]);

  // Le choix de la source se fait ici, et non dans des <source media> : tous
  // les navigateurs ne respectent pas l'attribut, et un téléphone qui
  // téléchargerait la version horizontale paierait pour rien.
  useEffect(() => {
    const v = video.current;
    if (!v) return;
    const sobre = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const economie = (navigator as Navigator & { connection?: Connexion }).connection?.saveData;
    if (sobre || economie) return;

    const nom = window.matchMedia("(max-width: 767px)").matches ? "hero-haute" : "hero-large";
    const accepteWebm = v.canPlayType('video/webm; codecs="vp9"') !== "";
    v.src = `/videos/${nom}.${accepteWebm ? "webm" : "mp4"}`;

    // Hors écran, la vidéo s'arrête : elle ne décode plus rien pour personne.
    const observateur = new IntersectionObserver(([e]) => {
      if (!e.isIntersecting) v.pause();
      else if (!v.dataset.arretee) v.play().catch(() => {});
    });
    observateur.observe(v);
    return () => observateur.disconnect();
  }, []);

  const basculerVideo = () => {
    const v = video.current;
    if (!v) return;
    if (v.paused) {
      delete v.dataset.arretee;
      v.play().catch(() => {});
      setVideoArretee(false);
    } else {
      v.dataset.arretee = "1";
      v.pause();
      setVideoArretee(true);
    }
  };

  const m = MESSAGES[index];

  return (
    <section
      className="relative isolate flex min-h-[calc(100svh-72px)] items-center overflow-hidden bg-[var(--color-nuit-profond)] sm:min-h-[max(600px,min(calc(100svh-72px),860px))]"
      onMouseEnter={() => setEnPause(true)}
      onMouseLeave={() => setEnPause(false)}
      onFocusCapture={() => setEnPause(true)}
      onBlurCapture={() => setEnPause(false)}
      aria-roledescription="carrousel"
      aria-label="Présentation d'ASCENDA"
    >
      {/* Le fond : l'image d'attente, puis la vidéo qui s'y substitue en fondu
          dès qu'elle joue vraiment. */}
      <div aria-hidden className="absolute inset-0 -z-10">
        <Image
          src="/videos/hero-haute.jpg"
          alt=""
          fill
          priority
          sizes="100vw"
          className="object-cover md:hidden"
        />
        <Image
          src="/videos/hero-large.jpg"
          alt=""
          fill
          priority
          sizes="100vw"
          className="hidden object-cover md:block"
        />
        <video
          ref={video}
          muted
          loop
          playsInline
          autoPlay
          preload="none"
          disablePictureInPicture
          onPlaying={() => setVideoPrete(true)}
          className={`absolute inset-0 h-full w-full scale-[1.04] object-cover transition-opacity duration-[1400ms] ${
            videoPrete ? "opacity-100" : "opacity-0"
          }`}
        />
        {/* Deux couches pour lire le texte sur n'importe quelle image : un
            assombrissement général teinté de nuit, et un creux plus sombre
            derrière le bloc central. Le bas se fond dans la section suivante. */}
        <div className="absolute inset-0 bg-[rgba(5,13,34,0.62)]" />
        <div
          className="absolute inset-0"
          style={{
            background:
              "radial-gradient(ellipse 70% 60% at 50% 50%, rgba(5,13,34,0.55) 0%, rgba(5,13,34,0) 72%), linear-gradient(180deg, rgba(5,13,34,0.35) 0%, rgba(5,13,34,0) 30%, rgba(5,13,34,0) 70%, var(--color-nuit-profond) 100%)",
          }}
        />
      </div>
      <Trame className="-z-10 opacity-60" />
      <Poussiere3D densite={0.00008} className="-z-10" />

      <div className="cadre relative w-full py-16 text-center sm:py-24">
        <div className="mx-auto flex max-w-[900px] flex-col items-center">
          <p className="oeil mb-5 transition-opacity duration-500">{m.oeil}</p>

          {/* Hauteur réservée : les trois titres n'ont pas la même longueur, et
              un bloc qui saute à chaque relais déplace les boutons sous le doigt. */}
          <div className="flex min-h-[9.2rem] items-center sm:min-h-[8.4rem] lg:min-h-[10rem]">
            <h1
              key={`t-${index}`}
              className="animate-[apparition_.6s_ease-out] text-balance text-[2.1rem] font-semibold leading-[1.1] text-[#f7f4ec] [text-shadow:0_2px_24px_rgba(5,13,34,0.6)] sm:text-[3rem] lg:text-[4.1rem]"
            >
              {m.titre}
            </h1>
          </div>

          <div className="min-h-[7.4rem] sm:min-h-[5.6rem]">
            <p
              key={`p-${index}`}
              className="mx-auto mt-5 max-w-[56ch] animate-[apparition_.7s_ease-out] text-pretty text-[0.98rem] leading-[1.72] text-[#d2d8e6] sm:text-[1.1rem]"
            >
              {m.texte}
            </p>
          </div>

          {/* Deux colonnes égales sur téléphone, côte à côte. */}
          <div className="mt-8 grid w-full max-w-[440px] grid-cols-2 gap-2.5 sm:flex sm:w-auto sm:max-w-none sm:justify-center sm:gap-3">
            <Bouton href="/commencer" taille="grand">
              Commencer gratuitement
            </Bouton>
            <Bouton href="/bibliotheque" variante="contour" taille="grand">
              Voir la bibliothèque
            </Bouton>
          </div>

          {/* Réservé aux grands écrans : sur téléphone, le moyen de paiement
              n'est pas ce qui décide quelqu'un à commencer. */}
          <p className="mt-5 hidden text-[0.84rem] text-[#9aa4bd] sm:block">
            Sans carte bancaire. Paiement par MTN Mobile Money et Orange Money.
          </p>

          {/* Pagination du carrousel */}
          <div className="mt-9 flex items-center justify-center gap-3">
            {MESSAGES.map((_, i) => (
              <button
                key={i}
                onClick={() => aller(i)}
                aria-label={`Message ${i + 1} sur ${MESSAGES.length}`}
                aria-current={i === index}
                className="group py-2"
              >
                <span
                  className={`block h-[3px] transition-all duration-500 ${
                    i === index
                      ? "w-10 bg-[var(--color-or)]"
                      : "w-5 bg-[rgba(255,255,255,0.22)] group-hover:bg-[rgba(232,192,112,0.5)]"
                  }`}
                />
              </button>
            ))}
            <span className="ml-1 text-[0.75rem] tabular-nums text-[#8590aa]">
              {index + 1} / {MESSAGES.length}
            </span>
          </div>
        </div>
      </div>

      {/* Toute animation de plus de cinq secondes doit pouvoir s'arrêter. */}
      {videoPrete && (
        <button
          type="button"
          onClick={basculerVideo}
          aria-label={videoArretee ? "Relancer la vidéo de fond" : "Mettre la vidéo de fond en pause"}
          className="absolute bottom-4 right-4 flex h-9 w-9 items-center justify-center border border-[rgba(255,255,255,0.18)] bg-[rgba(5,13,34,0.5)] text-[#d2d8e6] backdrop-blur-sm transition hover:border-[var(--color-or)] hover:text-[var(--color-or-clair)] sm:bottom-6 sm:right-6"
        >
          {videoArretee ? (
            <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
              <path d="M2.5 1.5v9l8-4.5z" fill="currentColor" />
            </svg>
          ) : (
            <svg width="12" height="12" viewBox="0 0 12 12" aria-hidden>
              <path d="M2.5 1.5h2.5v9H2.5zM7 1.5h2.5v9H7z" fill="currentColor" />
            </svg>
          )}
        </button>
      )}

      <style>{`
        @keyframes apparition {
          from { opacity: 0; transform: translateY(10px); }
          to   { opacity: 1; transform: none; }
        }
        @media (prefers-reduced-motion: reduce) {
          .animate-\\[apparition_\\.6s_ease-out\\],
          .animate-\\[apparition_\\.7s_ease-out\\] { animation: none !important; }
        }
      `}</style>
    </section>
  );
}
