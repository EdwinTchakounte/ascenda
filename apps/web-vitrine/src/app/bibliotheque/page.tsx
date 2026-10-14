import Link from "next/link";
import Entete from "@/components/Entete";
import { Carreaux, Voile } from "@/components/Formes";
import Pied from "@/components/Pied";
import IconeAxe from "@/components/IconesAxes";
import { heures, lesAxes, lesOuvrages, type Ouvrage } from "@/lib/api";

export const metadata = {
  title: "Bibliothèque ASCENDA",
  description:
    "79 ouvrages classés en 17 axes : intelligence artificielle, pensée africaine, littérature, économie, sciences.",
};

const NIVEAUX: Record<string, string> = {
  debutant: "Débutant",
  intermediaire: "Intermédiaire",
  avance: "Avancé",
};

function Carte({ o }: { o: Ouvrage }) {
  // La carte entière est un lien : afficher une fiche sans pouvoir l'ouvrir
  // était le seul cul-de-sac qui restait sur la bibliothèque.
  //
  // Le liseré de gauche porte la teinte du pôle, la même que sur les cartes de
  // parcours et que le dos des volumes de l'étagère. Une grille de soixante
  // cartes blanches ne dit pas de quoi elle est faite ; une grille de soixante
  // liserés colorés se lit d'un coup d'oeil.
  const teinte = o.axes[0] ? `axe-${o.axes[0].slug.slice(0, 2)}` : "";
  return (
    <li className={`${teinte} group relative flex flex-col rounded-none border border-[var(--trait)] bg-[var(--surface)] transition-all duration-200 hover:-translate-y-0.5 hover:border-[rgba(212,162,63,0.4)] hover:shadow-[var(--shadow-douce)]`}>
     <span
       aria-hidden
       className="absolute inset-y-0 left-0 w-[3px] opacity-70 transition-opacity duration-200 group-hover:opacity-100"
       style={{ background: "var(--teinte, transparent)" }}
     />
     <Link href={`/ouvrage/${o.id}`} className="flex flex-1 flex-col p-5 pl-6">
      <div className="flex items-start justify-between gap-3">
        <h3 className="text-[1rem] font-semibold leading-snug">{o.titre}</h3>
        {!o.lecture_integrale && (
          <span
            title="Ouvrage non redistribuable : ASCENDA en cite des extraits avec leur page."
            className="mt-0.5 shrink-0 rounded-none bg-[var(--fond-creux)] px-2 py-0.5 text-[0.66rem] font-medium text-[var(--texte-doux)]"
          >
            extraits
          </span>
        )}
      </div>

      {o.auteurs.length > 0 && (
        <p className="mt-1.5 text-[0.85rem] text-[var(--texte-doux)]">
          {o.auteurs.slice(0, 2).join(", ")}
          {o.auteurs.length > 2 && " et al."}
          {o.annee ? ` · ${o.annee}` : ""}
        </p>
      )}

      {o.these && (
        <p className="mt-3 line-clamp-3 text-[0.86rem] leading-[1.62] text-[var(--texte-doux)]">
          {o.these}
        </p>
      )}

      <div className="mt-auto flex flex-wrap items-center gap-1.5 pt-4">
        {o.niveau && (
          <span className="rounded-none bg-[var(--fond-creux)] px-2.5 py-1 text-[0.72rem] text-[var(--texte-doux)]">
            {NIVEAUX[o.niveau] ?? o.niveau}
          </span>
        )}
        {o.duree_min ? (
          <span className="rounded-none bg-[var(--fond-creux)] px-2.5 py-1 text-[0.72rem] text-[var(--texte-doux)]">
            {heures(o.duree_min)}
          </span>
        ) : null}
        {o.pages ? (
          <span className="rounded-none bg-[var(--fond-creux)] px-2.5 py-1 text-[0.72rem] text-[var(--texte-doux)]">
            {o.pages} p.
          </span>
        ) : null}
      </div>
     </Link>
    </li>
  );
}

