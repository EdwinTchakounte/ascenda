import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/client.dart';
import '../theme/couleurs.dart';

/// Les états qui ne sont pas le cas idéal. Ils sont dessinés, pas subis :
/// beaucoup de nos lecteurs sont sur des connexions intermittentes, et une
/// page blanche avec un message technique est la pire réponse possible.

class EtatMessage extends StatelessWidget {
  const EtatMessage({
    super.key,
    required this.titre,
    required this.texte,
    this.icone,
    this.action,
    this.libelleAction,
    this.teinte,
  });

  final String titre;
  final String texte;
  final IconData? icone;
  final VoidCallback? action;
  final String? libelleAction;
  final Color? teinte;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final couleur = teinte ?? Couleurs.grisChaud;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icone != null)
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icone, size: 30, color: couleur),
              ),
            const SizedBox(height: 20),
            Text(titre, style: t.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              texte,
              style: t.textTheme.bodyMedium?.copyWith(color: Couleurs.grisChaud),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              OutlinedButton(onPressed: action, child: Text(libelleAction ?? 'Réessayer')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Traduit une exception en écran compréhensible. Le hors-ligne, le quota et
/// l'offre payante ne se disent pas de la même façon.
class EtatErreur extends StatelessWidget {
  const EtatErreur({super.key, required this.erreur, this.reessayer});

  final Object erreur;
  final VoidCallback? reessayer;

  @override
  Widget build(BuildContext context) {
    if (erreur is HorsLigne) {
      return EtatMessage(
        icone: Icons.cloud_off_rounded,
        titre: 'Pas de connexion',
        texte: "ASCENDA n'a pas pu joindre le serveur. Vérifiez votre réseau : "
            "vos notes et votre progression sont conservées.",
        action: reessayer,
      );
    }
    if (erreur is ErreurApi) {
      final e = erreur as ErreurApi;
      // Buter sur l'offre payante et n'avoir qu'un bouton « Réessayer » sous les
      // yeux est une impasse : réessayer donnera exactement le même refus. On
      // ouvre donc l'abonnement, qui est la seule suite possible.
      final versAbonnement = e.estPremium || e.estQuota;
      return EtatMessage(
        icone: e.estQuota
            ? Icons.hourglass_bottom_rounded
            : (e.estPremium ? Icons.workspace_premium_outlined : Icons.error_outline_rounded),
        teinte: e.estQuota || e.estPremium ? Couleurs.or : Couleurs.terracotta,
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
      teinte: Couleurs.terracotta,
      titre: "Une erreur est survenue",
      texte: "Réessayez dans un instant. Si cela persiste, redémarrez l'application.",
      action: reessayer,
    );
  }
}

/// Squelette de chargement : des blocs à la forme du contenu attendu, plutôt
/// qu'un tourniquet centré qui ne dit rien de ce qui arrive.
class Squelette extends StatefulWidget {
  const Squelette({super.key, this.hauteur = 16, this.largeur, this.rayon = 8});

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
    final base = Theme.of(context).colorScheme.surfaceContainer;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        height: widget.hauteur,
        width: widget.largeur,
        decoration: BoxDecoration(
          color: Color.lerp(base, base.withValues(alpha: 0.45), _c.value),
          borderRadius: BorderRadius.circular(widget.rayon),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Squelette(hauteur: 20, largeur: 190),
          const SizedBox(height: 14),
          for (var i = 0; i < lignes; i++) ...[
            Squelette(hauteur: 12, largeur: i.isEven ? double.infinity : 220),
            const SizedBox(height: 9),
          ],
        ],
      ),
    );
  }
}

/// Bandeau discret pour signaler une limite de droits sur un ouvrage.
class BandeauDroits extends StatelessWidget {
  const BandeauDroits({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: Couleurs.or.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.menu_book_outlined, size: 18, color: Couleurs.orTexte),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Couleurs.grisChaud, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
