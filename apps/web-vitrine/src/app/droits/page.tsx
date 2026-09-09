import Link from "next/link";

import PageTexte, { Bloc } from "@/components/PageTexte";
import { DROITS, EDITEUR } from "@/lib/editeur";

export const metadata = {
  title: "Droits et citations",
  description:
    "Comment ASCENDA traite les 78 ouvrages de son corpus : sept intégralement, soixante et onze par extraits plafonnés.",
};

export default function Page() {
  return (
    <PageTexte
      oeil="Ce que nous montrons, et pourquoi"
      titre="Droits et citations"
      chapeau="ASCENDA travaille sur des ouvrages qui ne lui appartiennent pas. Cette page dit exactement ce qui est affiché de chacun, et comment demander un retrait."
    >
      <Bloc titre="Deux régimes, jamais un seul">
        <p>
          Le corpus compte <strong>{DROITS.ouvrages} ouvrages</strong>. Ils ne sont pas traités
          de la même façon, parce qu&apos;ils n&apos;ont pas le même statut.
        </p>
        <table>
          <thead>
            <tr>
              <th>Régime</th>
              <th>Ouvrages</th>
              <th>Ce qui est affiché</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>Lecture intégrale</td>
              <td>{DROITS.integraux}</td>
              <td>
                Le texte entier. Domaine public, licence libre, ou autorisation de
                l&apos;ayant droit.
              </td>
            </tr>
            <tr>
              <td>Extraits plafonnés</td>
              <td>{DROITS.extraits}</td>
              <td>
                Des passages courts, chacun avec son ouvrage et sa page. Jamais le chapitre,
                jamais le livre.
              </td>
            </tr>
          </tbody>
        </table>
        <p>
          Sur la bibliothèque, un ouvrage du second régime porte la mention{" "}
          <strong>extraits</strong>. Ce n&apos;est pas une décoration : c&apos;est la règle
          appliquée à tout ce que le produit affiche de lui.
        </p>
      </Bloc>

      <Bloc titre="Le plafond n'est pas une consigne, c'est un mécanisme">
        <p>
          Chaque ouvrage non redistribuable porte en base un nombre maximal de caractères
          citables. Il vaut le plus souvent {DROITS.plafondCourant}, et n&apos;excède jamais{" "}
          {DROITS.plafondMax}. Un ouvrage est même à zéro : rien n&apos;en est cité.
        </p>
        <p>
          Ce plafond est appliqué par le serveur, en un seul endroit, avant que quoi que ce
          soit ne parte vers un écran. Le lecteur, l&apos;agent, les quiz, les synthèses et
          les exports passent tous par la même porte. Il n&apos;existe pas de chemin qui la
          contourne, et c&apos;est délibéré : une règle qu&apos;on peut oublier d&apos;appeler
          finit toujours par être oubliée quelque part.
        </p>
        <p>
          Quand une séance porte sur plusieurs passages, le budget est réparti du plus court
          au plus long, pour qu&apos;un passage bref ne soit pas sacrifié à un passage long.
        </p>
      </Bloc>

      <Bloc titre="Chaque phrase porte sa source">
        <p>
          L&apos;agent ne répond que sur le corpus. Il cite l&apos;ouvrage et la page. Quand il
          ne trouve rien, il le dit au lieu d&apos;inventer. Une réponse sans source n&apos;a
          pas de valeur, et une réponse inventée en a une négative.
        </p>
      </Bloc>

      <Bloc titre="Vous êtes ayant droit et vous voulez un retrait">
        <p>
          Écrivez à <a href={`mailto:${EDITEUR.courriel}`}>{EDITEUR.courriel}</a> en indiquant
          le titre, l&apos;auteur et la qualité qui vous permet d&apos;en disposer. La marche à
          suivre et ce que nous nous engageons à faire figurent sur la page{" "}
          <Link href="/retrait">demande de retrait</Link>.
        </p>
        <p>
          Le retrait est prévu dans le modèle de données : un ouvrage retiré cesse
          d&apos;apparaître partout, y compris dans les plans déjà construits, sans qu&apos;il
          faille reconstruire quoi que ce soit.
        </p>
      </Bloc>
    </PageTexte>
  );
}
