import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/fournisseurs.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../widgets/annotations.dart';
import '../widgets/derives.dart';
import '../widgets/etats.dart';
import 'agent.dart';

/// Le lecteur : plein écran, fond ivoire, serif confortable.
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

  @override
  Widget build(BuildContext context) {
    final cle = (documentId: widget.documentId, chapitreId: widget.chapitreId);
    final lecture = ref.watch(lectureProvider(cle));
    final t = Theme.of(context);

    return Scaffold(
      backgroundColor: t.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: t.colorScheme.surfaceContainerLowest,
        actions: [
          IconButton(
            tooltip: 'Taille du texte',
            icon: const Icon(Icons.text_fields_rounded),
            onPressed: () => setState(() => _taille = _taille >= 22 ? 16 : _taille + 2),
          ),
          IconButton(
            tooltip: "Demander à l'agent",
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => _ouvrirAgent(context),
          ),
        ],
      ),
      body: lecture.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Squelette(hauteur: 26, largeur: 240),
              SizedBox(height: 24),
              Squelette(hauteur: 14),
              SizedBox(height: 10),
              Squelette(hauteur: 14),
              SizedBox(height: 10),
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

          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                children: [
                  Text(
                    '${ouvrage['titre']}',
                    style: t.textTheme.labelMedium?.copyWith(color: Couleurs.orTexte),
                  ),
                  const SizedBox(height: 8),
                  Text('${chapitre['titre'] ?? 'Chapitre ${chapitre['ordre']}'}',
                      style: t.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (chapitre['page_debut'] != null)
                        'p. ${chapitre['page_debut']}'
                            '${chapitre['page_fin'] != null ? ' à ${chapitre['page_fin']}' : ''}',
                      if (chapitre['duree_min'] != null) '${chapitre['duree_min']} min',
                    ].join(' · '),
                    style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
                  ),

                  if (droits['message'] != null)
                    BandeauDroits(message: '${droits['message']}'),

                  const SizedBox(height: 20),
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
                    for (final p in passages) ...[
                      SelectableText.rich(
                        _teinter(
                          '${p['texte']}',
                          surlignages,
                          t.textTheme.bodyLarge?.copyWith(
                            fontFamily: t.textTheme.headlineSmall?.fontFamily,
                            fontSize: _taille,
                            height: 1.72,
                          ),
                        ),
                        contextMenuBuilder: (c, etat) => _menuTexte(
                          c,
                          etat,
                          '${p['texte']}',
                          p['page_debut'] as int? ?? chapitre['page_debut'] as int?,
                          '${p['id'] ?? ''}',
                        ),
                      ),
                      if (p['tronque'] == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Extrait abrégé.',
                            style: t.textTheme.labelSmall?.copyWith(color: Couleurs.grisChaud),
                          ),
                        ),
                      const SizedBox(height: 22),
                    ],

                  // Complément : le reste de la plage de la séance, quand elle
                  // regroupe plusieurs chapitres.
                  if (_debordement(chapitre) case (final d, final f))
                    _PagesSupplementaires(
                      documentId: widget.documentId,
                      debut: d,
                      fin: f,
                      taille: _taille,
                    ),

                  if (suivant != null) ...[
                    const Divider(height: 40),
                    InkWell(
                      onTap: () => context.pushReplacement(
                          '/lecture/${widget.documentId}/${suivant['id']}'),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Chapitre suivant',
                                      style: t.textTheme.labelSmall
                                          ?.copyWith(color: Couleurs.grisChaud)),
                                  const SizedBox(height: 3),
                                  Text('${suivant['titre'] ?? ''}',
                                      style: t.textTheme.titleMedium),
                                ],
                              ),
                            ),
                            const Icon(Icons.arrow_forward_rounded, color: Couleurs.orTexte),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              // Barre d'action basse, flottante.
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              _terminerSeance(widget.livrable, widget.livrableId),
                          icon: const Icon(Icons.check_rounded, size: 19),
                          label: Text(widget.seanceId != null
                              ? 'Terminer la séance'
                              : 'Marquer comme lu'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _BoutonRond(
                        icone: Icons.edit_note_rounded,
                        tooltip: 'Prendre une note',
                        onTap: () => _prendreNote(chapitre['page_debut'] as int?),
                      ),
                      const SizedBox(width: 10),
                      _BoutonRond(
                        icone: Icons.bookmarks_outlined,
                        tooltip: 'Vos annotations',
                        onTap: _ouvrirAnnotations,
                      ),
                    ],
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
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
    if (marques.isEmpty) return TextSpan(text: texte, style: base);

    marques.sort((a, b) => a.debut.compareTo(b.debut));
    final morceaux = <TextSpan>[];
    var curseur = 0;
    for (final m in marques) {
      // Deux surlignages qui se chevauchent : on garde le premier et on saute
      // le second, plutôt que de produire des indices négatifs.
      if (m.debut < curseur) continue;
      if (m.debut > curseur) {
        morceaux.add(TextSpan(text: texte.substring(curseur, m.debut), style: base));
      }
      morceaux.add(TextSpan(
        text: texte.substring(m.debut, m.fin),
        style: base?.copyWith(backgroundColor: m.teinte.withValues(alpha: 0.28)),
      ));
      curseur = m.fin;
    }
    if (curseur < texte.length) {
      morceaux.add(TextSpan(text: texte.substring(curseur), style: base));
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
      final choisi = selection.textInside(etat.textEditingValue.text).trim();
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
          .showSnackBar(const SnackBar(content: Text('Passage surligné.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Le surlignage n'a pas pu être enregistré.")),
      );
    }
  }

  void _ouvrirAnnotations() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
          .showSnackBar(const SnackBar(content: Text('Note enregistrée.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("La note n'a pas pu être enregistrée.")),
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
    final t = Theme.of(context);
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: t.colorScheme.surface,
        shape: const CircleBorder(),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(width: 52, height: 52, child: Icon(icone, size: 22)),
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
    required this.taille,
  });

  final String documentId;
  final int debut;
  final int fin;
  final double taille;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
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
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'Suite de la séance, p. $debut à $fin',
                style: t.textTheme.labelMedium?.copyWith(color: Couleurs.orTexte),
              ),
            ),
            for (final p in passages) ...[
              SelectableText(
                '${p['texte']}',
                style: t.textTheme.bodyLarge?.copyWith(
                  fontFamily: t.textTheme.headlineSmall?.fontFamily,
                  fontSize: taille,
                  height: 1.72,
                ),
              ),
              const SizedBox(height: 22),
            ],
          ],
        );
      },
    );
  }
}
