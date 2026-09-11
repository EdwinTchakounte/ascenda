"use client";

import { useRef } from "react";

/**
 * Une surface qui prend du relief sous le pointeur.
 *
 * La carte s'incline vraiment : `perspective` sur le parent, `rotateX` et
 * `rotateY` calculés depuis la position du pointeur, et le contenu remonte en
 * `translateZ`. Un reflet doré suit la main comme sur un vernis.
 *
 * Tout passe par des variables CSS posées sur le noeud : React ne redessine
 * rien pendant le mouvement, sans quoi une grille de onze cartes rendrait
 * soixante fois par seconde pour un effet décoratif.
 *
 * Rien de tout cela ne s'active au doigt : sur un écran tactile il n'y a pas de
 * survol, seulement un temps d'attente avant que la carte réponde au clic.
 */
export default function Relief({
  children,
  intensite = 7,
  className = "",
}: {
  children: React.ReactNode;
  intensite?: number;
  className?: string;
}) {
  const boite = useRef<HTMLDivElement | null>(null);
  const fin = useRef<boolean | null>(null);

  const utilisable = () => {
    if (fin.current === null) {
      fin.current =
        window.matchMedia("(hover: hover) and (pointer: fine)").matches &&
        !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    }
    return fin.current;
  };

  const suivre = (e: React.PointerEvent<HTMLDivElement>) => {
    const n = boite.current;
    if (!n || !utilisable()) return;
    const r = n.getBoundingClientRect();
    const x = (e.clientX - r.left) / r.width;
    const y = (e.clientY - r.top) / r.height;
    n.style.setProperty("--rx", `${(0.5 - y) * intensite}deg`);
    n.style.setProperty("--ry", `${(x - 0.5) * intensite}deg`);
    n.style.setProperty("--lx", `${x * 100}%`);
    n.style.setProperty("--ly", `${y * 100}%`);
    n.style.setProperty("--eclat", "1");
  };

  const lacher = () => {
    const n = boite.current;
    if (!n) return;
    n.style.setProperty("--rx", "0deg");
    n.style.setProperty("--ry", "0deg");
    n.style.setProperty("--eclat", "0");
  };

  return (
    <div
      ref={boite}
      className={`relief ${className}`}
      onPointerMove={suivre}
      onPointerLeave={lacher}
    >
      <div className="relief-plan">
        {children}
        <span aria-hidden className="relief-reflet" />
      </div>
    </div>
  );
}
