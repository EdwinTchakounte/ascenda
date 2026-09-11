import Link from "next/link";

import Entete from "@/components/Entete";
import Pied from "@/components/Pied";
import { APPLICATION } from "@/lib/editeur";

export const metadata = {
  title: "Se connecter à ASCENDA",
  description: "Votre compte, votre chronogramme et vos notes vivent dans l'application.",
};

export default function Connexion() {
  return (
    <>
      <Entete />
      <main className="cadre max-w-[560px] py-20 sm:py-28">
        <p className="oeil mb-3">Votre compte</p>
        <h1 className="text-[1.9rem] font-semibold leading-[1.18] text-[var(--titre)] sm:text-[2.3rem]">
          La connexion se fait dans l&apos;application
        </h1>
        <p className="mt-5 text-[1rem] leading-[1.74] text-[var(--texte-doux)]">
          Votre chronogramme, vos quiz, vos notes et votre progression y sont conservés. Ce
          site n&apos;héberge pas de session : il n&apos;a rien à savoir de vous.
        </p>

        <div className="mt-9 flex flex-wrap gap-3">
          {APPLICATION.web && (
            <a
              href={APPLICATION.web}
              className="inline-flex items-center justify-center rounded-none bg-[var(--color-or)] px-7 py-3.5 text-[0.98rem] font-medium text-[#1a1400] transition-colors hover:bg-[var(--color-or-clair)]"
            >
              Ouvrir l&apos;application
            </a>
          )}
          <Link
            href="/commencer"
            className="inline-flex items-center justify-center rounded-none border border-[var(--trait)] bg-[var(--surface)] px-7 py-3.5 text-[0.98rem] font-medium text-[var(--titre)] transition-colors hover:border-[rgba(212,162,63,0.5)]"
          >
            {APPLICATION.web ? "Je n'ai pas encore de compte" : "Comment commencer"}
          </Link>
        </div>

        {/* Ce paragraphe disait que la réinitialisation n'existait pas et
            renvoyait au formulaire de contact. Elle existe depuis, dans l'API
            comme dans l'application : la page envoyait donc les gens écrire
            pour un bouton qu'ils avaient sous les yeux. */}
        <p className="mt-10 text-[0.88rem] leading-[1.7] text-[var(--texte-doux)]">
          Mot de passe perdu ? L&apos;application vous le réinitialise :
          « J&apos;ai oublié mon mot de passe » sur l&apos;écran de connexion vous envoie un
          lien par courriel. Si l&apos;adresse du compte ne vous appartient plus,{" "}
          <Link href="/contact" className="text-[var(--accent-texte)] underline underline-offset-2">
            écrivez-nous
          </Link>{" "}
          et nous rouvrons votre accès.
        </p>
      </main>
      <Pied />
    </>
  );
}
