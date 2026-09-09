import Link from "next/link";

import PageTexte, { Bloc, ARenseigner } from "@/components/PageTexte";
import { EDITEUR } from "@/lib/editeur";

export const metadata = {
  title: "Mentions légales",
  description: "Éditeur, responsable de publication et hébergement du service ASCENDA.",
};

export default function Page() {
  return (
    <PageTexte oeil="Informations légales" titre="Mentions légales">
      <Bloc titre="Éditeur">
        <p>
          <strong>{EDITEUR.nom}</strong>
          <br />
          Responsable de la publication : {EDITEUR.responsable}
          <br />
          Contact : <a href={`mailto:${EDITEUR.courriel}`}>{EDITEUR.courriel}</a>
          <br />
          Pays : {EDITEUR.pays}
        </p>
        {!EDITEUR.formeJuridique && (
          <ARenseigner quoi="la forme juridique de l'éditeur (personne physique, société, association)." />
        )}
        {!EDITEUR.immatriculation && (
          <ARenseigner quoi="le numéro d'immatriculation au registre du commerce, ou l'équivalent applicable." />
        )}
        {!EDITEUR.adresse && <ARenseigner quoi="l'adresse du siège ou du domicile de l'éditeur." />}
        {!EDITEUR.telephone && <ARenseigner quoi="un numéro de téléphone joignable." />}
      </Bloc>

      <Bloc titre="Hébergement">
        {EDITEUR.hebergeur ? (
          <p>{EDITEUR.hebergeur}</p>
        ) : (
          <ARenseigner quoi="le nom, la raison sociale, l'adresse et le téléphone de l'hébergeur du site et de la base de données." />
        )}
      </Bloc>

      <Bloc titre="Propriété intellectuelle">
        <p>
          La marque ASCENDA, le logo, la charte graphique, les textes de ce site et le code du
          service appartiennent à l&apos;éditeur.
        </p>
        <p>
          Les ouvrages du corpus appartiennent à leurs auteurs et à leurs éditeurs respectifs.
          ASCENDA n&apos;en revendique aucun droit et n&apos;en affiche que ce que le régime de
          chacun autorise. Le détail figure sur la page{" "}
          <Link href="/droits">droits et citations</Link>, et la marche à suivre pour un
          retrait sur la page <Link href="/retrait">demande de retrait</Link>.
        </p>
        <p>
          Les photographies du site sont sous licence Unsplash, qui autorise l&apos;usage
          commercial sans attribution obligatoire. Chacune est tracée par son identifiant
          d&apos;origine dans le dépôt du projet.
        </p>
      </Bloc>

      <Bloc titre="Responsabilité">
        <p>
          ASCENDA construit des plans de lecture et restitue des extraits d&apos;ouvrages avec
          leur source. Les analyses, opinions et affirmations contenues dans ces ouvrages sont
          celles de leurs auteurs, et non celles de l&apos;éditeur du service.
        </p>
        <p>
          Les réponses de l&apos;agent sont fondées sur le corpus et portent leurs références.
          Elles ne constituent ni un conseil juridique, ni médical, ni financier.
        </p>
      </Bloc>

      <Bloc titre="Données personnelles">
        <p>
          Le traitement de vos données est décrit sur la page{" "}
          <Link href="/confidentialite">confidentialité</Link>.
        </p>
      </Bloc>
    </PageTexte>
  );
}
