import Bouton from "./Bouton";
import { Carreaux, Voile } from "./Formes";
import { lesTarifs, montant } from "@/lib/api";

const FORMULES = [
  {
    code: "free",
    nom: "Découverte",
    prix: "Gratuit",
    detail: "Sans carte bancaire",
    resume: "De quoi lire sérieusement, sans rien payer.",
    inclus: [
      "La bibliothèque de base, 78 ouvrages",
      "Un axe et un chronogramme",
      "Les quiz déjà préparés, avec leurs justificatifs",
      "20 questions par jour à l'agent",
      "Notes, surlignages et glossaire",
    ],
    exclus: ["Vos propres documents", "Replanification automatique"],
    mise_en_avant: false,
  },
  {
    code: "premium",
    nom: "Ascension",
    prix: null,
    detail: null,
    resume: "Quand la lecture devient un travail suivi.",
    inclus: [
      "Tout ce que contient Découverte",
      "Vos propres documents, importés et indexés",
      "Axes et chronogrammes illimités",
      "Chronogramme adaptatif : le plan se recompose",
      "Synthèses et quiz à la demande, à votre niveau",
      "Export PDF et reconnaissance de texte sur les scans",
    ],
    exclus: [],
    mise_en_avant: true,
  },
];

function Coche({ actif }: { actif: boolean }) {
  return (
    <svg viewBox="0 0 16 16" className="mt-[3px] h-4 w-4 shrink-0" aria-hidden="true">
      {actif ? (
        <path
          d="m3.5 8.5 3 3 6-7"
          fill="none"
          stroke="var(--color-sauge)"
          strokeWidth="1.8"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      ) : (
        <path
          d="M4 8h8"
          fill="none"
          stroke="var(--texte-doux)"
          strokeWidth="1.8"
          strokeLinecap="round"
          opacity="0.55"
        />
      )}
    </svg>
  );
}

