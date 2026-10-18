import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/icones.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import '../widgets/annotations.dart';
import '../widgets/derives.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';
import 'agent.dart';
import 'lecteur_pdf.dart';

/// Le lecteur : une page de livre, pas un écran d'application.
class EcranLecteur extends ConsumerStatefulWidget {
  const EcranLecteur({
    super.key,
    required this.documentId,
    required this.chapitreId,
    this.seanceId,
    this.livrable,
    this.livrableId,
    this.pageDebut,
    this.pageFin,
  });

  final String documentId;
  final String chapitreId;
  final String? seanceId;

  /// Ce que la séance attend après la lecture : un quiz, ou une note.
  final String? livrable;
  final String? livrableId;

  /// La plage de pages de la séance. Quand elle déborde du chapitre, c'est
  /// qu'elle en regroupe plusieurs : on lit alors par pages, pas par chapitre.
  final int? pageDebut;
  final int? pageFin;

  @override
  ConsumerState<EcranLecteur> createState() => _EcranLecteurState();
}

/// Une lettre, pour savoir si un passage peut porter une lettrine.
final _lettre = RegExp(r'\p{L}', unicode: true);

class _EcranLecteurState extends ConsumerState<EcranLecteur> {
  double _taille = 18;
  bool _marquee = false;

  @override
  void initState() {
    super.initState();
    // Le journal de progression alimente la replanification : on signale
    // l'ouverture sans attendre la réponse.
    ref.read(clientApiProvider).post('/lecteur/${widget.documentId}/ouvert').ignore();
  }

  Future<void> _terminerSeance(String? livrable, String? livrableId) async {
    final api = ref.read(clientApiProvider);
    if (widget.seanceId != null && !_marquee) {
      try {
        await api.patch('/seances/${widget.seanceId}', corps: {'statut': 'fait'});
        _marquee = true;
        rafraichirProgression(ref);
      } catch (_) {
        // Marquer la séance ne doit pas empêcher d'enchaîner sur le quiz.
      }
    }
    if (!mounted) return;
    if (livrable == 'quiz' && livrableId != null) {
      context.pushReplacement('/quiz/$livrableId?seance=${widget.seanceId ?? ''}');
    } else {
      context.pop();
    }
  }

  /// Le texte de lecture : Fraunces, interligne ample
  TextStyle? _styleLecture(ThemeData t, Palette p) => t.textTheme.bodyLarge?.copyWith(
        fontFamily: t.textTheme.headlineSmall?.fontFamily,
        fontSize: _taille,
        height: 1.75,
        color: Color.lerp(p.texte, p.encre, 0.45),
        letterSpacing: 0.05,
      );

