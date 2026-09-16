import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../widgets/cartes.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// L'onglet des progrès : l'avancement en grand, les chiffres clés en tuiles,
/// puis la régularité, la carte des notions et le journal qui fonde le tout.
///
/// Aucun chiffre n'est fabriqué ici : tout vient des trois fournisseurs de la
/// progression, et le journal permet de recouper chacun d'eux.
class EcranProgression extends ConsumerWidget {
  const EcranProgression({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progression = ref.watch(progressionProvider);
    final t = Theme.of(context);
    final p = context.palette;

    return Scaffold(
      body: RefreshIndicator(
        color: p.accent,
        onRefresh: () async {
          ref.invalidate(progressionProvider);
          ref.invalidate(regulariteProvider);
          ref.invalidate(maitriseProvider);
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              leading: const BoutonMenu(),
              titleSpacing: 4,
              toolbarHeight: 68,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Texte('Votre parcours', style: t.textTheme.labelMedium?.copyWith(color: p.attenue)),
                  Texte('Progression', style: t.textTheme.titleLarge?.copyWith(fontSize: 21)),
                ],
              ),
              actions: const [AvatarCompte()],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 36),
              sliver: SliverList.list(children: [
                progression.when(
                  loading: () => const SqueletteCarte(lignes: 4),
                  error: (e, _) => EtatErreur(
                    erreur: e,
                    reessayer: () => ref.invalidate(progressionProvider),
                  ),
                  data: (pr) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Anneau(progression: pr),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _Tuile(
                              valeur: dureeLisible(pr.minutesLues),
                              libelle: 'de lecture',
                              icone: Icons.schedule_rounded,
                              couleur: p.accentTexte,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _Tuile(
                              valeur: '${pr.ouvragesTermines}',
                              libelle: pr.ouvragesTermines > 1 ? 'ouvrages terminés' : 'ouvrage terminé',
                              icone: Icons.auto_stories_rounded,
                              couleur: Couleurs.poles['02']!,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _Tuile(
                              valeur: pr.scoreMoyen == null ? '-' : '${(pr.scoreMoyen! * 100).round()}',
                              unite: pr.scoreMoyen == null ? null : '%',
                              libelle: 'de réussite aux quiz',
                              icone: Icons.quiz_rounded,
                              couleur: Couleurs.poles['08']!,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _Tuile(
                              valeur: '${pr.notionsMaitrisees}',
                              libelle: 'notions acquises',
                              icone: Icons.psychology_rounded,
                              couleur: p.succes,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const TitreSection(
                  'Régularité',
                  sousTitre: 'Douze semaines. Ce sont les trous qui comptent, pas les pics.',
                ),
                const SizedBox(height: 12),
                const _Regularite(),
                const SizedBox(height: 28),
                // La carte dit où l'on en est ; le glossaire dit ce qu'il y a
                // à savoir. L'un sans l'autre laisse le lecteur devant un
                // constat sans issue.
                TitreSection(
                  'Carte des notions',
                  action: 'Toutes les notions',
                  onAction: () => context.push('/notions'),
                ),
                const SizedBox(height: 12),
                const _Maitrise(),
                const SizedBox(height: 28),
                const TitreSection(
                  'Ce que vous avez fait',
                  sousTitre: 'Le détail dont sont tirés les chiffres ci-dessus.',
                ),
                const SizedBox(height: 12),
                const _Journal(),
              ]),
            ),
          ],
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
    final p = context.palette;
    final journal = ref.watch(journalProvider);
    return journal.when(
      loading: () => const SqueletteCarte(lignes: 4),
      error: (e, _) => EtatErreur(
        erreur: e,
        reessayer: () => ref.invalidate(journalProvider),
      ),
      data: (lignes) {
        if (lignes.isEmpty) {
          return Surface(
            child: Row(
              children: [
                IconePastille(Icons.history_rounded, couleur: p.attenue, taille: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Texte(
                    "Rien encore. Votre première séance ouvrira ce journal.",
                    style: t.textTheme.bodyMedium?.copyWith(color: p.attenue),
                  ),
                ),
              ],
            ),
          );
        }
        final affichees = lignes.take(40).toList();
        return Surface(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            children: [
              for (var i = 0; i < affichees.length; i++)
                _LigneJournal(
                  evenement: affichees[i],
                  recits: _recits,
                  derniere: i == affichees.length - 1,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LigneJournal extends StatelessWidget {
  const _LigneJournal({required this.evenement, required this.recits, required this.derniere});

  final Map<String, dynamic> evenement;
  final Map<String, (String, IconData)> recits;

  /// La dernière ligne n'a pas de filet de frise sous elle.
  final bool derniere;

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
    final p = context.palette;
    final type = '${evenement['type']}';
    final recit = recits[type];
    final quand = _quand(DateTime.tryParse('${evenement['le']}')?.toLocal());
    final precision = _precision();
    final termine = type == 'session_done';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // La frise : une pastille par évènement, reliée à la suivante.
          Column(
            children: [
              IconePastille(
                recit?.$2 ?? Icons.circle_outlined,
                couleur: termine ? p.succes : p.accentTexte,
                taille: 32,
              ),
              if (!derniere)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(color: p.trait, borderRadius: Rayons.pilule),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Texte(
                    recit?.$1 ?? type.replaceAll('_', ' '),
                    style: t.textTheme.bodyMedium?.copyWith(color: p.encre, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ('${evenement['ouvrage'] ?? ''}'.isNotEmpty)
                    Texte('${evenement['ouvrage']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (precision.isNotEmpty)
                  Texte(precision,
                      style: t.textTheme.labelMedium?.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
                Texte(quand, style: t.textTheme.labelSmall?.copyWith(color: p.attenue)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La carte de mise en avant : l'anneau d'avancement du chronogramme.
class _Anneau extends StatelessWidget {
  const _Anneau({required this.progression});
  final Progression progression;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final pr = progression;
    return SurfaceHeros(
      child: Row(
        children: [
          SizedBox(
            width: 104,
            height: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: pr.avancement.clamp(0, 1).toDouble(),
                    strokeWidth: 10,
                    strokeCap: StrokeCap.round,
                    color: p.accentSurHeros,
                    backgroundColor: p.surHeros.withValues(alpha: 0.12),
                  ),
                ),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${(pr.avancement * 100).round()}'),
                    TextSpan(
                      text: ' %',
                      style: t.textTheme.labelLarge?.copyWith(color: p.surHerosDoux),
                    ),
                  ]),
                  style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 28, height: 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Surtitre('Avancement', couleur: p.accentSurHeros),
                const SizedBox(height: 6),
                Texte(
                  '${pr.seancesFaites} séance'
                  '${pr.seancesFaites > 1 ? 's' : ''} sur ${pr.seancesTotal}',
                  style: t.textTheme.titleLarge?.copyWith(color: p.surHeros, fontSize: 20),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                if (pr.enRetard > 0)
                  _EtiquetteHeros(
                    texte: '${pr.enRetard} en retard',
                    icone: Icons.schedule_rounded,
                    couleur: p.alerte,
                  )
                else if (pr.seancesTotal > 0)
                  _EtiquetteHeros(
                    texte: 'Vous êtes à jour.',
                    icone: Icons.check_rounded,
                    couleur: p.succes,
                  )
                else
                  Texte(
                    'Aucun chronogramme actif.',
                    style: t.textTheme.bodySmall?.copyWith(color: p.surHerosDoux),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Une étiquette posée sur la carte de mise en avant : la teinte en pastille
/// pleine, le texte clair du héros par-dessus, lisible dans les quatre thèmes.
class _EtiquetteHeros extends StatelessWidget {
  const _EtiquetteHeros({required this.texte, required this.icone, required this.couleur});
  final String texte;
  final IconData icone;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: p.surHeros.withValues(alpha: 0.12),
        borderRadius: Rayons.pilule,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Texte(
              texte,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: p.surHeros, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile({
    required this.valeur,
    required this.libelle,
    required this.icone,
    required this.couleur,
    this.unite,
  });
  final String valeur;
  final String? unite;
  final String libelle;
  final IconData icone;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconePastille(icone, couleur: couleur, taille: 36),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: valeur),
              if (unite != null)
                TextSpan(text: ' $unite', style: t.textTheme.labelLarge?.copyWith(color: p.attenue)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.headlineSmall?.copyWith(fontSize: 24, height: 1),
          ),
          const SizedBox(height: 5),
          Texte(libelle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.3)),
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
    final pal = context.palette;

    return points.when(
      loading: () => const Squelette(hauteur: 130, rayon: 20),
      error: (_, _) => const SizedBox.shrink(),
      data: (liste) {
        if (liste.isEmpty) return const SizedBox.shrink();
        final max = liste.fold<int>(1, (m, p) => (p['minutes'] as int) > m ? p['minutes'] as int : m);
        final visibles = liste.skip(liste.length > 84 ? liste.length - 84 : 0).toList();
        // Le décompte des jours actifs se lit dans les barres mêmes : on ne
        // fait que les compter, sans rien ajouter.
        final actifs = visibles.where((p) => (p['actions'] as int) > 0).length;
        return Surface(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconePastille(Icons.local_fire_department_rounded, couleur: pal.accentTexte, taille: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '$actifs'),
                        TextSpan(
                          text: ' jour${actifs > 1 ? 's' : ''} actif${actifs > 1 ? 's' : ''} sur ${visibles.length}',
                          style: t.textTheme.bodySmall?.copyWith(color: pal.attenue),
                        ),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.headlineSmall?.copyWith(fontSize: 22, height: 1.1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 68,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final p in visibles)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0.6),
                          child: Container(
                            height: (p['minutes'] as int) == 0
                                ? 3
                                : 6 + 62 * ((p['minutes'] as int) / max),
                            decoration: BoxDecoration(
                              gradient: (p['actions'] as int) > 0
                                  ? LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [pal.accent, pal.accentSurHeros],
                                    )
                                  : null,
                              color: (p['actions'] as int) > 0 ? null : pal.surfaceCreuse,
                              borderRadius: Rayons.pilule,
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
                  Texte('il y a 12 semaines',
                      style: t.textTheme.labelSmall?.copyWith(color: pal.attenue)),
                  Texte("aujourd'hui",
                      style: t.textTheme.labelSmall?.copyWith(color: pal.attenue)),
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

  /// Les trois niveaux, dans l'ordre où on les lit : ce qui est acquis
  /// d'abord, ce qui est fragile ensuite.
  static const _niveaux = [
    ('acquis', 'Acquises'),
    ('en_cours', 'En cours'),
    ('fragile', 'Fragiles'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notions = ref.watch(maitriseProvider);
    final t = Theme.of(context);
    final p = context.palette;
    final couleurs = {
      'acquis': p.succes,
      'en_cours': p.accentTexte,
      'fragile': p.alerte,
    };

    return notions.when(
      loading: () => const Squelette(hauteur: 90, rayon: 20),
      error: (_, _) => const SizedBox.shrink(),
      data: (liste) {
        if (liste.isEmpty) {
          return const Surface(
            child: EtatMessage(
              icone: Icons.psychology_outlined,
              titre: 'Rien encore',
              texte: "Les notions apparaîtront ici au fil des quiz : celles que vous "
                  "ratez sont suivies et reviennent régulièrement.",
            ),
          );
        }
        final total = liste.length;
        return Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // La répartition d'un coup d'oeil : une barre en trois segments.
              ClipRRect(
                borderRadius: Rayons.pilule,
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: [
                      for (final (cle, _) in _niveaux)
                        if (liste.any((n) => n.niveau == cle))
                          Expanded(
                            flex: liste.where((n) => n.niveau == cle).length,
                            child: ColoredBox(color: couleurs[cle]!),
                          ),
                      if (liste.any((n) => !couleurs.containsKey(n.niveau)))
                        Expanded(
                          flex: liste.where((n) => !couleurs.containsKey(n.niveau)).length,
                          child: ColoredBox(color: p.surfaceCreuse),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  for (final (cle, libelle) in _niveaux)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: couleurs[cle], shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Texte(
                          '$libelle ${liste.where((n) => n.niveau == cle).length}',
                          style: t.textTheme.labelMedium?.copyWith(color: p.attenue),
                        ),
                      ],
                    ),
                  Texte('sur $total', style: t.textTheme.labelMedium?.copyWith(color: p.attenue)),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  // Pas la brique Pastille : un terme long doit pouvoir passer
                  // à la ligne au lieu de déborder sur un petit écran.
                  for (final n in liste)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: (couleurs[n.niveau] ?? p.attenue).withValues(alpha: p.sombre ? 0.18 : 0.11),
                        borderRadius: Rayons.pilule,
                      ),
                      child: Texte(
                        n.terme,
                        style: t.textTheme.labelMedium?.copyWith(
                          color: couleurs[n.niveau] ?? p.attenue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
