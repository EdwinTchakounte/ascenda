import Link from "next/link";
import Logo from "./Logo";

const COLONNES = [
  {
    titre: "Produit",
    liens: [
      { href: "/#axes", texte: "Les 11 axes" },
      { href: "/#methode", texte: "Comment ça marche" },
      { href: "/bibliotheque", texte: "Bibliothèque" },
      { href: "/#tarifs", texte: "Tarifs" },
    ],
  },
  {
    titre: "En savoir plus",
    liens: [
      { href: "/a-propos", texte: "Le projet" },
      { href: "/droits", texte: "Droits et citations" },
      { href: "/contact", texte: "Nous écrire" },
    ],
  },
  {
    titre: "Légal",
    liens: [
      { href: "/mentions-legales", texte: "Mentions légales" },
      { href: "/confidentialite", texte: "Confidentialité" },
      { href: "/retrait", texte: "Demande de retrait" },
    ],
  },
];

export default function Pied() {
  return (
    <footer className="border-t border-[rgba(232,192,112,0.12)] bg-[var(--color-nuit)] py-16">
      <div className="cadre">
        {/* Deux colonnes de liens sur téléphone : en une seule, le pied de page
            tenait sept cents pixels. */}
        <div className="grid grid-cols-2 gap-x-6 gap-y-10 md:grid-cols-[1.4fr_repeat(3,1fr)] md:gap-12">
          <div className="col-span-2 md:col-span-1">
            <div className="flex items-center gap-2.5">
              <Logo taille={34} />
              <div>
                <p className="font-[family-name:var(--font-titre)] text-[1.18rem] font-semibold tracking-[0.14em] text-[#f4f1e8]">
                  ASCENDA
                </p>
                <p className="text-[0.7rem] tracking-[0.18em] text-[var(--color-or-clair)]">
                  Learn. Grow. Become.
                </p>
              </div>
            </div>
            <p className="mt-4 max-w-[38ch] text-[0.88rem] leading-[1.7] text-[#8590aa]">
              Sortir de la précarité par la lecture. Une bibliothèque, un plan, et un
              agent qui cite ses sources.
            </p>
          </div>

          {COLONNES.map((c) => (
            <nav key={c.titre} aria-label={c.titre}>
              <h3 className="text-[0.78rem] font-semibold uppercase tracking-[0.12em] text-[var(--color-or-clair)]">
                {c.titre}
              </h3>
              <ul className="mt-4 space-y-2.5">
                {c.liens.map((l) => (
                  <li key={l.href}>
                    <Link
                      href={l.href}
                      className="text-[0.88rem] text-[#8590aa] transition-colors hover:text-[var(--color-or-clair)]"
                    >
                      {l.texte}
                    </Link>
                  </li>
                ))}
              </ul>
            </nav>
          ))}
        </div>

        <div className="mt-14 flex flex-col gap-3 border-t border-[rgba(255,255,255,0.06)] pt-7 text-[0.82rem] text-[#6b7591] sm:flex-row sm:items-center sm:justify-between">
          <p>© {new Date().getFullYear()} ASCENDA. Learn. Grow. Become.</p>
          <p>
            Les ouvrages non redistribuables sont cités, jamais reproduits.{" "}
            <Link href="/droits" className="underline underline-offset-2 hover:text-[var(--color-or-clair)]">
              En savoir plus
            </Link>
          </p>
        </div>
      </div>
    </footer>
  );
}
