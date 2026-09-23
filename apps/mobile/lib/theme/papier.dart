import 'dart:math';

import 'package:flutter/material.dart';

import 'palette.dart';
import 'texte.dart';

/// La matière de l'application : du papier, de l'encre, des filets.
///
/// Un aplat de couleur derrière des cartes blanches, c'est le décor de
/// n'importe quelle application. Ici le fond porte un grain de papier, les
/// séparations sont des filets d'imprimeur, et les titres se posent comme sur
/// une page de livre. Tout est dessiné, rien n'est une image : le grain suit le
/// thème, il ne jure jamais avec lui, et l'application ne grossit pas.

/// Le grain du papier, posé une fois pour toute la page.
///
/// Semé par une graine fixe : le grain ne bouge pas d'une image à l'autre, donc
/// il ne scintille pas au défilement.
class FondPapier extends StatelessWidget {
  const FondPapier({super.key, required this.child, this.grain = 1});

  final Widget child;

  /// 0 supprime le grain, 1 est la valeur de lecture, 2 le double.
  final double grain;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(color: p.fond),
      child: CustomPaint(
        painter: _Grain(p, grain),
        isComplex: true,
        willChange: false,
        child: child,
      ),
    );
  }
}

class _Grain extends CustomPainter {
  _Grain(this.p, this.force);
  final Palette p;
  final double force;

  @override
  void paint(Canvas canvas, Size taille) {
    final hasard = Random(20260923);
    // Des fibres courtes, très peu contrastées : on ne les voit pas, on les
    // sent. Sur un fond sombre elles éclairent, sur un fond clair elles
    // assombrissent.
    final encre = p.sombre ? Colors.white : p.encre;
    final n = (taille.width * taille.height / 900).round();
    for (var i = 0; i < n; i++) {
      final x = hasard.nextDouble() * taille.width;
      final y = hasard.nextDouble() * taille.height;
      final longueur = 1 + hasard.nextDouble() * 2.6;
      final angle = hasard.nextDouble() * pi;
      final alpha = (p.sombre ? 0.030 : 0.042) * force * (0.35 + hasard.nextDouble() * 0.65);
      canvas.drawLine(
        Offset(x, y),
        Offset(x + cos(angle) * longueur, y + sin(angle) * longueur),
        Paint()
          ..color = encre.withValues(alpha: alpha)
          ..strokeWidth = 0.9
          ..strokeCap = StrokeCap.round,
      );
    }
    // Une ombre de reliure au bord gauche et un voile en bas : la page a une
    // épaisseur.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 26, taille.height),
      Paint()
        ..shader = LinearGradient(
          colors: [encre.withValues(alpha: p.sombre ? 0.10 : 0.045), encre.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, 26, taille.height)),
    );
  }

  @override
  bool shouldRepaint(covariant _Grain autre) => autre.p.id != p.id || autre.force != force;
}

/// Un filet d'imprimeur : trait fin, parfois doublé d'un trait plus fin encore.
class Filet extends StatelessWidget {
  const Filet({super.key, this.redouble = false, this.couleur, this.largeur, this.marge = 0});

  /// Deux traits, le second plus pâle : la marque d'un filet d'imprimeur.
  final bool redouble;
  final Color? couleur;
  final double? largeur;
  final double marge;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = couleur ?? p.encre.withValues(alpha: p.sombre ? 0.22 : 0.16);
    final trait = Container(height: 1, width: largeur, color: c, margin: EdgeInsets.symmetric(vertical: marge));
    if (!redouble) return trait;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        trait,
        const SizedBox(height: 3),
        Container(height: 1, width: largeur, color: c.withValues(alpha: 0.45)),
      ],
    );
  }
}

/// Une étiquette entre crochets, en petites capitales : la marque d'un cahier
/// d'atelier. « ⟦ SÉANCE DU JOUR ⟧ ».
class EtiquetteCrochet extends StatelessWidget {
  const EtiquetteCrochet(this.texte, {super.key, this.couleur, this.capitales = true});
  final String texte;
  final Color? couleur;

  /// Les petites capitales sont la règle. On les retire quand le libellé doit
  /// rester lisible tel quel, par exemple une phrase entière.
  final bool capitales;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = couleur ?? p.accentTexte;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: c,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
          height: 1.1,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Crochet(couleur: c, ouvrant: true),
        const SizedBox(width: 8),
        Flexible(
          child: Texte(capitales ? texte.toUpperCase() : texte,
              style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 8),
        _Crochet(couleur: c, ouvrant: false),
      ],
    );
  }
}

