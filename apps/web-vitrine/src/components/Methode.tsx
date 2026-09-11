import { Carreaux, Eclats, Voile } from "./Formes";

const ETAPES = [
  {
    n: "01",
    titre: "Vous dites où vous en êtes",
    texte:
      "Dix questions. Six sur votre situation : le temps dont vous disposez vraiment, votre objectif, votre aisance devant un texte d'idées. Quatre tirées des ouvrages eux-mêmes, parce qu'on se surestime ou se sous-estime toujours un peu.",
  },
  {
    n: "02",
    titre: "ASCENDA construit votre chronogramme",
    texte:
      "Des séances datées, d'une durée que vous tenez, réparties sur des jours espacés. Chaque séance nomme l'ouvrage, le chapitre et les pages. Aucun modèle de langage n'intervient : le plan doit être reproductible et explicable.",
  },
  {
    n: "03",
    titre: "Vous lisez, l'agent répond, le plan s'adapte",
    texte:
      "Un quiz à la fin de chaque séance, corrigé avec l'extrait du livre qui justifie la réponse. Ce que vous ratez revient en révision espacée. Et quand vous prenez du retard, le plan se recompose au lieu de vous accabler.",
  },
];

export default function Methode() {
  return (
    <section id="methode" className="relative overflow-hidden bg-[var(--fond-creux)] py-24">
      <Carreaux pas={56} masque="radial-gradient(ellipse 60% 70% at 50% 30%, #000 10%, transparent 76%)" />
      <Voile teinte="#4a6fa5" opacite={0.11} className="left-[-10%] top-[-12%] h-[440px] w-[600px]" />
      <Voile teinte="#d4a23f" opacite={0.12} className="bottom-[-16%] right-[-6%] h-[420px] w-[560px]" />
      <Eclats teintes={["#4a6fa5", "#d4a23f", "#6f8f57"]} />

      <div className="cadre relative">
        <div className="mx-auto max-w-[58ch] text-center">
          <p className="oeil">La méthode</p>
          <h2 className="mt-3 text-[2.1rem] font-semibold leading-tight sm:text-[2.5rem]">
            Trois étapes, et la première est la vôtre
          </h2>
        </div>

        <ol className="mt-14 grid gap-8 md:grid-cols-3">
          {ETAPES.map((e) => (
            <li key={e.n} className="relative">
              <div className="flex items-baseline gap-3">
                <span className="font-[family-name:var(--font-titre)] text-[2.4rem] font-semibold leading-none text-[rgba(212,162,63,0.32)]">
                  {e.n}
                </span>
                <span className="h-px flex-1 bg-[var(--trait)]" />
              </div>
              <h3 className="mt-5 text-[1.18rem] font-semibold leading-snug">{e.titre}</h3>
              <p className="mt-3 text-[0.95rem] leading-[1.75] text-[var(--texte-doux)]">
                {e.texte}
              </p>
            </li>
          ))}
        </ol>
      </div>
    </section>
  );
}
