import Link from "next/link";

import PageTexte, { Bloc } from "@/components/PageTexte";
import { leCorpus } from "@/lib/api";
import { EDITEUR } from "@/lib/editeur";

export const metadata = {
  title: "Le projet ASCENDA",
  description:
    "Pourquoi un plan de lecture plutôt qu'une bibliothèque de plus, et comment ASCENDA le construit.",
};

export default async function Page() {
  const CORPUS = await leCorpus();
  return (
    <PageTexte
      oeil="Learn. Grow. Become."
      titre="Le projet"
      chapeau="ASCENDA part d'un constat simple : l'accès aux livres n'est plus le problème. Ce qui manque, c'est un chemin dedans."
    >
      <Bloc titre="Le problème n'est pas la quantité">
        <p>
          On peut aujourd&apos;hui télécharger plus d&apos;ouvrages qu&apos;on n&apos;en lira
          dans une vie. Cela n&apos;a pas produit plus de lecteurs. Une bibliothèque sans plan
          intimide : on ne sait pas par où entrer, on commence trois livres, on n&apos;en
          finit aucun, et l&apos;on conclut qu&apos;on n&apos;a pas le temps.
        </p>
        <p>
          Le temps existe pourtant. Ce qui manque, c&apos;est un découpage : savoir que ce soir,
          entre vingt et une heures et vingt et une heures trente, on lit ces pages-là de ce
          livre-là, et qu&apos;on saura ensuite si on a compris.
        </p>
      </Bloc>

      <Bloc titre="Ce que fait ASCENDA">
        <p>
          Le corpus compte <strong>{CORPUS.ouvrages} ouvrages</strong>, soit{" "}
          {CORPUS.pages.toLocaleString("fr-FR")} pages, rangés en {CORPUS.axes} axes. À partir
          d&apos;un diagnostic de six minutes et du temps que vous déclarez avoir, ASCENDA
          compose un chronogramme : des séances datées, tenables, avec leurs pages exactes.
        </p>
        <p>
          Chaque séance est suivie d&apos;un quiz, corrigé avec l&apos;extrait du livre qui
          justifie la réponse. Ce que vous ratez revient en révision espacée. Quand vous
          prenez du retard, le plan se recompose sur le temps qu&apos;il reste au lieu de vous
          accabler d&apos;un arriéré.
        </p>
        <p>
          Un agent répond à vos questions sur le corpus, en citant le livre et la page. Quand
          il ne trouve rien, il le dit.
        </p>
      </Bloc>

      <Bloc titre="Trois partis pris">
        <h3>Le plan ne demande rien à un modèle de langue</h3>
        <p>
          La composition du chronogramme est déterministe : mêmes réponses, même plan.
          Explicable, reproductible, et gratuite à produire. Le modèle de langue n&apos;est
          appelé que pour rédiger les réponses de l&apos;agent, là où il apporte réellement
          quelque chose.
        </p>

        <h3>Les droits sont une porte, pas une politique</h3>
        <p>
          Sept ouvrages sont lisibles intégralement, soixante et onze ne le sont pas et
          ASCENDA n&apos;en cite que des passages plafonnés. Ce contrôle est appliqué en un
          seul endroit du serveur, que tout traverse. Le détail est sur la page{" "}
          <Link href="/droits">droits et citations</Link>.
        </p>

        <h3>Le produit doit tenir sur une connexion faible</h3>
        <p>
          Un pack hors ligne, des exports PDF, des images chargées en différé, un paiement par
          mobile money et non par carte bancaire. Nos lecteurs paient leur mégaoctet.
        </p>
      </Bloc>

      <Bloc titre="Qui">
        <p>
          ASCENDA est porté par {EDITEUR.responsable}, ingénieur camerounais. L&apos;ambition
          tient en une phrase : que la lecture cesse d&apos;être un privilège de ceux qui
          savent déjà par où commencer.
        </p>
        <p>
          Pour écrire : <Link href="/contact">la page contact</Link>.
        </p>
      </Bloc>
    </PageTexte>
  );
}
