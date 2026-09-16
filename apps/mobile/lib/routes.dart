import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'ecrans/abonnement.dart';
import 'ecrans/agent.dart';
import 'ecrans/auth.dart';
import 'ecrans/axe.dart';
import 'ecrans/bibliotheque.dart';
import 'ecrans/chronogramme.dart';
import 'ecrans/codes.dart';
import 'ecrans/coque.dart';
import 'ecrans/demarrage.dart';
import 'ecrans/diagnostic.dart';
import 'ecrans/fiche_ouvrage.dart';
import 'ecrans/glossaire.dart';
import 'ecrans/hors_ligne.dart';
import 'ecrans/lecteur.dart';
import 'ecrans/mot_de_passe.dart';
import 'ecrans/profil.dart';
import 'ecrans/progression.dart';
import 'ecrans/quiz.dart';
import 'ecrans/quiz_ouvrage.dart';
import 'ecrans/recherche.dart';
import 'ecrans/revision.dart';
import 'ecrans/aujourdhui.dart';
import 'ecrans/lecteur_pdf.dart';
import 'ecrans/cercle.dart';
import 'etat/session.dart';
import 'theme/texte.dart';

final _racine = GlobalKey<NavigatorState>();
final _coque = GlobalKey<NavigatorState>();

/// Réveille le routeur quand la session change, sans le reconstruire.
///
/// Reconstruire le GoRouter à chaque changement d'état ramènerait l'application
/// à sa route initiale : après une inscription, l'utilisateur était renvoyé à
/// l'accueil au lieu du diagnostic. On notifie donc, on ne recrée pas.
class _EveilSession extends ChangeNotifier {
  _EveilSession(this._ref) {
    _ref.listen<Session>(sessionProvider, (_, _) => notifyListeners());
  }
  final Ref _ref;
}

