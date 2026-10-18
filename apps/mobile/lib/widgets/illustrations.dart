import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/palette.dart';

enum Scene {
  rayonVide,
  lampe,
  graine,
  cercleVide,
  sansReseau,
  laurier,
  pageBlanche,
  loupeVide,
}

class Illustration extends StatelessWidget {
  const Illustration(this.scene, {super.key, this.taille = 148, this.couleur, this.accent});

  final Scene scene;
  final double taille;
  final Color? couleur;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: taille,
      height: taille * 0.78,
      child: CustomPaint(
        painter: _Scene(scene, couleur ?? p.encre.withValues(alpha: p.sombre ? 0.85 : 0.72), accent ?? p.accentTexte),
      ),
    );
  }
}

class _Scene extends CustomPainter {
  _Scene(this.scene, this.encre, this.or);

  final Scene scene;
  final Color encre;
  final Color or;

  @override
  void paint(Canvas canvas, Size t) {
    canvas.scale(t.width / 120, t.height / 94);
    final trait = Paint()
      ..color = encre
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rehaut = Paint()
      ..color = or
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final voile = Paint()..color = or.withValues(alpha: 0.16);

    switch (scene) {
      case Scene.rayonVide:
        canvas.drawLine(const Offset(10, 70), const Offset(110, 70), trait);
        canvas.drawLine(const Offset(16, 70), const Offset(16, 78), trait);
        canvas.drawLine(const Offset(104, 70), const Offset(104, 78), trait);
        for (var i = 0; i < 2; i++) {
          final y = 70.0 - 9 * (i + 1);
          canvas.drawRect(Rect.fromLTWH(20 + i * 3, y, 34 - i * 4, 8), trait);
        }
        canvas.drawRect(const Rect.fromLTWH(20, 52, 30, 8), voile);
        for (var x = 64.0; x < 100; x += 8) {
          canvas.drawLine(Offset(x, 70), Offset(x + 4, 70), rehaut);
        }
        canvas.drawRect(const Rect.fromLTWH(64, 34, 36, 36), Paint()
          ..color = encre.withValues(alpha: 0.10)
          ..style = PaintingStyle.fill);

      case Scene.lampe:
        final abatjour = Path()
          ..moveTo(44, 34)
          ..lineTo(76, 34)
          ..lineTo(86, 52)
          ..lineTo(34, 52)
          ..close();
        canvas.drawPath(abatjour, trait);
        canvas.drawPath(abatjour, voile);
        canvas.drawLine(const Offset(60, 34), const Offset(60, 20), trait);
        canvas.drawLine(const Offset(60, 52), const Offset(60, 62), rehaut);
        for (var k = -2; k <= 2; k++) {
          canvas.drawLine(Offset(60 + k * 9, 56), Offset(60 + k * 16.0, 70), rehaut..color = or.withValues(alpha: 0.5));
        }
        _livreOuvert(canvas, trait, const Offset(60, 78));

      case Scene.graine:
        canvas.drawLine(const Offset(16, 74), const Offset(104, 74), trait);
        canvas.drawLine(const Offset(60, 74), const Offset(60, 40), trait);
        final feuille = Path()
          ..moveTo(60, 50)
          ..cubicTo(76, 48, 86, 38, 88, 24)
          ..cubicTo(72, 26, 62, 36, 60, 50)
          ..close();
        canvas.drawPath(feuille, trait);
        canvas.drawPath(feuille, voile);
        final feuille2 = Path()
          ..moveTo(60, 62)
          ..cubicTo(46, 60, 38, 52, 36, 40)
          ..cubicTo(48, 42, 58, 50, 60, 62)
          ..close();
        canvas.drawPath(feuille2, trait);
        canvas.drawArc(const Rect.fromLTWH(48, 74, 24, 16), pi, pi, false, rehaut);

      case Scene.cercleVide:
        canvas.drawOval(const Rect.fromLTWH(26, 40, 68, 32), trait);
        canvas.drawCircle(const Offset(60, 26), 9, trait);
        canvas.drawCircle(const Offset(60, 26), 9, voile);
        for (final x in [24.0, 96.0]) {
          final tirets = Path();
          for (var a = 0.0; a < 2 * pi; a += pi / 6) {
            tirets
              ..moveTo(x + cos(a) * 9, 58 + sin(a) * 9)
              ..lineTo(x + cos(a + pi / 12) * 9, 58 + sin(a + pi / 12) * 9);
          }
          canvas.drawPath(tirets, rehaut);
        }

      case Scene.sansReseau:
        final nuage = Path()
          ..addArc(const Rect.fromLTWH(34, 22, 30, 30), pi, pi)
          ..addArc(const Rect.fromLTWH(56, 26, 26, 26), pi * 1.2, pi * 1.1)
          ..moveTo(34, 37)
          ..lineTo(82, 37);
        canvas.drawPath(nuage, trait);
        canvas.drawLine(const Offset(40, 18), const Offset(80, 48), rehaut);
        _livreOuvert(canvas, trait, const Offset(60, 74));

      case Scene.laurier:
        for (final sens in [-1.0, 1.0]) {
          final rameau = Path()..moveTo(60 + sens * 14, 74);
          for (var i = 0; i < 5; i++) {
            final y = 68.0 - i * 10;
            rameau
              ..moveTo(60 + sens * (14 + i * 1.5), y)
              ..cubicTo(60 + sens * 26, y - 4, 60 + sens * 30, y - 10, 60 + sens * 24, y - 14);
          }
          rameau
            ..moveTo(60 + sens * 14, 74)
            ..cubicTo(60 + sens * 20, 58, 60 + sens * 22, 40, 60 + sens * 16, 26);
          canvas.drawPath(rameau, trait);
        }
        final etoile = Path();
        for (var k = 0; k < 5; k++) {
          final a = -pi / 2 + k * 2 * pi / 5;
          final b = -pi / 2 + (k + 0.5) * 2 * pi / 5;
          if (k == 0) etoile.moveTo(60 + cos(a) * 14, 44 + sin(a) * 14);
          etoile
            ..lineTo(60 + cos(a) * 14, 44 + sin(a) * 14)
            ..lineTo(60 + cos(b) * 6, 44 + sin(b) * 6);
        }
        etoile.close();
        canvas.drawPath(etoile, rehaut);
        canvas.drawPath(etoile, voile);

      case Scene.pageBlanche:
        canvas.drawRect(const Rect.fromLTWH(34, 18, 52, 62), trait);
        for (var y = 34.0; y < 74; y += 10) {
          canvas.drawLine(Offset(42, y), Offset(78, y), Paint()
            ..color = encre.withValues(alpha: 0.28)
            ..strokeWidth = 1.4);
        }
        final plume = Path()
          ..moveTo(74, 72)
          ..cubicTo(86, 62, 94, 44, 96, 24)
          ..cubicTo(82, 32, 74, 50, 72, 68)
          ..close();
        canvas.drawPath(plume, trait);
        canvas.drawPath(plume, voile);

      case Scene.loupeVide:
        canvas.drawRect(const Rect.fromLTWH(26, 20, 50, 58), trait);
        canvas.drawCircle(const Offset(72, 52), 20, trait);
        canvas.drawCircle(const Offset(72, 52), 20, Paint()..color = or.withValues(alpha: 0.10));
        canvas.drawLine(const Offset(86, 66), const Offset(100, 80), rehaut);
        for (var y = 30.0; y < 70; y += 10) {
          canvas.drawLine(Offset(34, y), Offset(52, y), Paint()
            ..color = encre.withValues(alpha: 0.22)
            ..strokeWidth = 1.4);
        }
    }
  }

