import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../theme/palette.dart';
import '../theme/texte.dart';
import 'illustrations.dart';

class EtatMessage extends StatelessWidget {
  const EtatMessage({
    super.key,
    required this.titre,
    required this.texte,
    this.icone,
    this.scene,
    this.action,
    this.libelleAction,
    this.teinte,
  });

  final String titre;
  final String texte;
  final IconData? icone;
  final Scene? scene;
  final VoidCallback? action;
  final String? libelleAction;
  final Color? teinte;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    final couleur = teinte ?? p.accentTexte;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (scene != null) ...[
                Illustration(scene!, taille: 172, accent: couleur),
                const SizedBox(height: 18),
              ] else if (icone != null) ...[
                _GrandePastille(icone: icone!, couleur: couleur),
                const SizedBox(height: 22),
              ],
              Texte(
                titre,
                style: t.textTheme.headlineSmall?.copyWith(fontSize: 23),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Texte(
                texte,
                style: t.textTheme.bodyMedium?.copyWith(color: p.attenue, height: 1.6),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: 26),
                FilledButton(
                  onPressed: action,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    shape: const RoundedRectangleBorder(borderRadius: Rayons.pilule),
                  ),
                  child: Texte(libelleAction ?? 'Réessayer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GrandePastille extends StatelessWidget {
  const _GrandePastille({required this.icone, required this.couleur});

  final IconData icone;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 104,
      height: 104,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [couleur.withValues(alpha: p.sombre ? 0.16 : 0.10), couleur.withValues(alpha: 0)],
        ),
      ),
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: p.sombre ? 0.18 : 0.11),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: couleur.withValues(alpha: 0.16)),
        ),
        child: Icon(icone, size: 34, color: couleur),
      ),
    );
  }
}

class EtatErreur extends StatelessWidget {
  const EtatErreur({super.key, required this.erreur, this.reessayer});

  final Object erreur;
  final VoidCallback? reessayer;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (erreur is HorsLigne) {
      return EtatMessage(
        scene: Scene.sansReseau,
        icone: Icons.cloud_off_rounded,
        teinte: p.attenue,
        titre: 'Pas de connexion',
        texte: "ASCENDA n'a pas pu joindre le serveur. Vérifiez votre réseau : "
            "vos notes et votre progression sont conservées.",
        action: reessayer,
      );
    }
    if (erreur is ErreurApi) {
      final e = erreur as ErreurApi;
      final versAbonnement = e.estPremium || e.estQuota;
      return EtatMessage(
        icone: e.estQuota
            ? Icons.hourglass_bottom_rounded
            : (e.estPremium ? Icons.workspace_premium_outlined : Icons.error_outline_rounded),
        teinte: e.estQuota || e.estPremium ? p.accentTexte : p.alerte,
        titre: e.estQuota
            ? 'Limite atteinte'
            : (e.estPremium ? 'Réservé à Ascension' : "Ça n'a pas fonctionné"),
        texte: e.message,
        action: versAbonnement ? () => context.push('/abonnement') : reessayer,
        libelleAction: versAbonnement ? 'Voir Ascension' : null,
      );
    }
    return EtatMessage(
      icone: Icons.error_outline_rounded,
      teinte: p.alerte,
      titre: "Une erreur est survenue",
      texte: "Réessayez dans un instant. Si cela persiste, redémarrez l'application.",
      action: reessayer,
    );
  }
}

class Squelette extends StatefulWidget {
  const Squelette({super.key, this.hauteur = 16, this.largeur, this.rayon = 0});

  final double hauteur;
  final double? largeur;
  final double rayon;

  @override
  State<Squelette> createState() => _SqueletteState();
}

class _SqueletteState extends State<Squelette> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = p.surfaceCreuse;
    final rayon = widget.rayon > 0 ? widget.rayon : math.min(widget.hauteur / 2, 10.0);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.hauteur,
        width: widget.largeur,
        decoration: BoxDecoration(
          color: Color.lerp(base, base.withValues(alpha: 0.45), Curves.easeInOut.transform(_c.value)),
          borderRadius: BorderRadius.circular(rayon),
        ),
      ),
    );
  }
}

class SqueletteCarte extends StatelessWidget {
  const SqueletteCarte({super.key, this.lignes = 3});

  final int lignes;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Rayons.carte,
        border: Border.all(color: p.trait),
        boxShadow: p.ombreCarte,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Squelette(hauteur: 42, largeur: 42, rayon: 13),
              SizedBox(width: 14),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(widthFactor: 0.7, child: Squelette(hauteur: 18)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < lignes; i++) ...[
            FractionallySizedBox(
              widthFactor: i.isEven ? 1 : 0.72,
              child: const Squelette(hauteur: 12),
            ),
            if (i < lignes - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class BandeauDroits extends StatelessWidget {
  const BandeauDroits({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      decoration: BoxDecoration(
        color: p.accentVoile,
        borderRadius: Rayons.carte,
        border: Border.all(color: p.accentTexte.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.surface.withValues(alpha: 0.7), borderRadius: Rayons.petit),
            child: Icon(Icons.menu_book_rounded, size: 18, color: p.accentTexte),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Texte(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.texte, height: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
