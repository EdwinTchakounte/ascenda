import { Voile } from "./Formes";

/**
 * Le chronogramme en détail : une maquette d'écran, trois annotations.
 * Les données affichées sortent d'un plan réellement généré par l'API.
 */
const ANNOTATIONS = [
  {
    titre: "Des pages, pas des pourcentages",
    texte: "« p. 46 à 55 » est une consigne qu'on peut suivre sur son exemplaire papier.",
  },
  {
    titre: "Une durée que vous tenez",
    texte: "Les chapitres trop courts sont regroupés, les trop longs découpés.",
  },
  {
    titre: "Le retard se rattrape",
    texte: "Le plan se recompose sur les séances restantes, sans effacer l'historique.",
  },
];

const LIGNES = [
  { jour: "Sam. 29 août", duree: 21, titre: "Comment l'IA transformera notre avenir", detail: "Introduction, p. 7-27", etat: "fait" },
  { jour: "Lun. 31 août", duree: 21, titre: "Comment l'IA transformera notre avenir", detail: "Résumé et 1 chapitre suivant, p. 28-34", etat: "fait" },
  { jour: "Mar. 1 sept.", duree: 28, titre: "La guerre des intelligences à l'heure de ChatGPT", detail: "2. La science-fiction, p. 46-55", etat: "aujourdhui" },
  { jour: "Mer. 2 sept.", duree: 42, titre: "La Vie algorithmique", detail: "3. Philosophes et mathématiciens, p. 61-75", etat: "a_venir" },
  { jour: "Jeu. 3 sept.", duree: 25, titre: "L'intelligence artificielle n'existe pas", detail: "Préambule, p. 36-45", etat: "a_venir" },
];

export default function Produit() {
  return (
    <section className="relative overflow-hidden bg-[var(--fond)] py-24">
      <Voile teinte="#9e6b8a" opacite={0.1} className="right-[-10%] top-[4%] h-[460px] w-[580px]" />
      <Voile teinte="#4f8687" opacite={0.1} className="bottom-[-12%] left-[-8%] h-[420px] w-[560px]" />

      <div className="cadre relative">
        <div className="mx-auto max-w-[58ch] text-center">
          <p className="oeil">Le chronogramme</p>
          <h2 className="mt-3 text-[2.1rem] font-semibold leading-tight sm:text-[2.5rem]">
            Un plan qu&apos;on peut réellement suivre
          </h2>
        </div>

        <div className="mt-14 grid gap-10 lg:grid-cols-[1.55fr_1fr] lg:items-center">
          {/* Cadre de navigateur */}
          <div className="overflow-hidden rounded-none border border-[var(--trait)] bg-[var(--surface)] shadow-[var(--shadow-flottante)]">
            <div className="flex items-center gap-2 border-b border-[var(--trait)] bg-[var(--fond-creux)] px-4 py-3">
              <span className="h-2.5 w-2.5 rounded-none bg-[rgba(196,112,79,0.5)]" />
              <span className="h-2.5 w-2.5 rounded-none bg-[rgba(212,162,63,0.5)]" />
              <span className="h-2.5 w-2.5 rounded-none bg-[rgba(124,154,130,0.5)]" />
              <span className="ml-3 text-[0.74rem] text-[var(--texte-doux)]">
                ascenda · Mon chronogramme
              </span>
            </div>

            <div className="p-5 sm:p-7">
              <div className="mb-5 flex flex-wrap items-baseline justify-between gap-3">
                <div>
                  <h3 className="text-[1.24rem] font-semibold">IA, société et éthique</h3>
                  <p className="mt-1 text-[0.82rem] text-[var(--texte-doux)]">
                    70 séances · 5 par semaine · 31 h 40 de lecture
                  </p>
                </div>
                <span className="rounded-none bg-[rgba(196,112,79,0.12)] px-3 py-1 text-[0.74rem] font-medium text-[var(--color-terracotta)]">
                  2 séances de retard
                </span>
              </div>

              <ul className="divide-y divide-[var(--trait)]">
                {LIGNES.map((l) => {
                  const actif = l.etat === "aujourdhui";
                  const fait = l.etat === "fait";
                  return (
                    <li
                      key={l.jour}
                      className={`flex items-center gap-4 py-3.5 ${actif ? "-mx-3 rounded-none bg-[rgba(212,162,63,0.08)] px-3" : ""}`}
                    >
                      <span
                        className={`w-[92px] shrink-0 text-[0.78rem] ${
                          actif
                            ? "font-semibold text-[var(--accent-texte)]"
                            : "text-[var(--texte-doux)]"
                        }`}
                      >
                        {l.jour}
                      </span>
                      <span
                        className={`h-2 w-2 shrink-0 rounded-none ${
                          fait
                            ? "bg-[var(--color-sauge)]"
                            : actif
                              ? "bg-[var(--color-or)]"
                              : "bg-[var(--trait)]"
                        }`}
                      />
                      <div className="min-w-0 flex-1">
                        <p
                          className={`truncate text-[0.92rem] ${
                            fait ? "text-[var(--texte-doux)]" : "font-medium"
                          }`}
                        >
                          {l.titre}
                        </p>
                        <p className="truncate text-[0.78rem] text-[var(--texte-doux)]">{l.detail}</p>
                      </div>
                      <span className="shrink-0 text-[0.78rem] tabular-nums text-[var(--texte-doux)]">
                        {l.duree} min
                      </span>
                    </li>
                  );
                })}
              </ul>
            </div>
          </div>

          <ul className="space-y-7">
            {ANNOTATIONS.map((a) => (
              <li key={a.titre} className="border-l-2 border-[rgba(212,162,63,0.45)] pl-5">
                <h4 className="text-[1.02rem] font-semibold">{a.titre}</h4>
                <p className="mt-1.5 text-[0.92rem] leading-[1.7] text-[var(--texte-doux)]">
                  {a.texte}
                </p>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}
