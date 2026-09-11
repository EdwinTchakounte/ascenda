import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import Entete from "@/components/Entete";
import IconeAxe from "@/components/IconesAxes";
import Pied from "@/components/Pied";
import { NIVEAUX, heures, laFicheAxe, parNiveau } from "@/lib/api";

type Params = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { slug } = await params;
  const a = await laFicheAxe(slug);
  if (!a) return { title: "Axe introuvable" };
  const description =
    a.description ??
    `${a.ouvrages.length} ouvrages sur ${a.label.toLowerCase()}, dans l'ordre où les lire.`;
  return {
    title: a.label,
    description: description.slice(0, 300),
    openGraph: { title: a.label, description: description.slice(0, 300) },
  };
}

export default async function Page({ params }: Params) {
  const { slug } = await params;
  const a = await laFicheAxe(slug);
  if (!a) notFound();

  const ouvrages = parNiveau(a.ouvrages);
  const pages = ouvrages.reduce((s, o) => s + (o.pages ?? 0), 0);
  const minutes = ouvrages.reduce((s, o) => s + (o.duree_min ?? 0), 0);

  return (
    <>
      <Entete />
      <main>
        <header className="border-b border-[rgba(232,192,112,.12)] bg-[var(--color-nuit-profond)] py-14 sm:py-20">
          <div className="cadre max-w-[820px]">
            <Link href="/bibliotheque" className="text-[.8rem] text-[#8590aa] hover:text-[var(--color-or-clair)]">
              Bibliothèque
            </Link>
            <div className="mt-5 flex items-center gap-4">
              <IconeAxe slug={a.slug} className="h-9 w-9 shrink-0 text-[var(--color-or-clair)]" />
              <h1 className="text-[1.9rem] font-semibold leading-[1.14] text-[#f7f4ec] sm:text-[2.4rem]">
                {a.label}
              </h1>
            </div>
            {a.description && (
              <p className="mt-5 max-w-[58ch] text-[1.02rem] leading-[1.72] text-[#b9c1d6]">
                {a.description}
              </p>
            )}
            <p className="mt-6 flex flex-wrap gap-x-6 gap-y-2 text-[.85rem] text-[#8590aa]">
              <span>{ouvrages.length} ouvrages</span>
              <span>{pages.toLocaleString("fr-FR")} pages</span>
              {minutes > 0 && <span>{heures(minutes)} de lecture</span>}
            </p>
          </div>
        </header>

        <div className="cadre max-w-[820px] py-14">
          <h2 className="text-[1.35rem] font-semibold text-[var(--titre)]">
            Dans quel ordre
          </h2>
          {/* L'ordre est l'information. Un axe qui listerait ses ouvrages par
              ordre alphabétique ne serait qu'un rayon de bibliothèque. */}
          <p className="mt-2 max-w-[62ch] text-[.94rem] leading-[1.68] text-[var(--texte-doux)]">
            Du plus accessible au plus exigeant. C&apos;est l&apos;ordre que suit le
            chronogramme, et il compte autant que la liste elle-même.
          </p>

          <ol className="mt-8 flex flex-col">
            {ouvrages.map((o, i) => (
              <li key={o.id} className="border-b border-[var(--trait)] last:border-0">
                <Link
                  href={`/ouvrage/${o.id}`}
                  className="flex gap-4 py-4 transition-colors hover:bg-[var(--fond-creux)]"
                >
                  <span className="w-7 shrink-0 text-right font-[family-name:var(--font-titre)] text-[1.05rem] tabular-nums text-[var(--texte-doux)]">
                    {i + 1}
                  </span>
                  <span className="min-w-0">
                    <span className="block font-medium leading-snug">{o.titre}</span>
                    {o.auteurs.length > 0 && (
                      <span className="mt-1 block text-[.86rem] text-[var(--texte-doux)]">
                        {o.auteurs.join(", ")}
                      </span>
                    )}
                    <span className="mt-1 block text-[.8rem] text-[var(--texte-doux)]">
                      {[
                        o.niveau ? NIVEAUX[o.niveau] : null,
                        o.pages ? `${o.pages} pages` : null,
                        o.lecture_integrale ? null : "extraits",
                      ]
                        .filter(Boolean)
                        .join("  ·  ")}
                    </span>
                  </span>
                </Link>
              </li>
            ))}
          </ol>

          <Link
            href="/commencer"
            className="mt-10 inline-flex items-center justify-center rounded-none bg-[var(--color-or)] px-7 py-3.5 text-[.98rem] font-medium text-[#1a1400] transition-colors hover:bg-[var(--color-or-clair)]"
          >
            Construire mon plan sur cet axe
          </Link>
        </div>
      </main>
      <Pied />
    </>
  );
}
