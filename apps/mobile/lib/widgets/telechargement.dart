import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../etat/hors_ligne.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../theme/icones.dart';
import '../theme/mouvement.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import 'livre.dart';
import 'ui.dart';

/// Le bloc de téléchargement d'un ouvrage.
class BlocTelechargement extends ConsumerStatefulWidget {
  const BlocTelechargement({
    super.key,
    required this.documentId,
    required this.titre,
    this.integral = false,
    this.pdfOctets,
  });

  final String documentId;
  final String titre;

  /// Ce lecteur peut emporter le texte intégral et le PDF (ouvrage réservé à
  /// l'application, lecteur abonné). Ils sont gardés chiffrés dans l'application.
  final bool integral;
  final int? pdfOctets;

  @override
  ConsumerState<BlocTelechargement> createState() => _BlocTelechargementState();
}

class _BlocTelechargementState extends ConsumerState<BlocTelechargement> {
  bool _enCours = false;
  bool _pdfEnCours = false;

  /// Ce que le PDF emporté pèse. Nul quand il n'y en a pas ; [_pdfSansTaille]
  /// dit qu'il y en a un mais qu'on ne sait pas le mesurer.
  int? _pdfOctetsLocal;
  bool _pdfSansTaille = false;

  @override
  void initState() {
    super.initState();
    _mesurerPdf();
  }

  /// La taille du PDF gardé sur l'appareil.
  Future<void> _mesurerPdf() async {
    final depot = ref.read(depotHorsLigneProvider);
    int? octets;
    var sansTaille = false;
    try {
      if (await depot.aPdf(widget.documentId)) {
        final clair = await depot.fichierPdfClair(widget.documentId);
        if (clair != null && await clair.exists()) {
          octets = await clair.length();
        } else if (widget.pdfOctets != null) {
          octets = widget.pdfOctets;
        } else {
          sansTaille = true;
        }
      }
    } catch (_) {
      // Une mesure impossible ne doit rien casser : on n'annonce alors que le
      // poids du pack.
    }
    if (!mounted) return;
    setState(() {
      _pdfOctetsLocal = octets;
      _pdfSansTaille = sansTaille;
    });
  }

  /// Ce que l'ouvrage occupe réellement : le pack, et le PDF s'il est là.
  String _tailleSurAppareil(PackHorsLigne local) {
    final total = local.octets + (_pdfOctetsLocal ?? 0);
    final poids = total < 1024 * 1024
        ? '${(total / 1024).round()} Ko'
        : '${(total / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
    return _pdfSansTaille ? '$poids, plus le PDF' : poids;
  }

