"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";

export type Dos = { id: string; titre: string; auteur: string; axe: string; slug: string };

/**
 * La bibliothèque en relief.
 *
 * Les ouvrages sont posés sur un arc de cercle : celui du milieu fait face,
 * ses voisins s'éloignent en `translateZ` et pivotent en `rotateY`. La
 * profondeur est réelle, pas simulée par une mise à l'échelle, et chaque
 * volume a une tranche pour qu'il se lise comme un objet et non comme une
 * vignette.
 *
 * On le fait tourner à la main, au doigt, aux flèches du clavier, et tout seul
 * quand personne n'y touche. Le geste s'arrête dès qu'on prend la main, parce
 * qu'un carrousel qui continue pendant qu'on lit un titre est un carrousel
 * qu'on quitte.
 */
export default function Etagere3D({ ouvrages }: { ouvrages: Dos[] }) {
  const [courant, setCourant] = useState(0);
  const [tenu, setTenu] = useState(false);
  const scene = useRef<HTMLDivElement | null>(null);
  const depart = useRef<{ x: number; index: number } | null>(null);
  const total = ouvrages.length;

  const aller = useCallback(
    (i: number) => setCourant(((i % total) + total) % total),
    [total],
  );

  // Le défilement automatique ne démarre que si la section est à l'écran et
  // que le système ne demande pas moins d'animation.
  useEffect(() => {
    if (tenu || total < 2) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const n = scene.current;
    if (!n) return;
    let horloge: ReturnType<typeof setInterval> | null = null;
    const oeil = new IntersectionObserver(([e]) => {
      if (e.isIntersecting && !horloge) {
        horloge = setInterval(() => setCourant((c) => (c + 1) % total), 4200);
      } else if (!e.isIntersecting && horloge) {
        clearInterval(horloge);
        horloge = null;
      }
    }, { threshold: 0.25 });
    oeil.observe(n);
    return () => {
      if (horloge) clearInterval(horloge);
      oeil.disconnect();
    };
  }, [tenu, total]);

  const prendre = (e: React.PointerEvent) => {
    depart.current = { x: e.clientX, index: courant };
    setTenu(true);
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
  };
  const glisser = (e: React.PointerEvent) => {
    const d = depart.current;
    if (!d || !scene.current) return;
    const pas = Math.max(scene.current.offsetWidth / 7, 60);
    aller(d.index - Math.round((e.clientX - d.x) / pas));
  };
  const lacher = () => {
    depart.current = null;
    setTenu(false);
  };

  if (!total) return null;

  return (
    <section id="etagere" className="relative overflow-hidden bg-[var(--color-nuit)] py-20 sm:py-24">
      <div className="cadre relative">
        <div className="mx-auto max-w-[60ch] text-center">
          <p className="oeil">La bibliothèque</p>
          <h2 className="mt-3 text-[2.1rem] font-semibold leading-tight text-[#f7f4ec] sm:text-[2.5rem]">
            Des ouvrages, pas des résumés d&apos;ouvrages
          </h2>
          <p className="mt-4 text-[1.02rem] leading-[1.72] text-[#a8b2c9]">
            Chaque volume est lu en entier par le moteur, découpé en chapitres,
            puis replacé dans un plan. Faites tourner l&apos;étagère.
          </p>
        </div>

        <div
          ref={scene}
          className="etagere mt-14 select-none"
          onPointerDown={prendre}
          onPointerMove={glisser}
          onPointerUp={lacher}
          onPointerCancel={lacher}
          role="group"
          aria-roledescription="étagère en relief"
          aria-label="Quelques ouvrages du corpus"
          tabIndex={0}
          onKeyDown={(e) => {
            if (e.key === "ArrowRight") { aller(courant + 1); e.preventDefault(); }
            if (e.key === "ArrowLeft") { aller(courant - 1); e.preventDefault(); }
          }}
        >
          {/* Le sol : une lueur sous l'étagère, qui pose les volumes au lieu de
              les laisser flotter dans le noir. */}
          <span aria-hidden className="etagere-sol" />
          <div className="etagere-scene">
            {ouvrages.map((o, i) => {
              // L'écart le plus court sur l'anneau : sans cela, passer du
              // dernier au premier ferait traverser toute l'étagère.
              let d = i - courant;
              if (d > total / 2) d -= total;
              if (d < -total / 2) d += total;
              const loin = Math.abs(d);
              if (loin > 3) return null;
              return (
                <article
                  key={o.id}
                  className="volume"
                  aria-hidden={d !== 0}
                  style={{
                    transform: `translate(-50%, -50%) translateX(${d * 94}%) translateZ(${-loin * 178}px) rotateY(${d * -39}deg)`,
                    zIndex: 10 - loin,
                    // Ce qui est loin s'efface vite : sans cela, sept volumes de
                    // même intensité se disputent le regard et aucun ne le
                    // retient. Le voisin reste lisible, le suivant devient une
                    // profondeur, le troisième une ombre.
                    opacity: [1, 0.72, 0.34, 0.15][loin],
                    filter: loin ? `brightness(${1 - loin * 0.2})` : undefined,
                  }}
                  onClick={() => d !== 0 && aller(i)}
                >
                  <span aria-hidden className={`volume-dos axe-${o.slug.slice(0, 2)}`} />
                  <span aria-hidden className="volume-tranche" />
                  <span aria-hidden className="volume-filet" />
                  <p className="volume-axe">{o.axe}</p>
                  <h3 className="volume-titre">{o.titre}</h3>
                  <p className="volume-auteur">{o.auteur}</p>
                  <span aria-hidden className="volume-lustre" />
                </article>
              );
            })}
          </div>
        </div>

        <div className="mt-9 flex flex-col items-center gap-4">
          <Link
            href={`/ouvrage/${ouvrages[courant].id}`}
            className="text-[0.92rem] text-[var(--color-or-clair)] underline-offset-4 hover:underline"
          >
            Ouvrir la fiche de « {ouvrages[courant].titre} »
          </Link>
          <div className="flex items-center gap-2">
            <button
              onClick={() => aller(courant - 1)}
              aria-label="Ouvrage précédent"
              className="grid h-10 w-10 place-items-center rounded-none border border-[rgba(232,192,112,0.28)] text-[var(--color-or-clair)] transition-colors hover:border-[var(--color-or)] hover:bg-[rgba(212,162,63,0.12)]"
            >
              <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="m14.4 5.6-6.4 6.4 6.4 6.4" /></svg>
            </button>
            <span className="w-16 text-center text-[0.78rem] tabular-nums text-[#7c88a6]">
              {courant + 1} / {total}
            </span>
            <button
              onClick={() => aller(courant + 1)}
              aria-label="Ouvrage suivant"
              className="grid h-10 w-10 place-items-center rounded-none border border-[rgba(232,192,112,0.28)] text-[var(--color-or-clair)] transition-colors hover:border-[var(--color-or)] hover:bg-[rgba(212,162,63,0.12)]"
            >
              <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="m9.6 5.6 6.4 6.4-6.4 6.4" /></svg>
            </button>
          </div>
        </div>
      </div>
    </section>
  );
}