export default async function Tarifs() {
  const grille = await lesTarifs();
  const mensuel =
    grille.formules.find((f) => f.periode_mois === 1) ?? grille.formules[0];
  return (
    <section id="tarifs" className="relative overflow-hidden bg-[var(--fond-creux)] py-24">
      <Carreaux pas={40} />
      <Voile teinte="#d4a23f" opacite={0.16} className="left-1/2 top-[-14%] h-[440px] w-[760px] -translate-x-1/2" />
      <Voile teinte="#6f8f57" opacite={0.1} className="bottom-[-14%] left-[-8%] h-[400px] w-[540px]" />

      <div className="cadre relative">
        <div className="mx-auto max-w-[56ch] text-center">
          <p className="oeil">Deux formules</p>
          <h2 className="mt-3 text-[2.1rem] font-semibold leading-tight sm:text-[2.5rem]">
            La gratuite n&apos;est pas une démonstration
          </h2>
          <p className="mt-4 text-[1.02rem] leading-[1.72] text-[var(--texte-doux)]">
            Elle donne accès au corpus entier et à un parcours complet. Ce qui coûte,
            c&apos;est d&apos;importer et d&apos;indexer vos propres documents : c&apos;est ce que
            l&apos;abonnement finance.
          </p>
        </div>

        <div className="mx-auto mt-14 grid max-w-[900px] gap-6 md:grid-cols-2">
          {FORMULES.map((f) => (
            <div
              key={f.code}
              className={`flex min-w-0 flex-col rounded-none bg-[var(--surface)] p-6 sm:p-8 ${
                f.mise_en_avant
                  ? "border-2 border-[var(--color-or)] shadow-[var(--shadow-flottante)]"
                  : "border border-[var(--trait)] shadow-[var(--shadow-douce)]"
              }`}
            >
              <div className="flex items-baseline justify-between gap-3">
                <h3 className="text-[1.42rem] font-semibold">{f.nom}</h3>
                {f.mise_en_avant && (
                  <span className="rounded-none bg-[rgba(212,162,63,0.14)] px-3 py-1 text-[0.7rem] font-semibold uppercase tracking-wider text-[var(--accent-texte)]">
                    Recommandé
                  </span>
                )}
              </div>
              <p className="mt-1 text-[0.92rem] text-[var(--texte-doux)]">{f.resume}</p>

              <div className="mt-6 border-y border-[var(--trait)] py-5">
                {f.code === "free" ? (
                  <>
                    <p className="font-[family-name:var(--font-titre)] text-[1.7rem] font-semibold">
                      {f.prix}
                    </p>
                    <p className="mt-0.5 text-[0.82rem] text-[var(--texte-doux)]">{f.detail}</p>
                  </>
                ) : (
                  <>
                    <p className="font-[family-name:var(--font-titre)] text-[1.7rem] font-semibold">
                      {montant(mensuel.montant, mensuel.devise)}
                      <span className="ml-1.5 text-[0.92rem] font-normal text-[var(--texte-doux)]">
                        par mois
                      </span>
                    </p>
                    <div className="mt-3 flex flex-wrap gap-2">
                      {grille.formules
                        .filter((t) => t.periode_mois > 1)
                        .map((t) => (
                          <span
                            key={t.periode_mois}
                            className="rounded-none bg-[var(--fond-creux)] px-3 py-1.5 text-[0.78rem] text-[var(--texte-doux)]"
                          >
                            {t.periode_mois} mois : {montant(t.montant, t.devise)}
                            <span className="ml-1.5 text-[var(--accent-texte)]">
                              soit {montant(t.par_mois, t.devise)} par mois
                            </span>
                          </span>
                        ))}
                    </div>
                  </>
                )}
              </div>

              <ul className="mt-6 space-y-3">
                {f.inclus.map((i) => (
                  <li key={i} className="flex gap-2.5 text-[0.92rem] leading-[1.55]">
                    <Coche actif />
                    <span>{i}</span>
                  </li>
                ))}
                {f.exclus.map((i) => (
                  <li
                    key={i}
                    className="flex gap-2.5 text-[0.92rem] leading-[1.55] text-[var(--texte-doux)]"
                  >
                    <Coche actif={false} />
                    <span>{i}</span>
                  </li>
                ))}
              </ul>

              <div className="mt-8 pt-2">
                <Bouton
                  href={f.code === "free" ? "/commencer" : "/commencer?formule=ascension"}
                  variante={f.mise_en_avant ? "or" : "clair"}
                  taille="grand"
                >
                  {f.code === "free" ? "Commencer gratuitement" : "Passer à Ascension"}
                </Bouton>
              </div>
            </div>
          ))}
        </div>

        {/* Moyens de paiement : les nommer rassure autant que le prix. */}
        <div className="mx-auto mt-12 max-w-[900px]">
          <p className="text-center text-[0.82rem] uppercase tracking-[0.14em] text-[var(--texte-doux)]">
            Paiement
          </p>
          <div className="mt-5 flex flex-wrap items-stretch justify-center gap-3">
            {grille.moyens.map((m) => (
              <div
                key={m.code}
                className="flex min-w-[220px] flex-1 items-center gap-3 rounded-none border border-[var(--trait)] bg-[var(--surface)] px-4 py-3.5"
              >
                <span
                  aria-hidden
                  className="flex h-9 w-9 shrink-0 items-center justify-center rounded-none text-[0.78rem] font-bold"
                  style={{
                    background: m.code === "mtn" ? "#FFCC00" : "#FF7900",
                    color: m.code === "mtn" ? "#1a1400" : "#fff",
                  }}
                >
                  {m.code === "mtn" ? "MTN" : "OM"}
                </span>
                <div className="min-w-0">
                  <p className="text-[0.92rem] font-semibold leading-tight">{m.libelle}</p>
                  <p className="text-[0.78rem] text-[var(--texte-doux)]">{m.operateur}</p>
                </div>
              </div>
            ))}
          </div>
          <p className="mt-5 text-center text-[0.84rem] leading-[1.7] text-[var(--texte-doux)]">
            Le paiement se valide sur votre téléphone, avec votre code mobile money.
            Aucune carte bancaire, aucun compte à créer ailleurs. Votre abonnement
            s&apos;arrête de lui-même à échéance : rien n&apos;est prélevé sans que
            vous le décidiez.
          </p>
        </div>
      </div>
    </section>
  );
}
