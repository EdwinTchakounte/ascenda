import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../etat/hors_ligne.dart';
import '../theme/mouvement.dart';
import '../theme/palette.dart';
import '../theme/papier.dart';
import '../theme/texte.dart';
import '../widgets/etats.dart';
import '../widgets/illustrations.dart';
import '../widgets/livre.dart';
import '../widgets/ui.dart';

/// Les ouvrages gardés sur l'appareil : lisibles sans réseau, et de quoi libérer
/// la place qu'ils prennent.
///
/// C'est une étagère personnelle, pas une liste de fichiers : les volumes
/// emportés sont posés sur leur tablette, signet dehors, et la notice de chacun
/// suit en dessous.
class EcranHorsLigne extends ConsumerWidget {
  const EcranHorsLigne({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = ref.watch(packsProvider);
    final t = Theme.of(context);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Texte('Livres hors ligne')),
      // Le grain du papier : l'étagère s'ouvre hors de la coque.
      body: FondPapier(
        child: packs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EtatErreur(erreur: e, reessayer: () => ref.invalidate(packsProvider)),
          data: (m) {
            if (m.isEmpty) {
              return EtatMessage(
                scene: Scene.rayonVide,
                titre: 'Rien sur cet appareil',
                texte: "Depuis la fiche d'un ouvrage, « Emporter » le garde ici : "
                    "fiche, sommaire et, avec Ascension, le texte et le PDF, lisibles sans réseau.",
                action: () => context.go('/bibliotheque'),
                libelleAction: 'Parcourir la bibliothèque',
              );
            }
            final total = m.values.fold<int>(0, (s, x) => s + x.octets);
            final volumes = m.values.toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, 10, 0, 32),
              children: [
                // L'étagère : les dos des volumes emportés, signet dehors.
                Apparition(
                  child: Rayon(
                    hauteur: 150,
                    volumes: [
                      for (final x in volumes)
                        (
                          titre: x.titre,
                          axeSlug: null,
                          marque: true,
                          onTap: () => context.push('/ouvrage/${x.documentId}'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          CompteurAnime(
                            volumes.length,
                            style: t.textTheme.headlineMedium?.copyWith(fontSize: 30, height: 1),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Texte(
                              volumes.length > 1 ? 'volumes emportés' : 'volume emporté',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.bodyMedium?.copyWith(color: p.attenue),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TitreCourant('sur cet appareil, chiffrés', folio: _poids(total)),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                for (final (i, x) in volumes.indexed)
                  Apparition(
                    rang: i + 1,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Surface(
                        padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                        onTap: () => context.push('/ouvrage/${x.documentId}'),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DosLivre(titre: x.titre, hauteur: 82, largeur: 32, marque: true),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Texte(x.titre,
                                      style: t.textTheme.titleMedium,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 8),
                                  const Filet(),
                                  const SizedBox(height: 8),
                                  Texte(
                                    '${x.compteurs['chapitres'] ?? 0} chapitres  ·  ${x.poids}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textTheme.labelSmall
                                        ?.copyWith(color: p.attenue, letterSpacing: 0.6),
                                  ),
                                  const SizedBox(height: 2),
                                  Texte(
                                    'emporté le ${DateFormat('d MMMM', 'fr_FR').format(x.telechargeLe)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.textTheme.labelSmall
                                        ?.copyWith(color: p.attenue, letterSpacing: 0.6),
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
                    ),
                  ),
                const SizedBox(height: 14),
                const Fleuron(),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _poids(int o) =>
      o < 1024 * 1024 ? '${(o / 1024).round()} Ko' : '${(o / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
}
