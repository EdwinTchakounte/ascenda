import Link from "next/link";

type Props = {
  href: string;
  children: React.ReactNode;
  variante?: "or" | "contour" | "clair";
  taille?: "normal" | "grand";
};

/**
 * Un seul composant de bouton pour tout le site : les trois variantes suffisent
 * et garantissent que le CTA d'une section ressemble à celui de la suivante.
 */
export default function Bouton({ href, children, variante = "or", taille = "normal" }: Props) {
  const base =
    "inline-flex items-center justify-center gap-2 rounded-none font-medium transition-all duration-200 focus-visible:outline-2";
  // Sur téléphone, deux boutons « grand » doivent tenir côte à côte dans trois
  // cent trente pixels : le rembourrage et le corps se resserrent sous `sm`, et
  // le libellé peut passer sur deux lignes plutôt que de pousser la rangée.
  const dimensions =
    taille === "grand"
      ? "px-3 py-3 text-[0.88rem] leading-tight text-center sm:px-7 sm:py-3.5 sm:text-[0.98rem]"
      : "px-5 py-2.5 text-[0.9rem]";

  const styles: Record<string, string> = {
    or: "bg-[var(--color-or)] text-[#1a1400] hover:bg-[var(--color-or-clair)] shadow-[0_4px_14px_rgba(212,162,63,0.28)] hover:shadow-[0_6px_20px_rgba(212,162,63,0.36)]",
    contour:
      "border border-[rgba(232,192,112,0.42)] text-[var(--color-or-clair)] hover:border-[var(--color-or)] hover:bg-[rgba(212,162,63,0.08)]",
    clair:
      "bg-[var(--surface)] text-[var(--titre)] border border-[var(--trait)] hover:border-[rgba(212,162,63,0.5)]",
  };

  return (
    <Link href={href} className={`${base} ${dimensions} ${styles[variante]}`}>
      {children}
    </Link>
  );
}
