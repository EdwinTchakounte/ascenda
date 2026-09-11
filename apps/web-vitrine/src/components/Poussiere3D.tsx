"use client";

import { useEffect, useRef } from "react";

/**
 * Une poussière d'étoiles en vraie perspective.
 *
 * Chaque grain porte trois coordonnées et se projette par `f / (f + z)` : les
 * grains proches sont gros et rapides, les lointains petits et lents. Ce n'est
 * pas un décor plat auquel on aurait ajouté du flou, c'est de la profondeur
 * calculée, et le regard la reconnaît tout de suite.
 *
 * Aucune bibliothèque. Une scène 3D importée pèserait cent cinquante kilo-octets
 * avant la première image, et ASCENDA s'ouvre sur des connexions où cela se
 * compte en secondes d'attente. Ici, deux kilo-octets et de la trigonométrie.
 *
 * Le rendu s'arrête dès que la section sort de l'écran ou que l'onglet passe en
 * arrière-plan : une animation qui tourne sans être vue vide une batterie.
 */
export default function Poussiere3D({
  densite = 0.00009,
  className = "",
}: {
  densite?: number;
  className?: string;
}) {
  const toile = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const c = toile.current;
    if (!c) return;
    const ctx = c.getContext("2d", { alpha: true });
    if (!ctx) return;

    const sobre = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    // Sur un écran très dense, dessiner à la résolution réelle coûte quatre fois
    // plus de pixels pour une poussière que personne ne regarde de près.
    const dpr = Math.min(window.devicePixelRatio || 1, 1.75);

    let l = 0, h = 0, grains: Grain[] = [], trame = 0, vivant = false;
    let viseX = 0, viseY = 0, panX = 0, panY = 0;

    type Grain = { x: number; y: number; z: number; r: number; teinte: number };

    const PROFONDEUR = 900;
    const FOCALE = 620;

    function semer() {
      const n = Math.round(Math.min(Math.max(l * h * densite, 26), 150));
      grains = Array.from({ length: n }, () => ({
        x: (Math.random() - 0.5) * l * 1.7,
        y: (Math.random() - 0.5) * h * 1.7,
        z: Math.random() * PROFONDEUR,
        r: 0.6 + Math.random() * 1.7,
        teinte: Math.random(),
      }));
    }

    function mesurer() {
      const r = c!.getBoundingClientRect();
      l = Math.max(r.width, 1);
      h = Math.max(r.height, 1);
      c!.width = Math.round(l * dpr);
      c!.height = Math.round(h * dpr);
      ctx!.setTransform(dpr, 0, 0, dpr, 0, 0);
      semer();
    }

    function dessiner(pas: number) {
      ctx!.clearRect(0, 0, l, h);
      // Le pointeur ne déplace pas les grains, il déplace la caméra. Les grains
      // proches bougent donc plus que les lointains, sans qu'on l'ait écrit.
      panX += (viseX - panX) * 0.045;
      panY += (viseY - panY) * 0.045;

      for (const g of grains) {
        g.z -= pas * 0.018;
        if (g.z <= 1) {
          g.z += PROFONDEUR;
          g.x = (Math.random() - 0.5) * l * 1.7;
          g.y = (Math.random() - 0.5) * h * 1.7;
        }
        const e = FOCALE / (FOCALE + g.z);
        const x = l / 2 + (g.x + panX * (1 - e) * 90) * e;
        const y = h / 2 + (g.y + panY * (1 - e) * 90) * e;
        if (x < -20 || x > l + 20 || y < -20 || y > h + 20) continue;
        const rayon = g.r * e * 1.9;
        const opacite = Math.min(e * e * 1.15, 0.85) * (0.35 + g.teinte * 0.65);
        ctx!.beginPath();
        ctx!.arc(x, y, rayon, 0, Math.PI * 2);
        ctx!.fillStyle =
          g.teinte > 0.72
            ? `rgba(232,192,112,${opacite.toFixed(3)})`
            : `rgba(190,203,230,${(opacite * 0.55).toFixed(3)})`;
        ctx!.fill();
      }
    }

    let precedent = 0;
    function boucle(t: number) {
      if (!vivant) return;
      const pas = Math.min(t - precedent || 16, 48);
      precedent = t;
      dessiner(pas);
      trame = requestAnimationFrame(boucle);
    }

    function demarrer() {
      if (vivant || sobre) return;
      vivant = true;
      precedent = 0;
      trame = requestAnimationFrame(boucle);
    }
    function arreter() {
      vivant = false;
      cancelAnimationFrame(trame);
    }

    function surPointeur(e: PointerEvent) {
      const r = c!.getBoundingClientRect();
      viseX = ((e.clientX - r.left) / r.width - 0.5) * 2;
      viseY = ((e.clientY - r.top) / r.height - 0.5) * 2;
    }

    mesurer();
    dessiner(0); // une image même en mode sobre : la profondeur reste, le mouvement part

    const surTaille = new ResizeObserver(() => {
      mesurer();
      if (!vivant) dessiner(0);
    });
    surTaille.observe(c);

    const oeil = new IntersectionObserver(
      ([e]) => (e.isIntersecting ? demarrer() : arreter()),
      { threshold: 0.02 },
    );
    oeil.observe(c);

    const surVisibilite = () => (document.hidden ? arreter() : demarrer());
    document.addEventListener("visibilitychange", surVisibilite);
    window.addEventListener("pointermove", surPointeur, { passive: true });

    return () => {
      arreter();
      surTaille.disconnect();
      oeil.disconnect();
      document.removeEventListener("visibilitychange", surVisibilite);
      window.removeEventListener("pointermove", surPointeur);
    };
  }, [densite]);

  return (
    <canvas
      ref={toile}
      aria-hidden
      className={`pointer-events-none absolute inset-0 h-full w-full ${className}`}
    />
  );
}
