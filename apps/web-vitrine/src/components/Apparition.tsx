"use client";

import { useEffect, useRef } from "react";

/**
 * Ce qui entre dans l'écran monte à sa place au lieu d'y être déjà.
 *
 * Aucun état React : la première version posait deux `useState` depuis un
 * effet, ce qui faisait rendre deux fois chaque section et donnait un éclair
 * visible, le contenu affiché, puis masqué, puis révélé. Ici, le serveur rend
 * le contenu visible, et le client ne masque que ce qui est encore sous
 * l'écran au moment où il prend la main. Ce qui est déjà visible le reste.
 *
 * Sans JavaScript, pour un moteur de recherche, ou quand le système demande
 * moins d'animation, rien n'est jamais caché.
 */
export default function Apparition({
  children,
  delai = 0,
  className = "",
}: {
  children: React.ReactNode;
  delai?: number;
  decalage?: number;
  className?: string;
}) {
  const noeud = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    const n = noeud.current;
    if (!n) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    if (n.getBoundingClientRect().top < window.innerHeight * 0.92) return;

    n.style.transitionDelay = `${delai}ms`;
    n.classList.add("apparition-armee");
    const oeil = new IntersectionObserver(
      ([e]) => {
        if (!e.isIntersecting) return;
        n.classList.remove("apparition-armee");
        oeil.disconnect();
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" },
    );
    oeil.observe(n);
    return () => oeil.disconnect();
  }, [delai]);

  return (
    <div ref={noeud} className={`apparition ${className}`}>
      {children}
    </div>
  );
}
