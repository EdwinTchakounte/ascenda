import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../etat/session.dart';
import '../theme/palette.dart';
import '../theme/texte.dart';

/// Les composants communs de l'interface. Un écran se compose de ces briques
/// plutôt que de conteneurs décorés à la main : l'application garde une seule
/// voix, dans les quatre thèmes.

/// Ouvre le tiroir de la coque depuis n'importe quel onglet.
final cleCoque = GlobalKey<ScaffoldState>();

/// Le bouton du tiroir, à placer en tête de la barre d'un onglet.
class BoutonMenu extends StatelessWidget {
  const BoutonMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu_rounded, size: 26),
      onPressed: () => cleCoque.currentState?.openDrawer(),
    );
  }
}

/// L'initiale du lecteur dans un disque doré. Ouvre le profil.
class AvatarCompte extends ConsumerWidget {
  const AvatarCompte({super.key, this.taille = 38, this.ouvrirProfil = true});

  final double taille;
  final bool ouvrirProfil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final session = ref.watch(sessionProvider);
    final u = session.utilisateur;
    // Sans compte, pas d'initiale inventée : une porte vers la connexion.
    if (!session.connecte && ouvrirProfil) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: IconButton(
          tooltip: 'Se connecter',
          icon: Icon(Icons.account_circle_outlined, size: taille * 0.78, color: p.texte),
          onPressed: () => context.go('/bienvenue'),
        ),
      );
    }
    final initiale = (u?.nom?.trim().isNotEmpty == true ? u!.nom!.trim()[0] : (u?.email?[0] ?? 'A')).toUpperCase();
    final disque = Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.accentSurHeros, p.accent],
        ),
        boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      alignment: Alignment.center,
      child: Text(
        initiale,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: p.surAccent,
              fontSize: taille * 0.42,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
    if (!ouvrirProfil) return disque;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkResponse(
        radius: taille * 0.7,
        onTap: () => context.push('/profil'),
        child: Semantics(label: 'Profil', button: true, child: disque),
      ),
    );
  }
}

