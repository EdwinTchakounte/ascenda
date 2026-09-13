import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../etat/hors_ligne.dart';
import '../etat/session.dart';
import '../theme/couleurs.dart';
import '../theme/texte.dart';

/// Le bloc de téléchargement d'un ouvrage.
///
/// Deux gestes distincts, pour deux besoins distincts.
///
/// - **Hors ligne** : le pack est rangé sur le téléphone et tout reste
///   utilisable sans réseau, y compris les quiz et leur correction. C'est la
///   fonction qui change l'usage réel sur une connexion intermittente.
/// - **PDF** : le même contenu, mis en page, pour imprimer ou partager.
class BlocTelechargement extends ConsumerStatefulWidget {
  const BlocTelechargement({super.key, required this.documentId, required this.titre});

  final String documentId;
  final String titre;

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
      final pack = await api.get('/bibliotheque/${widget.documentId}/pack', auth: false)
          as Map<String, dynamic>;
      await depot.enregistrer(widget.documentId, pack);
      ref.invalidate(packsProvider);
      ref.invalidate(packLocalProvider(widget.documentId));
      if (!mounted) return;
      final c = pack['compteurs'] as Map;
      messager.showSnackBar(SnackBar(
        content: Texte(
          "Disponible hors ligne : ${c['chapitres']} chapitres, "
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
    final packs = ref.watch(packsProvider);
    final local = packs.maybeWhen(
      data: (m) => m[widget.documentId],
      orElse: () => null,
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.colorScheme.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: local != null
              ? Couleurs.sauge.withValues(alpha: 0.4)
              : (t.dividerTheme.color ?? Couleurs.traitClair),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                local != null ? Icons.offline_pin_rounded : Icons.download_rounded,
                size: 20,
                color: local != null ? Couleurs.sauge : Couleurs.orTexte,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Texte(
                  local != null ? 'Disponible hors ligne' : 'Emporter cet ouvrage',
                  style: t.textTheme.titleMedium?.copyWith(fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Texte(
            local != null
                ? "${local.compteurs['chapitres'] ?? 0} chapitres, "
                    "${local.compteurs['citations'] ?? 0} citations, "
                    "${local.compteurs['questions'] ?? 0} questions. ${local.poids} sur l'appareil."
                : "Fiche, idées-force, citations avec leurs pages, quiz et plan de "
                    "lecture. Tout reste utilisable sans réseau, y compris les quiz.",
            style: t.textTheme.bodySmall?.copyWith(color: Couleurs.grisChaud, height: 1.55),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: local != null
                    ? OutlinedButton.icon(
                        onPressed: _supprimer,
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Texte('Retirer'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Couleurs.grisChaud,
                          side: BorderSide(color: t.dividerTheme.color ?? Couleurs.traitClair),
                          minimumSize: const Size(0, 46),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _enCours ? null : _telecharger,
                        icon: _enCours
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.download_rounded, size: 18),
                        label: Texte(_enCours ? 'En cours' : 'Emporter'),
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
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
                  label: const Texte('PDF'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
