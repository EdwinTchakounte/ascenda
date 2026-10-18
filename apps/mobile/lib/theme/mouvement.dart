import 'package:flutter/material.dart';

abstract final class Duree {
  static const bref = Duration(milliseconds: 180);
  static const moyen = Duration(milliseconds: 300);
  static const ample = Duration(milliseconds: 420);
  static const decalage = Duration(milliseconds: 55);
}

const courbeDouce = Curves.easeOutCubic;

bool _reduites(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

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
  final double depuis;
  final bool echelle;

  @override
  State<Apparition> createState() => _ApparitionState();
}

class _ApparitionState extends State<Apparition> with SingleTickerProviderStateMixin {
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

String millier(num n) {
  final chiffres = n.round().abs().toString();
  final tampon = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < chiffres.length; i++) {
    if (i > 0 && (chiffres.length - i) % 3 == 0) tampon.write('\u00A0');
    tampon.write(chiffres[i]);
  }
  return tampon.toString();
}

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
    String texte(double v) => (decimales == 0
            ? millier(v)
            : v.toStringAsFixed(decimales).replaceAll('.', ',')) +
        suffixe;
    if (_reduites(context)) return Text(texte(valeur.toDouble()), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: valeur.toDouble()),
      duration: duree,
      curve: courbeDouce,
      builder: (_, v, _) => Text(texte(v), style: style),
    );
  }
}

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
