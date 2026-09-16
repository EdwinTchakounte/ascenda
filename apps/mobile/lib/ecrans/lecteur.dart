import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/annotations.dart';
import '../widgets/derives.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';
import 'agent.dart';
import '../theme/texte.dart';

/// Le lecteur : plein écran, sur le papier du thème choisi, serif confortable.
///
/// Sur les 71 ouvrages non redistribuables, le serveur ne renvoie que des
/// extraits plafonnés. On le dit clairement plutôt que de laisser croire à un
/// bug d'affichage.
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

  /// Le texte de lecture : Fraunces, interligne ample, et une encre un peu
  /// plus soutenue que le texte d'interface. Sur le papier Sépia comme sur la
  /// Nuit, c'est le contraste d'un livre, pas celui d'un formulaire.
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

    return Scaffold(
      backgroundColor: p.fond,
      appBar: AppBar(
        backgroundColor: p.fond,
        toolbarHeight: 52,
        actionsIconTheme: IconThemeData(color: p.attenue, size: 22),
        actions: [
          if (lecture.valueOrNull?['droits']?['pdf'] == true)
            IconButton(
              tooltip: 'Voir cette page dans le PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              color: p.attenue,
              onPressed: () {
                final d = lecture.valueOrNull!;
                final page = d['chapitre']?['page_debut'];
                context.push('/pdf/${widget.documentId}'
                    '?titre=${Uri.encodeComponent('${d['ouvrage']?['titre'] ?? ''}')}'
                    '${page != null ? '&page=$page' : ''}');
              },
            ),
          IconButton(
            tooltip: 'Taille du texte',
            icon: const Icon(Icons.text_fields_rounded),
            color: p.attenue,
            onPressed: () => setState(() => _taille = _taille >= 22 ? 16 : _taille + 2),
          ),
          IconButton(
            tooltip: "Demander à l'agent",
            icon: const Icon(Icons.forum_outlined),
            color: p.attenue,
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
                  Texte(
                    '${ouvrage['titre']}'.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.labelSmall?.copyWith(
                      color: p.accentTexte,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Texte('${chapitre['titre'] ?? 'Chapitre ${chapitre['ordre']}'}',
                      style: t.textTheme.headlineMedium?.copyWith(fontSize: 27, height: 1.2)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (chapitre['page_debut'] != null)
                        Pastille(
                          'p. ${chapitre['page_debut']}'
                          '${chapitre['page_fin'] != null ? ' à ${chapitre['page_fin']}' : ''}',
                          icone: Icons.menu_book_outlined,
                          couleur: p.attenue,
                        ),
                      if (chapitre['duree_min'] != null)
                        Pastille('${chapitre['duree_min']} min', icone: Icons.schedule_rounded, couleur: p.attenue),
                    ],
                  ),
                  const SizedBox(height: 22),
                  // Un court filet doré : la fin de l'en-tête et le début du
                  // texte, comme l'ornement sous un titre de chapitre.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 44,
                      height: 3,
                      decoration: BoxDecoration(color: p.accent, borderRadius: Rayons.pilule),
                    ),
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
                    for (final x in passages) ...[
                      SelectableText.rich(
                        textAlign: Texte.alignement('${x['texte']}', TextStyle(fontSize: _taille), null,
                                largeur: MediaQuery.sizeOf(context).width) ??
                            TextAlign.start,
                        _teinter(
                          '${x['texte']}',
                          surlignages,
                          style,
                        ),
                        contextMenuBuilder: (c, etat) => _menuTexte(
                          c,
                          etat,
                          '${x['texte']}',
                          x['page_debut'] as int? ?? chapitre['page_debut'] as int?,
                          '${x['id'] ?? ''}',
                        ),
                      ),
                      if (x['tronque'] == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(Icons.more_horiz_rounded, size: 16, color: p.attenue),
                              const SizedBox(width: 6),
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

                  if (suivant != null) ...[
                    const SizedBox(height: 16),
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
                                Texte('Chapitre suivant',
                                    style: t.textTheme.labelSmall?.copyWith(
                                      color: p.accentTexte,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    )),
                                const SizedBox(height: 4),
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
                            decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                            child: Icon(Icons.arrow_forward_rounded, size: 21, color: p.surAccent),
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
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: Rayons.pilule,
                          border: Border.all(color: p.trait),
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
                                    shape: const StadiumBorder(),
                                  ),
                                  icon: const Icon(Icons.check_rounded, size: 19),
                                  // Sous 360 px, le libellé complet ne tient pas à côté
                                  // des deux boutons ronds : on garde le verbe.
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
                              _BoutonRond(
                                icone: Icons.edit_note_rounded,
                                tooltip: 'Prendre une note',
                                onTap: () => _prendreNote(chapitre['page_debut'] as int?),
                              ),
                              const SizedBox(width: 6),
                              _BoutonRond(
                                icone: Icons.bookmarks_outlined,
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
    );
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
  ///
  /// On retrouve chaque citation par recherche littérale dans le passage. Une
  /// citation qui ne s'y retrouve plus (texte corrigé depuis, extrait abrégé
  /// autrement) est simplement ignorée : mieux vaut un surlignage qui ne
  /// s'affiche pas qu'un texte qui refuse de s'afficher.
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
  ///
  /// On garde les entrées natives (copier, tout sélectionner) : les remplacer
  /// priverait le lecteur de gestes qu'il connaît déjà.
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

class _BoutonRond extends StatelessWidget {
  const _BoutonRond({required this.icone, required this.onTap, this.tooltip});
  final IconData icone;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: p.surfaceCreuse,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 50, height: 50, child: Icon(icone, size: 22, color: p.encre)),
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
    final p = context.palette;
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
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 18),
              child: Row(
                children: [
                  Icon(Icons.south_rounded, size: 15, color: p.accentTexte),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Texte(
                      'Suite de la séance, p. $debut à $fin',
                      maxLines: 2,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: p.accentTexte,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Divider(height: 1, color: p.trait)),
                ],
              ),
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
