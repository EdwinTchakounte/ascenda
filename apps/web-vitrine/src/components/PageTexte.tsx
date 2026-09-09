import Entete from "./Entete";
import Pied from "./Pied";

/**
 * Le gabarit des pages de texte : mentions légales, droits, confidentialité.
 *
 * Elles n'ont pas besoin d'un hero animé ni de photographies. Elles ont besoin
 * d'être lisibles jusqu'au bout, donc d'une colonne étroite, d'un interlignage
 * généreux et de rien d'autre.
 */
export default function PageTexte({
  oeil,
  titre,
  chapeau,
  children,
}: {
  oeil?: string;
  titre: string;
  chapeau?: string;
  children: React.ReactNode;
}) {
  return (
    <>
      <Entete />
      <main>
        <header className="border-b border-[var(--trait)] bg-[var(--fond-creux)] py-16 sm:py-20">
          <div className="cadre max-w-[760px]">
            {oeil && <p className="oeil mb-3">{oeil}</p>}
            <h1 className="text-[2rem] font-semibold leading-[1.15] text-[var(--titre)] sm:text-[2.6rem]">
              {titre}
            </h1>
            {chapeau && (
              <p className="mt-5 max-w-[58ch] text-[1.02rem] leading-[1.72] text-[var(--texte-doux)]">
                {chapeau}
              </p>
            )}
          </div>
        </header>

        <div className="cadre max-w-[760px] py-14 sm:py-20">
          <div className="prose-ascenda">{children}</div>
        </div>
      </main>
      <Pied />
    </>
  );
}

/** Une section de page de texte : un titre, puis du texte. */
export function Bloc({ titre, children }: { titre: string; children: React.ReactNode }) {
  return (
    <section className="mb-12 last:mb-0">
      <h2 className="mb-4 text-[1.35rem] font-semibold leading-snug text-[var(--titre)]">
        {titre}
      </h2>
      {children}
    </section>
  );
}

/**
 * Ce qui reste à renseigner, dit en clair sur la page plutôt que caché dans un
 * commentaire de code. Tant que ce bandeau s'affiche, la page n'est pas prête
 * pour une mise en ligne publique.
 */
export function ARenseigner({ quoi }: { quoi: string }) {
  return (
    <p className="my-4 rounded-[var(--radius-douce)] border border-dashed border-[var(--color-terracotta)] bg-[rgba(196,112,79,0.07)] px-4 py-3 text-[0.9rem] leading-[1.6] text-[var(--texte)]">
      <strong className="font-semibold">À renseigner avant la mise en ligne :</strong> {quoi}
    </p>
  );
}
