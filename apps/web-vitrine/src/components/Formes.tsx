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

/**
 * Un voile de couleur : une nappe très floue posée derrière une section.
 *
 * C'est la seule forme ronde que le site s'autorise, et elle passe parce
 * qu'elle n'a pas de bord : à cent vingt pixels de flou, on ne voit pas un
 * cercle, on voit une couleur qui se lève. Un carré net de la même teinte
 * serait un bloc posé sur la page ; celui-ci est une atmosphère.
 *
 * Les teintes sont celles des pôles. En descendant la page, la couleur change
 * de section en section, ce qui donne un parcours au lieu d'un empilement de
 * bandes de la même valeur.
 */
export function Voile({
  teinte = "#d4a23f",
  className = "",
  opacite = 0.1,
  flou = 120,
}: {
  teinte?: string;
  className?: string;
  opacite?: number;
  flou?: number;
}) {
  return (
    <div
      aria-hidden
      className={`pointer-events-none absolute rounded-full ${className}`}
      style={{
        background: `radial-gradient(circle, ${teinte} 0%, transparent 68%)`,
        opacity: opacite,
        filter: `blur(${flou}px)`,
      }}
    />
  );
}

/**
 * Un quadrillage, comme un papier millimétré très pâle.
 *
 * Il dit la même chose que les angles droits des cartes, en fond : que la page
 * est construite sur une grille. Masqué en dégradé pour qu'il s'efface aux
 * bords plutôt que de s'arrêter net.
 */
export function Carreaux({
  className = "",
  pas = 44,
  couleur = "rgba(11,20,53,0.055)",
  masque = "radial-gradient(ellipse 70% 60% at 50% 40%, #000 20%, transparent 78%)",
}: {
  className?: string;
  pas?: number;
  couleur?: string;
  masque?: string;
}) {
  return (
    <div
      aria-hidden
      className={`pointer-events-none absolute inset-0 ${className}`}
      style={{
        backgroundImage: `linear-gradient(${couleur} 1px, transparent 1px), linear-gradient(90deg, ${couleur} 1px, transparent 1px)`,
        backgroundSize: `${pas}px ${pas}px`,
        maskImage: masque,
        WebkitMaskImage: masque,
      }}
    />
  );
}

/**
 * Des carrés au trait qui dérivent lentement.
 *
 * Trois suffisent : au-delà, ce n'est plus une atmosphère, c'est un motif. Ils
 * tournent d'un huitième de tour pour ne pas s'aligner sur la grille, et leur
 * dérive s'arrête quand le système demande moins d'animation.
 */
export function Eclats({
  teintes = ["#d4a23f", "#4a6fa5", "#7c9a82"],
  className = "",
}: {
  teintes?: string[];
  className?: string;
}) {
  const poses = [
    { top: "12%", left: "6%", taille: 92, tour: 12, duree: 26 },
    { top: "58%", left: "88%", taille: 128, tour: -18, duree: 34 },
    { top: "78%", left: "18%", taille: 64, tour: 40, duree: 30 },
  ];
  return (
    <div aria-hidden className={`pointer-events-none absolute inset-0 ${className}`}>
      {poses.map((p, i) => (
        <span
          key={i}
          className="eclat absolute block border"
          style={{
            top: p.top,
            left: p.left,
            width: p.taille,
            height: p.taille,
            borderColor: teintes[i % teintes.length],
            opacity: 0.16,
            transform: `rotate(${p.tour}deg)`,
            animationDuration: `${p.duree}s`,
            animationDelay: `${i * -6}s`,
          }}
        />
      ))}
    </div>
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
        className="absolute -inset-2 rounded-none opacity-60 blur-xl"
        style={{
          background:
            "linear-gradient(135deg, rgba(212,162,63,0.28), transparent 55%, rgba(232,192,112,0.2))",
        }}
      />
      <div className="relative overflow-hidden rounded-none ring-1 ring-[rgba(232,192,112,0.22)]">
        {children}
      </div>
    </div>
  );
}
