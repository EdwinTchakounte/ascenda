import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/avantages.dart';
import '../widgets/cartes.dart';
import '../widgets/exploitation.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// L'écran d'accueil : ce qu'il y a à faire maintenant, puis de quoi garder
/// l'élan. La séance du jour d'abord, en grand ; les repères de la semaine
/// ensuite ; les portes vers la bibliothèque et les pôles pour finir.
class EcranAujourdhui extends ConsumerWidget {
  const EcranAujourdhui({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donnees = ref.watch(aujourdhuiProvider);
    final session = ref.watch(sessionProvider);
    final t = Theme.of(context);
    final p = context.palette;
    final prenom = session.utilisateur?.nom?.split(' ').first;

    return Scaffold(
      body: RefreshIndicator(
        color: p.accent,
        onRefresh: () async => rafraichirProgression(ref),
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
                  Texte(
                    toBeginningOfSentenceCase(
                      DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now()),
                    ),
                    style: t.textTheme.labelMedium?.copyWith(color: p.attenue),
                  ),
                  Texte(
                    _salutation(prenom),
                    style: t.textTheme.titleLarge?.copyWith(fontSize: 21),
                  ),
                ],
              ),
              actions: const [AvatarCompte()],
            ),
            donnees.when(
              loading: () => const SliverPadding(
                padding: EdgeInsets.all(20),
                sliver: SliverToBoxAdapter(child: SqueletteCarte(lignes: 4)),
              ),
              error: (e, _) => SliverFillRemaining(
                hasScrollBody: false,
                child: EtatErreur(
                  erreur: e,
                  reessayer: () => ref.invalidate(aujourdhuiProvider),
                ),
              ),
              data: (a) => SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 36),
                sliver: SliverList.list(children: [
                  // Le bandeau de lancement, s'il y a lieu. Il se retire tout
                  // seul à l'échéance, sans rien à changer dans l'application.
                  const BandeauLancement(),
                  const BandeauRecompense(),
                  if (a.seance != null)
                    CarteSeance(
                      seance: a.seance!,
                      onCommencer: () => _ouvrirSeance(context, a),
                    )
                  else
                    const _AucuneSeance(),
                  const SizedBox(height: 22),
                  const _Elan(),
                  const SizedBox(height: 26),
                  const TitreSection('Votre semaine'),
                  const SizedBox(height: 12),
                  Surface(
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                    child: PastillesSemaine(jours: a.semaine),
                  ),
                  if (a.notionsAReviser > 0) ...[
                    const SizedBox(height: 14),
                    _CarteRevision(nombre: a.notionsAReviser),
                  ],
                  const SizedBox(height: 14),
                  const _RaccourcisChronogramme(),
                  const SizedBox(height: 26),
                  const TitreSection('Accès rapides'),
                  const SizedBox(height: 12),
                  const _AccesRapides(),
                  const SizedBox(height: 28),
                  const _Poles(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _salutation(String? prenom) {
    final h = DateTime.now().hour;
    final moment = h < 12 ? 'Bonjour' : (h < 18 ? 'Bon après-midi' : 'Bonsoir');
    return prenom == null || prenom.isEmpty ? moment : '$moment, $prenom';
  }

  void _ouvrirSeance(BuildContext context, Aujourdhui a) {
    final s = a.seance!;
    if (s.documentId != null && s.chapitreId != null) {
      final params = {
        'seance': s.id,
        if (s.livrable != null) 'livrable': s.livrable!,
        if (s.livrableId != null) 'livrable_id': s.livrableId!,
        if (s.pageDebut != null) 'page_debut': '${s.pageDebut}',
        if (s.pageFin != null) 'page_fin': '${s.pageFin}',
      }.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      context.push('/lecture/${s.documentId}/${s.chapitreId}?$params');
    } else if (s.documentId != null) {
      context.push('/ouvrage/${s.documentId}');
    }
  }
}

class _AucuneSeance extends StatelessWidget {
  const _AucuneSeance();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return SurfaceHeros(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconePastille(Icons.explore_rounded, couleur: p.accentSurHeros, taille: 50),
          const SizedBox(height: 18),
          Surtitre('Votre parcours', couleur: p.accentSurHeros),
          const SizedBox(height: 8),
          Texte('Aucune séance prévue',
              style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 25)),
          const SizedBox(height: 8),
          Texte(
            "Créez un chronogramme et ASCENDA vous proposera chaque jour une "
            "séance de lecture à votre mesure.",
            style: t.textTheme.bodyMedium?.copyWith(color: p.surHerosDoux),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/diagnostic'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 20),
              iconAlignment: IconAlignment.end,
              label: const Texte('Faire le diagnostic'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trois chiffres qui disent l'élan, tirés de la progression réelle.
class _Elan extends ConsumerWidget {
  const _Elan();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prog = ref.watch(progressionProvider).valueOrNull;
    if (prog == null) return const SizedBox.shrink();
    final p = context.palette;
    final heures = prog.minutesLues ~/ 60;
    return Row(
      children: [
        Expanded(
          child: _Chiffre(
            icone: Icons.schedule_rounded,
            valeur: prog.minutesLues < 60 ? '${prog.minutesLues}' : '$heures',
            unite: prog.minutesLues < 60 ? 'min' : 'h',
            libelle: 'de lecture',
            couleur: p.accentTexte,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Chiffre(
            icone: Icons.task_alt_rounded,
            valeur: '${prog.seancesFaites}',
            libelle: prog.seancesFaites > 1 ? 'séances faites' : 'séance faite',
            couleur: p.succes,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Chiffre(
            icone: Icons.psychology_alt_outlined,
            valeur: '${prog.notionsMaitrisees}',
            libelle: prog.notionsMaitrisees > 1 ? 'notions acquises' : 'notion acquise',
            couleur: Couleurs.poles['02']!,
          ),
        ),
      ],
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.icone, required this.valeur, required this.libelle, required this.couleur, this.unite});
  final IconData icone;
  final String valeur;
  final String? unite;
  final String libelle;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Surface(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconePastille(icone, couleur: couleur, taille: 34),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: valeur),
              if (unite != null)
                TextSpan(text: ' $unite', style: t.textTheme.labelLarge?.copyWith(color: p.attenue)),
            ]),
            style: t.textTheme.headlineSmall?.copyWith(fontSize: 24, height: 1),
          ),
          const SizedBox(height: 4),
          Texte(libelle,
              style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 0.1, height: 1.25),
              maxLines: 2),
        ],
      ),
    );
  }
}