  void _livreOuvert(Canvas canvas, Paint trait, Offset centre) {
    final c = centre;
    final gauche = Path()
      ..moveTo(c.dx, c.dy)
      ..cubicTo(c.dx - 10, c.dy - 8, c.dx - 26, c.dy - 8, c.dx - 34, c.dy - 4)
      ..lineTo(c.dx - 34, c.dy + 8)
      ..cubicTo(c.dx - 26, c.dy + 4, c.dx - 10, c.dy + 4, c.dx, c.dy + 10)
      ..close();
    final droite = Path()
      ..moveTo(c.dx, c.dy)
      ..cubicTo(c.dx + 10, c.dy - 8, c.dx + 26, c.dy - 8, c.dx + 34, c.dy - 4)
      ..lineTo(c.dx + 34, c.dy + 8)
      ..cubicTo(c.dx + 26, c.dy + 4, c.dx + 10, c.dy + 4, c.dx, c.dy + 10)
      ..close();
    canvas.drawPath(gauche, trait);
    canvas.drawPath(droite, trait);
    canvas.drawLine(Offset(c.dx, c.dy), Offset(c.dx, c.dy + 10), trait);
  }

  @override
  bool shouldRepaint(covariant _Scene a) => a.scene != scene || a.encre != encre || a.or != or;
}
