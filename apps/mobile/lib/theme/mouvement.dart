import 'package:flutter/material.dart';

/// Le mouvement d'ASCENDA : ce qui rend l'application vivante sans la rendre
/// bavarde.
///
/// Trois règles, tenues partout :
///
/// 1. **Une entrée se voit une fois.** Une liste qui arrive se pose ligne après
///    ligne, avec un décalage de quelques dizaines de millisecondes. Au
///    défilement, plus rien ne bouge : une animation qui se rejoue à chaque
///    passage fatigue.
/// 2. **Un chiffre qui change se compte.** Une jauge se remplit, un nombre
///    monte. C'est ce qui donne le sentiment d'avancer.
/// 3. **Rien ne dure plus de 420 ms**, et tout respecte le réglage
///    « animations réduites » du téléphone : sous ce réglage, l'écran s'affiche
///    d'un coup, sans que rien ne disparaisse.
abstract final class Duree {
  static const bref = Duration(milliseconds: 180);
  static const moyen = Duration(milliseconds: 300);
  static const ample = Duration(milliseconds: 420);
  static const decalage = Duration(milliseconds: 55);
}

const courbeDouce = Curves.easeOutCubic;

bool _reduites(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Une apparition : le contenu monte de quelques pixels en se révélant.
///
/// [rang] décale l'entrée pour qu'une liste se pose en cascade.
class Apparition extends StatefulWidget {
  const Apparition({
    super.key,
    required this.child,
    this.rang = 0,
    this.duree = Duree.ample,
    this.depuis = 16,
    this.echelle = false,
  });

  final Widget child;
  final int rang;
  final Duration duree;

  /// De combien de pixels le contenu monte en entrant.
  final double depuis;

  /// Ajoute un léger agrandissement : réservé aux éléments qu'on veut fêter
  /// (un résultat de quiz, une récompense).
  final bool echelle;

  @override
  State<Apparition> createState() => _ApparitionState();
}

class _ApparitionState extends State<Apparition> with SingleTickerProviderStateMixin {
  // Le décalage de la cascade est porté par la courbe, pas par un minuteur.
  // Un `Future.delayed` survivait à la disparition de l'écran : en test, Flutter
  // signalait « A Timer is still pending », et en vrai un écran quitté trop vite
  // laissait tourner une attente pour rien.
  late final Duration _attente = Duree.decalage * widget.rang;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duree + _attente)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduites(context)) return widget.child;
    final total = _c.duration!.inMilliseconds;
    final debut = total == 0 ? 0.0 : _attente.inMilliseconds / total;
    final t = CurvedAnimation(parent: _c, curve: Interval(debut, 1, curve: courbeDouce));
    return AnimatedBuilder(
      animation: t,
      child: widget.child,
      builder: (context, enfant) => Opacity(
        opacity: t.value,
        child: Transform.translate(
          offset: Offset(0, widget.depuis * (1 - t.value)),
          child: widget.echelle ? Transform.scale(scale: 0.94 + 0.06 * t.value, child: enfant) : enfant,
        ),
      ),
    );
  }
}

/// Un nombre qui monte jusqu'à sa valeur.
class CompteurAnime extends StatelessWidget {
  const CompteurAnime(
    this.valeur, {
    super.key,
    this.style,
    this.duree = Duree.ample,
    this.suffixe = '',
    this.decimales = 0,
  });

  final num valeur;
  final TextStyle? style;
  final Duration duree;
  final String suffixe;
  final int decimales;

  @override
  Widget build(BuildContext context) {
    String texte(double v) => v.toStringAsFixed(decimales).replaceAll('.', ',') + suffixe;
    if (_reduites(context)) return Text(texte(valeur.toDouble()), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valeur.toDouble()),
      duration: duree,
      curve: courbeDouce,
      builder: (_, v, _) => Text(texte(v), style: style),
    );
  }
}

/// Une pulsation lente, pour attirer l'oeil sans l'agiter : la séance du jour,
/// un bouton qui attend une réponse.
class Respire extends StatefulWidget {
  const Respire({super.key, required this.child, this.amplitude = 0.02});
  final Widget child;
  final double amplitude;

  @override
  State<Respire> createState() => _RespireState();
}

class _RespireState extends State<Respire> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduites(context)) return widget.child;
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1 + widget.amplitude)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}

/// La page qui se tourne : la transition des écrans de lecture.
///
/// Un glissement horizontal accompagné d'une ombre portée, comme une page qu'on
/// soulève. Material propose un fondu vertical, excellent mais anonyme.
class PageQuiTourne extends PageRouteBuilder {
  PageQuiTourne({required this.page, super.settings})
      : super(
          transitionDuration: Duree.ample,
          reverseTransitionDuration: Duree.moyen,
          pageBuilder: (_, _, _) => page,
          transitionsBuilder: (context, animation, secondaire, enfant) {
            final t = CurvedAnimation(parent: animation, curve: courbeDouce);
            return SlideTransition(
              position: Tween(begin: const Offset(0.18, 0), end: Offset.zero).animate(t),
              child: FadeTransition(opacity: t, child: enfant),
            );
          },
        );

  final Widget page;
}
