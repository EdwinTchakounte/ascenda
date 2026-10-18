
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../etat/fournisseurs.dart';
import '../etat/hors_ligne.dart';
import '../etat/session.dart';
import '../theme/icones.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import '../widgets/etats.dart';
import '../widgets/livre.dart';
import '../widgets/ui.dart';

final reservesConnus = <String, bool>{};

class EcranLecteurPdf extends ConsumerStatefulWidget {
  const EcranLecteurPdf({super.key, required this.documentId, this.titre, this.page});

  final String documentId;
  final String? titre;
  final int? page;

  @override
  ConsumerState<EcranLecteurPdf> createState() => _EcranLecteurPdfState();
}

class _EcranLecteurPdfState extends ConsumerState<EcranLecteurPdf> {
  final _controleur = PdfViewerController();

  File? _fichier;

  Uint8List? _octets;
  Object? _erreur;
  int _recu = 0;
  int? _total;
  int _page = 1;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    _ouvrir();
  }

  Future<void> _ouvrir() async {
    setState(() {
      _erreur = null;
      _fichier = null;
      _octets = null;
      _recu = 0;
      _total = null;
    });
    final depot = ref.read(depotHorsLigneProvider);
    try {
      final clair = await depot.fichierPdfClair(widget.documentId);
      if (clair != null && await clair.exists()) {
        if (mounted) setState(() => _fichier = clair);
        return;
      }
      final garde = await depot.lirePdf(widget.documentId);
      if (garde != null) {
        if (mounted) setState(() => _octets = garde);
        return;
      }
      final reserve = await _reserve(depot);
      void avance(int recu, int? total) {
        if (mounted) {
          setState(() {
            _recu = recu;
            _total = total;
          });
        }
      }

      if (!reserve && clair != null) {
        final ecrit = await ref
            .read(clientApiProvider)
            .telechargerVers('/lecteur/${widget.documentId}/pdf', clair, progression: avance);
        if (mounted) setState(() => _fichier = ecrit);
        return;
      }
      final octets = await ref.read(clientApiProvider).telecharger(
        '/lecteur/${widget.documentId}/pdf',
        progression: avance,
      );
      if (reserve || clair == null) {
        await depot.enregistrerPdf(widget.documentId, octets);
        if (mounted) setState(() => _octets = octets);
        return;
      }
      final provisoire = File('${clair.path}.part');
      await provisoire.writeAsBytes(octets, flush: true);
      await provisoire.rename(clair.path);
      if (mounted) setState(() => _fichier = clair);
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  Future<bool> _reserve(DepotHorsLigne depot) async {
    final connu = reservesConnus[widget.documentId];
    if (connu != null) return connu;
    if (mounted) {
      final fiche = ficheOuvrageProvider(widget.documentId);
      if (ProviderScope.containerOf(context, listen: false).exists(fiche)) {
        final droits = ref.read(fiche).valueOrNull?['droits'];
        if (droits is Map) return droits['application_seulement'] == true;
      }
    }
    final pack = await depot.lire(widget.documentId);
    return pack == null || pack['lecture'] != null;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return FondPapier(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          leading: IconButton(
            tooltip: 'Retour',
            icon: Transform.scale(
              scaleX: -1,
              child: IconeAscenda(Icone.fleche, taille: 21, couleur: p.attenue),
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Texte(widget.titre ?? 'Lecture',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.appBarTheme.titleTextStyle?.copyWith(fontSize: 18)),
          actions: [
            if (_pages > 0) _Folio(page: _page, pages: _pages, onTap: _allerA),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(top: false, child: _corps(t)),
      ),
    );
  }

  Future<void> _allerA() async {
    final saisie = TextEditingController();
    final page = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Texte('Aller à la page'),
        content: TextField(
          controller: saisie,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 à $_pages'),
          onSubmitted: (v) => Navigator.of(c).pop(int.tryParse(v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Texte('Annuler')),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(int.tryParse(saisie.text)),
            child: const Texte('Ouvrir'),
          ),
        ],
      ),
    );
    if (page == null || !mounted) return;
    await _controleur.goToPage(pageNumber: page.clamp(1, _pages));
  }

  Widget _corps(ThemeData t) {
    if (_erreur != null) {
      final e = _erreur;
      return EtatErreur(erreur: e!, reessayer: _ouvrir);
    }
    final parametres = PdfViewerParams(
      backgroundColor: Colors.transparent,
      margin: 12,
      calculateInitialPageNumber: (document, controleur) =>
          widget.page?.clamp(1, document.pages.length),
      viewerOverlayBuilder: (context, taille, lien) => [
        PdfViewerScrollThumb(
          controller: _controleur,
          orientation: ScrollbarOrientation.right,
          thumbSize: const Size(52, 30),
          thumbBuilder: (context, taille, page, controleur) => Container(
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
              border: Border.all(
                  color: context.palette.encre
                      .withValues(alpha: context.palette.sombre ? 0.22 : 0.12)),
              boxShadow: context.palette.ombreCarte,
            ),
            alignment: Alignment.center,
            child: Texte(page == null ? '' : 'p. $page',
                style: TextStyle(
                  color: context.palette.encre,
                  fontSize: 12,
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
          ),
        ),
      ],
      onViewerReady: (document, controleur) {
        if (mounted) {
          setState(() {
            _pages = document.pages.length;
            _page = controleur.pageNumber ?? widget.page?.clamp(1, _pages) ?? 1;
          });
        }
      },
      onPageChanged: (page) {
        if (mounted && page != null) setState(() => _page = page);
      },
      loadingBannerBuilder: (context, recu, total) => const Center(
        child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6)),
      ),
    );
    if (_fichier != null) {
      return PdfViewer.file(_fichier!.path, controller: _controleur, params: parametres);
    }
    if (_octets != null) {
      return PdfViewer.data(_octets!,
          sourceName: '${widget.documentId}.pdf', controller: _controleur, params: parametres);
    }
    return _Telechargement(recu: _recu, total: _total, titre: widget.titre);
  }
}

