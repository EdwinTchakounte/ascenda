"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Ce qui entre dans l'écran monte à sa place au lieu d'y être déjà.
 *
 * Une page qui se révèle au défilement se lit comme une page vivante, à
 * condition que le mouvement soit court et qu'il n'arrive qu'une fois : une
 * section qui rejoue son entrée à chaque passage devient une gêne.
 *
 * Sans JavaScript, ou quand le système demande moins d'animation, le contenu
 * est simplement là. Il n'est jamais caché par défaut côté serveur : une
 * section invisible pour un moteur de recherche serait une section perdue.
 */
export default function Apparition({
  children,
  delai = 0,
  decalage = 26,
  className = "",
}: {
  children: React.ReactNode;
  delai?: number;
  decalage?: number;
  className?: string;
}) {
  const noeud = useRef<HTMLDivElement | null>(null);
  const [vu, setVu] = useState(false);
  const [arme, setArme] = useState(false);

  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setVu(true);
      return;
    }
    setArme(true);
    const n = noeud.current;
    if (!n) return;
    const oeil = new IntersectionObserver(
      ([e]) => {
        if (e.isIntersecting) {
          setVu(true);
          oeil.disconnect();
        }
      },
      { threshold: 0.12, rootMargin: "0px 0px -8% 0px" },
    );
    oeil.observe(n);
    return () => oeil.disconnect();
  }, []);

  return (
    <div
      ref={noeud}
      className={className}
      style={
        arme && !vu
          ? { opacity: 0, transform: `translate3d(0, ${decalage}px, 0)` }
          : {
              opacity: 1,
              transform: "none",
              transition: `opacity .7s ease-out ${delai}ms, transform .7s cubic-bezier(.22,.8,.3,1) ${delai}ms`,
            }
      }
    >
      {children}
    </div>
  );
}
