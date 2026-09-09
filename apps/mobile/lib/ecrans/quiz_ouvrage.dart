import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/etats.dart';
import '../widgets/invitation.dart';

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
      appBar: AppBar(title: Text(titre ?? 'Quiz de l\'ouvrage')),
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
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(
                  '${d['total_questions']} questions sur ${lots.length} chapitres',
                  style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud),
                ),
                const SizedBox(height: 16),
                const InvitationCompte(
                  compact: true,
                  raison: "Créez votre compte pour passer ces quiz et garder vos scores.",
                ),
                for (final c in lots)
                  _LigneQuiz(
                    lot: c,
                    score: meilleurs['${c['chapitre_id']}'],
                    connecte: session.etat == EtatSession.connecte,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LigneQuiz extends StatelessWidget {
  const _LigneQuiz({required this.lot, required this.score, required this.connecte});

  final Map<String, dynamic> lot;
  final num? score;
  final bool connecte;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final n = lot['nb_questions'] as int? ?? 0;
    final pages = lot['page_debut'] == null
        ? ''
        : 'p. ${lot['page_debut']}${lot['page_fin'] != null ? ' à ${lot['page_fin']}' : ''}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('${lot['titre'] ?? 'Chapitre'}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium),
        subtitle: Text(
          [if (pages.isNotEmpty) pages, '$n question${n > 1 ? 's' : ''}'].join('  ·  '),
          style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
        ),
        trailing: score == null
            ? const Icon(Icons.chevron_right_rounded, size: 22)
            : _Pastille(score: score!),
        enabled: connecte,
        onTap: connecte ? () => context.push('/quiz/${lot['quiz_id']}') : null,
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
    final pourcent = (score <= 1 ? score * 100 : score).round();
    final teinte = pourcent >= 80
        ? Couleurs.sauge
        : (pourcent >= 50 ? Couleurs.or : Couleurs.terracotta);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: teinte.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$pourcent %',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: pourcent >= 80 ? const Color(0xFF476A4E) : Couleurs.orTexte,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