export default async function Bibliotheque({
  searchParams,
}: {
  searchParams: Promise<{ axe?: string }>;
}) {
  const { axe } = await searchParams;
  const [axes, resultat] = await Promise.all([
    lesAxes(),
    lesOuvrages(axe ? { axe } : {}),
  ]);
  const axeActif = axes.find((a) => a.slug === axe);
  const indisponible = resultat.ouvrages.length === 0;

  return (
    <>
      <Entete />
      <main className="min-h-[70vh] bg-[var(--fond)] pb-24">
        <div className="relative overflow-hidden border-b border-[var(--trait)] bg-[var(--fond-creux)] py-14">
          <Carreaux pas={48} masque="linear-gradient(180deg, #000 0%, transparent 92%)" />
          <Voile teinte="#8a7f9e" opacite={0.12} className="right-[-6%] top-[-36%] h-[380px] w-[520px]" />
          <Voile teinte="#6f8f57" opacite={0.1} className="bottom-[-44%] left-[-6%] h-[340px] w-[460px]" />
          <div className="cadre">
            <p className="oeil">Bibliothèque</p>
            <h1 className="mt-3 text-[2.2rem] font-semibold leading-tight sm:text-[2.6rem]">
              {axeActif ? axeActif.label : "79 ouvrages, 17 parcours"}
            </h1>
            <p className="mt-3 max-w-[64ch] text-[1rem] leading-[1.7] text-[var(--texte-doux)]">
              {axeActif
                ? `${axeActif.nb_ouvrages} ouvrages · ${axeActif.nb_pages.toLocaleString("fr-FR")} pages · ${heures(axeActif.duree_estimee_min)} de lecture.`
                : "Chaque ouvrage porte son niveau, sa durée de lecture et sa thèse centrale. Les titres non redistribuables sont cités, jamais reproduits."}
            </p>
          </div>
        </div>

        <div className="cadre">
          {/* Filtres par axe, en pilules */}
          <nav aria-label="Filtrer par axe" className="flex flex-wrap gap-2 py-8">
            <Link
              href="/bibliotheque"
              className={`rounded-none border px-4 py-2 text-[0.85rem] transition-colors ${
                !axe
                  ? "border-[var(--color-or)] bg-[rgba(212,162,63,0.1)] font-medium text-[var(--accent-texte)]"
                  : "border-[var(--trait)] text-[var(--texte-doux)] hover:border-[rgba(212,162,63,0.4)]"
              }`}
            >
              Tous
            </Link>
            {axes.map((a) => (
              <Link
                key={a.slug}
                href={`/bibliotheque?axe=${a.slug}`}
                className={`flex items-center gap-2 rounded-none border px-4 py-2 text-[0.85rem] transition-colors ${
                  axe === a.slug
                    ? "border-[var(--color-or)] bg-[rgba(212,162,63,0.1)] font-medium text-[var(--accent-texte)]"
                    : "border-[var(--trait)] text-[var(--texte-doux)] hover:border-[rgba(212,162,63,0.4)]"
                }`}
              >
                <IconeAxe slug={a.slug} className="h-4 w-4" />
                {a.label}
                <span className="opacity-55">{a.nb_ouvrages}</span>
              </Link>
            ))}
          </nav>

          {indisponible ? (
            /* État vide honnête : on ne fait pas croire que le corpus est vide. */
            <div className="rounded-none border border-dashed border-[var(--trait)] px-8 py-16 text-center">
              <h2 className="text-[1.2rem] font-semibold">Le catalogue n&apos;a pas pu être chargé</h2>
              <p className="mx-auto mt-3 max-w-[52ch] text-[0.94rem] leading-[1.7] text-[var(--texte-doux)]">
                La bibliothèque est servie par l&apos;API ASCENDA, qui ne répond pas pour le
                moment. Les {axes.length} axes ci-dessus restent consultables et le
                corpus, lui, est intact.
              </p>
            </div>
          ) : (
            <>
              <p className="mb-5 text-[0.86rem] text-[var(--texte-doux)]">
                {resultat.total} ouvrage{resultat.total > 1 ? "s" : ""}
              </p>
              <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {resultat.ouvrages.map((o) => (
                  <Carte key={o.id} o={o} />
                ))}
              </ul>
            </>
          )}
        </div>
      </main>
      <Pied />
    </>
  );
}
