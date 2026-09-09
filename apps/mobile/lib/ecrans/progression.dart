import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../widgets/cartes.dart';
import '../widgets/etats.dart';

class EcranProgression extends ConsumerWidget {
  const EcranProgression({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progression = ref.watch(progressionProvider);
    final t = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: Couleurs.or,
          onRefresh: () async {
            ref.invalidate(progressionProvider);
            ref.invalidate(regulariteProvider);
            ref.invalidate(maitriseProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text('Progression', style: t.textTheme.headlineSmall),
              const SizedBox(height: 20),
              progression.when(
                loading: () => const SqueletteCarte(lignes: 4),
                error: (e, _) => EtatErreur(
                  erreur: e,
                  reessayer: () => ref.invalidate(progressionProvider),
                ),
                data: (p) => Column(
                  children: [
                    _Anneau(progression: p),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _Tuile(
                            valeur: dureeLisible(p.minutesLues),
                            libelle: 'de lecture',
                            icone: Icons.schedule_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Tuile(
                            valeur: '${p.ouvragesTermines}',
                            libelle: p.ouvragesTermines > 1
                                ? 'ouvrages terminés'
                                : 'ouvrage terminé',
                            icone: Icons.auto_stories_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _Tuile(
                            valeur: p.scoreMoyen == null
                                ? '-'
                                : '${(p.scoreMoyen! * 100).round()} %',
                            libelle: 'de réussite aux quiz',
                            icone: Icons.quiz_rounded,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Tuile(
                            valeur: '${p.notionsMaitrisees}',
                            libelle: 'notions acquises',
                            icone: Icons.psychology_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Text('Régularité', style: t.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                "Douze semaines. Ce sont les trous qui comptent, pas les pics.",
                style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
              ),
              const SizedBox(height: 16),
              const _Regularite(),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: Text('Carte des notions', style: t.textTheme.titleLarge),
                  ),
                  // La carte dit où l'on en est ; le glossaire dit ce qu'il y a
                  // à savoir. L'un sans l'autre laisse le lecteur devant un
                  // constat sans issue.
                  TextButton(
                    onPressed: () => context.push('/notions'),
                    child: const Text('Toutes les notions'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const _Maitrise(),
              const SizedBox(height: 30),
              Text('Ce que vous avez fait', style: t.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                "Le détail dont sont tirés les chiffres ci-dessus.",
                style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
              ),
              const SizedBox(height: 14),
              const _Journal(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le journal d'activité.
///
/// La table est en ajout seul et porte tout ce qui a été fait. La montrer telle
/// quelle permet de vérifier un total qu'on trouverait douteux : un compteur
/// qu'on ne peut pas recouper est un compteur qu'on finit par ignorer.
class _Journal extends ConsumerWidget {
  const _Journal();

  /// Ce que raconte chaque type d'évènement, du point de vue du lecteur et non
  /// de la base. Un type inconnu s'affiche sous son nom technique plutôt que de
  /// disparaître, sinon le journal mentirait par omission.
  static const _recits = {
    'quiz_attempt': ('Quiz passé', Icons.quiz_outlined),
    'question_asked': ("Question à l'agent", Icons.forum_outlined),
    'note_created': ('Note prise', Icons.edit_note_rounded),
    'read_pages': ('Pages lues', Icons.menu_book_outlined),
    'opened_doc': ('Ouvrage ouvert', Icons.auto_stories_outlined),
    'session_done': ('Séance terminée', Icons.check_circle_outline_rounded),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final journal = ref.watch(journalProvider);
    return journal.when(
      loading: () => const SqueletteCarte(lignes: 4),
      error: (e, _) => EtatErreur(
        erreur: e,
        reessayer: () => ref.invalidate(journalProvider),
      ),
      data: (lignes) {
        if (lignes.isEmpty) {
          return Text(
            "Rien encore. Votre première séance ouvrira ce journal.",
            style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud),
          );
        }
        return Column(
          children: [
            for (final l in lignes.take(40)) _LigneJournal(evenement: l, recits: _recits),
          ],
        );
      },
    );
  }
}

class _LigneJournal extends StatelessWidget {
  const _LigneJournal({required this.evenement, required this.recits});

  final Map<String, dynamic> evenement;
  final Map<String, (String, IconData)> recits;

  /// « il y a 3 h », « hier », « le 12/08 ». Une date absolue pour ce qui est
  /// vieux, un repère relatif pour ce qui est récent : c'est ainsi qu'on situe
  /// spontanément ce qu'on vient de faire.
  String _quand(DateTime? d) {
    if (d == null) return '';
    final ecart = DateTime.now().difference(d);
    if (ecart.inMinutes < 60) return 'il y a ${ecart.inMinutes} min';
    if (ecart.inHours < 24) return 'il y a ${ecart.inHours} h';
    if (ecart.inDays == 1) return 'hier';
    if (ecart.inDays < 7) return 'il y a ${ecart.inDays} jours';
    return 'le ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  /// Le chiffre qui donne sa valeur à la ligne : un score, un nombre de pages.
  String _precision() {
    final d = evenement['details'];
    if (d is! Map) return '';
    final score = d['score'];
    if (score is num) return '${(score <= 1 ? score * 100 : score).round()} %';
    final debut = d['page_debut'], fin = d['page_fin'];
    if (debut != null && fin != null) return 'p. $debut à $fin';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final type = '${evenement['type']}';
    final recit = recits[type];
    final quand = _quand(DateTime.tryParse('${evenement['le']}')?.toLocal());
    final precision = _precision();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(recit?.$2 ?? Icons.circle_outlined, size: 18, color: Couleurs.grisChaud),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recit?.$1 ?? type.replaceAll('_', ' '),
                    style: t.textTheme.bodyMedium),
                if ('${evenement['ouvrage'] ?? ''}'.isNotEmpty)
                  Text('${evenement['ouvrage']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (precision.isNotEmpty)
                Text(precision,
                    style: t.textTheme.labelSmall?.copyWith(color: Couleurs.orTexte)),
              Text(quand,
                  style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Anneau extends StatelessWidget {
  const _Anneau({required this.progression});
  final Progression progression;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 92,
                  height: 92,
                  child: CircularProgressIndicator(
                    value: progression.avancement,
                    strokeWidth: 8,
                    strokeCap: StrokeCap.round,
                    backgroundColor: t.colorScheme.surfaceContainer,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${(progression.avancement * 100).round()}',
                        style: t.textTheme.headlineSmall?.copyWith(fontSize: 24)),
                    Text('%', style: t.textTheme.labelSmall
                        ?.copyWith(color: Couleurs.grisChaud)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${progression.seancesFaites} séance'
                  '${progression.seancesFaites > 1 ? 's' : ''} sur ${progression.seancesTotal}',
                  style: t.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                if (progression.enRetard > 0)
                  Text(
                    '${progression.enRetard} en retard',
                    style: t.textTheme.bodySmall?.copyWith(color: Couleurs.terracotta),
                  )
                else if (progression.seancesTotal > 0)
                  Text(
                    'Vous êtes à jour.',
                    style: t.textTheme.bodySmall?.copyWith(color: Couleurs.sauge),
                  )
                else
                  Text(
                    'Aucun chronogramme actif.',
                    style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile({required this.valeur, required this.libelle, required this.icone});
  final String valeur;
  final String libelle;
  final IconData icone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 19, color: Couleurs.orTexte),
          const SizedBox(height: 12),
          Text(valeur, style: t.textTheme.titleLarge?.copyWith(fontSize: 21)),
          const SizedBox(height: 2),
          Text(libelle,
              style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud)),
        ],
      ),
    );
  }
}

class _Regularite extends ConsumerWidget {
  const _Regularite();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(regulariteProvider);
    final t = Theme.of(context);

    return points.when(
      loading: () => const Squelette(hauteur: 96, rayon: 16),
      error: (_, _) => const SizedBox.shrink(),
      data: (liste) {
        if (liste.isEmpty) return const SizedBox.shrink();
        final max = liste.fold<int>(1, (m, p) => (p['minutes'] as int) > m ? p['minutes'] as int : m);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.dividerTheme.color ?? Couleurs.traitClair),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 68,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final p in liste.skip(liste.length > 84 ? liste.length - 84 : 0))
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0.6),
                          child: Container(
                            height: (p['minutes'] as int) == 0
                                ? 3
                                : 6 + 62 * ((p['minutes'] as int) / max),
                            decoration: BoxDecoration(
                              color: (p['actions'] as int) > 0
                                  ? Couleurs.or
                                  : t.colorScheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('il y a 12 semaines',
                      style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
                  Text("aujourd'hui",
                      style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Maitrise extends ConsumerWidget {
  const _Maitrise();

  static const _couleurs = {
    'acquis': Couleurs.sauge,
    'en_cours': Couleurs.or,
    'fragile': Couleurs.terracotta,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notions = ref.watch(maitriseProvider);
    final t = Theme.of(context);

    return notions.when(
      loading: () => const Squelette(hauteur: 90, rayon: 16),
      error: (_, _) => const SizedBox.shrink(),
      data: (liste) {
        if (liste.isEmpty) {
          return const EtatMessage(
            icone: Icons.psychology_outlined,
            titre: 'Rien encore',
            texte: "Les notions apparaîtront ici au fil des quiz : celles que vous "
                "ratez sont suivies et reviennent régulièrement.",
          );
        }
        return Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final n in liste)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: (_couleurs[n.niveau] ?? Couleurs.grisChaud).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  n.terme,
                  style: t.textTheme.labelMedium?.copyWith(
                    color: _couleurs[n.niveau] ?? Couleurs.grisChaud,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
