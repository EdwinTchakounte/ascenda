import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../etat/hors_ligne.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../theme/texte.dart';
import 'ui.dart';

/// Le bloc de téléchargement d'un ouvrage.
///
/// Deux gestes distincts, pour deux besoins distincts.
///
/// - **Hors ligne** : le pack est rangé sur le téléphone et tout reste
///   utilisable sans réseau, y compris les quiz et leur correction. C'est la
///   fonction qui change l'usage réel sur une connexion intermittente.
/// - **PDF** : le même contenu, mis en page, pour imprimer ou partager.
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
          // Un bandeau teinté en tête : vert quand l'ouvrage est déjà sur le
          // téléphone, doré quand il reste à emporter. L'état se lit avant le
          // texte.
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            color: teinte.withValues(alpha: p.sombre ? 0.14 : 0.08),
            child: Row(
              children: [
                IconePastille(
                  garde ? Icons.offline_pin_rounded : Icons.download_for_offline_rounded,
                  couleur: teinte,
                  taille: 44,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Texte(
                        garde ? 'Disponible hors ligne' : 'Emporter cet ouvrage',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleLarge?.copyWith(fontSize: 18),
                      ),
                      if (garde) ...[
                        const SizedBox(height: 2),
                        Texte(
                          local.poids,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Texte(
                  garde
                      ? "${local.compteurs['chapitres'] ?? 0} chapitres, "
                          "${local.compteurs['citations'] ?? 0} citations, "
                          "${local.compteurs['questions'] ?? 0} questions. ${local.poids} sur l'appareil."
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
                                  : const Icon(Icons.download_rounded, size: 18),
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
                            : const Icon(Icons.picture_as_pdf_outlined, size: 18),
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
