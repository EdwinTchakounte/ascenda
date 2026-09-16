
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../etat/hors_ligne.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../theme/texte.dart';
import '../widgets/etats.dart';

/// Lire le PDF d'origine d'un ouvrage, page par page, dans l'application.
///
/// Pour les ouvrages lisibles en entier : libres, ou réservés à l'application
/// pour un abonné. L'API refuse les autres, et la fiche ne propose le bouton que
/// là où il fonctionne. Le fichier est gardé chiffré sur le téléphone après la
/// première ouverture, et ne s'ouvre qu'ici.
class EcranLecteurPdf extends ConsumerStatefulWidget {
  const EcranLecteurPdf({super.key, required this.documentId, this.titre, this.page});

  final String documentId;
  final String? titre;

  /// La page où ouvrir : celle du chapitre ou de la séance d'où l'on vient.
  final int? page;

  @override
  ConsumerState<EcranLecteurPdf> createState() => _EcranLecteurPdfState();
}

class _EcranLecteurPdfState extends ConsumerState<EcranLecteurPdf> {
  final _controleur = PdfViewerController();
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
      _recu = 0;
      _total = null;
    });
    final depot = ref.read(depotHorsLigneProvider);
    try {
      // Déjà emporté : lu depuis le coffre, sans réseau.
      final garde = await depot.lirePdf(widget.documentId);
      if (garde != null) {
        if (mounted) setState(() => _octets = garde);
        return;
      }
      final octets = await ref.read(clientApiProvider).telecharger(
        '/lecteur/${widget.documentId}/pdf',
        progression: (recu, total) {
          if (mounted) {
            setState(() {
              _recu = recu;
              _total = total;
            });
          }
        },
      );
      // Gardé chiffré dans l'espace privé de l'application : on relit sans
      // réseau, on ne paie pas deux fois les mégaoctets, et le fichier ne
      // s'ouvre nulle part ailleurs. Jamais écrit en clair sur le disque.
      await depot.enregistrerPdf(widget.documentId, octets);
      if (mounted) setState(() => _octets = octets);
    } catch (e) {
      if (mounted) setState(() => _erreur = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      backgroundColor: Couleurs.papier,
      appBar: AppBar(
        title: Texte(widget.titre ?? 'Lecture', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_pages > 0)
            TextButton(
              // Toucher le compteur ouvre « aller à la page » : dans un livre de
              // 700 pages, faire défiler jusqu'à la page 412 n'est pas une option.
              onPressed: _allerA,
              child: Texte('$_page / $_pages',
                  style: t.textTheme.labelLarge?.copyWith(color: Couleurs.encreDouce)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(top: false, child: _corps(t)),
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
      backgroundColor: Couleurs.papier,
      margin: 10,
      calculateInitialPageNumber: (document, controleur) =>
          widget.page?.clamp(1, document.pages.length),
      // Une réglette sur le bord droit, qui porte le numéro de page : on
      // traverse le livre d'un geste.
      viewerOverlayBuilder: (context, taille, lien) => [
        PdfViewerScrollThumb(
          controller: _controleur,
          orientation: ScrollbarOrientation.right,
          thumbSize: const Size(48, 30),
          thumbBuilder: (context, taille, page, controleur) => Container(
            color: Couleurs.nuit,
            alignment: Alignment.center,
            child: Texte(page == null ? '' : '$page',
                style: const TextStyle(color: Couleurs.orClair, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
      onViewerReady: (document, controleur) {
        // Ouvert à une page précise, le compteur doit l'annoncer tout de suite :
        // le changement de page initial ne déclenche pas `onPageChanged`.
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
    if (_octets != null) {
      return PdfViewer.data(_octets!,
          sourceName: '${widget.documentId}.pdf', controller: _controleur, params: parametres);
    }
    return _Telechargement(recu: _recu, total: _total);
  }
}

class _Telechargement extends StatelessWidget {
  const _Telechargement({required this.recu, required this.total});

  final int recu;
  final int? total;

  String _mo(int octets) => '${(octets / 1e6).toStringAsFixed(1).replaceAll('.', ',')} Mo';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final part = (total != null && total! > 0) ? recu / total! : null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf_outlined, size: 40, color: Couleurs.orTexte),
            const SizedBox(height: 16),
            Texte('Préparation du PDF', style: t.textTheme.titleMedium),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: part, minHeight: 4),
            const SizedBox(height: 10),
            Texte(
              total != null ? '${_mo(recu)} sur ${_mo(total!)}' : _mo(recu),
              style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
            ),
            const SizedBox(height: 6),
            Texte(
              "Gardé sur le téléphone ensuite : la prochaine ouverture se fera sans réseau.",
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud),
            ),
          ],
        ),
      ),
    );
  }
}