class _CarteRevision extends StatelessWidget {
  const _CarteRevision({required this.nombre});
  final int nombre;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Surface(
      onTap: () => context.push('/revision'),
      couleur: Color.alphaBlend(p.accentVoile, p.surface),
      child: Row(
        children: [
          const IconePastille(Icons.replay_rounded, taille: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Texte(
                  nombre == 1 ? '1 notion à revoir' : '$nombre notions à revoir',
                  style: t.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Texte('Cinq minutes suffisent.', style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_rounded, color: p.accentTexte),
        ],
      ),
    );
  }
}

class _RaccourcisChronogramme extends ConsumerWidget {
  const _RaccourcisChronogramme();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(chronogrammesProvider);
    final t = Theme.of(context);
    final p = context.palette;

    return plans.when(
      loading: () => const Squelette(hauteur: 74, rayon: 20),
      error: (_, _) => const SizedBox.shrink(),
      data: (liste) {
        final actifs = liste.where((c) => c['statut'] == 'actif').toList();
        if (actifs.isEmpty) return const SizedBox.shrink();
        final c = actifs.first;
        final faites = c['faites'] as int? ?? 0;
        final total = c['seances'] as int? ?? 0;
        final retard = c['en_retard'] as int? ?? 0;
        final part = total == 0 ? 0.0 : faites / total;

        return Surface(
          onTap: () => context.push('/chronogramme/${c['id']}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const IconePastille(Icons.route_rounded, taille: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Surtitre('Chronogramme', couleur: p.attenue),
                        const SizedBox(height: 2),
                        Texte('${c['axe_label']}', style: t.textTheme.titleMedium, maxLines: 2),
                      ],
                    ),
                  ),
                  Texte('${(part * 100).round()} %',
                      style: t.textTheme.titleLarge?.copyWith(color: p.accentTexte, fontSize: 19)),
                ],
              ),
              const SizedBox(height: 14),
              Jauge(valeur: part),
              const SizedBox(height: 10),
              Row(
                children: [
                  Texte('$faites séances sur $total', style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
                  const Spacer(),
                  if (retard > 0)
                    Pastille(retard == 1 ? '1 en retard' : '$retard en retard', couleur: p.alerte),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AccesRapides extends StatelessWidget {
  const _AccesRapides();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final acces = [
      (icone: Icons.auto_stories_rounded, libelle: 'Bibliothèque', detail: 'Choisir un livre', couleur: p.accentTexte, aller: () => context.go('/bibliotheque')),
      (icone: Icons.forum_rounded, libelle: 'Agent', detail: 'Poser une question', couleur: Couleurs.poles['02']!, aller: () => context.go('/agent')),
      (icone: Icons.lightbulb_rounded, libelle: 'Notions', detail: 'Les idées clés', couleur: Couleurs.poles['08']!, aller: () => context.push('/notions')),
      (icone: Icons.download_done_rounded, libelle: 'Hors ligne', detail: 'Vos livres emportés', couleur: p.succes, aller: () => context.push('/hors-ligne')),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.3,
      padding: EdgeInsets.zero,
      children: [
        for (final a in acces)
          Surface(
            padding: const EdgeInsets.all(14),
            onTap: a.aller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconePastille(a.icone, couleur: a.couleur, taille: 38),
                const Spacer(),
                Texte(a.libelle, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15)),
                Texte(a.detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
      ],
    );
  }
}

/// Les pôles en carrousel : chacun à sa teinte, celle de ses couvertures.
class _Poles extends ConsumerWidget {
  const _Poles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final axes = ref.watch(axesProvider).valueOrNull;
    if (axes == null || axes.isEmpty) return const SizedBox.shrink();
    final groupes = regrouperParPole(axes);
    final t = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TitreSection('Explorer par pôle', action: 'Tout voir', onAction: () => context.go('/bibliotheque')),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: groupes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final g = groupes[i];
              final a = g.axes.first;
              final teinte = Couleurs.pole(g.poleSlug ?? a.slug) ?? context.palette.heros;
              final nb = g.axes.fold<int>(0, (s, x) => s + x.nbOuvrages);
              return SizedBox(
                width: 168,
                child: Material(
                  borderRadius: Rayons.carte,
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color.lerp(teinte, Colors.white, 0.06)!, Color.lerp(teinte, Colors.black, 0.32)!],
                      ),
                    ),
                    child: InkWell(
                      onTap: () => context.push('/axe/${a.slug}'),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -18,
                            bottom: -26,
                            child: Icon(Icons.auto_stories_rounded, size: 96, color: Colors.white.withValues(alpha: 0.10)),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: Rayons.pilule,
                                  ),
                                  child: Texte(
                                    '$nb ouvrage${nb > 1 ? 's' : ''}',
                                    style: t.textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const Spacer(),
                                Texte(
                                  g.poleLabel ?? a.label,
                                  style: t.textTheme.titleMedium?.copyWith(color: Colors.white, height: 1.25),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
