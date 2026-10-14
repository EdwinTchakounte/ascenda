import Link from "next/link";

import Entete from "@/components/Entete";
import Pied from "@/components/Pied";
import { APPLICATION } from "@/lib/editeur";
import { apk, apk32, apkUniverselle } from "@/lib/telechargements";

export const metadata = {
  title: "Commencer avec ASCENDA",
  description:
    "Le diagnostic prend six minutes et donne un plan de lecture daté, tiré de 79 ouvrages.",
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
  const ancien = apk32();
  const universelle = apkUniverselle();
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

            {/* Le téléchargement au premier écran. Il était à mille six cents
                pixels de hauteur sur téléphone, sous trois étapes à lire, alors
                que c'est ce qu'on vient chercher sur cette page. */}
            {android ? (
              <div className="mt-8 grid grid-cols-2 gap-2.5 sm:flex sm:gap-3">
                <a
                  href={android}
                  download
                  className="inline-flex items-center justify-center gap-2 rounded-none bg-[var(--color-or)] px-3 py-3 text-center text-[0.88rem] font-semibold leading-tight text-[#1a1400] shadow-[0_4px_14px_rgba(212,162,63,0.28)] transition-colors hover:bg-[var(--color-or-clair)] sm:px-7 sm:py-3.5 sm:text-[0.98rem]"
                >
                  <svg viewBox="0 0 24 24" aria-hidden="true" className="hidden h-5 w-5 sm:block" fill="currentColor">
                    <path d="M17.6 9.48 19.44 6.3a.38.38 0 0 0-.66-.38l-1.87 3.23a11.5 11.5 0 0 0-9.82 0L5.22 5.92a.38.38 0 0 0-.66.38L6.4 9.48A10.8 10.8 0 0 0 1 18h22a10.8 10.8 0 0 0-5.4-8.52ZM7 15.25a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Zm10 0a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Z" />
                  </svg>
                  Télécharger l&apos;application
                </a>
                <a
                  href="#telecharger"
                  className="inline-flex items-center justify-center rounded-none border border-[rgba(232,192,112,0.42)] px-3 py-3 text-center text-[0.88rem] font-medium leading-tight text-[var(--color-or-clair)] transition-colors hover:border-[var(--color-or)] hover:bg-[rgba(212,162,63,0.08)] sm:px-7 sm:py-3.5 sm:text-[0.98rem]"
                >
                  Comment l&apos;installer
                </a>
              </div>
            ) : null}
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

        {/* Le téléchargement. La carte « dans le navigateur » a disparu : il n'y
            a pas de version web déployée, et une carte qui annonce ce qui
            n'existe pas détourne l'attention du seul accès réel. */}
        <section id="telecharger" className="relative overflow-hidden bg-[var(--color-nuit)] py-16 sm:py-20">
          <div className="cadre relative max-w-[880px]">
            <div className="grid items-center gap-10 md:grid-cols-[1.1fr_0.9fr]">
              <div>
                <p className="oeil text-[var(--color-or-clair)]">L&apos;application</p>
                <h2 className="mt-3 text-[1.8rem] font-semibold leading-tight text-[#f7f4ec] sm:text-[2.2rem]">
                  ASCENDA sur votre téléphone
                </h2>
                <p className="mt-4 text-[1rem] leading-[1.72] text-[#b9c1d6]">
                  Le diagnostic, le chronogramme, le lecteur et l&apos;agent vivent dans
                  l&apos;application. Ce site présente la bibliothèque ; l&apos;application
                  la fait travailler.
                </p>

                {android ? (
                  <div className="mt-8">
                    <a
                      href={android}
                      download
                      className="inline-flex w-full items-center justify-center gap-3 rounded-none bg-[var(--color-or)] px-6 py-3.5 sm:px-7 sm:py-4 text-[1rem] font-semibold text-[#1a1400] shadow-[0_4px_14px_rgba(212,162,63,0.28)] transition-colors hover:bg-[var(--color-or-clair)] sm:w-auto"
                    >
                      <svg viewBox="0 0 24 24" aria-hidden="true" className="h-5 w-5" fill="currentColor">
                        <path d="M17.6 9.48 19.44 6.3a.38.38 0 0 0-.66-.38l-1.87 3.23a11.5 11.5 0 0 0-9.82 0L5.22 5.92a.38.38 0 0 0-.66.38L6.4 9.48A10.8 10.8 0 0 0 1 18h22a10.8 10.8 0 0 0-5.4-8.52ZM7 15.25a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Zm10 0a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5Z" />
                      </svg>
                      {/* Le poids passe sous le libellé sur téléphone : sur une ligne,
                          il se coupait en colonne à côté du texte. */}
                      <span className="flex flex-col items-start leading-tight sm:flex-row sm:items-baseline sm:gap-2">
                        <span>Télécharger pour Android</span>
                        {fichier ? (
                          <span className="text-[0.82rem] font-normal opacity-70 sm:text-[1rem]">
                            {fichier.megaoctets.toLocaleString("fr-FR")} Mo
                          </span>
                        ) : null}
                      </span>
                    </a>
                    {ancien || universelle ? (
                      <p className="mt-4 text-[0.84rem] leading-[1.6] text-[#8590aa]">
                        {/* « Le package semble non valide » veut dire, neuf fois sur dix,
                            que le téléphone n'a pas le processeur de ce fichier là. Le
                            message d'Android ne le dit pas : la page le dit à sa place. */}
                        Android répond que le fichier n&apos;est pas valide ?{" "}
                        {ancien ? (
                          <>
                            Sur un téléphone ancien ou d&apos;entrée de gamme,{" "}
                            <a href={ancien.url} download className="text-[var(--color-or-clair)] underline underline-offset-2">
                              prenez la version 32 bits
                            </a>{" "}
                            ({ancien.megaoctets.toLocaleString("fr-FR")} Mo).{" "}
                          </>
                        ) : null}
                        {universelle ? (
                          <>
                            Dans le doute,{" "}
                            <a href={universelle.url} download className="text-[var(--color-or-clair)] underline underline-offset-2">
                              la version universelle
                            </a>{" "}
                            ({universelle.megaoctets.toLocaleString("fr-FR")} Mo) s&apos;installe sur tous les
                            téléphones.
                          </>
                        ) : null}
                      </p>
                    ) : null}
                  </div>
                ) : (
                  <p className="mt-8 rounded-none border border-dashed border-[rgba(232,192,112,0.3)] px-5 py-4 text-[0.92rem] leading-[1.6] text-[#b9c1d6]">
                    L&apos;application n&apos;est pas encore publiée. Le fichier arrivera ici.
                  </p>
                )}
              </div>

              {/* Comment installer : sans ces trois lignes, Android bloque le
                  fichier et la personne croit que l'application est cassée. */}
              <ol className="grid gap-3">
                {[
                  ["Téléchargez le fichier", "depuis le téléphone où vous installerez l'application."],
                  ["Ouvrez-le", "dans vos téléchargements. Android demande d'autoriser l'installation depuis le navigateur : acceptez pour ce fichier."],
                  ["Créez votre compte", "et passez le diagnostic. Six minutes, gratuit."],
                ].map(([titre, texte], i) => (
                  <li key={titre} className="flex gap-4 border border-[rgba(232,192,112,0.14)] bg-[rgba(255,255,255,0.02)] p-4">
                    <span className="grid h-8 w-8 flex-none place-items-center bg-[rgba(212,162,63,0.16)] text-[0.85rem] font-semibold text-[var(--color-or-clair)]">
                      {i + 1}
                    </span>
                    <p className="text-[0.9rem] leading-[1.55] text-[#b9c1d6]">
                      <span className="font-semibold text-[#f4f1e8]">{titre}</span> {texte}
                    </p>
                  </li>
                ))}
              </ol>
            </div>

            <p className="mt-10 text-[0.88rem] leading-[1.7] text-[#8590aa]">
              En attendant, la bibliothèque se parcourt ici même, sans compte :{" "}
              <Link href="/bibliotheque" className="text-[var(--color-or-clair)] underline underline-offset-2">
                ouvrir le catalogue
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
