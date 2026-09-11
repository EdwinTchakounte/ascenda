import Link from "next/link";

import Entete from "@/components/Entete";
import Pied from "@/components/Pied";
import { APPLICATION } from "@/lib/editeur";
import { apk } from "@/lib/telechargements";

export const metadata = {
  title: "Commencer avec ASCENDA",
  description:
    "Le diagnostic prend six minutes et donne un plan de lecture daté, tiré de 78 ouvrages.",
};

const ETAPES = [
  {
    titre: "Dites où vous en êtes",
    texte:
      "Dix questions, dont quatre tirées de vrais quiz du corpus. Elles situent votre niveau au lieu de vous le demander : personne ne sait s'auto-évaluer sur un domaine qu'il découvre.",
  },
  {
    titre: "Donnez le temps que vous avez vraiment",
    texte:
      "Trois séances par semaine de quarante minutes, ou cinq de vingt. C'est cette contrainte, et non le nombre de pages, qui détermine le plan.",
  },
  {
    titre: "Recevez un chronogramme daté",
    texte:
      "Des séances avec leur ouvrage, leurs pages et leur date. Un quiz après chacune, corrigé avec l'extrait qui le justifie. Ce que vous ratez revient en révision espacée.",
  },
];

export default function Commencer() {
  // L'APK déposée dans public/telechargements/ prime sur l'adresse configurée :
  // servir le fichier depuis le site évite une redirection de plus, et le poids
  // affiché est celui du fichier réel, pas une valeur recopiée à la main.
  const fichier = apk();
  const android = fichier ? fichier.url : APPLICATION.android;

  return (
    <>
      <Entete />
      <main>
        <header className="border-b border-[rgba(232,192,112,0.12)] bg-[var(--color-nuit-profond)] py-16 sm:py-24">
          <div className="cadre max-w-[820px]">
            <p className="oeil mb-3 text-[var(--color-or-clair)]">Six minutes</p>
            <h1 className="text-[2.1rem] font-semibold leading-[1.14] text-[#f7f4ec] sm:text-[2.8rem]">
              Le premier pas n&apos;est pas un livre.
              <br />
              <span className="text-[var(--color-or-clair)]">C&apos;est une question.</span>
            </h1>
            <p className="mt-5 max-w-[56ch] text-[1.02rem] leading-[1.72] text-[#b9c1d6]">
              ASCENDA ne vous demande pas ce que vous voulez lire. Il vous demande où vous en
              êtes et combien de temps vous avez, puis il construit le plan. Le diagnostic et
              le premier parcours sont gratuits, sans carte bancaire.
            </p>
          </div>
        </header>

        <section className="cadre max-w-[820px] py-16 sm:py-20">
          <ol className="grid gap-8 sm:grid-cols-3">
            {ETAPES.map((e, i) => (
              <li key={e.titre}>
                <span className="mb-3 inline-flex h-8 w-8 items-center justify-center rounded-none bg-[rgba(212,162,63,0.14)] text-[0.85rem] font-semibold tabular-nums text-[var(--accent-texte)]">
                  {i + 1}
                </span>
                <h2 className="mb-2 text-[1.05rem] font-semibold leading-snug text-[var(--titre)]">
                  {e.titre}
                </h2>
                <p className="text-[0.94rem] leading-[1.7] text-[var(--texte-doux)]">{e.texte}</p>
              </li>
            ))}
          </ol>
        </section>

        <section className="border-y border-[var(--trait)] bg-[var(--fond-creux)] py-16">
          <div className="cadre max-w-[760px]">
            <h2 className="text-[1.5rem] font-semibold leading-snug text-[var(--titre)]">
              Ouvrir ASCENDA
            </h2>
            <p className="mt-3 text-[0.98rem] leading-[1.72] text-[var(--texte-doux)]">
              Le diagnostic, le chronogramme et le lecteur vivent dans l&apos;application. Le
              site que vous lisez est la vitrine : il présente le corpus, il ne le fait pas
              travailler.
            </p>

            <div className="mt-8 grid gap-4 sm:grid-cols-2">
              <Acces
                titre="Sur Android"
                texte={
                  fichier
                    ? `Le fichier d'installation, ${fichier.megaoctets} Mo, à ouvrir depuis votre téléphone.`
                    : "Le fichier d'installation, à ouvrir depuis votre téléphone."
                }
                href={android}
                libelle={fichier ? `Télécharger (${fichier.megaoctets} Mo)` : "Télécharger"}
                manque="L'application n'est pas encore publiée. Le fichier arrivera ici."
              />
              <Acces
                titre="Dans le navigateur"
                texte="La même application, sans rien installer."
                href={APPLICATION.web}
                libelle="Ouvrir"
                manque="La version web n'est pas encore déployée."
              />
            </div>

            <p className="mt-8 text-[0.88rem] leading-[1.7] text-[var(--texte-doux)]">
              En attendant, la bibliothèque est consultable ici même, sans compte :{" "}
              <Link
                href="/bibliotheque"
                className="text-[var(--accent-texte)] underline underline-offset-2"
              >
                les 78 ouvrages et leurs 11 axes
              </Link>
              .
            </p>
          </div>
        </section>
      </main>
      <Pied />
    </>
  );
}

/**
 * Un accès à l'application. Quand l'adresse n'est pas configurée, la carte le
 * dit au lieu d'afficher un bouton qui ne mène nulle part : c'est exactement ce
 * défaut qui rendait cette page nécessaire.
 */
function Acces({
  titre,
  texte,
  href,
  libelle,
  manque,
}: {
  titre: string;
  texte: string;
  href: string | null;
  libelle: string;
  manque: string;
}) {
  return (
    <div className="rounded-none border border-[var(--trait)] bg-[var(--surface)] p-6">
      <h3 className="text-[1.02rem] font-semibold text-[var(--titre)]">{titre}</h3>
      <p className="mt-2 text-[0.9rem] leading-[1.65] text-[var(--texte-doux)]">{texte}</p>
      {href ? (
        <a
          href={href}
          className="mt-5 inline-flex items-center justify-center rounded-none bg-[var(--color-or)] px-6 py-2.5 text-[0.92rem] font-medium text-[#1a1400] transition-colors hover:bg-[var(--color-or-clair)]"
        >
          {libelle}
        </a>
      ) : (
        <p className="mt-5 rounded-none border border-dashed border-[var(--trait)] px-4 py-3 text-[0.85rem] leading-[1.6] text-[var(--texte-doux)]">
          {manque}
        </p>
      )}
    </div>
  );
}