  @override
  Widget build(BuildContext context) {
    final cle = (documentId: widget.documentId, chapitreId: widget.chapitreId);
    final lecture = ref.watch(lectureProvider(cle));
    final t = Theme.of(context);
    final p = context.palette;
    // Des marges de livre : généreuses sur téléphone, et une colonne de 680 px
    // au plus sur tablette, au-delà de quoi l'oeil perd la ligne suivante.
    final largeur = MediaQuery.sizeOf(context).width;
    final marge = largeur > 728 ? (largeur - 680) / 2 : 26.0;

    // Le grain du papier sous toute la page, barre du haut comprise : la
    // page n'est pas coupée en deux.
    return FondPapier(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          toolbarHeight: 52,
          leading: IconButton(
            tooltip: 'Retour',
            // La flèche du kit, retournée : la même plume que le reste de la page.
            icon: Transform.scale(
              scaleX: -1,
              child: IconeAscenda(Icone.fleche, taille: 21, couleur: p.attenue),
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          actions: [
            if (lecture.valueOrNull?['droits']?['pdf'] == true)
              IconButton(
                tooltip: 'Voir cette page dans le PDF',
                icon: IconeAscenda(Icone.page, taille: 21, couleur: p.attenue),
                onPressed: () {
                  final d = lecture.valueOrNull!;
                  final page = d['chapitre']?['page_debut'];
                  // Le lecteur de PDF ne reçoit que l'identifiant
                  reservesConnus[widget.documentId] =
                      d['droits']?['application_seulement'] == true;
                  context.push('/pdf/${widget.documentId}'
                      '?titre=${Uri.encodeComponent('${d['ouvrage']?['titre'] ?? ''}')}'
                      '${page != null ? '&page=$page' : ''}');
                },
              ),
            IconButton(
              tooltip: 'Taille du texte',
              // Deux A de la police de lecture : le bouton montre ce qu'il règle.
              icon: Texte('Aa',
                  style: t.textTheme.titleLarge
                      ?.copyWith(fontSize: 17, height: 1, color: p.attenue)),
              onPressed: () => setState(() => _taille = _taille >= 22 ? 16 : _taille + 2),
            ),
            IconButton(
              tooltip: "Demander à l'agent",
              icon: IconeAscenda(Icone.plume, taille: 21, couleur: p.attenue),
              onPressed: () => _ouvrirAgent(context),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: lecture.when(
          loading: () => Padding(
            padding: EdgeInsets.fromLTRB(marge, 16, marge, 24),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Squelette(hauteur: 12, largeur: 140),
                SizedBox(height: 14),
                Squelette(hauteur: 28, largeur: 260),
                SizedBox(height: 28),
                Squelette(hauteur: 14),
                SizedBox(height: 12),
                Squelette(hauteur: 14),
                SizedBox(height: 12),
                Squelette(hauteur: 14, largeur: 200),
              ],
            ),
          ),
          error: (e, _) => EtatErreur(erreur: e, reessayer: () => ref.invalidate(lectureProvider(cle))),
          data: (d) {
            final ouvrage = d['ouvrage'] as Map<String, dynamic>;
            final chapitre = d['chapitre'] as Map<String, dynamic>;
            final droits = d['droits'] as Map<String, dynamic>;
            final passages = (d['passages'] as List).cast<Map<String, dynamic>>();
            final suivant = d['suivant'] as Map<String, dynamic>?;
            // Une liste vide si l'appel échoue : ne pas pouvoir teinter le texte
            // ne doit pas empêcher de le lire.
            final surlignages =
                ref.watch(surlignagesProvider(widget.documentId)).valueOrNull ?? const [];
            final style = _styleLecture(t, p);

            return Stack(
              children: [
                ListView(
                  padding: EdgeInsets.fromLTRB(marge, 6, marge, 136),
                  children: [
                    // Le titre courant et son folio : on sait toujours quel
                    // ouvrage on tient, et à quelles pages on est.
                    TitreCourant('${ouvrage['titre']}', folio: _folio(chapitre)),
                    const SizedBox(height: 24),
                    Texte('${chapitre['titre'] ?? 'Chapitre ${chapitre['ordre']}'}',
                        style: t.textTheme.headlineMedium?.copyWith(fontSize: 27, height: 1.2)),
                    if (chapitre['duree_min'] != null) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: EtiquetteCrochet('${chapitre['duree_min']} min de lecture'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    // Le filet d'imprimeur qui ferme l'en-tête et ouvre le texte.
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(width: 92, child: Filet(redouble: true)),
                    ),

                    if (droits['message'] != null) ...[
                      const SizedBox(height: 10),
                      BandeauDroits(message: '${droits['message']}'),
                    ],

                    const SizedBox(height: 22),
                    CompteRenduChapitre(
                      contenu: d['compte_rendu'] as Map<String, dynamic>?,
                    ),
                    if (passages.isEmpty)
                      const EtatMessage(
                        icone: Icons.menu_book_outlined,
                        titre: 'Pas de texte à afficher',
                        texte: "Ce chapitre ne comporte pas de passage lisible ici. "
                            "Le sommaire et les quiz de l'ouvrage restent disponibles.",
                      )
                    else
                      for (final (i, x) in passages.indexed) ...[
                        _passage(
                          context,
                          x,
                          chapitre,
                          surlignages,
                          style,
                          lettrine: i == 0,
                        ),
                        if (x['tronque'] == true)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 26,
                                  child: Filet(couleur: p.attenue.withValues(alpha: 0.7)),
                                ),
                                const SizedBox(width: 8),
                                Texte(
                                  'Extrait abrégé.',
                                  style: t.textTheme.labelSmall?.copyWith(color: p.attenue, fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),
                      ],

                    // Complément : le reste de la plage de la séance, quand elle
                    // regroupe plusieurs chapitres.
                    if (_debordement(chapitre) case (final debut, final fin))
                      _PagesSupplementaires(
                        documentId: widget.documentId,
                        debut: debut,
                        fin: fin,
                        style: style,
                      ),

                    // Le fleuron qui clôt le chapitre, avant la porte du suivant.
                    if (passages.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const Fleuron(),
                    ],

                    if (suivant != null) ...[
                      const SizedBox(height: 22),
                      Surface(
                        onTap: () => context.pushReplacement(
                            '/lecture/${widget.documentId}/${suivant['id']}'),
                        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const EtiquetteCrochet('chapitre suivant'),
                                  const SizedBox(height: 8),
                                  Texte('${suivant['titre'] ?? ''}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.textTheme.titleLarge?.copyWith(fontSize: 17)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                              child: IconeAscenda(Icone.fleche, taille: 20, couleur: p.surAccent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                // Le texte s'efface sous la barre d'actions au lieu d'être coupé
                // net par elle.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 120,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [p.fond.withValues(alpha: 0), p.fond.withValues(alpha: 0.94)],
                        ),
                      ),
                    ),
                  ),
                ),

                // Barre d'actions basse, flottante et arrondie.
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        // Une réglette posée sur la page plutôt qu'une pilule
                        // flottante : le filet d'encre, et les outils de l'atelier.
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: p.surface,
                            borderRadius: Rayons.moyen,
                            border: Border.all(
                                color: p.encre.withValues(alpha: p.sombre ? 0.22 : 0.12)),
                            boxShadow: p.ombreCarte,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () =>
                                        _terminerSeance(widget.livrable, widget.livrableId),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 50),
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      shape: const RoundedRectangleBorder(borderRadius: Rayons.petit),
                                    ),
                                    // Le sceau : la séance se clôt comme on cachette
                                    // une page lue.
                                    icon: IconeAscenda(Icone.sceau, taille: 19, couleur: p.surAccent),
                                    // Sous 360 px, le libellé complet ne tient pas à côté
                                    // des deux outils : on garde le verbe.
                                    label: Texte(
                                      MediaQuery.sizeOf(context).width < 360
                                          ? (widget.seanceId != null ? 'Terminer' : 'Lu')
                                          : (widget.seanceId != null ? 'Terminer la séance' : 'Marquer comme lu'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _BoutonOutil(
                                  icone: Icone.encrier,
                                  tooltip: 'Prendre une note',
                                  onTap: () => _prendreNote(chapitre['page_debut'] as int?),
                                ),
                                const SizedBox(width: 6),
                                _BoutonOutil(
                                  icone: Icone.signet,
                                  tooltip: 'Vos annotations',
                                  onTap: _ouvrirAnnotations,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Le folio du chapitre : la plage de pages qu'il occupe dans l'ouvrage.
  String? _folio(Map<String, dynamic> chapitre) {
    final debut = chapitre['page_debut'];
    if (debut == null) return null;
    final fin = chapitre['page_fin'];
    return fin == null ? 'p. $debut' : 'p. $debut à $fin';
  }

  /// Un passage du chapitre, sélectionnable et surlignable.
  Widget _passage(
    BuildContext context,
    Map<String, dynamic> x,
    Map<String, dynamic> chapitre,
    List<Map<String, dynamic>> surlignages,
    TextStyle? style, {
    required bool lettrine,
  }) {
    final texte = '${x['texte']}';
    final corps = _teinter(texte, surlignages, style);
    final initiale = lettrine ? _initiale(texte) : null;
    // La lettrine tient exactement sur la première ligne : plus haute, elle
    // mordrait sur la deuxième, que le texte ne peut pas décaler.
    final cote = _taille * 1.75;

    final page = SelectableText.rich(
      textAlign: Texte.alignement(texte, TextStyle(fontSize: _taille), null,
              largeur: MediaQuery.sizeOf(context).width) ??
          TextAlign.start,
      initiale == null ? corps : _placeALaLettrine(corps, style, cote),
      contextMenuBuilder: (c, etat) => _menuTexte(
        c,
        etat,
        texte,
        x['page_debut'] as int? ?? chapitre['page_debut'] as int?,
        '${x['id'] ?? ''}',
      ),
    );
    if (initiale == null) return page;
    return Stack(
      children: [
        page,
        Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(child: Lettrine(initiale, taille: cote)),
        ),
      ],
    );
  }

  /// La lettre qui ouvre un passage, quand il en ouvre bien un par une lettre :
  /// un passage qui commence par un guillemet ou un chiffre n'a pas de lettrine.
  String? _initiale(String texte) =>
      texte.isNotEmpty && _lettre.hasMatch(texte[0]) ? texte[0] : null;

  /// Le texte du premier passage, moins sa lettre initiale
  TextSpan _placeALaLettrine(TextSpan corps, TextStyle? base, double cote) {
    final espaces = ' ' * _espacesPour(cote + 10, base);
    final enfants = corps.children;
    if (enfants == null) {
      return TextSpan(text: espaces + '${corps.text}'.substring(1), style: corps.style ?? base);
    }
    final premier = enfants.first as TextSpan;
    final debut = premier.text ?? '';
    return TextSpan(children: [
      TextSpan(text: espaces, style: base),
      if (debut.length > 1) TextSpan(text: debut.substring(1), style: premier.style),
      ...enfants.skip(1),
    ]);
  }

  /// Combien d'espaces couvrent une largeur, dans le style de lecture.
  int _espacesPour(double largeur, TextStyle? style) {
    double mesure(String texte) {
      final peintre = TextPainter(
        text: TextSpan(text: texte, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final l = peintre.width;
      peintre.dispose();
      return l;
    }

    final espace = mesure('n n') - mesure('nn');
    if (espace <= 0) return 6;
    return (largeur / espace).ceil();
  }

  /// La part de la séance qui dépasse le chapitre affiché, s'il y en a une.
  (int, int)? _debordement(Map<String, dynamic> chapitre) {
    final finChapitre = chapitre['page_fin'] as int?;
    final finSeance = widget.pageFin;
    if (finChapitre == null || finSeance == null || finSeance <= finChapitre) {
      return null;
    }
    return (finChapitre + 1, finSeance);
  }

  void _ouvrirAgent(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Le fond du papier de lecture, arrondi en haut seulement : la feuille
      // monte du bas de l'écran, ses coins inférieurs ne se voient pas.
      backgroundColor: context.palette.fond,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: PanneauAgent(documentId: widget.documentId, chapitreId: widget.chapitreId),
      ),
    );
  }

  /// Compose le texte en teintant les portions déjà surlignées.
  TextSpan _teinter(String texte, List<Map<String, dynamic>> surlignages, TextStyle? base) {
    // Même longueur que le texte d'origine : les positions trouvées sur l'un
    // valent pour l'autre.
    final affiche = lisible(texte, composes: false);
    final marques = <({int debut, int fin, Color teinte})>[];
    for (final s in surlignages) {
      final citation = '${s['citation'] ?? ''}';
      if (citation.isEmpty) continue;
      final debut = texte.indexOf(citation);
      if (debut < 0) continue;
      marques.add((
        debut: debut,
        fin: debut + citation.length,
        teinte: teinteDe(s['couleur'] as String?),
      ));
    }
    if (marques.isEmpty) return TextSpan(text: affiche, style: base);

    marques.sort((a, b) => a.debut.compareTo(b.debut));
    final morceaux = <TextSpan>[];
    var curseur = 0;
    for (final m in marques) {
      // Deux surlignages qui se chevauchent : on garde le premier et on saute
      // le second, plutôt que de produire des indices négatifs.
      if (m.debut < curseur) continue;
      if (m.debut > curseur) {
        morceaux.add(TextSpan(text: affiche.substring(curseur, m.debut), style: base));
      }
      morceaux.add(TextSpan(
        text: affiche.substring(m.debut, m.fin),
        style: base?.copyWith(backgroundColor: m.teinte.withValues(alpha: 0.28)),
      ));
      curseur = m.fin;
    }
    if (curseur < texte.length) {
      morceaux.add(TextSpan(text: affiche.substring(curseur), style: base));
    }
    return TextSpan(children: morceaux);
  }

  /// Le menu de sélection, augmenté d'un « Surligner ».
  Widget _menuTexte(
    BuildContext context,
    EditableTextState etat,
    String texte,
    int? page,
    String chunkId,
  ) {
    final entrees = etat.contextMenuButtonItems;
    final selection = etat.textEditingValue.selection;
    if (selection.isValid && !selection.isCollapsed) {
      // Le texte affiché porte des espaces insécables (voir `lisible`) : la
      // citation enregistrée garde les espaces du livre.
      final choisi = selection.textInside(etat.textEditingValue.text).replaceAll('\u00A0', ' ').trim();
      if (choisi.isNotEmpty && choisi.length <= 2000) {
        entrees.insert(
          0,
          ContextMenuButtonItem(
            label: 'Surligner',
            onPressed: () {
              etat.hideToolbar();
              _surligner(choisi, page, chunkId);
            },
          ),
        );
      }
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: etat.contextMenuAnchors,
      buttonItems: entrees,
    );
  }

  Future<void> _surligner(String citation, int? page, String chunkId) async {
    try {
      await ref.read(clientApiProvider).post('/surlignages', corps: {
        'document_id': widget.documentId,
        if (chunkId.isNotEmpty) 'chunk_id': chunkId,
        'page': page,
        'citation': citation,
        'couleur': 'or',
      });
      if (!mounted) return;
      ref.invalidate(surlignagesProvider(widget.documentId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Texte('Passage surligné.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Texte("Le surlignage n'a pas pu être enregistré.")),
      );
    }
  }

  void _ouvrirAnnotations() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.palette.fond,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.86,
        child: PanneauAnnotations(documentId: widget.documentId),
      ),
    );
  }

  Future<void> _prendreNote(int? page) async {
    final texte = await editerNote(context);
    if (texte == null || texte.isEmpty || !mounted) return;
    try {
      await ref.read(clientApiProvider).post('/notes', corps: {
        'document_id': widget.documentId,
        'page': page,
        'texte': texte,
      });
      if (!mounted) return;
      ref.invalidate(notesProvider(widget.documentId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Texte('Note enregistrée.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Texte("La note n'a pas pu être enregistrée.")),
      );
    }
  }
}

/// Un outil de la réglette basse : une icône à la plume sur un creux de papier.
class _BoutonOutil extends StatelessWidget {
  const _BoutonOutil({required this.icone, required this.onTap, this.tooltip});
  final Icone icone;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: p.surfaceCreuse,
        shape: const RoundedRectangleBorder(borderRadius: Rayons.petit),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 50,
            height: 50,
            child: Center(child: IconeAscenda(icone, taille: 22, couleur: p.encre)),
          ),
        ),
      ),
    );
  }
}


/// Les pages d'une séance qui débordent du chapitre courant.
class _PagesSupplementaires extends ConsumerWidget {
  const _PagesSupplementaires({
    required this.documentId,
    required this.debut,
    required this.fin,
    required this.style,
  });

  final String documentId;
  final int debut;
  final int fin;

  /// Le style du texte principal, pour que la suite se lise sans rupture.
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suite = ref.watch(
      lecturePagesProvider((documentId: documentId, debut: debut, fin: fin)),
    );
    return suite.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Squelette(hauteur: 14),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (d) {
        final passages = (d['passages'] as List).cast<Map<String, dynamic>>();
        if (passages.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // La suite reprend comme une nouvelle page du même livre : son
            // titre courant, son folio, son filet.
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: TitreCourant('suite de la séance', folio: 'p. $debut à $fin'),
            ),
            for (final x in passages) ...[
              SelectableText(
                lisible('${x['texte']}', composes: false),
                textAlign: Texte.alignement('${x['texte']}', TextStyle(fontSize: style?.fontSize), null,
                        largeur: MediaQuery.sizeOf(context).width) ??
                    TextAlign.start,
                style: style,
              ),
              const SizedBox(height: 24),
            ],
          ],
        );
      },
    );
  }
}
