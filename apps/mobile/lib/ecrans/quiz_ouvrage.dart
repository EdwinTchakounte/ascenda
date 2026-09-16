import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/palette.dart';
import '../widgets/etats.dart';
import '../widgets/invitation.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// Tous les quiz d'un ouvrage, hors séance.
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
      body: SafeArea(
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
                icone: Icons.quiz_outlined,
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
                SurfaceHeros(
                  child: Row(
                    children: [
                      IconePastille(Icons.quiz_rounded, couleur: p.accentSurHeros, taille: 50),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: '${d['total_questions']}'),
                                TextSpan(
                                  text: ' questions',
                                  style: t.textTheme.titleMedium?.copyWith(color: p.surHerosDoux),
                                ),
                              ]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.headlineMedium?.copyWith(color: p.surHeros, height: 1.1),
                            ),
                            const SizedBox(height: 4),
                            Texte(
                              'sur ${lots.length} chapitres',
                              style: t.textTheme.bodyMedium?.copyWith(color: p.surHerosDoux),
                            ),
                            if (tentes > 0) ...[
                              const SizedBox(height: 10),
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
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const InvitationCompte(
                  compact: true,
                  raison: "Créez votre compte pour passer ces quiz et garder vos scores.",
                ),
                const SizedBox(height: 4),
                for (var i = 0; i < lots.length; i++) ...[
                  _LigneQuiz(
                    numero: i + 1,
                    lot: lots[i],
                    score: meilleurs['${lots[i]['chapitre_id']}'],
                    connecte: connecte,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LigneQuiz extends StatelessWidget {
  const _LigneQuiz({required this.numero, required this.lot, required this.score, required this.connecte});

  final int numero;
  final Map<String, dynamic> lot;
  final num? score;
  final bool connecte;

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
      child: Surface(
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        onTap: connecte ? () => context.push('/quiz/${lot['quiz_id']}') : null,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.accentVoile, borderRadius: Rayons.moyen),
              child: Texte(
                '$numero',
                style: t.textTheme.titleMedium?.copyWith(
                  color: p.accentTexte,
                  fontFamily: t.textTheme.headlineSmall?.fontFamily,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Texte('${lot['titre'] ?? 'Chapitre'}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium?.copyWith(fontSize: 15)),
                  const SizedBox(height: 3),
                  Texte(
                    [if (pages.isNotEmpty) pages, '$n question${n > 1 ? 's' : ''}'].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            score == null
                ? Icon(connecte ? Icons.chevron_right_rounded : Icons.lock_outline_rounded, size: 22, color: p.attenue)
                : _Pastille(score: score!),
          ],
        ),
      ),
    );
  }
}

/// Le meilleur score obtenu, en couleur.
///
/// Le vert marque un chapitre acquis, l'or un chapitre à consolider, la
/// terracotta un chapitre à reprendre. Trois seuils suffisent : au delà, on
/// demande au lecteur de lire une échelle au lieu de lire son résultat.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.score});
  final num score;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pourcent = (score <= 1 ? score * 100 : score).round();
    final teinte = pourcent >= 80
        ? p.succes
        : (pourcent >= 50 ? p.accentTexte : p.alerte);
    return Pastille(
      '$pourcent %',
      icone: pourcent >= 80 ? Icons.star_rounded : null,
      couleur: teinte,
    );
  }
}