/// Le routeur est créé une seule fois. La redirection lit l'état courant à
/// chaque navigation : aucun écran n'a besoin de code de garde.
final routeurProvider = Provider<GoRouter>((ref) {
  final eveil = _EveilSession(ref);
  ref.onDispose(eveil.dispose);

  return GoRouter(
    refreshListenable: eveil,
    navigatorKey: _racine,
    initialLocation: '/aujourdhui',
    redirect: (context, etat) {
      final session = ref.read(sessionProvider);
      final chemin = etat.matchedLocation;
      final surAuth = chemin.startsWith('/bienvenue') || chemin.startsWith('/connexion');

      // Tant qu'on ignore s'il y a une session, on n'envoie l'utilisateur
      // nulle part : on l'attend sur un écran qui porte la marque.
      if (session.etat == EtatSession.inconnu) {
        return chemin == '/demarrage' ? null : '/demarrage';
      }
      if (chemin == '/demarrage') {
        return session.etat == EtatSession.connecte ? '/aujourdhui' : '/bienvenue';
      }
      if (session.etat == EtatSession.deconnecte) {
        // La bibliothèque et les fiches restent consultables sans compte :
        // c'est la vitrine du produit, pas une zone protégée.
        final libre = chemin.startsWith('/bibliotheque') ||
            chemin.startsWith('/ouvrage') ||
            chemin.startsWith('/mot-de-passe-oublie') ||
            chemin.startsWith('/recherche') ||
            chemin.startsWith('/hors-ligne') ||
            chemin.startsWith('/notion') ||
            chemin.startsWith('/axe/');
        return (surAuth || libre) ? null : '/bienvenue';
      }
      return surAuth ? '/aujourdhui' : null;
    },
    routes: [
      GoRoute(path: '/demarrage', builder: (c, s) => const EcranDemarrage()),
      GoRoute(path: '/bienvenue', builder: (c, s) => const EcranBienvenue()),
      GoRoute(
        path: '/connexion',
        builder: (c, s) => EcranConnexion(connexion: s.uri.queryParameters['mode'] == 'connexion'),
      ),
      GoRoute(path: '/abonnement', builder: (c, s) => const EcranAbonnement()),
      GoRoute(path: '/codes', builder: (c, s) => const EcranCodes()),
      GoRoute(
        path: '/mot-de-passe-oublie',
        builder: (c, s) => EcranMotDePasseOublie(email: s.uri.queryParameters['email']),
      ),
      GoRoute(path: '/mot-de-passe', builder: (c, s) => const EcranChangerMotDePasse()),
      GoRoute(
        path: '/ouvrage/:id/quiz',
        builder: (c, s) => EcranQuizOuvrage(
          documentId: s.pathParameters['id']!,
          titre: s.uri.queryParameters['titre'],
        ),
      ),
      GoRoute(path: '/axe/:slug', builder: (c, s) => EcranAxe(slug: s.pathParameters['slug']!)),
      GoRoute(path: '/notions', builder: (c, s) => EcranGlossaire(axe: s.uri.queryParameters['axe'])),
      GoRoute(path: '/notion/:id', builder: (c, s) => EcranNotion(notionId: s.pathParameters['id']!)),
      GoRoute(
        path: '/recherche',
        builder: (c, s) => EcranRecherche(initiale: s.uri.queryParameters['q']),
      ),
      GoRoute(path: '/diagnostic', builder: (c, s) => DiagnosticEcran(axe: s.uri.queryParameters['axe'])),
      GoRoute(
        parentNavigatorKey: _racine,
        path: '/ouvrage/:id',
        builder: (c, s) => FicheOuvrage(documentId: s.pathParameters['id']!),
      ),
      GoRoute(
        parentNavigatorKey: _racine,
        path: '/cercle/ami/:id',
        builder: (c, s) => EcranConversation(amiId: s.pathParameters['id']!, nom: s.uri.queryParameters['nom']),
      ),
      GoRoute(
        parentNavigatorKey: _racine,
        path: '/pdf/:doc',
        builder: (c, s) => EcranLecteurPdf(
          documentId: s.pathParameters['doc']!,
          titre: s.uri.queryParameters['titre'],
          page: int.tryParse(s.uri.queryParameters['page'] ?? ''),
        ),
      ),
      GoRoute(
        parentNavigatorKey: _racine,
        path: '/lecture/:doc/:chap',
        builder: (c, s) => EcranLecteur(
          documentId: s.pathParameters['doc']!,
          chapitreId: s.pathParameters['chap']!,
          seanceId: s.uri.queryParameters['seance'],
          livrable: s.uri.queryParameters['livrable'],
          livrableId: s.uri.queryParameters['livrable_id'],
          pageDebut: int.tryParse(s.uri.queryParameters['page_debut'] ?? ''),
          pageFin: int.tryParse(s.uri.queryParameters['page_fin'] ?? ''),
        ),
      ),
      GoRoute(
        parentNavigatorKey: _racine,
        path: '/quiz/:id',
        builder: (c, s) => EcranQuiz(
          quizId: s.pathParameters['id']!,
          seanceId: s.uri.queryParameters['seance'],
        ),
      ),
      GoRoute(
        parentNavigatorKey: _racine,
        path: '/chronogramme/:id',
        builder: (c, s) => EcranChronogramme(chronogrammeId: s.pathParameters['id']!),
      ),
      // Hors de la barre d'onglets : ouverts depuis le tiroir, en plein écran.
      GoRoute(parentNavigatorKey: _racine, path: '/profil', builder: (c, s) => const EcranProfil()),
      GoRoute(parentNavigatorKey: _racine, path: '/cercle', builder: (c, s) => const EcranCercle()),
      GoRoute(parentNavigatorKey: _racine, path: '/hors-ligne', builder: (c, s) => const EcranHorsLigne()),
      GoRoute(
        parentNavigatorKey: _racine,
        path: '/revision',
        builder: (c, s) => const EcranRevision(),
      ),
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _racine,
        builder: (c, s, coque) => CoqueAscenda(coque: coque),
        branches: [
          StatefulShellBranch(navigatorKey: _coque, routes: [
            GoRoute(path: '/aujourdhui', builder: (c, s) => const EcranAujourdhui()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/bibliotheque', builder: (c, s) => const EcranBibliotheque()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/agent', builder: (c, s) => const EcranAgent()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/progression', builder: (c, s) => const EcranProgression()),
          ]),
        ],
      ),
    ],
    errorBuilder: (c, s) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_outlined, size: 40),
              const SizedBox(height: 16),
              Texte('Cette page n\'existe pas.',
                  style: Theme.of(c).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () => c.go('/aujourdhui'),
                child: const Texte("Revenir à l'accueil"),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});