  Future<void> _telecharger() async {
    setState(() => _enCours = true);
    final messager = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(clientApiProvider);
      final depot = ref.read(depotHorsLigneProvider);
      final pack = await api.get('/bibliotheque/${widget.documentId}/pack') as Map<String, dynamic>;
      await depot.enregistrer(widget.documentId, pack);
      // Le PDF part avec le texte quand le lecteur peut les emporter : lire hors
      // ligne, c'est aussi pouvoir retrouver une figure ou un tableau.
      if (pack['lecture'] != null && widget.integral && !await depot.aPdf(widget.documentId)) {
        final octets = await api.telecharger('/lecteur/${widget.documentId}/pdf');
        await depot.enregistrerPdf(widget.documentId, octets);
      }
      ref.invalidate(packsProvider);
      ref.invalidate(packLocalProvider(widget.documentId));
      await _mesurerPdf();
      if (!mounted) return;
      final c = pack['compteurs'] as Map;
      messager.showSnackBar(SnackBar(
        content: Texte(
          pack['lecture'] != null
              ? "Lisible hors ligne dans ASCENDA : texte intégral, PDF et "
                  "${c['questions']} questions, gardés chiffrés sur ce téléphone."
              : "Disponible hors ligne : ${c['chapitres']} chapitres, "
                  "${c['citations']} citations, ${c['questions']} questions.",
        ),
      ));
    } on HorsLigne {
      messager.showSnackBar(const SnackBar(
        content: Texte("Pas de connexion. Le téléchargement demande du réseau une fois."),
      ));
    } catch (_) {
      messager.showSnackBar(const SnackBar(
        content: Texte("Le téléchargement n'a pas abouti. Réessayez."),
      ));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<void> _supprimer() async {
    await ref.read(depotHorsLigneProvider).supprimer(widget.documentId);
    ref.invalidate(packsProvider);
    ref.invalidate(packLocalProvider(widget.documentId));
    await _mesurerPdf();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Texte("Pack retiré de l'appareil.")));
  }

  Future<void> _ouvrirPdf() async {
    setState(() => _pdfEnCours = true);
    final messager = ScaffoldMessenger.of(context);
    try {
      final base = ref.read(clientApiProvider).base;
      final url = Uri.parse('$base/v1/bibliotheque/${widget.documentId}/export.pdf');
      // On laisse le système ouvrir le PDF : visionneuse, partage et
      // impression sont déjà là, il n'y a rien à réécrire.
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        messager.showSnackBar(const SnackBar(
          content: Texte("Aucune application ne peut ouvrir le PDF."),
        ));
      }
    } catch (_) {
      messager.showSnackBar(const SnackBar(
        content: Texte("L'export PDF n'a pas pu être ouvert."),
      ));
    } finally {
      if (mounted) setState(() => _pdfEnCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final packs = ref.watch(packsProvider);
    final local = packs.maybeWhen(
      data: (m) => m[widget.documentId],
      orElse: () => null,
    );
    final garde = local != null;
    final teinte = garde ? p.succes : p.accentTexte;

    return Surface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Un bandeau teinté en tête : vert quand l'ouvrage est déjà sur le téléphone
          Apparition(
            key: ValueKey(garde),
            echelle: garde,
            depuis: 10,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              color: teinte.withValues(alpha: p.sombre ? 0.14 : 0.08),
              child: Row(
                children: [
                  // Le dos du volume, signet dehors une fois emporté.
                  DosLivre(titre: widget.titre, hauteur: 62, largeur: 26, marque: garde),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        EtiquetteCrochet(
                          garde ? 'sur votre étagère' : 'à emporter',
                          couleur: teinte,
                        ),
                        const SizedBox(height: 8),
                        Texte(
                          garde ? 'Disponible hors ligne' : 'Emporter cet ouvrage',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.titleLarge?.copyWith(fontSize: 18),
                        ),
                        if (garde) ...[
                          const SizedBox(height: 3),
                          Texte(
                            _tailleSurAppareil(local),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.labelMedium?.copyWith(color: p.succes, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Texte(
                  garde
                      ? "${local.compteurs['chapitres'] ?? 0} chapitres, "
                          "${local.compteurs['citations'] ?? 0} citations, "
                          "${local.compteurs['questions'] ?? 0} questions. "
                          "Sur l'appareil : ${_tailleSurAppareil(local)}."
                      : widget.integral
                          ? "Le texte intégral et le PDF${widget.pdfOctets != null ? ' (${(widget.pdfOctets! / 1048576).toStringAsFixed(0)} Mo)' : ''}, "
                              "les quiz et le plan, lisibles sans réseau. Gardés chiffrés : ils ne "
                              "s'ouvrent que dans ASCENDA."
                          : "Fiche, idées-force, citations avec leurs pages, quiz et plan de "
                              "lecture. Tout reste utilisable sans réseau, y compris les quiz.",
                  style: t.textTheme.bodySmall?.copyWith(color: p.texte, height: 1.55),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: garde
                          ? OutlinedButton.icon(
                              onPressed: _supprimer,
                              icon: const Icon(Icons.delete_outline_rounded, size: 18),
                              label: const Texte('Retirer', maxLines: 1, overflow: TextOverflow.ellipsis),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: p.attenue,
                                side: BorderSide(color: p.trait),
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                            )
                          : FilledButton.icon(
                              onPressed: _enCours ? null : _telecharger,
                              icon: _enCours
                                  ? SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: p.surAccent))
                                  : IconeAscenda(Icone.signet, taille: 18, couleur: p.surAccent),
                              label: Texte(_enCours ? 'En cours' : 'Emporter',
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 48),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pdfEnCours ? null : _ouvrirPdf,
                        icon: _pdfEnCours
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : IconeAscenda(Icone.page, taille: 18, couleur: p.accentTexte),
                        // Le compagnon de lecture (fiche, citations, quiz), jamais le livre.
                        label: const Texte('Compagnon', maxLines: 1, overflow: TextOverflow.ellipsis),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
