import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/modeles.dart';
import '../etat/fournisseurs.dart';
import '../theme/couleurs.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/papier.dart';
import '../widgets/etats.dart';
import '../widgets/illustrations.dart';
import '../widgets/ui.dart';
import '../theme/texte.dart';

/// L'onglet des progrès : le carnet de bord du lecteur.
///
/// L'avancement en grand sur la page de garde, les chiffres clés en fiches, la
/// régularité comme un calendrier de cahier, les notions en étiquettes, et le
/// journal qui fonde le tout.
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
              // Le carnet s'ouvre page après page : une entrée en cascade, une
              // seule fois, à l'arrivée sur l'onglet.
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
                      Apparition(child: _Anneau(progression: pr)),
                      const SizedBox(height: 14),
                      Apparition(
                        rang: 1,
                        child: Row(
                          children: [
                            Expanded(child: _FicheDuree(minutes: pr.minutesLues)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Fiche(
                                nombre: pr.ouvragesTermines,
                                libelle: pr.ouvragesTermines > 1 ? 'ouvrages terminés' : 'ouvrage terminé',
                                icone: Icone.volumes,
                                couleur: Couleurs.poles['02']!,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Apparition(
                        rang: 2,
                        child: Row(
                          children: [
                            Expanded(
                              child: _Fiche(
                                nombre: pr.scoreMoyen == null ? null : (pr.scoreMoyen! * 100).round(),
                                unite: pr.scoreMoyen == null ? null : '%',
                                libelle: 'de réussite aux quiz',
                                icone: Icone.question,
                                couleur: Couleurs.poles['08']!,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _Fiche(
                                nombre: pr.notionsMaitrisees,
                                libelle: 'notions acquises',
                                icone: Icone.clef,
                                couleur: p.succes,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Apparition(
                  rang: 3,
                  child: TitreSection(
                    'Régularité',
                    sousTitre: 'Douze semaines. Ce sont les trous qui comptent, pas les pics.',
                  ),
                ),
                const SizedBox(height: 12),
                const Apparition(rang: 3, child: _Regularite()),
                const SizedBox(height: 28),
                // La carte dit où l'on en est ; le glossaire dit ce qu'il y a
                // à savoir. L'un sans l'autre laisse le lecteur devant un
                // constat sans issue.
                Apparition(
                  rang: 4,
                  child: TitreSection(
                    'Carte des notions',
                    action: 'Toutes les notions',
                    onAction: () => context.push('/notions'),
                  ),
                ),
                const SizedBox(height: 12),
                const Apparition(rang: 4, child: _Maitrise()),
                const SizedBox(height: 28),
                const Apparition(
                  rang: 5,
                  child: TitreSection(
                    'Ce que vous avez fait',
                    sousTitre: 'Le détail dont sont tirés les chiffres ci-dessus.',
                  ),
                ),
                const SizedBox(height: 12),
                const Apparition(rang: 5, child: _Journal()),
                const SizedBox(height: 26),
                const Apparition(rang: 6, child: Fleuron()),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le réglage « animations réduites » du téléphone. Les briques de
/// `mouvement.dart` le lisent déjà ; les mouvements écrits ici le lisent par
/// cette même porte.
bool _reduites(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

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
    'quiz_attempt': ('Quiz passé', Icone.question),
    'question_asked': ("Question à l'agent", Icone.plume),
    'note_created': ('Note prise', Icone.encrier),
    'read_pages': ('Pages lues', Icone.page),
    'opened_doc': ('Ouvrage ouvert', Icone.volumes),
    'session_done': ('Séance terminée', Icone.soleil),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journal = ref.watch(journalProvider);
    return journal.when(
      loading: () => const SqueletteCarte(lignes: 4),
      error: (e, _) => EtatErreur(
        erreur: e,
        reessayer: () => ref.invalidate(journalProvider),
      ),
      data: (lignes) {
        if (lignes.isEmpty) {
          return const Surface(
            padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: EtatMessage(
              scene: Scene.pageBlanche,
              titre: 'Rien encore',
              texte: "Votre première séance ouvrira ce journal.",
            ),
          );
        }
        final affichees = lignes.take(40).toList();
        return Surface(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TitreCourant('journal de lecture'),
              const SizedBox(height: 14),
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
  final Map<String, (String, Icone)> recits;

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
          // La frise : un cachet à l'encre par évènement, relié au suivant.
          Column(
            children: [
              _CachetIcone(
                icone: recit?.$2 ?? Icone.cercle,
                couleur: termine ? p.succes : p.accentTexte,
                taille: 32,
              ),
              if (!derniere)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    color: p.encre.withValues(alpha: p.sombre ? 0.22 : 0.16),
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

/// Une icône de la plume dans un cadre d'encre : le cachet d'un carnet.
///
/// La brique `IconePastille` attend une icône Material ; celle-ci porte les
/// icônes dessinées d'ASCENDA, dans un cadre plutôt que sur un voile arrondi.
class _CachetIcone extends StatelessWidget {
  const _CachetIcone({required this.icone, this.couleur, this.taille = 36});
  final Icone icone;
  final Color? couleur;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = couleur ?? p.accentTexte;
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.sombre ? 0.14 : 0.08),
        border: Border.all(color: c.withValues(alpha: 0.42)),
      ),
      child: IconeAscenda(icone, taille: taille * 0.52, couleur: c),
    );
  }
}

/// La page de garde du carnet : l'anneau d'avancement du chronogramme, tracé à
/// l'encre et rempli à l'ouverture.
class _Anneau extends StatelessWidget {
  const _Anneau({required this.progression});
  final Progression progression;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final pr = progression;
    final part = pr.avancement.clamp(0, 1).toDouble();
    return SurfaceHeros(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EtiquetteCrochet('carnet de bord', couleur: p.accentSurHeros),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 104,
                height: 104,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: part),
                  duration: _reduites(context) ? Duration.zero : Duree.ample,
                  curve: courbeDouce,
                  builder: (_, v, enfant) => CustomPaint(
                    painter: _AnneauPeint(
                      part: v,
                      piste: p.surHeros.withValues(alpha: 0.12),
                      encre: p.accentSurHeros,
                    ),
                    child: enfant,
                  ),
                  child: Center(
                    // Le chiffre tient dans l'anneau, même avec une grande
                    // police : il se réduit plutôt que de déborder.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          CompteurAnime(
                            (pr.avancement * 100).round(),
                            style: t.textTheme.headlineSmall?.copyWith(color: p.surHeros, fontSize: 28, height: 1),
                          ),
                          Texte(' %', style: t.textTheme.labelLarge?.copyWith(color: p.surHerosDoux)),
                        ],
                      ),
                    ),
                  ),
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
                        couleur: p.alerte,
                      )
                    else if (pr.seancesTotal > 0)
                      _EtiquetteHeros(
                        texte: 'Vous êtes à jour.',
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
        ],
      ),
    );
  }
}

/// L'anneau : une piste, un arc d'encre, et le cerne fin d'un tampon.
class _AnneauPeint extends CustomPainter {
  _AnneauPeint({required this.part, required this.piste, required this.encre});
  final double part;
  final Color piste;
  final Color encre;

  @override
  void paint(Canvas canvas, Size t) {
    final centre = Offset(t.width / 2, t.height / 2);
    final rayon = (min(t.width, t.height) - 14) / 2;
    canvas.drawCircle(
      centre,
      rayon,
      Paint()
        ..color = piste
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9,
    );
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: rayon),
      -pi / 2,
      2 * pi * part.clamp(0, 1),
      false,
      Paint()
        ..color = encre
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 9,
    );
    canvas.drawCircle(
      centre,
      rayon + 7,
      Paint()
        ..color = encre.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _AnneauPeint a) =>
      a.part != part || a.encre != encre || a.piste != piste;
}

/// Une étiquette posée sur la carte de mise en avant : la teinte en pastille
/// pleine, le texte clair du héros par-dessus, lisible dans les quatre thèmes.
class _EtiquetteHeros extends StatelessWidget {
  const _EtiquetteHeros({required this.texte, required this.couleur});
  final String texte;
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

/// Une fiche de chiffre : le cachet, le nombre qui monte, son libellé.
class _Fiche extends StatelessWidget {
  const _Fiche({
    required this.libelle,
    required this.icone,
    required this.couleur,
    this.nombre,
    this.unite,
  });

  /// Sans nombre, la fiche n'a rien à compter : elle montre un tiret.
  final num? nombre;
  final String? unite;
  final String libelle;
  final Icone icone;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final style = t.textTheme.headlineSmall?.copyWith(fontSize: 24, height: 1);
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CachetIcone(icone: icone, couleur: couleur),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: nombre == null
                    ? Texte('-', style: style, maxLines: 1, overflow: TextOverflow.ellipsis)
                    : CompteurAnime(nombre!, style: style),
              ),
              if (unite != null)
                Flexible(
                  child: Texte(' $unite',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.labelLarge?.copyWith(color: p.attenue)),
                ),
            ],
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

/// Le temps de lecture : les minutes montent en dessous d'une heure, les heures
/// au-dessus, avec les minutes restantes en unité. Le libellé reste celui de
/// `dureeLisible` : « 45 min », « 2 h », « 2 h 30 ».
class _FicheDuree extends StatelessWidget {
  const _FicheDuree({required this.minutes});
  final int minutes;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (minutes < 60) {
      return _Fiche(
        nombre: minutes,
        unite: 'min',
        libelle: 'de lecture',
        icone: Icone.page,
        couleur: p.accentTexte,
      );
    }
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return _Fiche(
      nombre: h,
      unite: m == 0 ? 'h' : 'h ${m.toString().padLeft(2, '0')}',
      libelle: 'de lecture',
      icone: Icone.page,
      couleur: p.accentTexte,
    );
  }
}

/// La régularité en calendrier de cahier : une case par jour, douze colonnes de
/// semaines. Une case pleine d'encre pour un jour lu, une case vide pour un
/// jour sans rien. Ce sont les trous qui se voient.
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
        // Le décompte des jours actifs se lit dans les cases mêmes : on ne
        // fait que les compter, sans rien ajouter.
        final actifs = visibles.where((p) => (p['actions'] as int) > 0).length;
        return Surface(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CachetIcone(icone: Icone.pousse, couleur: pal.accentTexte),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        CompteurAnime(
                          actifs,
                          style: t.textTheme.headlineSmall?.copyWith(fontSize: 22, height: 1.1),
                        ),
                        Expanded(
                          child: Texte(
                            ' jour${actifs > 1 ? 's' : ''} actif${actifs > 1 ? 's' : ''} sur ${visibles.length}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.bodySmall?.copyWith(color: pal.attenue),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _CalendrierCahier(points: visibles, maximum: max),
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

/// Les cases du calendrier : une colonne par semaine, sept lignes par colonne,
/// du lundi au dimanche. L'intensité de l'encre dit les minutes lues.
class _CalendrierCahier extends StatelessWidget {
  const _CalendrierCahier({required this.points, required this.maximum});

  final List<Map<String, dynamic>> points;
  final int maximum;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final aujourdhui = DateUtils.dateOnly(DateTime.now());
    // La date d'un point : celle du serveur quand elle se lit, sinon déduite de
    // son rang, la série se terminant toujours aujourd'hui.
    DateTime jourDe(int i) =>
        DateTime.tryParse('${points[i]['jour']}') ??
        aujourdhui.subtract(Duration(days: points.length - 1 - i));

    final premier = jourDe(0);
    final decalage = premier.weekday - 1;
    final colonnes = ((decalage + points.length) / 7).ceil();

    return LayoutBuilder(
      builder: (context, contraintes) {
        const espace = 3.0;
        final cote = ((contraintes.maxWidth - espace * (colonnes - 1)) / colonnes)
            .clamp(6.0, 18.0)
            .toDouble();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < colonnes; c++) ...[
              if (c > 0) const SizedBox(width: espace),
              Column(
                children: [
                  for (var l = 0; l < 7; l++) ...[
                    if (l > 0) const SizedBox(height: espace),
                    Builder(builder: (context) {
                      final i = c * 7 + l - decalage;
                      if (i < 0 || i >= points.length) {
                        return SizedBox(width: cote, height: cote);
                      }
                      final pt = points[i];
                      final minutes = pt['minutes'] as int;
                      final actif = (pt['actions'] as int) > 0;
                      final force = maximum == 0 ? 0.0 : minutes / maximum;
                      return _Case(
                        cote: cote,
                        encre: actif
                            ? p.accentTexte.withValues(
                                alpha: (p.sombre ? 0.30 : 0.22) + 0.62 * force.clamp(0, 1))
                            : null,
                      );
                    }),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Case extends StatelessWidget {
  const _Case({required this.cote, this.encre});
  final double cote;
  final Color? encre;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: cote,
      height: cote,
      decoration: BoxDecoration(
        color: encre ?? p.surfaceCreuse,
        border: Border.all(color: p.encre.withValues(alpha: p.sombre ? 0.16 : 0.10)),
      ),
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
            padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: EtatMessage(
              scene: Scene.graine,
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
                  // Des fiches de glossaire plutôt que des pastilles : un terme
                  // long doit pouvoir passer à la ligne au lieu de déborder sur
                  // un petit écran.
                  for (final n in liste)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: (couleurs[n.niveau] ?? p.attenue).withValues(alpha: p.sombre ? 0.14 : 0.08),
                        border: Border.all(color: (couleurs[n.niveau] ?? p.attenue).withValues(alpha: 0.40)),
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
