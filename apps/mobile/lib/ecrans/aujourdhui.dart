import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../etat/hors_ligne.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/avantages.dart';
import '../widgets/cartes.dart';
import '../widgets/exploitation.dart';
import '../widgets/etats.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/papier.dart';
import '../widgets/livre.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// L'écran d'accueil : ce qu'il y a à faire maintenant, puis de quoi garder l'élan.
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
              toolbarHeight: 74,
              // Le haut de l'accueil est une page de titre : la date en petites
              // capitales, la salutation en grand, un filet dessous.
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Texte(
                    toBeginningOfSentenceCase(
                      DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.now()),
                    ).toUpperCase(),
                    style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 1.4),
                  ),
                  const SizedBox(height: 2),
                  Texte(
                    _salutation(prenom),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.headlineSmall?.copyWith(fontSize: 26),
                  ),
                ],
              ),
              actions: const [AvatarCompte()],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Filet(redouble: true),
                ),
              ),
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
                  // L'accueil se pose bloc par bloc : on voit la page se
                  // construire, une fois, à l'ouverture.

                  // Le bandeau de lancement, s'il y a lieu. Il se retire tout
                  // seul à l'échéance, sans rien à changer dans l'application.
                  const BandeauLancement(),
                  const BandeauRecompense(),
                  Apparition(
                    child: a.seance != null
                        ? CarteSeance(seance: a.seance!, onCommencer: () => _ouvrirSeance(context, a))
                        : const _AucuneSeance(),
                  ),
                  const SizedBox(height: 22),
                  const Apparition(rang: 1, child: _Elan()),
                  const SizedBox(height: 26),
                  const Apparition(rang: 2, child: TitreSection('Votre semaine')),
                  const SizedBox(height: 12),
                  Apparition(
                    rang: 2,
                    child: Surface(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                      child: PastillesSemaine(jours: a.semaine),
                    ),
                  ),
                  if (a.notionsAReviser > 0) ...[
                    const SizedBox(height: 14),
                    Apparition(rang: 3, child: _CarteRevision(nombre: a.notionsAReviser)),
                  ],
                  const SizedBox(height: 14),
                  const Apparition(rang: 3, child: _RaccourcisChronogramme()),
                  const SizedBox(height: 26),
                  const Apparition(rang: 4, child: _Rayon()),
                  const Apparition(rang: 5, child: TitreSection('Accès rapides')),
                  const SizedBox(height: 12),
                  const Apparition(rang: 5, child: _AccesRapides()),
                  const SizedBox(height: 28),
                  const Apparition(rang: 6, child: _Poles()),
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
    return Surface(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EtiquetteCrochet('votre parcours'),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Lettrine('A', taille: 58),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Texte('Aucune séance prévue',
                        style: t.textTheme.headlineSmall?.copyWith(fontSize: 23, height: 1.15)),
                    const SizedBox(height: 6),
                    Texte(
                      "Dites à ASCENDA ce que vous voulez apprendre : il découpe les ouvrages en séances que vous pouvez tenir.",
                      style: t.textTheme.bodyMedium?.copyWith(color: p.attenue),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Filet(redouble: true),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/diagnostic'),
              icon: const IconeAscenda(Icone.boussole, taille: 20, couleur: Color(0xFF1A1400)),
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
    final heures = prog.minutesLues ~/ 60;
    // Trois chiffres sur une seule bande, séparés par des filets : c'est la
    // ligne de repères d'une page de titre, pas trois tuiles d'application.
    return Surface(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 14),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Chiffre(
                valeur: prog.minutesLues < 60 ? prog.minutesLues : heures,
                unite: prog.minutesLues < 60 ? 'min' : 'h',
                libelle: 'de lecture',
              ),
            ),
            const _FiletVertical(),
            Expanded(
              child: _Chiffre(
                valeur: prog.seancesFaites,
                libelle: prog.seancesFaites > 1 ? 'séances faites' : 'séance faite',
              ),
            ),
            const _FiletVertical(),
            Expanded(
              child: _Chiffre(
                valeur: prog.notionsMaitrisees,
                libelle: prog.notionsMaitrisees > 1 ? 'notions acquises' : 'notion acquise',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FiletVertical extends StatelessWidget {
  const _FiletVertical();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 2),
        color: context.palette.encre.withValues(alpha: context.palette.sombre ? 0.20 : 0.12),
      );
}

class _Chiffre extends StatelessWidget {
  const _Chiffre({required this.valeur, required this.libelle, this.unite});
  final int valeur;
  final String? unite;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              CompteurAnime(valeur, style: t.textTheme.headlineSmall?.copyWith(fontSize: 27, height: 1)),
              if (unite != null)
                Texte(' $unite',
                    style: t.textTheme.labelMedium?.copyWith(color: p.attenue, letterSpacing: 0.4)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Texte(
          libelle.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 1.1, height: 1.25),
        ),
      ],
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

/// Le rayon : les volumes du corpus, posés sur une tablette.
class _Rayon extends ConsumerWidget {
  const _Rayon();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(bibliothequeProvider(const FiltreBiblio())).valueOrNull;
    final emportes = ref.watch(packsProvider).valueOrNull ?? const {};
    if (page == null || page.ouvrages.isEmpty) return const SizedBox.shrink();
    final volumes = <({String titre, String? axeSlug, bool marque, VoidCallback? onTap})>[
      for (final o in page.ouvrages.take(14))
        (
          titre: o.titre,
          axeSlug: o.axeSlug,
          marque: emportes.containsKey(o.id),
          onTap: () => context.push('/ouvrage/${o.id}'),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TitreSection('Votre rayon',
            sousTitre: '${page.total} ouvrages dans la bibliothèque',
            action: 'Tout voir',
            onAction: () => context.go('/bibliotheque')),
        const SizedBox(height: 10),
        Rayon(volumes: volumes, padding: EdgeInsets.zero),
        const SizedBox(height: 22),
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
