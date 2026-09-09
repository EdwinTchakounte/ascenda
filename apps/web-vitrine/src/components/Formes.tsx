/**
 * Les formes décoratives du site : un halo doré, une trame de points, une
 * courbe de séparation. Dessinées en SVG et en CSS plutôt qu'importées : sur
 * une connexion à 30 Ko/s, chaque fichier économisé se voit.
 */

export function Halo({
  className = "",
  couleur = "#d4a23f",
  opacite = 0.16,
}: {
  className?: string;
  couleur?: string;
  opacite?: number;
}) {
  return (
    <div
      aria-hidden
      className={`pointer-events-none absolute rounded-full blur-[110px] ${className}`}
      style={{
        background: `radial-gradient(circle, ${couleur} 0%, transparent 70%)`,
        opacity: opacite,
      }}
    />
  );
}

/** Trame de points, très discrète, qui donne de la matière aux fonds sombres. */
export function Trame({ className = "" }: { className?: string }) {
  return (
    <div
      aria-hidden
      className={`pointer-events-none absolute inset-0 ${className}`}
      style={{
        backgroundImage:
          "radial-gradient(circle at 1px 1px, rgba(232,192,112,0.18) 1px, transparent 0)",
        backgroundSize: "28px 28px",
        maskImage: "radial-gradient(ellipse 80% 60% at 50% 0%, #000 40%, transparent 100%)",
        WebkitMaskImage:
          "radial-gradient(ellipse 80% 60% at 50% 0%, #000 40%, transparent 100%)",
      }}
    />
  );
}

/** Séparation courbe entre deux sections, pour rompre l'empilement de bandes. */
export function Vague({
  couleur = "var(--fond)",
  inverse = false,
}: {
  couleur?: string;
  inverse?: boolean;
}) {
  return (
    <div aria-hidden className="pointer-events-none relative -mb-px w-full leading-none">
      <svg
        viewBox="0 0 1440 64"
        preserveAspectRatio="none"
        className={`block h-[44px] w-full sm:h-[64px] ${inverse ? "rotate-180" : ""}`}
      >
        <path
          d="M0 64 C 240 8, 480 8, 720 32 C 960 56, 1200 56, 1440 20 L1440 64 Z"
          fill={couleur}
        />
      </svg>
    </div>
  );
}

/** Un cadre arrondi rempli d'un dégradé doré très dilué, pour porter une image. */
export function CadreDore({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative">
      <div
        aria-hidden
        className="absolute -inset-2 rounded-[28px] opacity-60 blur-xl"
        style={{
          background:
            "linear-gradient(135deg, rgba(212,162,63,0.28), transparent 55%, rgba(232,192,112,0.2))",
        }}
      />
      <div className="relative overflow-hidden rounded-[24px] ring-1 ring-[rgba(232,192,112,0.22)]">
        {children}
      </div>
    </div>
  );
}
