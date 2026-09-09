import Link from "next/link";

import PageTexte, { Bloc, ARenseigner } from "@/components/PageTexte";
import { EDITEUR } from "@/lib/editeur";

export const metadata = {
  title: "Confidentialité",
  description: "Ce qu'ASCENDA conserve de vous, pourquoi, pendant combien de temps.",
};

export default function Page() {
  return (
    <PageTexte
      oeil="Vos données"
      titre="Confidentialité"
      chapeau="La liste est courte, et elle est exhaustive. Ce qui n'est pas écrit ici n'est pas collecté."
    >
      <Bloc titre="Ce que nous conservons">
        <table>
          <thead>
            <tr>
              <th>Donnée</th>
              <th>Pourquoi</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>Adresse électronique</td>
              <td>Identifier votre compte et vous écrire au sujet de votre abonnement.</td>
            </tr>
            <tr>
              <td>Nom d&apos;affichage, si vous en donnez un</td>
              <td>Vous appeler par votre nom dans l&apos;application. Il est facultatif.</td>
            </tr>
            <tr>
              <td>Empreinte du mot de passe</td>
              <td>
                Vous reconnaître à la connexion. Le mot de passe lui-même n&apos;est jamais
                conservé : seule une empreinte Argon2, dont on ne revient pas au mot de passe.
              </td>
            </tr>
            <tr>
              <td>Votre progression</td>
              <td>
                Niveau au diagnostic, séances faites, scores aux quiz, notions à réviser,
                notes et surlignages. C&apos;est la matière même du service.
              </td>
            </tr>
            <tr>
              <td>Vos questions à l&apos;agent</td>
              <td>
                Retrouver une conversation passée. Elles ne servent à entraîner aucun modèle.
              </td>
            </tr>
            <tr>
              <td>Vos paiements</td>
              <td>
                Numéro mobile money, opérateur, montant, date, statut. Nécessaire pour
                rattacher un versement à votre abonnement et pour vous répondre en cas de
                litige.
              </td>
            </tr>
          </tbody>
        </table>
        <p>
          Nous ne collectons ni votre position, ni votre carnet d&apos;adresses, ni votre
          activité en dehors d&apos;ASCENDA. Le site vitrine que vous lisez n&apos;a aucun
          traceur publicitaire et n&apos;ouvre pas de session.
        </p>
      </Bloc>

      <Bloc titre="Qui d'autre y a accès">
        <ul>
          <li>
            <strong>Tara</strong>, notre intermédiaire de paiement mobile money, reçoit votre
            numéro et le montant. Il ne reçoit rien de votre lecture. Nous ne voyons jamais
            votre code secret : vous validez sur votre propre téléphone.
          </li>
          <li>
            <strong>Notre service d&apos;envoi de courriel</strong> reçoit votre adresse pour
            vous transmettre les messages liés à votre compte.
          </li>
          <li>
            <strong>Le modèle de langue</strong> qui rédige les réponses de l&apos;agent
            reçoit votre question et les extraits du corpus qui s&apos;y rapportent. Il ne
            reçoit ni votre identité ni votre historique.
          </li>
        </ul>
        <p>Rien n&apos;est vendu, loué, ni cédé à des fins publicitaires.</p>
      </Bloc>

      <Bloc titre="Combien de temps">
        <ul>
          <li>
            Tant que votre compte existe, pour ce qui touche à votre progression. Un
            chronogramme n&apos;a aucun sens sans son historique.
          </li>
          <li>
            Les jetons de connexion expirent d&apos;eux-mêmes, et une déconnexion les révoque
            immédiatement côté serveur.
          </li>
          <li>
            Les traces de paiement sont conservées plus longtemps, parce qu&apos;une
            transaction doit rester justifiable après coup.
          </li>
        </ul>
      </Bloc>

      <Bloc titre="Ce que vous pouvez demander">
        <p>
          L&apos;accès à ce que nous détenons sur vous, sa rectification, sa suppression, ou
          une copie exploitable. Écrivez à{" "}
          <a href={`mailto:${EDITEUR.courriel}`}>{EDITEUR.courriel}</a>. La suppression du
          compte efface la progression, les notes et les conversations ; les traces de
          paiement subsistent, pour la raison dite plus haut.
        </p>
        <ARenseigner quoi="l'hébergeur des données et le pays où elles résident, ainsi que le responsable de traitement déclaré si la législation applicable l'exige." />
      </Bloc>

      <Bloc titre="Les mineurs">
        <p>
          ASCENDA s&apos;adresse à des lecteurs majeurs. Nous ne cherchons pas à identifier
          l&apos;âge de nos membres et ne collectons rien qui s&apos;y rapporte.
        </p>
      </Bloc>

      <Bloc titre="Voir aussi">
        <p>
          Les <Link href="/mentions-legales">mentions légales</Link> et la page{" "}
          <Link href="/droits">droits et citations</Link>, qui traite des ouvrages et non des
          personnes.
        </p>
      </Bloc>
    </PageTexte>
  );
}
