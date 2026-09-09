import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import Entete from "@/components/Entete";
import Pied from "@/components/Pied";
import { NIVEAUX, laFiche } from "@/lib/api";

type Params = { params: Promise<{ id: string }> };

/**
 * La page d'un ouvrage.
 *
 * Elle existe surtout pour être trouvée. Un site de deux pages ne capte
 * personne : quatre-vingts fiches d'ouvrage et onze fiches d'axe donnent au
 * corpus autant de portes d'entrée depuis un moteur de recherche, et chacune
 * arrive sur ce que le lecteur cherchait vraiment.
 */
export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { id } = await params;
  const f = await laFiche(id);
  if (!f) return { title: "Ouvrage introuvable" };
  const auteurs = f.auteurs.join(", ");
  const description =
    f.pedagogie.these_centrale ??
    `${f.titre}${auteurs ? `, de ${auteurs}` : ""}. Dans le corpus ASCENDA, avec ses quiz et ses citations sourcées.`;
  return {
    title: `${f.titre}${auteurs ? ` · ${auteurs}` : ""}`,
    description: description.slice(0, 300),
    openGraph: { title: f.titre, description: description.slice(0, 300), type: "book" },
  };
}

export default async function Page({ params }: Params) {
  const { id } = await params;
  const f = await laFiche(id);
  if (!f) notFound();

  const auteurs = f.auteurs.join(", ");
  const niveau = f.pedagogie.niveau ? NIVEAUX[f.pedagogie.niveau] : null;
  const idees = (f.pedagogie.idees_force ?? [])
    .map((i) => (typeof i === "string" ? i : ((i as Record<string, string>)?.titre ?? "")))
    .filter(Boolean)
    .slice(0, 5);

  // Une fiche de livre reconnue par les moteurs. Aucune donnée inventée : ce
  // qui n'est pas connu est simplement absent du balisage.
  const balisage = {
    "@context": "https://schema.org",
    "@type": "Book",
    name: f.titre,
    ...(auteurs && { author: f.auteurs.map((n) => ({ "@type": "Person", name: n })) }),
    ...(f.annee && { datePublished: String(f.annee) }),
    ...(f.editeur && { publisher: { "@type": "Organization", name: f.editeur } }),
    ...(f.isbn && { isbn: f.isbn }),
    ...(f.pages && { numberOfPages: f.pages }),
    inLanguage: f.langue ?? "fr",
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(balisage) }}
      />
      <Entete />
      <main>
        <header className="border-b border-[rgba(232,192,112,.12)] bg-[var(--color-nuit-profond)] py-14 sm:py-20">
          <div className="cadre max-w-[820px]">
            <nav className="mb-5 flex flex-wrap gap-2 text-[.8rem]">
              <Link href="/bibliotheque" className="text-[#8590aa] hover:text-[var(--color-or-clair)]">
                Bibliothèque
              </Link>
              {f.axes.map((a) => (
                <Link
                  key={a.slug}
                  href={`/axe/${a.slug}`}
                  className="text-[var(--color-or-clair)] hover:underline"
                >
                  · {a.label}
                </Link>
              ))}
            </nav>
            <h1 className="text-[1.9rem] font-semibold leading-[1.16] text-[#f7f4ec] sm:text-[2.5rem]">
              {f.titre}
            </h1>
            {f.sous_titre && (
              <p className="mt-3 text-[1.05rem] text-[#b9c1d6]">{f.sous_titre}</p>
            )}
            {auteurs && <p className="mt-4 text-[.98rem] text-[var(--color-or-clair)]">{auteurs}</p>}
            <p className="mt-5 flex flex-wrap gap-x-5 gap-y-2 text-[.85rem] text-[#8590aa]">
              {f.annee && <span>{f.annee}</span>}
              {f.pages && <span>{f.pages} pages</span>}
              {niveau && <span>{niveau}</span>}
              {f.editeur && <span>{f.editeur}</span>}
            </p>
          </div>
        </header>

        <div className="cadre max-w-[820px] py-14">
          {f.pedagogie.these_centrale && (
            <section className="mb-12">
              <h2 className="mb-3 text-[1.35rem] font-semibold text-[var(--titre)]">
                Ce que l&apos;ouvrage soutient
              </h2>
              <p className="text-[1.02rem] leading-[1.72]">{f.pedagogie.these_centrale}</p>
            </section>
          )}

          {idees.length > 0 && (
            <section className="mb-12">
              <h2 className="mb-4 text-[1.35rem] font-semibold text-[var(--titre)]">
                Les idées force
              </h2>
              <ul className="flex flex-col gap-3">
                {idees.map((idee, i) => (
                  <li key={i} className="flex gap-3">
                    <span className="mt-[.55rem] h-[5px] w-[5px] shrink-0 rounded-full bg-[var(--accent-texte)]" />
                    <span className="leading-[1.68]">{idee}</span>
                  </li>
                ))}
              </ul>
            </section>
          )}

          <section className="mb-12">
            <h2 className="mb-4 text-[1.35rem] font-semibold text-[var(--titre)]">
              Ce qu&apos;ASCENDA en a préparé
            </h2>
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
              <Compteur valeur={f.contenu.chapitres} libelle="chapitres" />
              <Compteur valeur={f.contenu.questions} libelle="questions" />
              <Compteur valeur={f.contenu.citations} libelle="citations" />
              <Compteur valeur={f.contenu.lots_quiz} libelle="lots de quiz" />
            </div>
          </section>

          <section className="mb-12 rounded-[var(--radius-carte)] border border-[var(--trait)] bg-[var(--fond-creux)] p-6">
            <h2 className="mb-2 text-[1.05rem] font-semibold text-[var(--titre)]">
              {f.droits.lecture_integrale ? "Lecture intégrale" : "Extraits cités"}
            </h2>
            <p className="text-[.94rem] leading-[1.68] text-[var(--texte-doux)]">
              {f.droits.message}{" "}
              <Link href="/droits" className="text-[var(--accent-texte)] underline underline-offset-2">
                Comment nous traitons les droits
              </Link>
              .
            </p>
          </section>

          <Link
            href="/commencer"
            className="inline-flex items-center justify-center rounded-full bg-[var(--color-or)] px-7 py-3.5 text-[.98rem] font-medium text-[#1a1400] transition-colors hover:bg-[var(--color-or-clair)]"
          >
            Mettre cet ouvrage dans mon plan
          </Link>
        </div>
      </main>
      <Pied />
    </>
  );
}

function Compteur({ valeur, libelle }: { valeur: number; libelle: string }) {
  return (
    <div>
      <div className="font-[family-name:var(--font-titre)] text-[1.7rem] font-semibold tabular-nums text-[var(--accent-texte)]">
        {valeur}
      </div>
      <div className="text-[.82rem] text-[var(--texte-doux)]">{libelle}</div>
    </div>
  );
}