class _Crochet extends StatelessWidget {
  const _Crochet({required this.couleur, required this.ouvrant});
  final Color couleur;
  final bool ouvrant;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 7,
        height: 16,
        child: CustomPaint(painter: _CrochetPeint(couleur, ouvrant)),
      );
}

class _CrochetPeint extends CustomPainter {
  _CrochetPeint(this.couleur, this.ouvrant);
  final Color couleur;
  final bool ouvrant;

  @override
  void paint(Canvas canvas, Size t) {
    final pinceau = Paint()
      ..color = couleur
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final x = ouvrant ? t.width : 0.0;
    final dos = ouvrant ? 1.0 : t.width - 1;
    canvas.drawPath(
      Path()
        ..moveTo(x, 0)
        ..lineTo(dos, 0)
        ..lineTo(dos, t.height)
        ..lineTo(x, t.height),
      pinceau,
    );
  }

  @override
  bool shouldRepaint(covariant _CrochetPeint a) => a.couleur != couleur || a.ouvrant != ouvrant;
}

/// La lettrine d'un chapitre : la première lettre en grand, dans un cadre à
/// l'encre, comme en tête d'un livre imprimé.
class Lettrine extends StatelessWidget {
  const Lettrine(this.lettre, {super.key, this.taille = 62, this.couleur});
  final String lettre;
  final double taille;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = couleur ?? p.accentTexte;
    return Container(
      width: taille,
      height: taille,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: c.withValues(alpha: 0.45), width: 1.4),
        color: c.withValues(alpha: p.sombre ? 0.14 : 0.07),
      ),
      child: Texte(
        lettre.toUpperCase(),
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontSize: taille * 0.58,
              height: 1,
              color: c,
            ),
      ),
    );
  }
}

/// Le titre courant d'une page de livre : petites capitales, filet dessous.
class TitreCourant extends StatelessWidget {
  const TitreCourant(this.texte, {super.key, this.folio});
  final String texte;
  final String? folio;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Texte(
                texte.toUpperCase(),
                style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 1.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (folio != null)
              Texte(folio!, style: t.textTheme.labelSmall?.copyWith(color: p.attenue, letterSpacing: 1)),
          ],
        ),
        const SizedBox(height: 6),
        const Filet(),
      ],
    );
  }
}

/// Un fleuron : le petit ornement qui clôt un chapitre dans un livre.
class Fleuron extends StatelessWidget {
  const Fleuron({super.key, this.taille = 26});
  final double taille;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: taille,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 60, child: Filet(couleur: p.accentTexte.withValues(alpha: 0.35))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Transform.rotate(
              angle: pi / 4,
              child: Container(
                width: taille * 0.3,
                height: taille * 0.3,
                decoration: BoxDecoration(
                  border: Border.all(color: p.accentTexte.withValues(alpha: 0.7), width: 1.4),
                ),
              ),
            ),
          ),
          SizedBox(width: 60, child: Filet(couleur: p.accentTexte.withValues(alpha: 0.35))),
        ],
      ),
    );
  }
}


/// Une coche tracée à la plume, en deux temps. Elle remplace la coche de
/// Material partout où l'on marque quelque chose comme fait : c'est le geste
/// d'un lecteur qui coche son cahier.
class Coche extends StatelessWidget {
  const Coche({super.key, this.taille = 20, this.couleur, this.epaisseur = 2.2});
  final double taille;
  final Color? couleur;
  final double epaisseur;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: taille,
        height: taille,
        child: CustomPaint(
          painter: _Trace(couleur ?? context.palette.succes, epaisseur, croix: false),
        ),
      );
}

/// La croix qui répond à la coche : ce qui manque, ce qui est faux.
class Croix extends StatelessWidget {
  const Croix({super.key, this.taille = 20, this.couleur, this.epaisseur = 2.2});
  final double taille;
  final Color? couleur;
  final double epaisseur;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: taille,
        height: taille,
        child: CustomPaint(
          painter: _Trace(couleur ?? context.palette.alerte, epaisseur, croix: true),
        ),
      );
}

class _Trace extends CustomPainter {
  _Trace(this.couleur, this.epaisseur, {required this.croix});
  final Color couleur;
  final double epaisseur;
  final bool croix;

  @override
  void paint(Canvas canvas, Size t) {
    final p = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = epaisseur
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.scale(t.width / 24, t.height / 24);
    if (croix) {
      canvas.drawPath(
        Path()
          ..moveTo(6, 6)
          ..lineTo(18, 18)
          ..moveTo(18, 6)
          ..lineTo(6, 18),
        p,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(4.5, 12.5)
          ..lineTo(10, 18)
          ..lineTo(19.5, 6),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Trace a) => a.couleur != couleur || a.croix != croix || a.epaisseur != epaisseur;
}