class _Folio extends StatelessWidget {
  const _Folio({required this.page, required this.pages, required this.onTap});

  final int page;
  final int pages;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: Rayons.petit,
            side: BorderSide(color: p.encre.withValues(alpha: p.sombre ? 0.22 : 0.12)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 34),
        ),
        child: Texte('p. $page sur $pages',
            maxLines: 1,
            style: t.textTheme.labelLarge?.copyWith(
              color: p.encre,
              letterSpacing: 0.6,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ),
    );
  }
}

class _Telechargement extends StatelessWidget {
  const _Telechargement({required this.recu, required this.total, this.titre});

  final int recu;
  final int? total;
  final String? titre;

  String _mo(int octets) => '${(octets / 1e6).toStringAsFixed(1).replaceAll('.', ',')} Mo';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final part = (total != null && total! > 0) ? recu / total! : null;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Surface(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (titre != null && titre!.isNotEmpty)
                  CouvertureLivre(titre: titre!, hauteur: 132)
                else
                  IconeAscenda(Icone.page, taille: 48, couleur: p.accentTexte),
                const SizedBox(height: 20),
                const EtiquetteCrochet('préparation du volume'),
                const SizedBox(height: 18),
                if (part != null)
                  Jauge(valeur: part, hauteur: 8)
                else
                  const ClipRRect(
                    borderRadius: Rayons.pilule,
                    child: LinearProgressIndicator(minHeight: 8),
                  ),
                const SizedBox(height: 10),
                Texte(
                  total != null ? '${_mo(recu)} sur ${_mo(total!)}' : _mo(recu),
                  style: t.textTheme.labelLarge?.copyWith(
                    color: p.encre,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 16),
                const Filet(redouble: true),
                const SizedBox(height: 12),
                Texte(
                  "Gardé sur le téléphone ensuite : la prochaine ouverture se fera sans réseau.",
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
