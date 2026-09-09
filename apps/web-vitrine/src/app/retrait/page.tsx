import Link from "next/link";

import PageTexte, { Bloc } from "@/components/PageTexte";
import { EDITEUR } from "@/lib/editeur";

export const metadata = {
  title: "Demande de retrait",
  description:
    "La marche à suivre pour un ayant droit qui souhaite qu'un ouvrage soit retiré du corpus ASCENDA.",
};

export default function Page() {
  return (
    <PageTexte
      oeil="Ayants droit"
      titre="Demander le retrait d'un ouvrage"
      chapeau="Si vous détenez des droits sur un ouvrage du corpus et souhaitez qu'il en sorte, voici la marche à suivre et ce que nous nous engageons à faire."
    >
      <Bloc titre="Ce qu'il nous faut">
        <p>Un seul message, à un seul endroit, contenant :</p>
        <ul>
          <li>le titre et l&apos;auteur de l&apos;ouvrage, tels qu&apos;ils apparaissent sur la
            page de notre bibliothèque, avec son adresse ;</li>
          <li>la qualité qui vous permet d&apos;en disposer : auteur, éditeur, cessionnaire,
            mandataire ;</li>
          <li>ce que vous demandez : le retrait complet, ou l&apos;abaissement du plafond de
            citation ;</li>
          <li>un moyen de vous répondre.</li>
        </ul>
        <p>
          Adresse : <a href={`mailto:${EDITEUR.courriel}`}>{EDITEUR.courriel}</a>, avec{" "}
          <strong>« retrait »</strong> en objet.
        </p>
      </Bloc>

      <Bloc titre="Ce que nous faisons">
        <ol>
          <li>
            <strong>Accusé de réception sous 72 heures.</strong> Il vous donne le nom de la
            personne qui traite la demande.
          </li>
          <li>
            <strong>Retrait de l&apos;affichage pendant l&apos;examen.</strong> Nous ne
            laissons pas un ouvrage contesté visible le temps de la discussion. La bascule est
            immédiate : l&apos;ouvrage disparaît de la bibliothèque, des recherches, des
            réponses de l&apos;agent, et des plans de lecture déjà construits.
          </li>
          <li>
            <strong>Réponse motivée sous 15 jours.</strong> Soit le retrait est confirmé et
            devient définitif, soit nous exposons pourquoi nous estimons l&apos;usage couvert,
            et vous gardez naturellement toute voie de recours.
          </li>
        </ol>
      </Bloc>

      <Bloc titre="Pourquoi le retrait est immédiat">
        <p>
          Le statut de retrait est une propriété de l&apos;ouvrage dans notre base, pas une
          opération de nettoyage. Le changer suffit : tout ce qui affiche du contenu passe par
          le même contrôle de droits, donc tout cesse de l&apos;afficher au même instant. Nous
          n&apos;avons rien à reconstruire, ce qui veut dire que rien ne peut être oublié.
        </p>
        <p>
          Les plans de lecture qui contenaient l&apos;ouvrage sont recomposés sur le reste du
          corpus. Un lecteur ne se retrouve pas avec un trou dans son chronogramme.
        </p>
      </Bloc>

      <Bloc titre="Avant d'écrire">
        <p>
          La page <Link href="/droits">droits et citations</Link> détaille ce qui est
          réellement affiché de chaque ouvrage. Sur les {""}
          soixante et onze ouvrages non redistribuables, il s&apos;agit de passages de
          quelques centaines de caractères, cités avec leur page. Cela lève souvent la
          question sans qu&apos;il soit besoin d&apos;aller plus loin.
        </p>
      </Bloc>
    </PageTexte>
  );
}
