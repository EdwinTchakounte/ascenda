library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../etat/session.dart';
import '../theme/palette.dart';
import '../theme/texte.dart';
import 'ui.dart';

bool aLeDroit(WidgetRef ref, String fonction) =>
    ref.watch(sessionProvider).utilisateur?.aAcces(fonction) ?? false;

class SelonDroit extends ConsumerWidget {
  const SelonDroit({
    super.key,
    required this.fonction,
    required this.enfant,
    this.titre = 'Réservé à Ascension',
    this.message,
    this.lignes = 3,
    this.substitut,
    this.onAbonnement,
  });

  final String fonction;
  final Widget enfant;
  final String titre;
  final String? message;
  final int lignes;
  final Widget? substitut;
  final VoidCallback? onAbonnement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (aLeDroit(ref, fonction)) return enfant;
    return substitut ??
        ContenuReserve(
          titre: titre,
          message: message,
          lignes: lignes,
          onAbonnement: onAbonnement,
        );
  }
}

class ContenuReserve extends StatelessWidget {
  const ContenuReserve({
    super.key,
    this.titre = 'Réservé à Ascension',
    this.message,
    this.lignes = 3,
    this.onAbonnement,
  });

  final String titre;
  final String? message;
  final int lignes;
  final VoidCallback? onAbonnement;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final largeurs = [0.92, 0.78, 0.86, 0.7, 0.81];
    return Semantics(
      label: '$titre. ${message ?? ''}',
      child: Surface(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        couleur: Color.alphaBlend(p.accentVoile.withValues(alpha: 0.5), p.surface),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.surface.withValues(alpha: 0.75),
                    borderRadius: Rayons.petit,
                    border: Border.all(color: p.accentTexte.withValues(alpha: 0.22)),
                  ),
                  child: Icon(Icons.lock_outline_rounded, size: 18, color: p.accentTexte),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Texte(titre, style: t.textTheme.titleMedium?.copyWith(fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < lignes; i++) ...[
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: largeurs[i % largeurs.length],
                child: Container(
                  height: 11,
                  decoration: BoxDecoration(
                    color: p.texte.withValues(alpha: p.sombre ? 0.10 : 0.07),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (i < lignes - 1) const SizedBox(height: 9),
            ],
            const SizedBox(height: 13),
            Texte(
              message ?? "Cette partie s'ouvre avec Ascension, un abonnement ou un code d'accès.",
              style: t.textTheme.bodySmall?.copyWith(color: p.attenue, height: 1.5),
            ),
            if (onAbonnement != null) ...[
              const SizedBox(height: 13),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onAbonnement,
                  icon: const Icon(Icons.workspace_premium_outlined, size: 18),
                  label: const Texte('Voir Ascension'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    shape: const RoundedRectangleBorder(borderRadius: Rayons.pilule),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
