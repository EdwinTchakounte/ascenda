import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../widgets/etats.dart';
import '../widgets/illustrations.dart';
import '../widgets/invitation.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// Tous les quiz d'un ouvrage, hors séance : le cahier d'exercices du volume,
/// chapitre après chapitre, chacun avec son folio.
///
/// Un livre du corpus porte souvent plus de deux cents questions, et on ne
/// pouvait y accéder qu'une séance à la fois. Cet écran ouvre le livre par ses
/// exercices : pour réviser avant un examen, ou reprendre un chapitre raté sans
/// attendre que le chronogramme le reprogramme.
class EcranQuizOuvrage extends ConsumerWidget {
  const EcranQuizOuvrage({super.key, required this.documentId, this.titre});

  final String documentId;
  final String? titre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final p = context.palette;
    final quiz = ref.watch(quizOuvrageProvider(documentId));
    final session = ref.watch(sessionProvider);
    final historique = session.etat == EtatSession.connecte
        ? ref.watch(historiqueQuizProvider(documentId)).valueOrNull
        : null;

    // Le meilleur score par chapitre : c'est ce qu'on veut voir en face d'un
    // titre, pas la liste de toutes les tentatives.
    final meilleurs = <String, num>{};
    for (final h in historique ?? const []) {
      final id = '${h['chapitre_id']}';
      final s = h['score'];
      if (s is num && (meilleurs[id] == null || s > meilleurs[id]!)) meilleurs[id] = s;
    }

    return Scaffold(
      appBar: AppBar(title: Texte(titre ?? 'Quiz de l\'ouvrage', maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: FondPapier(
        child: SafeArea(
          bottom: false,
          child: quiz.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: SqueletteCarte(lignes: 5),
            ),
            error: (e, _) => EtatErreur(
              erreur: e,
              reessayer: () => ref.invalidate(quizOuvrageProvider(documentId)),
            ),
            data: (d) {
              // Les chapitres d'appareil sont enregistrés avec zéro question et
              // le motif qui l'explique. Les montrer ferait une liste où une
              // ligne sur trois n'est pas cliquable.
              final lots = ((d['chapitres'] as List?) ?? [])
                  .cast<Map<String, dynamic>>()
                  .where((c) => (c['nb_questions'] as int? ?? 0) > 0)
                  .toList();
              if (lots.isEmpty) {
                return const EtatMessage(
                  scene: Scene.pageBlanche,
                  titre: 'Pas encore de quiz',
                  texte: "Les questions de cet ouvrage n'ont pas encore été préparées. "
                      "Elles arriveront avec les prochaines mises à jour du corpus.",
                );
              }
              final connecte = session.etat == EtatSession.connecte;
              // Les chapitres déjà tentés, comptés sur les scores déjà chargés.
              final tentes = lots.where((c) => meilleurs.containsKey('${c['chapitre_id']}')).length;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Apparition(
                    child: SurfaceHeros(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          EtiquetteCrochet("cahier d'exercices", couleur: p.accentSurHeros),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              CompteurAnime(
                                d['total_questions'] is num ? d['total_questions'] as num : 0,
                                style: t.textTheme.headlineMedium?.copyWith(color: p.surHeros, height: 1.1),
                              ),
                              Flexible(
                                child: Texte(
                                  ' questions',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.textTheme.titleMedium?.copyWith(color: p.surHerosDoux),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Texte(
                            'sur ${lots.length} chapitres',
                            style: t.textTheme.bodyMedium?.copyWith(color: p.surHerosDoux),
                          ),
                          if (tentes > 0) ...[
                            const SizedBox(height: 12),
                            Jauge(
                              valeur: tentes / lots.length,
                              hauteur: 6,
                              piste: p.surHeros.withValues(alpha: 0.12),
                            ),
                            const SizedBox(height: 6),
                            Texte(
                              '$tentes déjà tenté${tentes > 1 ? 's' : ''}',
                              style: t.textTheme.labelSmall?.copyWith(color: p.surHerosDoux),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const InvitationCompte(
                    compact: true,
                    raison: "Créez votre compte pour passer ces quiz et garder vos scores.",
                  ),
                  const SizedBox(height: 10),
                  const Apparition(rang: 1, child: TitreCourant('sommaire des exercices')),
                  const SizedBox(height: 12),
                  // Le sommaire est une seule feuille : des lignes numérotées
                  // séparées par des filets, et non douze cartes empilées.
                  Surface(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < lots.length; i++)
                          Apparition(
                            // La cascade s'arrête au septième rang : au delà, la
                            // dernière ligne arriverait après que l'oeil est passé.
                            rang: 1 + (i < 6 ? i + 1 : 6),
                            child: _LigneQuiz(
                              numero: i + 1,
                              lot: lots[i],
                              score: meilleurs['${lots[i]['chapitre_id']}'],
                              connecte: connecte,
                              derniere: i == lots.length - 1,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  const Fleuron(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Une ligne du sommaire des exercices : son numéro à l'encre, son titre, son
/// folio, et le meilleur score obtenu.
class _LigneQuiz extends StatelessWidget {
  const _LigneQuiz({
    required this.numero,
    required this.lot,
    required this.score,
    required this.connecte,
    required this.derniere,
  });

  final int numero;
  final Map<String, dynamic> lot;
  final num? score;
  final bool connecte;
  final bool derniere;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final n = lot['nb_questions'] as int? ?? 0;
    final pages = lot['page_debut'] == null
        ? ''
        : 'p. ${lot['page_debut']}${lot['page_fin'] != null ? ' à ${lot['page_fin']}' : ''}';

    // Sans compte, la ligne reste lisible mais en retrait : l'invitation
    // au-dessus dit pourquoi on ne peut pas l'ouvrir.
    return Opacity(
      opacity: connecte ? 1 : 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: connecte ? () => context.push('/quiz/${lot['quiz_id']}') : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Lettrine('$numero', taille: 38),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Texte('${lot['titre'] ?? 'Chapitre'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleMedium?.copyWith(fontSize: 15)),
                        const SizedBox(height: 3),
                        Texte(
                          [if (pages.isNotEmpty) pages, '${millier(n)} question${n > 1 ? 's' : ''}'].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 0.6),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  score == null
                      ? (connecte
                          ? IconeAscenda(Icone.fleche, taille: 20, couleur: p.attenue)
                          : Icon(Icons.lock_outline_rounded, size: 20, color: p.attenue))
                      : _Score(score: score!),
                ],
              ),
            ),
          ),
          if (!derniere) const Filet(),
        ],
      ),
    );
  }
}

/// Le meilleur score obtenu, en couleur.
///
/// Le vert marque un chapitre acquis, l'or un chapitre à consolider, la
/// terracotta un chapitre à reprendre. Trois seuils suffisent : au delà, on
/// demande au lecteur de lire une échelle au lieu de lire son résultat.
class _Score extends StatelessWidget {
  const _Score({required this.score});
  final num score;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pourcent = (score <= 1 ? score * 100 : score).round();
    final teinte = pourcent >= 80
        ? p.succes
        : (pourcent >= 50 ? p.accentTexte : p.alerte);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: teinte.withValues(alpha: p.sombre ? 0.14 : 0.08),
        border: Border.all(color: teinte.withValues(alpha: 0.45)),
      ),
      child: Texte(
        '$pourcent %',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: teinte,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
