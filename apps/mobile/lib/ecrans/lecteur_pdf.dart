import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../theme/texte.dart';
import '../widgets/etats.dart';

/// Lire le PDF d'origine d'un ouvrage, page par page, dans l'application.
///
/// Réservé aux ouvrages redistribuables : l'API refuse les autres, et la fiche
/// ne propose le bouton que là où il fonctionne. Le fichier est gardé sur le
/// téléphone après la première ouverture : on relit sans réseau, et on ne paie
/// pas deux fois les mégaoctets.
class EcranLecteurPdf extends ConsumerStatefulWidget {
  const EcranLecteurPdf({super.key, required this.documentId, this.titre});

  final String documentId;
  final String? titre;

  @override
  ConsumerState<EcranLecteurPdf> createState() => _EcranLecteurPdfState();
}

class _EcranLecteurPdfState extends ConsumerState<EcranLecteurPdf> {
  final _controleur = PdfViewerController();
  String? _chemin;
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

  Future<File?> _fichierLocal() async {
    if (kIsWeb) return null;
    final base = await getApplicationSupportDirectory();
    final dossier = Directory('${base.path}/pdf');
    if (!dossier.existsSync()) dossier.createSync(recursive: true);
    return File('${dossier.path}/${widget.documentId}.pdf');
  }

  Future<void> _ouvrir() async {
    setState(() {
      _erreur = null;
      _recu = 0;
      _total = null;
    });
    try {
      final fichier = await _fichierLocal();
      if (fichier != null && fichier.existsSync() && fichier.lengthSync() > 0) {
        setState(() => _chemin = fichier.path);
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
      if (fichier != null) {
        // Écrit sous un nom provisoire puis renommé : un téléchargement coupé
        // ne laisse jamais un PDF tronqué qu'on rouvrirait ensuite.
        final provisoire = File('${fichier.path}.part');
        await provisoire.writeAsBytes(octets, flush: true);
        await provisoire.rename(fichier.path);
        if (mounted) setState(() => _chemin = fichier.path);
      } else if (mounted) {
        setState(() => _octets = octets);
      }
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
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Texte('$_page / $_pages',
                    style: t.textTheme.labelLarge?.copyWith(color: Couleurs.grisChaud)),
              ),
            ),
        ],
      ),
      body: SafeArea(top: false, child: _corps(t)),
    );
  }

  Widget _corps(ThemeData t) {
    if (_erreur != null) {
      final e = _erreur;
      return EtatErreur(erreur: e!, reessayer: _ouvrir);
    }
    final parametres = PdfViewerParams(
      backgroundColor: Couleurs.papier,
      margin: 10,
      onViewerReady: (document, controleur) {
        if (mounted) setState(() => _pages = document.pages.length);
      },
      onPageChanged: (page) {
        if (mounted && page != null) setState(() => _page = page);
      },
      loadingBannerBuilder: (context, recu, total) => const Center(
        child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6)),
      ),
    );
    if (_chemin != null) {
      return PdfViewer.file(_chemin!, controller: _controleur, params: parametres);
    }
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
