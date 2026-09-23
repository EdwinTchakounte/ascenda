// Le banc de capture : il rend les écrans hors ligne et les écrit en images.
//
// Ce n'est pas un test de non-régression, c'est un outil de revue : on juge un
// design sur des pixels, pas sur du code. Les écrans sont nourris par un client
// d'API factice, puis capturés dans les quatre thèmes.
//
//   flutter test test/apercu_test.dart --update-goldens
//
// Les images sortent dans test/apercu/. Elles ne sont pas versionnées : le
// dépôt n'a pas à porter des captures d'écran, et un écart de rendu entre deux
// machines ferait échouer la suite pour rien.
@Tags(['apercu'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ascenda/api/client.dart';
import 'package:ascenda/api/modeles.dart';
import 'package:ascenda/ecrans/aujourdhui.dart';
import 'package:ascenda/ecrans/bibliotheque.dart';
import 'package:ascenda/ecrans/fiche_ouvrage.dart';
import 'package:ascenda/ecrans/lecteur.dart';
import 'package:ascenda/ecrans/progression.dart';
import 'package:ascenda/etat/fournisseurs.dart';
import 'package:ascenda/etat/session.dart';
import 'package:ascenda/theme/palette.dart';
import 'package:ascenda/theme/theme.dart';

const _doc = 'd1';
const _chap = 'c1';

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
    if (chemin == '/auth/moi') return _lecteur;
    if (chemin == '/aujourdhui') return _aujourdhui;
    if (chemin == '/axes') return _axes;
    if (chemin == '/bibliotheque') return _biblio;
    if (chemin == '/bibliotheque/$_doc') return _fiche;
    if (chemin == '/bibliotheque/$_doc/sommaire') return _sommaire;
    if (chemin == '/lecteur/$_doc/chapitre/$_chap') return _chapitre;
    if (chemin == '/progression') return _progression;
    if (chemin == '/progression/regularite') return _regularite;
    if (chemin == '/chronogrammes') return [_chronogramme];
    if (chemin == '/concepts/maitrise') return _notions;
    if (chemin == '/concepts/a-reviser') return const [];
    return const [];
  }

  @override
  Future<dynamic> post(String chemin, {Object? corps, bool auth = true}) async => null;
}

const _lecteur = {'id': 'u1', 'email': 'awa@example.com', 'nom': 'Awa Ndiaye', 'plan': 'premium'};

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
  {'slug': '12-agriculture-elevage', 'label': 'Agriculture et élevage', 'nb_ouvrages': 1, 'nb_pages': 1698,
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
    _ouvrage(_doc, "Mémento de l'agronome", '12-agriculture-elevage', 1698),
    _ouvrage('d2', 'ChatGPT. Le guide du débutant', '01-ia-fondamentaux', 240),
    _ouvrage('d3', 'Nations nègres et culture', '07-afrique-histoire-pensee', 560),
    _ouvrage('d4', 'La Planète invisible', '11-sciences-environnement', 320),
    _ouvrage('d5', "Lexique de l'intelligence artificielle", '01-ia-fondamentaux', 48),
  ],
};

final _fiche = {
  ..._ouvrage(_doc, "Mémento de l'agronome", '12-agriculture-elevage', 1698),
  'sous_titre': null,
  'editeur': 'CIRAD, GRET, ministère des Affaires étrangères',
  'axes': [
    {'slug': '12-agriculture-elevage', 'label': 'Agriculture et élevage'},
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

final _sommaire = [
  for (var i = 1; i <= 12; i++)
    {
      'id': i == 1 ? _chap : 'c$i',
      'ordre': i,
      'titre': [
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
      ][i - 1],
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
     'minutes': (i * 7) % 45},
];

const _chronogramme = {
  'id': 'ch1',
  'axe_label': 'Agriculture et élevage',
  'statut': 'actif',
  'seances': 24,
  'faites': 11,
  'en_retard': 1,
};

final _notions = [
  {'id': 'n1', 'terme': 'Érosion hydrique', 'definition': "Le transport des particules de sol par l'eau.",
   'maitrise': 0.8, 'occurrences': 12},
  {'id': 'n2', 'terme': 'Jachère', 'definition': 'Une terre laissée au repos pour se reconstituer.',
   'maitrise': 0.4, 'occurrences': 6},
];

Widget _sous(Widget ecran, Palette p) => ProviderScope(
      overrides: [
        clientApiProvider.overrideWithValue(_Faux()),
        // Le sondage de l'état du service tourne toutes les deux minutes : il
        // n'a rien à faire dans un banc de capture.
        etatServiceProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(
        theme: ThemeAscenda.depuis(p),
        home: ecran,
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final ecrans = <String, Widget>{
    'accueil': const EcranAujourdhui(),
    'bibliotheque': const EcranBibliotheque(),
    'fiche': const FicheOuvrage(documentId: _doc),
    'lecteur': const EcranLecteur(documentId: _doc, chapitreId: _chap),
    'progres': const EcranProgression(),
  };

  for (final p in [Palette.ivoire, Palette.nuit, Palette.sepia]) {
    for (final e in ecrans.entries) {
      testWidgets('${e.key} en ${p.nom}', (t) async {
        t.view.physicalSize = const Size(1080, 2000);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        Palette.courante = p;
        await t.pumpWidget(_sous(e.value, p));
        await t.pump(const Duration(milliseconds: 900));
        await t.pump(const Duration(milliseconds: 900));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('apercu/${e.key}-${p.id}.png'),
        );
      });
    }
  }
}
