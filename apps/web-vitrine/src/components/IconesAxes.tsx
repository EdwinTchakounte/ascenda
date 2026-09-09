/**
 * Une icône au trait par axe. Dessinées à la main plutôt qu'importées d'une
 * bibliothèque : onze traits cohérents pèsent moins qu'un paquet d'icônes, et
 * la connexion de beaucoup de nos lecteurs se compte en kilo-octets.
 */
type Props = { className?: string };

const T = {
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.4,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
};

function Cadre({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <svg viewBox="0 0 32 32" className={className} aria-hidden="true">
      {children}
    </svg>
  );
}

/* 01 : une graine qui germe : les fondamentaux */
const Fondamentaux = (p: Props) => (
  <Cadre className={p.className}>
    <path {...T} d="M16 27V14" />
    <path {...T} d="M16 14c0-4 3-7 7-7 0 4-3 7-7 7Z" />
    <path {...T} d="M16 18c0-3-2.5-5.5-5.5-5.5 0 3 2.5 5.5 5.5 5.5Z" />
    <path {...T} d="M10 27h12" />
  </Cadre>
);

/* 02 : un réseau de neurones : la technique */
const Technique = (p: Props) => (
  <Cadre className={p.className}>
    <circle {...T} cx="7" cy="16" r="2.4" />
    <circle {...T} cx="16" cy="8" r="2.4" />
    <circle {...T} cx="16" cy="24" r="2.4" />
    <circle {...T} cx="25" cy="16" r="2.4" />
    <path {...T} d="M9.2 14.6 13.9 9.6M9.2 17.4l4.7 5M18.1 9.6l4.7 5M18.1 22.4l4.7-5" />
  </Cadre>
);

/* 03 : un curseur et une invite : les outils */
const Outils = (p: Props) => (
  <Cadre className={p.className}>
    <rect {...T} x="4" y="7" width="24" height="18" rx="3" />
    <path {...T} d="m9 14 3 3-3 3M15 20h8" />
  </Cadre>
);

/* 04 : une balance : société et éthique */
const Societe = (p: Props) => (
  <Cadre className={p.className}>
    <path {...T} d="M16 6v20M9 26h14" />
    <path {...T} d="M6 11h20M6 11l-3 7h6l-3-7ZM26 11l-3 7h6l-3-7Z" />
  </Cadre>
);

/* 05 : un livre ouvert : l'éducation */
const Education = (p: Props) => (
  <Cadre className={p.className}>
    <path {...T} d="M16 9c-2.5-2-5.5-2.6-9-2v16c3.5-.6 6.5 0 9 2 2.5-2 5.5-2.6 9-2V7c-3.5-.6-6.5 0-9 2Z" />
    <path {...T} d="M16 9v16" />
  </Cadre>
);

/* 06 : un engrenage et une main : le travail */
const Travail = (p: Props) => (
  <Cadre className={p.className}>
    <circle {...T} cx="16" cy="14" r="4" />
    <path {...T} d="M16 5v2.5M16 20.5V23M25 14h-2.5M9.5 14H7M22.4 7.6l-1.8 1.8M11.4 18.6l-1.8 1.8M22.4 20.4l-1.8-1.8M11.4 9.4 9.6 7.6" />
    <path {...T} d="M9 27h14" />
  </Cadre>
);

/* 07 : le continent, tracé au trait : Afrique */
const Afrique = (p: Props) => (
  <Cadre className={p.className}>
    <path
      {...T}
      d="M12 4h9l1.5 4-2 3 1.5 4-2.5 4 .5 4-3 5-3-2-1-5-3-3 .5-4-2.5-3 1-4 3-3Z"
    />
  </Cadre>
);

/* 08 : une plume : la littérature */
const Litterature = (p: Props) => (
  <Cadre className={p.className}>
    <path {...T} d="M6 26c0-9 6-18 16-20 1 10-4 17-11 18l-5 2Z" />
    <path {...T} d="M11 24c3-4 6.5-7 11-9" />
  </Cadre>
);

/* 09 : une flèche qui monte en marches : le développement personnel */
const Developpement = (p: Props) => (
  <Cadre className={p.className}>
    <path {...T} d="M5 25h5v-6h6v-6h6V7h5" />
    <path {...T} d="M21 7h5v5" />
  </Cadre>
);

/* 10 : une pièce et une courbe : l'économie */
const Economie = (p: Props) => (
  <Cadre className={p.className}>
    <circle {...T} cx="12" cy="12" r="6" />
    <path {...T} d="M12 9v6M10 11h4M10 13h4" />
    <path {...T} d="M6 26c4-1 7-3 9-6s5-5 11-5" />
  </Cadre>
);

/* 11 : une feuille dans un cercle : sciences et environnement */
const Sciences = (p: Props) => (
  <Cadre className={p.className}>
    <circle {...T} cx="16" cy="16" r="11" />
    <path {...T} d="M11 21c0-6 4-9 10-9 0 6-4 9-10 9Z" />
    <path {...T} d="M11 21c2.5-2.5 5-4.5 8-6" />
  </Cadre>
);

export const ICONES: Record<string, (p: Props) => React.ReactElement> = {
  "01-ia-fondamentaux-vulgarisation": Fondamentaux,
  "02-ia-technique-academique": Technique,
  "03-ia-outils-pratique-prompting": Outils,
  "04-ia-societe-ethique-philosophie": Societe,
  "05-ia-education-pedagogie": Education,
  "06-ia-travail-management-metiers": Travail,
  "07-afrique-histoire-pensee": Afrique,
  "08-litterature-romans": Litterature,
  "09-developpement-personnel-influence": Developpement,
  "10-economie-entrepreneuriat-finance": Economie,
  "11-sciences-environnement": Sciences,
};

export default function IconeAxe({ slug, className }: { slug: string; className?: string }) {
  const Icone = ICONES[slug] ?? Fondamentaux;
  return <Icone className={className} />;
}
