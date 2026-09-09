import Link from "next/link";

import PageTexte, { Bloc } from "@/components/PageTexte";
import { EDITEUR } from "@/lib/editeur";

export const metadata = {
  title: "Nous écrire",
  description: "Comment joindre ASCENDA, et à quelle adresse selon votre demande.",
};

const CAS = [
  {
    objet: "compte",
    titre: "Un souci de compte",
    texte:
      "Connexion impossible, mot de passe perdu, adresse à changer. La réinitialisation autonome n'est pas encore en place : nous rouvrons l'accès à la main.",
  },
  {
    objet: "paiement",
    titre: "Un paiement",
    texte:
      "Un versement débité sans que l'abonnement s'ouvre, ou une échéance qui vous semble fausse. Donnez la date, le montant et le numéro utilisé : chaque paiement est tracé de bout en bout chez nous.",
  },
  {
    objet: "retrait",
    titre: "Un retrait d'ouvrage",
    texte:
      "Vous détenez des droits sur un ouvrage du corpus. La marche à suivre et nos délais figurent sur la page dédiée.",
  },
  {
    objet: "contenu",
    titre: "Une erreur dans le contenu",
    texte:
      "Une citation fautive, une page qui ne correspond pas, un quiz dont la réponse vous paraît erronée. Ce sont les messages les plus utiles que nous recevons.",
  },
];

export default function Page() {
  return (
    <PageTexte
      oeil="Contact"
      titre="Nous écrire"
      chapeau="Une seule adresse, et un objet qui dit de quoi il s'agit. C'est ce qui nous permet de répondre vite."
    >
      <Bloc titre="L'adresse">
        <p>
          <a href={`mailto:${EDITEUR.courriel}`} className="text-[1.05rem]">
            {EDITEUR.courriel}
          </a>
        </p>
        <p>
          Mettez en objet le mot indiqué ci-dessous selon votre cas. Nous répondons en
          français.
        </p>
      </Bloc>

      <Bloc titre="Selon ce qui vous amène">
        <table>
          <thead>
            <tr>
              <th>Objet</th>
              <th>Cas</th>
            </tr>
          </thead>
          <tbody>
            {CAS.map((c) => (
              <tr key={c.objet}>
                <td>
                  <strong>{c.objet}</strong>
                </td>
                <td>
                  <strong>{c.titre}.</strong> {c.texte}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <p>
          Pour un retrait, lisez d&apos;abord <Link href="/retrait">la page dédiée</Link> :
          elle dit ce qu&apos;il nous faut et sous quels délais nous agissons.
        </p>
      </Bloc>

      <Bloc titre="Ce que nous ne traitons pas par courriel">
        <p>
          Nous ne demandons jamais votre mot de passe ni votre code mobile money, et nous ne
          les accepterons pas si vous nous les envoyez. Aucun message légitime d&apos;ASCENDA
          ne vous les réclamera : si vous en recevez un, il ne vient pas de nous.
        </p>
      </Bloc>
    </PageTexte>
  );
}
