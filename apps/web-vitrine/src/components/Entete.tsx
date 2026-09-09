import Link from "next/link";
import Bouton from "./Bouton";
import Logo from "./Logo";

const LIENS = [
  { href: "/#axes", texte: "Les axes" },
  { href: "/#methode", texte: "Comment ça marche" },
  { href: "/bibliotheque", texte: "Bibliothèque" },
  { href: "/#tarifs", texte: "Tarifs" },
];

export default function Entete() {
  return (
    <header className="sticky top-0 z-50 border-b border-[rgba(232,192,112,0.12)] bg-[rgba(5,13,34,0.86)] backdrop-blur-md">
      <div className="cadre flex h-[72px] items-center justify-between gap-6">
        <Link href="/" className="flex items-center gap-2.5" aria-label="ASCENDA, accueil">
          <Logo taille={34} />
          <span className="font-[family-name:var(--font-titre)] text-[1.3rem] font-semibold tracking-[0.14em] text-[#f4f1e8]">
            ASCENDA
          </span>
        </Link>

        <nav className="hidden items-center gap-8 md:flex" aria-label="Navigation principale">
          {LIENS.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className="text-[0.9rem] text-[#b9c1d6] transition-colors hover:text-[var(--color-or-clair)]"
            >
              {l.texte}
            </Link>
          ))}
        </nav>

        <div className="flex items-center gap-3">
          <Link
            href="/connexion"
            className="hidden text-[0.9rem] text-[#b9c1d6] transition-colors hover:text-[var(--color-or-clair)] sm:block"
          >
            Se connecter
          </Link>
          <Bouton href="/commencer">Commencer</Bouton>
        </div>
      </div>
    </header>
  );
}