/// Une surface posée sur le fond : arrondie, ombre légère, filet discret.
class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.couleur,
    this.rayon = Rayons.carte,
    this.ombre = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? couleur;
  final BorderRadius rayon;
  final bool ombre;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: rayon,
        boxShadow: ombre ? p.ombreCarte : null,
      ),
      child: Material(
        color: couleur ?? p.surface,
        shape: RoundedRectangleBorder(borderRadius: rayon, side: BorderSide(color: p.trait)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// La grande carte de mise en avant, sur le dégradé profond du thème.
class SurfaceHeros extends StatelessWidget {
  const SurfaceHeros({super.key, required this.child, this.padding = const EdgeInsets.all(22), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: Rayons.grand, boxShadow: p.ombreHeros),
      child: ClipRRect(
        borderRadius: Rayons.grand,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(gradient: p.degradeHeros),
            child: InkWell(
              onTap: onTap,
              child: Stack(
                children: [
                  // Deux halos dorés, très bas : la lumière d'une lampe de lecture.
                  Positioned(
                    right: -60,
                    top: -70,
                    child: _Halo(couleur: p.accentSurHeros.withValues(alpha: 0.13), taille: 240),
                  ),
                  Positioned(
                    left: -40,
                    bottom: -90,
                    child: _Halo(couleur: p.surHeros.withValues(alpha: 0.06), taille: 200),
                  ),
                  Padding(padding: padding, child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({required this.couleur, required this.taille});
  final Color couleur;
  final double taille;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: taille,
          height: taille,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [couleur, couleur.withValues(alpha: 0)]),
          ),
        ),
      );
}

/// Une icône dans une pastille arrondie teintée.
class IconePastille extends StatelessWidget {
  const IconePastille(this.icone, {super.key, this.couleur, this.taille = 42, this.fond});

  final IconData icone;
  final Color? couleur;
  final Color? fond;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = couleur ?? p.accentTexte;
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        color: fond ?? c.withValues(alpha: p.sombre ? 0.18 : 0.11),
        borderRadius: BorderRadius.circular(taille * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(icone, size: taille * 0.5, color: c),
    );
  }
}

/// Le titre d'une section, avec son action éventuelle à droite.
class TitreSection extends StatelessWidget {
  const TitreSection(this.titre, {super.key, this.sousTitre, this.action, this.onAction});

  final String titre;
  final String? sousTitre;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Texte(titre, style: t.textTheme.titleLarge?.copyWith(fontSize: 20)),
              if (sousTitre != null) ...[
                const SizedBox(height: 2),
                Texte(sousTitre!, style: t.textTheme.bodySmall?.copyWith(color: p.attenue)),
              ],
            ],
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 36)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Texte(action!),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

/// Une petite étiquette en capitales espacées, en or : le surtitre d'un bloc.
class Surtitre extends StatelessWidget {
  const Surtitre(this.texte, {super.key, this.couleur});
  final String texte;
  final Color? couleur;

  @override
  Widget build(BuildContext context) => Texte(
        texte.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: couleur ?? context.palette.accentTexte,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
      );
}

/// Une pastille : un libellé court sur un voile de couleur.
class Pastille extends StatelessWidget {
  const Pastille(this.texte, {super.key, this.icone, this.couleur});
  final String texte;
  final IconData? icone;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = couleur ?? p.accentTexte;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.sombre ? 0.18 : 0.11),
        borderRadius: Rayons.pilule,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[Icon(icone, size: 13, color: c), const SizedBox(width: 5)],
          Texte(texte, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Une jauge arrondie.
class Jauge extends StatelessWidget {
  const Jauge({super.key, required this.valeur, this.hauteur = 8, this.couleur, this.piste});
  final double valeur;
  final double hauteur;
  final Color? couleur;
  final Color? piste;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: Rayons.pilule,
      child: SizedBox(
        height: hauteur,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: piste ?? p.surfaceCreuse)),
            FractionallySizedBox(
              widthFactor: valeur.clamp(0, 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: Rayons.pilule,
                  gradient: LinearGradient(colors: [couleur ?? p.accent, (couleur ?? p.accentSurHeros)]),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un message d'erreur de formulaire, sur un voile de la couleur d'alerte.
class AlerteFormulaire extends StatelessWidget {
  const AlerteFormulaire(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.alerte.withValues(alpha: p.sombre ? 0.16 : 0.09),
        borderRadius: Rayons.moyen,
        border: Border.all(color: p.alerte.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 19, color: p.alerte),
          const SizedBox(width: 10),
          Expanded(
            child: Texte(
              message,
              style: t.textTheme.bodySmall?.copyWith(color: p.alerte, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// La saisie d'un message : une pilule flottante et son bouton d'envoi rond.
/// Sert à l'agent comme aux conversations du cercle.
class ZoneMessage extends StatelessWidget {
  const ZoneMessage({
    super.key,
    required this.controleur,
    required this.onEnvoyer,
    this.attente = false,
    this.indication = 'Votre message',
    this.lignesMax = 4,
    this.longueurMax,
    this.envoiAuClavier = false,
  });

  final TextEditingController controleur;
  final VoidCallback onEnvoyer;

  /// Un envoi est en cours : le bouton s'éteint.
  final bool attente;
  final String indication;
  final int lignesMax;
  final int? longueurMax;

  /// La touche Entrée du clavier envoie (une question courte) au lieu d'aller
  /// à la ligne (un message).
  final bool envoiAuClavier;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 5, 5, 5),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: const BorderRadius.all(Radius.circular(28)),
        border: Border.all(color: p.trait),
        boxShadow: p.ombreCarte,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controleur,
              minLines: 1,
              maxLines: lignesMax,
              maxLength: longueurMax,
              textInputAction: envoiAuClavier ? TextInputAction.send : null,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: envoiAuClavier ? (_) => onEnvoyer() : null,
              style: t.textTheme.bodyMedium?.copyWith(color: p.encre),
              decoration: InputDecoration(
                hintText: indication,
                hintStyle: t.textTheme.bodyMedium?.copyWith(color: p.attenue),
                counterText: '',
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 4),
          BoutonEnvoi(actif: !attente, onTap: onEnvoyer),
        ],
      ),
    );
  }
}

/// Le bouton rond d'envoi, en or ; éteint pendant un envoi.
class BoutonEnvoi extends StatelessWidget {
  const BoutonEnvoi({super.key, required this.actif, required this.onTap});

  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: 'Envoyer',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: actif ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: p.accent.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Material(
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [p.accentSurHeros, p.accent],
                ),
              ),
              child: InkWell(
                onTap: actif ? onTap : null,
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(Icons.arrow_upward_rounded, color: p.surAccent),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
