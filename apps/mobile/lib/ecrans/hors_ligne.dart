import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../etat/hors_ligne.dart';
import '../theme/palette.dart';
import '../theme/texte.dart';
import '../widgets/etats.dart';
import '../widgets/ui.dart';

/// Les ouvrages gardés sur l'appareil : lisibles sans réseau, et de quoi libérer
/// la place qu'ils prennent.
class EcranHorsLigne extends ConsumerWidget {
  const EcranHorsLigne({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(packsProvider);
    final t = Theme.of(context);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Texte('Livres hors ligne')),
      body: packs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EtatErreur(erreur: e, reessayer: () => ref.invalidate(packsProvider)),
        data: (m) {
          if (m.isEmpty) {
            return EtatMessage(
              icone: Icons.download_for_offline_outlined,
              titre: 'Rien sur cet appareil',
              texte: "Depuis la fiche d'un ouvrage, « Emporter » le garde ici : "
                  "fiche, sommaire et, avec Ascension, le texte et le PDF, lisibles sans réseau.",
              action: () => context.go('/bibliotheque'),
              libelleAction: 'Parcourir la bibliothèque',
            );
          }
          final total = m.values.fold<int>(0, (s, x) => s + x.octets);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              SurfaceHeros(
                child: Row(
                  children: [
                    IconePastille(Icons.offline_pin_rounded, couleur: p.accentSurHeros, taille: 48),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Texte('${m.length} ouvrage${m.length > 1 ? 's' : ''} emporté${m.length > 1 ? 's' : ''}',
                              style: t.textTheme.titleLarge?.copyWith(color: p.surHeros)),
                          const SizedBox(height: 2),
                          Texte('${_poids(total)} sur l\'appareil, chiffrés',
                              style: t.textTheme.bodySmall?.copyWith(color: p.surHerosDoux)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              for (final x in m.values) ...[
                Surface(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  onTap: () => context.push('/ouvrage/${x.documentId}'),
                  child: Row(
                    children: [
                      const IconePastille(Icons.menu_book_rounded, taille: 46),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Texte(x.titre, style: t.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Texte(
                              '${x.compteurs['chapitres'] ?? 0} chapitres · ${x.poids} · '
                              'le ${DateFormat('d MMM', 'fr_FR').format(x.telechargeLe)}',
                              style: t.textTheme.bodySmall?.copyWith(color: p.attenue),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: "Retirer de l'appareil",
                        icon: Icon(Icons.delete_outline_rounded, color: p.attenue),
                        onPressed: () async {
                          await ref.read(depotHorsLigneProvider).supprimer(x.documentId);
                          ref.invalidate(packsProvider);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _poids(int o) =>
      o < 1024 * 1024 ? '${(o / 1024).round()} Ko' : '${(o / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
}
