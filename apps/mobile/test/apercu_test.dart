// Le banc de capture : il rend les écrans hors ligne et les écrit en images.
@Tags(['apercu'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ascenda/api/client.dart';
import 'package:ascenda/ecrans/abonnement.dart';
import 'package:ascenda/ecrans/agent.dart';
import 'package:ascenda/ecrans/aujourdhui.dart';
import 'package:ascenda/ecrans/axe.dart';
import 'package:ascenda/ecrans/bibliotheque.dart';
import 'package:ascenda/ecrans/cercle.dart';
import 'package:ascenda/ecrans/chronogramme.dart';
import 'package:ascenda/ecrans/codes.dart';
import 'package:ascenda/ecrans/diagnostic.dart';
import 'package:ascenda/ecrans/fiche_ouvrage.dart';
import 'package:ascenda/ecrans/glossaire.dart';
import 'package:ascenda/ecrans/hors_ligne.dart';
import 'package:ascenda/ecrans/lecteur.dart';
import 'package:ascenda/ecrans/profil.dart';
import 'package:ascenda/ecrans/progression.dart';
import 'package:ascenda/ecrans/quiz.dart';
import 'package:ascenda/ecrans/quiz_ouvrage.dart';
import 'package:ascenda/ecrans/recherche.dart';
import 'package:ascenda/ecrans/revision.dart';
import 'package:ascenda/etat/fournisseurs.dart';
import 'package:ascenda/etat/hors_ligne.dart';
import 'package:ascenda/etat/session.dart';
import 'package:ascenda/theme/palette.dart';
import 'package:ascenda/theme/texte.dart';
import 'package:ascenda/theme/theme.dart';

const _doc = 'd1';
const _chap = 'c1';
const _quiz = 'qz1';
const _chrono = 'ch1';
const _slugAxe = '12-agriculture-elevage';

final _texteLong = List.generate(
  9,
  (i) => "La conservation des sols repose d'abord sur une observation patiente du "
      "terrain : la pente, la couverture, le sens du travail. Les techniques "
      "mécaniques viennent ensuite, et seulement là où elles se justifient. "
      "Paragraphe ${i + 1}.",
).join('\n\n');

/// Un client qui répond à tout, sans réseau.
class _Faux extends ClientApi {
  @override
  Future<bool> get aUneSession async => true;

  @override
  Future<dynamic> get(String chemin, {Map<String, dynamic>? params, bool auth = true}) async {
    switch (chemin) {
      case '/auth/moi':
        return _lecteur;
      case '/aujourdhui':
        return _aujourdhui;
      case '/axes':
        return _axes;
      case '/axes/$_slugAxe':
        return _ficheAxe;
      case '/bibliotheque':
        return _biblio;
      case '/bibliotheque/$_doc':
        return _fiche;
      case '/bibliotheque/$_doc/sommaire':
        return _sommaire;
      case '/lecteur/$_doc/chapitre/$_chap':
        return _chapitre;
      case '/progression':
        return _progression;
      case '/progression/regularite':
        return {'jours': 84, 'serie_en_cours': 5, 'jours_actifs': 37, 'points': _regularite};
      case '/progression/maitrise':
        return _maitrise;
      case '/progression/journal':
        return _journal;
      case '/chronogrammes':
        return [_resumeChronogramme];
      case '/chronogrammes/$_chrono':
        return _chronogramme;
      case '/concepts':
        return _glossaire;
      case '/concepts/a-reviser':
        return {'notions': _aReviser};
      case '/quiz/$_quiz':
        return _quizJson;
      case '/quiz/document/$_doc':
        return _quizOuvrage;
      case '/quiz/document/$_doc/historique':
        return _historiqueQuiz;
      case '/recherche':
        return _resultatsRecherche;
      case '/recherche/suggestions':
        return {'ouvrages': _suggestions};
      case '/compte':
        return _compte;
      case '/compte/usage':
        return _usage;
      case '/compte/formules':
        return _formules;
      case '/codes/moi':
        return _codes;
      case '/paiements':
        return _paiements;
      case '/paiements/tarifs':
        return _tarifs;
      case '/paiements/abonnement/etat':
        return _abonnement;
      case '/agent/conversations':
        return _conversations;
      case '/agent/suggestions':
        return {'suggestions': _suggestionsAgent};
      case '/cercle/moi':
        return _cercleMoi;
      case '/cercle/amis':
        return _amis;
      case '/cercle/demandes':
        return _demandes;
      case '/cercle/fil':
        return _fil;
      case '/cercle/encouragements':
        return _encouragements;
      case '/notes':
        return const [];
      case '/surlignages':
        return const [];
    }
    return const [];
  }

  @override
  Future<dynamic> post(String chemin, {Object? corps, bool auth = true}) async {
    if (chemin == '/quiz/$_quiz/corriger') return _correction;
    return null;
  }
}

const _lecteur = {
  'id': 'u1',
  'email': 'awa@example.com',
  'nom': 'Awa Ndiaye',
  'plan': 'premium',
  'acces': {
    'complet': true,
    'fonctions': ['agent_question', 'quiz_generated', 'export_pdf', 'lecture_application'],
    'source': 'abonnement',
    'jusqu_au': '2026-10-19T00:00:00Z',
    'codes': [],
  },
};

const _aujourdhui = {
  'seance': {
    'id': 's1',
    'objectif': 'Comprendre les mécanismes de l’érosion',
    'duree_min': 24,
    'document_id': _doc,
    'ouvrage': "Mémento de l'agronome",
    'auteurs': ['CIRAD', 'GRET'],
    'chapitre_id': _chap,
    'chapitre': 'Les mécanismes et les conséquences de l’érosion',
    'page_debut': 244,
    'page_fin': 247,
    'livrable': 'quiz',
    'statut': 'a_venir',
    'axe_label': 'Agriculture et élevage',
  },
  'semaine': [
    {'jour': '2026-09-21', 'statut': 'fait', 'nb': 1},
    {'jour': '2026-09-22', 'statut': 'fait', 'nb': 1},
    {'jour': '2026-09-23', 'statut': 'a_venir', 'nb': 1},
  ],
  'notions_a_reviser': 5,
};

const _axes = [
  {'slug': _slugAxe, 'label': 'Agriculture et élevage', 'nb_ouvrages': 1, 'nb_pages': 1698,
   'duree_min': 5443, 'premium': false, 'pole': null},
  {'slug': '01-ia-fondamentaux', 'label': "Fondamentaux de l'IA", 'nb_ouvrages': 11, 'nb_pages': 3200,
   'duree_min': 4000, 'premium': false},
];

Map<String, dynamic> _ouvrage(String id, String titre, String axe, int pages) => {
      'id': id,
      'titre': titre,
      'auteurs': ['CIRAD', 'GRET'],
      'annee': 2002,
      'pages': pages,
      'niveau': 'intermediaire',
      'duree_min': 5443,
      'axe_slug': axe,
      'these': "Aider un agriculteur ne consiste plus à diffuser des recettes, mais à raisonner un diagnostic.",
      'a_quiz': true,
      'lecture_integrale': true,
    };

final _biblio = {
  'total': 79,
  'page': 1,
  'ouvrages': [
    _ouvrage(_doc, "Mémento de l'agronome", _slugAxe, 1698),
    _ouvrage('d2', 'ChatGPT. Le guide du débutant', '01-ia-fondamentaux', 240),
    _ouvrage('d3', 'Nations nègres et culture', '07-afrique-histoire-pensee', 560),
    _ouvrage('d4', 'La Planète invisible', '11-sciences-environnement', 320),
    _ouvrage('d5', "Lexique de l'intelligence artificielle", '01-ia-fondamentaux', 48),
  ],
};

final _fiche = {
  ..._ouvrage(_doc, "Mémento de l'agronome", _slugAxe, 1698),
  'sous_titre': null,
  'editeur': 'CIRAD, GRET, ministère des Affaires étrangères',
  'axes': [
    {'slug': _slugAxe, 'label': 'Agriculture et élevage'},
  ],
  'pedagogie': {
    'niveau': 'intermediaire',
    'duree_min': 5443,
    'these_centrale': "Aider un agriculteur ne consiste plus à diffuser des recettes techniques, mais à "
        "raisonner à partir d'un diagnostic de la situation réelle : l'exploitation dans sa diversité, son "
        "environnement économique et social, et les savoirs des paysans.",
    'idees_force': [
      "Un outil d'aide au raisonnement, pas un recueil de recettes.",
      'Chaque rédacteur précise le domaine de validité de ce qu’il avance.',
      "Le diagnostic précède toujours l'intervention.",
    ],
  },
  'contenu': {'chapitres': 318, 'questions': 1190, 'citations': 0},
  'droits': {
    'lecture_integrale': true,
    'pdf': true,
    'pdf_octets': 10124858,
    'application_seulement': true,
    'hors_ligne_integral': true,
    'statut': 'restricted',
    'message': null,
  },
  'dialogue_avec': const [],
};

const _titresChapitres = [
  'Introduction',
  'Le monde change, les agronomes aussi',
  'La place des diagnostics',
  'Les principaux outils de diagnostic',
  'Des outils pour collecter et traiter l’information',
  'Les composantes du milieu agricole',
  'Les hypothèses du diagnostic local',
  'Du visible à l’invisible',
  'Les entretiens',
  'Les mécanismes et les conséquences de l’érosion',
  'Les techniques de contrôle et les aménagements anti-érosifs',
  'La gestion des forêts et des pâturages',
];

final _sommaire = [
  for (var i = 1; i <= 12; i++)
    {
      'id': i == 1 ? _chap : 'c$i',
      'ordre': i,
      'titre': _titresChapitres[i - 1],
      'page_debut': 13 + i * 19,
      'page_fin': 20 + i * 19,
      'tokens': 900,
      'duree_min': 8 + i,
      'nb_questions': 3,
    },
];

final _chapitre = {
  'ouvrage': {'id': _doc, 'titre': "Mémento de l'agronome", 'auteurs': ['CIRAD', 'GRET']},
  'chapitre': {
    'id': _chap,
    'ordre': 10,
    'titre': 'Les mécanismes et les conséquences de l’érosion',
    'page_debut': 244,
    'page_fin': 247,
    'duree_min': 24,
  },
  'passages': [
    {'id': 'p1', 'page_debut': 244, 'page_fin': 245, 'texte': _texteLong},
    {'id': 'p2', 'page_debut': 246, 'page_fin': 247, 'texte': _texteLong},
  ],
  'droits': {'lecture_integrale': true, 'pdf': true, 'tronque': false, 'hors_ligne': false, 'message': null},
  'suivant': {'id': 'c11', 'titre': 'Les techniques de contrôle et les aménagements anti-érosifs'},
  'precedent': null,
  'compte_rendu': null,
};

const _progression = {
  'seances': {'total': 24, 'faites': 11, 'en_retard': 1, 'minutes_lues': 412, 'avancement': 0.46},
  'quiz': {'score_moyen': 0.78, 'tentatives': 9},
  'ouvrages': {'commences': 3, 'termines': 1},
  'notions': {'suivies': 42, 'maitrisees': 17, 'a_revoir': 5},
};

final _regularite = [
  for (var i = 83; i >= 0; i--)
    {'jour': DateTime(2026, 9, 23).subtract(Duration(days: i)).toIso8601String().substring(0, 10),
     'actions': (i * 7) % 45 > 12 ? 1 + i % 3 : 0,
     'minutes': (i * 7) % 45},
];

final _journal = [
  for (var i = 0; i < 12; i++)
    {
      'id': 'j$i',
      'genre': i.isEven ? 'seance' : 'quiz',
      'libelle': i.isEven
          ? "Séance lue : ${_titresChapitres[i % _titresChapitres.length]}"
          : 'Quiz passé : ${(60 + i * 3)} %',
      'ouvrage': "Mémento de l'agronome",
      'minutes': 18 + i,
      'le': DateTime(2026, 9, 23).subtract(Duration(days: i)).toIso8601String(),
    },
];

const _resumeChronogramme = {
  'id': _chrono,
  'axe_label': 'Agriculture et élevage',
  'statut': 'actif',
  'seances': 24,
  'faites': 11,
  'en_retard': 1,
};

/// Le plan de lecture complet : onze séances faites, une en retard, le reste
/// à venir. C'est l'état le plus riche de l'écran, donc celui qu'on regarde.
final _chronogramme = {
  'id': _chrono,
  'version': 2,
  'axe': _slugAxe,
  'axe_label': 'Agriculture et élevage',
  'debut': '2026-09-01',
  'cible': '2026-12-20',
  'statut': 'actif',
  'adaptatif': true,
  'justification': "Vingt-quatre séances de trente minutes, trois par semaine : c'est le rythme "
      "que vous avez indiqué, et il mène au bout du Mémento en deux mois.",
  'seances': [
    for (var i = 0; i < 16; i++)
      {
        'id': 's$i',
        'ordre': i + 1,
        'objectif': "Mémento de l'agronome : ${_titresChapitres[i % _titresChapitres.length]}",
        'duree_min': 30,
        'chronogramme_id': _chrono,
        'document_id': _doc,
        'ouvrage': "Mémento de l'agronome",
        'auteurs': ['CIRAD', 'GRET'],
        'chapitre_id': i == 0 ? _chap : 'c${i + 1}',
        'chapitre': _titresChapitres[i % _titresChapitres.length],
        'page_debut': 13 + i * 19,
        'page_fin': 20 + i * 19,
        'livrable': i.isEven ? 'quiz' : null,
        'livrable_id': i.isEven ? _quiz : null,
        'prevue_le': DateTime(2026, 9, 1).add(Duration(days: i * 3)).toIso8601String(),
        'statut': i < 11 ? 'fait' : 'a_venir',
        'faite_le': i < 11
            ? DateTime(2026, 9, 1).add(Duration(days: i * 3, hours: 19)).toIso8601String()
            : null,
        'en_retard': i == 11,
        'lecture_integrale': true,
        'axe_label': 'Agriculture et élevage',
      },
    // Une séance de révision : ni ouvrage ni chapitre, comme le planificateur
    // les produit en fin de semaine.
    {
      'id': 's16',
      'ordre': 17,
      'objectif': 'Révision des notions de la semaine.',
      'duree_min': 20,
      'chronogramme_id': _chrono,
      'document_id': null,
      'ouvrage': null,
      'auteurs': [],
      'chapitre_id': null,
      'chapitre': null,
      'page_debut': null,
      'page_fin': null,
      'livrable': 'revision',
      'livrable_id': null,
      'prevue_le': DateTime(2026, 11, 2, 18).toIso8601String(),
      'statut': 'a_venir',
      'faite_le': null,
      'en_retard': false,
      'lecture_integrale': null,
      'axe_label': 'Agriculture et élevage',
    },
  ],
};

/// Les notions suivies, telles que les lit `Notion.depuisJson`.
const _maitrise = [
  {'concept_id': 'n1', 'terme': 'Érosion hydrique', 'axe': _slugAxe,
   'axe_label': 'Agriculture et élevage', 'revisions': 5, 'facilite': 2.6,
   'niveau': 'acquis', 'prochaine_revision': '2026-10-12T06:00:00Z'},
  {'concept_id': 'n2', 'terme': 'Jachère', 'axe': _slugAxe,
   'axe_label': 'Agriculture et élevage', 'revisions': 2, 'facilite': 2.2,
   'niveau': 'en_cours', 'prochaine_revision': '2026-09-27T06:00:00Z'},
  {'concept_id': 'n3', 'terme': 'Apprentissage supervisé', 'axe': null,
   'axe_label': null, 'revisions': 1, 'facilite': 2.1, 'niveau': 'fragile',
   'prochaine_revision': null},
];

/// Les notions à revoir : le serveur les donne sans niveau, et l'axe y est un
/// slug et non un libellé. C'est la forme réelle, gardée telle quelle.
const _aReviser = [
  {'concept_id': 'n1', 'terme': 'Érosion hydrique', 'axe': _slugAxe,
   'definition': "Le détachement puis le transport des particules de sol par l'eau de "
       "pluie et de ruissellement, jusqu'à la perte de l'horizon fertile.",
   'facilite': 2.5, 'intervalle_jours': 3, 'revisions': 2,
   'a_revoir_depuis': '2026-09-23T06:00:00Z'},
  {'concept_id': 'n2', 'terme': 'Jachère', 'axe': null,
   'definition': 'Une terre laissée au repos pour que sa fertilité se reconstitue.',
   'facilite': 1.9, 'intervalle_jours': 1, 'revisions': 0, 'a_revoir_depuis': null},
];

/// Le glossaire, tel que l'écran le lit : des lignes brutes, pas des `Notion`.
const _glossaire = [
  {'id': 'n1', 'terme': 'Érosion hydrique', 'axe': _slugAxe,
   'axe_label': 'Agriculture et élevage', 'occurrences': 12,
   'definition': "Le détachement puis le transport des particules de sol par l'eau de "
       "pluie et de ruissellement."},
  {'id': 'n2', 'terme': 'Jachère', 'axe': _slugAxe,
   'axe_label': 'Agriculture et élevage', 'occurrences': 6,
   'definition': 'Une terre laissée au repos pour que sa fertilité se reconstitue.'},
  {'id': 'n4', 'terme': 'Assolement', 'axe': _slugAxe,
   'axe_label': 'Agriculture et élevage', 'occurrences': 14,
   'definition': "La répartition des cultures entre les parcelles d'une exploitation au "
       "cours d'une campagne."},
  {'id': 'n3', 'terme': 'Apprentissage supervisé', 'axe': '01-ia-fondamentaux',
   'axe_label': "Fondamentaux de l'IA", 'occurrences': 0,
   'definition': "Un modèle qu'on entraîne sur des exemples déjà étiquetés."},
];

/// Un quiz de chapitre : quatre questions, quatre choix chacune.
const _quizJson = {
  'quiz_id': _quiz,
  'ouvrage': "Mémento de l'agronome",
  'chapitre': 'Les mécanismes et les conséquences de l’érosion',
  'document_id': _doc,
  'chapitre_id': _chap,
  'questions': [
    {
      'index': 0,
      'niveau': 'comprehension',
      'page': 245,
      'question': "Qu'est-ce qui déclenche l'érosion hydrique d'un sol nu ?",
      'choix': [
        "L'impact des gouttes de pluie, qui détache les particules de surface.",
        'La remontée de la nappe phréatique sous la parcelle.',
        'Le tassement du sol par le passage répété des animaux.',
        "L'évaporation rapide de l'eau retenue entre les mottes.",
      ],
    },
    {
      'index': 1,
      'niveau': 'connaissance',
      'page': 246,
      'question': 'Dans quel sens travailler une parcelle en pente ?',
      'choix': [
        'Dans le sens de la pente, pour évacuer l’eau plus vite.',
        'Perpendiculairement à la pente, en suivant les courbes de niveau.',
        "Peu importe : le sens du travail n'a pas d'effet mesurable.",
        'En diagonale, pour partager la contrainte entre les deux sens.',
      ],
    },
    {
      'index': 2,
      'niveau': 'application',
      'page': 247,
      'question': "Que vise en premier un aménagement anti-érosif ?",
      'choix': [
        "Ralentir le ruissellement avant de chercher à l'évacuer.",
        'Augmenter le rendement de la parcelle dès la première saison.',
        'Remplacer la couverture végétale par un revêtement minéral.',
        'Drainer le plus vite possible vers le bas-fond voisin.',
      ],
    },
    {
      'index': 3,
      'niveau': 'analyse',
      'page': 247,
      'question': 'Pourquoi un diagnostic précède-t-il toute intervention ?',
      'choix': [
        "Parce que la même technique n'a pas le même effet selon le terrain.",
        'Parce que la réglementation agricole l’impose partout.',
        "Parce qu'il permet de facturer l'intervention plus cher.",
        'Parce qu’il remplace la mesure des pentes sur le terrain.',
      ],
    },
  ],
};

const _correction = {
  'quiz_id': _quiz,
  'reussi': true,
  'score': 0.75,
  'justes': 3,
  'total': 4,
  'details': [
    {
      'index': 0,
      'question': "Qu'est-ce qui déclenche l'érosion hydrique d'un sol nu ?",
      'juste': true,
      'votre_reponse': 0,
      'bonne_reponse': 0,
      'page': 245,
      'niveau': 'comprehension',
      'explication': "C'est l'énergie cinétique de la goutte qui rompt les agrégats : le "
          "ruissellement ne fait ensuite que transporter ce qui a déjà été détaché.",
      'extrait': {
        'portee': 'chapitre',
        'page': 245,
        'texte': "Sur un sol nu, l'impact des gouttes détache les particules ; le film d'eau "
            "qui se forme ensuite les emporte vers l'aval.",
      },
    },
    {
      'index': 1,
      'question': 'Dans quel sens travailler une parcelle en pente ?',
      'juste': true,
      'votre_reponse': 1,
      'bonne_reponse': 1,
      'page': 246,
      'explication': 'Le travail suivant les courbes de niveau oppose au ruissellement une '
          'suite de petits obstacles, et retient la terre sur la parcelle.',
      'extrait': {
        'portee': 'chapitre',
        'page': 246,
        'texte': 'Le labour perpendiculaire à la pente reste la mesure la moins coûteuse et '
            'la plus efficace sur les pentes faibles.',
      },
    },
    {
      'index': 2,
      'question': "Que vise en premier un aménagement anti-érosif ?",
      'juste': false,
      'votre_reponse': 3,
      'bonne_reponse': 0,
      'page': 247,
      'explication': "Évacuer vite déplace le problème vers l'aval. On cherche d'abord à "
          "ralentir l'eau pour qu'elle s'infiltre là où elle tombe.",
      'extrait': {
        'portee': 'chapitre',
        'page': 247,
        'texte': "Ralentir, retenir, infiltrer : l'évacuation ne vient qu'en dernier recours, "
            "et jamais sans exutoire aménagé.",
      },
    },
    {
      'index': 3,
      'question': 'Pourquoi un diagnostic précède-t-il toute intervention ?',
      'juste': true,
      'votre_reponse': 0,
      'bonne_reponse': 0,
      'page': 247,
      'explication': "Chaque rédacteur du Mémento précise le domaine de validité de ce qu'il "
          "avance : hors de ce domaine, la recette devient une erreur.",
      'extrait': null,
    },
  ],
};

final _quizOuvrage = {
  'document_id': _doc,
  'total_questions': 1190,
  'chapitres': [
    for (var i = 1; i <= 12; i++)
      {
        'quiz_id': i == 1 ? _quiz : 'qz$i',
        'chapitre_id': i == 1 ? _chap : 'c$i',
        'ordre': i,
        'titre': _titresChapitres[i - 1],
        'page_debut': 13 + i * 19,
        'page_fin': 20 + i * 19,
        // Un chapitre d'appareil est enregistré sans question : l'écran doit
        // le retirer du sommaire plutôt que d'afficher une ligne morte.
        'nb_questions': i == 1 ? 0 : 3 + (i % 4),
        'motif_vide': i == 1 ? "Chapitre d'appareil : pas de contenu interrogeable." : null,
      },
  ],
};

const _historiqueQuiz = [
  {'quiz_id': 'qz2', 'chapitre_id': 'c2', 'score': 0.75, 'justes': 3, 'total': 4,
   'le': '2026-09-20T09:15:00Z'},
  {'quiz_id': 'qz3', 'chapitre_id': 'c3', 'score': 1.0, 'justes': 4, 'total': 4,
   'le': '2026-09-18T18:40:00Z'},
];

final _ficheAxe = {
  'slug': _slugAxe,
  'label': 'Agriculture et élevage',
  'description': "Produire de quoi manger sur un sol qui s'épuise : diagnostic de "
      "l'exploitation, conduite des cultures, conservation des sols et des eaux.",
  'premium': false,
  'pole': {'slug': 'sciences-de-la-terre', 'label': 'Sciences de la terre'},
  'ouvrages': [
    {
      'id': _doc,
      'titre': "Mémento de l'agronome",
      'auteurs': ['CIRAD', 'GRET'],
      'annee': 2002,
      'pages': 1698,
      'niveau': 'intermediaire',
      'duree_min': 5443,
      'lecture_integrale': true,
      'perimetre': {
        'pages': 412,
        'duree_min': 1320,
        'sections': [
          {'chapitre_id': _chap, 'titre': _titresChapitres[9], 'page_debut': 244,
           'page_fin': 247, 'sous_sections': 4},
          {'chapitre_id': 'c11', 'titre': _titresChapitres[10], 'page_debut': 248,
           'page_fin': 262, 'sous_sections': 0},
        ],
      },
    },
    {
      'id': 'd6',
      'titre': "L'agriculture de conservation en Afrique de l'Ouest",
      'auteurs': ['FAO'],
      'annee': 2015,
      'pages': 214,
      'niveau': 'debutant',
      'duree_min': 680,
      'lecture_integrale': false,
    },
    {
      'id': 'd7',
      'titre': "Élevage et pastoralisme au Sahel : un précis de conduite des troupeaux",
      'auteurs': ['IRAM', 'CIRAD'],
      'annee': 2011,
      'pages': 386,
      'niveau': 'avance',
      'duree_min': 1240,
      'lecture_integrale': true,
    },
  ],
};

final _resultatsRecherche = {
  'requete': 'érosion',
  'mode': 'hybride',
  'total': 34,
  'resultats': [
    {
      'chunk_id': 'k1',
      'auteurs': ['CIRAD', 'GRET'],
      'page_fin': 246,
      'document_id': _doc,
      'ouvrage': "Mémento de l'agronome",
      'chapitre': 'Les mécanismes et les conséquences de l’érosion',
      'chapitre_id': _chap,
      'page': 245,
      'extrait': "Sur un sol nu, l'impact des gouttes détache les particules ; le film d'eau "
          "qui se forme ensuite les emporte vers l'aval, et la parcelle perd en une saison "
          "ce que dix années ont mis à construire.",
    },
    {
      'chunk_id': 'k2',
      'auteurs': ['CIRAD', 'GRET'],
      'page_fin': null,
      'document_id': _doc,
      'ouvrage': "Mémento de l'agronome",
      'chapitre': 'Les techniques de contrôle et les aménagements anti-érosifs',
      'chapitre_id': 'c11',
      'page': 251,
      'extrait': "Ralentir, retenir, infiltrer : l'évacuation ne vient qu'en dernier recours, "
          "et jamais sans exutoire aménagé.",
    },
    {
      'chunk_id': 'k3',
      'auteurs': ['IRAM', 'CIRAD'],
      'page_fin': null,
      'document_id': 'd7',
      'ouvrage': "Élevage et pastoralisme au Sahel",
      'chapitre': 'La charge des parcours',
      'chapitre_id': 'c2',
      'page': 88,
      'extrait': "Le surpâturage agit comme un décapage lent : la couverture disparaît avant "
          "le sol, mais le sol suit toujours.",
    },
  ],
};

final _suggestions = [
  _ouvrage(_doc, "Mémento de l'agronome", _slugAxe, 1698),
  {
    ..._ouvrage('d7', "Élevage et pastoralisme au Sahel", _slugAxe, 386),
    'auteurs': ['IRAM', 'CIRAD'],
    'annee': 2011,
  },
];

const _compte = {
  'id': 'u1',
  'email': 'awa@example.com',
  'nom': 'Awa Ndiaye',
  'plan': 'premium',
  'plan_jusqu_au': '2026-10-19T00:00:00Z',
  'inscrit_le': '2026-03-04T08:00:00Z',
  'profil': {
    'niveau': 'intermediaire',
    'evalue_le': '2026-03-04T08:22:00Z',
    'objectif': "Conseiller des exploitations familiales dans l'Ouest",
    'minutes_semaine': 180,
    'vitesse_lecture_wpm': 210,
    'langue': 'fr',
  },
  'abonnement': {
    'plan': 'premium',
    'statut': 'active',
    'debut': '2025-10-19T00:00:00Z',
    'fin': '2026-10-19T00:00:00Z',
    'montant_centimes': 28000,
    'devise': 'XAF',
    'fournisseur': 'tara',
  },
  'axes': [
    {'slug': _slugAxe, 'label': 'Agriculture et élevage',
     'objectif': "Conduire un diagnostic d'exploitation", 'statut': 'actif',
     'echeance': '2026-12-20'},
  ],
};

const _usage = {
  'plan': 'premium',
  'tokens_du_mois': 48211,
  'compteurs': [
    {'type': 'agent_question', 'periode': 'day', 'limite': 400, 'utilise': 37,
     'restant': 363, 'bloquant': false},
    {'type': 'chronogram_active', 'periode': 'total', 'limite': null, 'utilise': 1,
     'restant': null, 'bloquant': false},
    {'type': 'doc_uploaded', 'periode': 'month', 'limite': 50, 'utilise': 6,
     'restant': 44, 'bloquant': true},
    {'type': 'ocr_pages', 'periode': 'month', 'limite': 2000, 'utilise': 318,
     'restant': 1682, 'bloquant': true},
    {'type': 'quiz_generated', 'periode': 'month', 'limite': null, 'utilise': 3,
     'restant': null, 'bloquant': false},
  ],
};

const _formules = [
  {
    'code': 'free',
    'nom': 'Découverte',
    'prix': 0,
    'devise': 'XAF',
    'periode_mois': null,
    'resume': 'La bibliothèque de base, un axe, un chronogramme, les quiz déjà préparés.',
    'limites': [
      {'type': 'agent_question', 'periode': 'day', 'limite': 20, 'bloquant': true},
      {'type': 'chronogram_active', 'periode': 'total', 'limite': 1, 'bloquant': true},
      {'type': 'doc_uploaded', 'periode': 'month', 'limite': 0, 'bloquant': true},
      {'type': 'export_pdf', 'periode': 'month', 'limite': 0, 'bloquant': true},
      {'type': 'ocr_pages', 'periode': 'month', 'limite': 0, 'bloquant': true},
      {'type': 'quiz_generated', 'periode': 'month', 'limite': 0, 'bloquant': true},
      {'type': 'synthesis_generated', 'periode': 'month', 'limite': 0, 'bloquant': true},
    ],
  },
  {
    'code': 'premium',
    'nom': 'Ascension',
    'prix': 3000,
    'devise': 'XAF',
    'periode_mois': 1,
    'resume': 'Vos propres documents, axes illimités, chronogramme adaptatif, synthèses '
        'et quiz à la demande, export.',
    'limites': [
      {'type': 'agent_question', 'periode': 'day', 'limite': 400, 'bloquant': false},
      {'type': 'chronogram_active', 'periode': 'total', 'limite': null, 'bloquant': false},
      {'type': 'doc_uploaded', 'periode': 'month', 'limite': 50, 'bloquant': true},
      {'type': 'export_pdf', 'periode': 'month', 'limite': null, 'bloquant': false},
      {'type': 'ocr_pages', 'periode': 'month', 'limite': 2000, 'bloquant': true},
      {'type': 'quiz_generated', 'periode': 'month', 'limite': null, 'bloquant': false},
      {'type': 'synthesis_generated', 'periode': 'month', 'limite': null, 'bloquant': false},
    ],
  },
];

const _codes = {
  'ambassadeur': {
    'code': 'AWA-7K2M',
    'actif': true,
    'pourcent': 20,
    'validite_jours': 60,
    'filleuls': 3,
    'message_partage': "Je lis sur ASCENDA. Avec mon code AWA-7K2M, votre premier "
        "abonnement est à moins vingt pour cent.",
  },
  'acces': {
    'complet': true,
    'fonctions': [
      'agent_question', 'quiz_generated', 'synthesis_generated', 'export_pdf',
      'chronogram_active', 'chronogramme_adaptatif', 'doc_uploaded',
      'axes_reserves', 'lecture_application',
    ],
    'source': 'code',
    'jusqu_au': '2026-11-30T23:59:59Z',
    'codes': [
      {
        'id': 'ac1',
        'code': 'LYCEE-2026',
        'libelle': 'Partenariat lycée de Bafoussam',
        'niveau': 'complet',
        'fonctions': [
          'agent_question', 'quiz_generated', 'synthesis_generated', 'export_pdf',
          'chronogram_active', 'chronogramme_adaptatif', 'doc_uploaded',
          'axes_reserves', 'lecture_application',
        ],
        'active_le': '2026-09-01T12:00:00Z',
        'fin': '2026-11-30T23:59:59Z',
        'jours_restants': 67,
      },
    ],
  },
  'reduction_prochaine': {'pourcent': 20, 'expire_le': '2026-11-18T00:00:00Z'},
  'bons': [
    {'id': 'b1', 'pourcent': 20, 'statut': 'disponible', 'expire_le': '2026-11-18T00:00:00Z',
     'utilise_le': null, 'gagne_le': '2026-09-19T00:00:00Z', 'filleul': 'Moussa',
     'nouveau': true},
    {'id': 'b2', 'pourcent': 20, 'statut': 'utilise', 'expire_le': '2026-09-10T00:00:00Z',
     'utilise_le': '2026-08-02T00:00:00Z', 'gagne_le': '2026-07-11T00:00:00Z',
     'filleul': 'Fatou', 'nouveau': false},
    {'id': 'b3', 'pourcent': 20, 'statut': 'expire', 'expire_le': '2026-06-30T00:00:00Z',
     'utilise_le': null, 'gagne_le': '2026-05-01T00:00:00Z', 'filleul': null,
     'nouveau': false},
  ],
  'nouveaux': 1,
  'fonctions': [
    {'cle': 'agent_question', 'libelle': "Questions à l'agent sans compter"},
    {'cle': 'quiz_generated', 'libelle': 'Quiz à la demande'},
    {'cle': 'synthesis_generated', 'libelle': 'Synthèses à la demande'},
    {'cle': 'export_pdf', 'libelle': 'Export PDF'},
    {'cle': 'chronogram_active', 'libelle': 'Plusieurs chronogrammes à la fois'},
    {'cle': 'chronogramme_adaptatif', 'libelle': 'Chronogramme adaptatif et replanification'},
    {'cle': 'doc_uploaded', 'libelle': 'Import de vos propres documents'},
    {'cle': 'axes_reserves', 'libelle': 'Parcours réservés à Ascension'},
    {'cle': 'lecture_application',
     'libelle': 'Lecture intégrale et hors ligne des ouvrages réservés'},
  ],
};

const _tarifs = {
  'moyens': [
    {'code': 'mtn', 'libelle': 'MTN Mobile Money', 'operateur': 'MTN Cameroun'},
    {'code': 'orange', 'libelle': 'Orange Money', 'operateur': 'Orange Cameroun'},
  ],
  'reduction': {'pourcent': 20, 'expire_le': '2026-11-18T00:00:00Z', 'motif': 'parrainage'},
  'formules': [
    {'periode_mois': 1, 'montant': 3000, 'montant_reduit': 2400, 'devise': 'XAF',
     'libelle': 'Ascension, un mois', 'par_mois': 3000},
    {'periode_mois': 3, 'montant': 8000, 'montant_reduit': 6400, 'devise': 'XAF',
     'libelle': 'Ascension, trois mois', 'par_mois': 2667},
    {'periode_mois': 12, 'montant': 28000, 'montant_reduit': 22400, 'devise': 'XAF',
     'libelle': 'Ascension, un an', 'par_mois': 2333},
  ],
};

const _abonnement = {
  'actif': true,
  'plan': 'premium',
  'statut': 'active',
  'debut': '2025-10-19T00:00:00Z',
  'fin': '2026-10-19T00:00:00Z',
  'jours_restants': 25,
  'periode_mois': 12,
  'montant': 28000,
  'devise': 'XAF',
};

const _paiements = [
  {'id': 'pa1', 'montant': 22400, 'montant_brut': 28000, 'reduction_pourcent': 20,
   'devise': 'XAF', 'periode_mois': 12, 'plan': 'premium', 'statut': 'valide',
   'motif_rejet': null, 'telephone': '+237690000000', 'reseau': 'MTN',
   'reference': 'TARA-8F3K21', 'url_paiement': null,
   'cree_le': '2025-10-19T11:02:00Z', 'valide_le': '2025-10-19T11:02:47Z',
   'message': 'Paiement confirmé. Votre abonnement est actif.'},
  {'id': 'pa2', 'montant': 3000, 'montant_brut': null, 'reduction_pourcent': null,
   'devise': 'XAF', 'periode_mois': 1, 'plan': 'premium', 'statut': 'rejete',
   'motif_rejet': "L'opérateur a refusé le débit : solde insuffisant.",
   'telephone': '+237690000000', 'reseau': 'ORANGE', 'reference': null,
   'url_paiement': null, 'cree_le': '2025-09-14T07:48:00Z', 'valide_le': null,
   'message': "L'opérateur a refusé le débit : solde insuffisant."},
];

const _conversations = [
  {'id': 'cv1', 'titre': "Pourquoi le labour dans le sens de la pente aggrave l'érosion",
   'ouvrage': "Mémento de l'agronome", 'document_id': _doc, 'nb_messages': 6,
   'derniere_activite': '2026-09-22T19:12:00Z'},
  {'id': 'cv2', 'titre': 'Différence entre jachère et rotation', 'ouvrage': null,
   'document_id': null, 'nb_messages': 4, 'derniere_activite': '2026-09-15T08:30:00Z'},
];

const _suggestionsAgent = [
  "Qu'est-ce qu'un diagnostic agronomique, en une phrase ?",
  "Quelles techniques anti-érosives pour une pente de 8 % ?",
  'Que dit le Mémento sur la jachère améliorée ?',
];

const _cercleMoi = {
  'code': 'AWA-7K2M',
  'partage_activite': true,
  'compteurs': {'demandes': 1, 'messages': 2, 'encouragements': 1, 'total': 4},
  'message_partage': "Rejoignez mon cercle de lecture sur ASCENDA avec le code AWA-7K2M.",
};

const _amis = [
  {
    'id': 'a1',
    'nom': 'Moussa Diallo',
    'non_lus': 2,
    'amis_depuis': '2026-06-12T00:00:00',
    'lecture': {
      'partage': true,
      'seances_semaine': 3,
      'minutes_semaine': 96,
      'jours_actifs_14': 9,
      'derniere_activite': '2026-09-23T07:40:00',
      'lit': "Mémento de l'agronome",
    },
  },
  // Un ami qui ne partage pas son activité : l'API ne renvoie alors que la
  // clé `partage`, et l'écran doit s'en accommoder.
  {
    'id': 'a4',
    'nom': 'Sandrine',
    'non_lus': 0,
    'amis_depuis': '2026-07-19T09:30:00Z',
    'lecture': {'partage': false},
  },
];

const _demandes = {
  'recues': [
    {'id': 'dm1', 'le': '2026-09-22T16:20:00', 'lecteur': {'id': 'a2', 'nom': 'Fatou Bamba'}},
  ],
  'envoyees': [
    {'id': 'dm2', 'le': '2026-09-21T10:05:00', 'lecteur': {'id': 'a3', 'nom': 'Ibrahim Sow'}},
  ],
};

const _fil = [
  {'id': 'f1', 'genre': 'seance', 'texte': 'a lu Les entretiens', 'encourage': false,
   'ouvrage': "Mémento de l'agronome", 'le': '2026-09-23T06:50:00',
   'lecteur': {'id': 'a1', 'nom': 'Moussa Diallo'}},
  {'id': 'f2', 'genre': 'quiz', 'texte': 'a obtenu 100 % au quiz du chapitre 3',
   'encourage': true, 'ouvrage': "Mémento de l'agronome", 'le': '2026-09-22T20:15:00',
   'lecteur': {'id': 'a1', 'nom': 'Moussa Diallo'}},
];

const _encouragements = [
  {'id': 'e1', 'genre': 'bravo', 'message': 'Onze séances d’affilée, continue !',
   'nouveau': true, 'ouvrage': "Mémento de l'agronome", 'le': '2026-09-23T08:05:00',
   'auteur': {'id': 'a1', 'nom': 'Moussa Diallo'}},
];

/// Un volume emporté sur l'appareil. Le dépôt hors ligne passe par des fichiers
/// chiffrés : il ne se nourrit pas par l'API, on surcharge donc son fournisseur.
final _packs = {
  _doc: PackHorsLigne(
    documentId: _doc,
    titre: "Mémento de l'agronome",
    telechargeLe: DateTime(2026, 9, 18, 21, 30),
    octets: 10124858,
    compteurs: const {'chapitres': 318, 'questions': 1190, 'citations': 42},
  ),
  'd7': PackHorsLigne(
    documentId: 'd7',
    titre: "Élevage et pastoralisme au Sahel : un précis de conduite des troupeaux",
    telechargeLe: DateTime(2026, 9, 12, 7, 5),
    octets: 486400,
    compteurs: const {'chapitres': 24, 'questions': 96, 'citations': 8},
  ),
};

Widget _sous(Widget ecran, Palette p) => ProviderScope(
      overrides: [
        clientApiProvider.overrideWithValue(_Faux()),
        // Le sondage de l'état du service tourne toutes les deux minutes : il
        // n'a rien à faire dans un banc de capture.
        etatServiceProvider.overrideWith((ref) => Stream.value(null)),
        // L'étagère hors ligne vit dans des fichiers chiffrés, hors de l'API.
        packsProvider.overrideWith((ref) async => _packs),
      ],
      child: MaterialApp(
        // Le ruban « debug » mangeait le coin haut droit de chaque capture.
        debugShowCheckedModeBanner: false,
        theme: ThemeAscenda.depuis(p),
        home: ecran,
      ),
    );

/// Retrouve un `Texte` par la chaîne qu'on lui a donnée. `find.text` échoue
/// ici : `Texte` recompose ses signes avant de les rendre.
Finder _texte(String data) => find.byWidgetPredicate(
      (w) => w is Texte && w.data == data,
      description: 'Texte("$data")',
    );

/// Les deux formats de revue, en points logiques.
const _formats = <({String nom, Size taille, double densite})>[
  (nom: '', taille: Size(1080, 2000), densite: 3),
  (nom: '-petit', taille: Size(320, 700), densite: 1),
];

/// La police des icônes n'est pas chargée dans un test : sans elle, chaque
/// icône se rend en carré vide.
Future<void> _chargerIcones() async {
  final racine = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.path;
  final f = File('$racine/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!f.existsSync()) return;
  final chargeur = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  await chargeur.load();
}

/// Les images d'asset se chargent hors de l'horloge du test : sans ce répit, le
/// logo manque à la première image capturée.
Future<void> _chargerImages(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await t.pump();
}

void main() {
  setUpAll(() async {
    await _chargerIcones();
    await initializeDateFormatting('fr_FR');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final ecrans = <String, Widget>{
    'accueil': const EcranAujourdhui(),
    'bibliotheque': const EcranBibliotheque(),
    'fiche': const FicheOuvrage(documentId: _doc),
    'lecteur': const EcranLecteur(documentId: _doc, chapitreId: _chap),
    'progres': const EcranProgression(),
    'quiz': const EcranQuiz(quizId: _quiz),
    'quiz-ouvrage': const EcranQuizOuvrage(documentId: _doc, titre: "Mémento de l'agronome"),
    'revision': const EcranRevision(),
    'chronogramme': const EcranChronogramme(chronogrammeId: _chrono),
    'diagnostic': const DiagnosticEcran(),
    'profil': const EcranProfil(),
    'abonnement': const EcranAbonnement(),
    'codes': const EcranCodes(),
    'agent': const EcranAgent(),
    'cercle': const EcranCercle(),
    'axe': const EcranAxe(slug: _slugAxe),
    'recherche': const EcranRecherche(initiale: 'érosion'),
    'glossaire': const EcranGlossaire(),
    'hors-ligne': const EcranHorsLigne(),
  };

  for (final p in [Palette.ivoire, Palette.nuit, Palette.sepia]) {
    for (final f in _formats) {
      for (final e in ecrans.entries) {
        testWidgets('${e.key}${f.nom} en ${p.nom}', (t) async {
          t.view.physicalSize = f.taille;
          t.view.devicePixelRatio = f.densite;
          addTearDown(t.view.reset);
          Palette.courante = p;
          await t.pumpWidget(_sous(e.value, p));
          await _chargerImages(t);
          await t.pump(const Duration(milliseconds: 900));
          await t.pump(const Duration(milliseconds: 900));
          // L'image est écrite avant le verdict : un débordement doit se
          // regarder, pas seulement se lire dans un journal de test.
          final incident = t.takeException();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('apercu/${e.key}-${p.id}${f.nom}.png'),
          );
          expect(incident, isNull, reason: 'rendu de ${e.key}${f.nom}');
        });
      }

      // La correction du quiz ne s'atteint qu'en répondant : on coche le
      // premier choix de chaque question, puis on demande la correction.
      testWidgets('quiz-correction${f.nom} en ${p.nom}', (t) async {
        t.view.physicalSize = f.taille;
        t.view.devicePixelRatio = f.densite;
        addTearDown(t.view.reset);
        Palette.courante = p;
        await t.pumpWidget(_sous(const EcranQuiz(quizId: _quiz), p));
        await _chargerImages(t);
        await t.pump(const Duration(milliseconds: 900));
        await t.pump(const Duration(milliseconds: 900));

        final questions = (_quizJson['questions'] as List).cast<Map<String, dynamic>>();
        for (var i = 0; i < questions.length; i++) {
          final choix = _texte('${(questions[i]['choix'] as List).first}');
          await t.ensureVisible(choix);
          await t.pumpAndSettle();
          await t.tap(choix);
          await t.pumpAndSettle();
          final bouton = _texte(i == questions.length - 1 ? 'Voir ma correction' : 'Suivant');
          await t.ensureVisible(bouton);
          await t.pumpAndSettle();
          await t.tap(bouton);
          await t.pump(const Duration(milliseconds: 900));
          await t.pump(const Duration(milliseconds: 900));
        }

        final incident = t.takeException();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('apercu/quiz-correction-${p.id}${f.nom}.png'),
        );
        expect(incident, isNull, reason: 'correction du quiz${f.nom}');
      });
    }
  }
}
