import 'dart:math';

import 'package:flutter/material.dart';

/// Les icônes d'ASCENDA, dessinées à la plume.
///
/// Les icônes de Material sont excellentes et se voient partout : elles font
/// ressembler l'application à toutes les autres. Celles-ci sont tracées à la
/// main dans une grille de 24, d'un seul trait d'épaisseur constante, avec le
/// vocabulaire du livre : la page, le dos, le signet, la plume, le fleuron.
///
/// Elles se dessinent, elles ne se chargent pas : la couleur suit le thème et
/// l'application ne porte aucune police d'icônes.
enum Icone {
  soleil,        // l'accueil : la séance du jour
  volumes,       // les livres
  plume,         // l'agent
  pousse,        // la progression
  cahier,        // le menu
  lecteur,       // un compte
  loupe,         // chercher
  signet,        // emporter, marquer
  page,          // un PDF, un document
  cercle,        // le cercle de lecture
  cartes,        // les révisions
  clef,          // les notions, le glossaire
  sceau,         // Ascension
  jeton,         // un code
  boussole,      // le diagnostic, le parcours
  question,      // un quiz
  encrier,       // une note
  fleche,        // aller plus loin
}

class IconeAscenda extends StatelessWidget {
  const IconeAscenda(this.icone, {super.key, this.taille = 24, this.couleur, this.epaisseur = 1.7, this.pleine = false});

  final Icone icone;
  final double taille;
  final Color? couleur;
  final double epaisseur;

  /// La variante « pleine » marque l'onglet actif : le même dessin, avec un
  /// aplat léger derrière le trait.
  final bool pleine;

  @override
  Widget build(BuildContext context) {
    final c = couleur ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: taille,
      height: taille,
      child: CustomPaint(painter: _Plume(icone, c, epaisseur, pleine)),
    );
  }
}

class _Plume extends CustomPainter {
  _Plume(this.icone, this.couleur, this.epaisseur, this.pleine);
  final Icone icone;
  final Color couleur;
  final double epaisseur;
  final bool pleine;

  @override
  void paint(Canvas canvas, Size t) {
    canvas.scale(t.width / 24, t.height / 24);
    final trait = Paint()
      ..color = couleur
      ..style = PaintingStyle.stroke
      ..strokeWidth = epaisseur
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final aplat = Paint()..color = couleur.withValues(alpha: 0.16);
    final chemins = _chemins(icone);
    if (pleine) {
      for (final c in chemins.pleins) {
        canvas.drawPath(c, aplat);
      }
    }
    for (final c in chemins.traits) {
      canvas.drawPath(c, trait);
    }
  }

  @override
  bool shouldRepaint(covariant _Plume a) =>
      a.icone != icone || a.couleur != couleur || a.epaisseur != epaisseur || a.pleine != pleine;
}

({List<Path> traits, List<Path> pleins}) _chemins(Icone i) {
  Path p() => Path();
  switch (i) {
    case Icone.soleil:
      // Un soleil qui se lève sur l'horizon : la séance du jour.
      final arc = p()
        ..addArc(Rect.fromCircle(center: const Offset(12, 15), radius: 5.5), pi, pi);
      final rayons = p();
      for (var k = 0; k < 5; k++) {
        final a = pi + pi * (k + 0.5) / 5;
        rayons
          ..moveTo(12 + cos(a) * 8, 15 + sin(a) * 8)
          ..lineTo(12 + cos(a) * 9.8, 15 + sin(a) * 9.8);
      }
      final sol = p()
        ..moveTo(3, 15)
        ..lineTo(21, 15);
      return (traits: [arc, rayons, sol], pleins: [arc..close()]);

    case Icone.volumes:
      // Trois volumes sur un rayon, dont un penché.
      final a = p()..addRect(const Rect.fromLTWH(4, 6, 4.4, 13));
      final b = p()..addRect(const Rect.fromLTWH(9.6, 6, 4.4, 13));
      final c = p()
        ..moveTo(16.2, 19)
        ..lineTo(19.2, 7.2)
        ..lineTo(21.6, 7.8)
        ..lineTo(18.7, 19.6)
        ..close();
      final tablette = p()
        ..moveTo(2.6, 20.4)
        ..lineTo(21.8, 20.4);
      final nerf = p()
        ..moveTo(4, 9.4)..lineTo(8.4, 9.4)
        ..moveTo(9.6, 9.4)..lineTo(14, 9.4);
      return (traits: [a, b, c, tablette, nerf], pleins: [a, b, c]);

    case Icone.plume:
      // Une plume et sa goutte d'encre : l'agent qui écrit en citant.
      final plume = p()
        ..moveTo(4.5, 19.5)
        ..cubicTo(9, 19, 17, 16, 19.5, 5)
        ..cubicTo(11, 6, 6, 11, 5.6, 17)
        ..close();
      final nervure = p()
        ..moveTo(6.6, 17.6)
        ..cubicTo(10, 13, 14, 9.6, 18.4, 6.4);
      final goutte = p()..addOval(Rect.fromCircle(center: const Offset(6.2, 5.6), radius: 1.5));
      return (traits: [plume, nervure, goutte], pleins: [plume]);

    case Icone.pousse:
      // Une pousse qui sort d'une ligne : ce qui grandit.
      final tige = p()
        ..moveTo(12, 21)
        ..cubicTo(12, 15, 12, 11, 12, 7);
      final feuilleD = p()
        ..moveTo(12, 12)
        ..cubicTo(15, 12, 18, 10, 18.6, 6.6)
        ..cubicTo(15, 7, 12.6, 9, 12, 12)
        ..close();
      final feuilleG = p()
        ..moveTo(12, 16)
        ..cubicTo(9.4, 16, 7, 14.4, 6.2, 11.6)
        ..cubicTo(9.2, 11.8, 11.4, 13.4, 12, 16)
        ..close();
      final sol = p()
        ..moveTo(6, 21)
        ..lineTo(18, 21);
      return (traits: [tige, feuilleD, feuilleG, sol], pleins: [feuilleD, feuilleG]);

    case Icone.cahier:
      // Un cahier fermé, trois signets : le menu.
      final couv = p()..addRect(const Rect.fromLTWH(4, 3.5, 16, 17));
      final dos = p()
        ..moveTo(7.4, 3.5)
        ..lineTo(7.4, 20.5);
      final signets = p()
        ..moveTo(11, 3.5)..lineTo(11, 9)..lineTo(12.6, 7.4)..lineTo(14.2, 9)..lineTo(14.2, 3.5);
      return (traits: [couv, dos, signets], pleins: [couv]);

    case Icone.lecteur:
      final tete = p()..addOval(Rect.fromCircle(center: const Offset(12, 8.6), radius: 3.8));
      final epaules = p()
        ..moveTo(4.6, 20)
        ..cubicTo(5.4, 15.4, 8.4, 13.4, 12, 13.4)
        ..cubicTo(15.6, 13.4, 18.6, 15.4, 19.4, 20);
      return (traits: [tete, epaules], pleins: [tete]);

    case Icone.loupe:
      final verre = p()..addOval(Rect.fromCircle(center: const Offset(10.6, 10.6), radius: 6.2));
      final manche = p()
        ..moveTo(15.2, 15.2)
        ..lineTo(20.4, 20.4);
      final ligne = p()
        ..moveTo(7.6, 9.6)..lineTo(13.4, 9.6)
        ..moveTo(7.6, 12.4)..lineTo(11.6, 12.4);
      return (traits: [verre, manche, ligne], pleins: [verre]);

    case Icone.signet:
      final ruban = p()
        ..moveTo(6.5, 3.6)
        ..lineTo(17.5, 3.6)
        ..lineTo(17.5, 20.6)
        ..lineTo(12, 16.2)
        ..lineTo(6.5, 20.6)
        ..close();
      return (traits: [ruban], pleins: [ruban]);

    case Icone.page:
      final feuille = p()
        ..moveTo(6, 3)
        ..lineTo(14.4, 3)
        ..lineTo(18.6, 7.2)
        ..lineTo(18.6, 21)
        ..lineTo(6, 21)
        ..close();
      final pli = p()
        ..moveTo(14.4, 3)
        ..lineTo(14.4, 7.2)
        ..lineTo(18.6, 7.2);
      final lignes = p()
        ..moveTo(8.8, 12)..lineTo(15.8, 12)
        ..moveTo(8.8, 15)..lineTo(15.8, 15)
        ..moveTo(8.8, 18)..lineTo(13, 18);
      return (traits: [feuille, pli, lignes], pleins: [feuille]);

    case Icone.cercle:
      final a = p()..addOval(Rect.fromCircle(center: const Offset(8, 9.6), radius: 3.2));
      final b = p()..addOval(Rect.fromCircle(center: const Offset(16, 9.6), radius: 3.2));
      final liens = p()
        ..moveTo(3.4, 20)
        ..cubicTo(4, 16.4, 5.8, 15, 8, 15)
        ..cubicTo(10.2, 15, 12, 16.4, 12.6, 20)
        ..moveTo(11.4, 20)
        ..cubicTo(12, 16.4, 13.8, 15, 16, 15)
        ..cubicTo(18.2, 15, 20, 16.4, 20.6, 20);
      return (traits: [a, b, liens], pleins: [a, b]);

    case Icone.cartes:
      final derriere = p()..addRect(const Rect.fromLTWH(7.4, 3.4, 12, 14.4));
      final devant = p()..addRect(const Rect.fromLTWH(4.6, 6.4, 12, 14.4));
      final ligne = p()
        ..moveTo(7.4, 11.6)..lineTo(13.6, 11.6)
        ..moveTo(7.4, 15)..lineTo(11.4, 15);
      return (traits: [derriere, devant, ligne], pleins: [devant]);

    case Icone.clef:
      final anneau = p()..addOval(Rect.fromCircle(center: const Offset(8.4, 15.6), radius: 4.4));
      final tige = p()
        ..moveTo(11.6, 12.4)
        ..lineTo(20, 4)
        ..moveTo(16.4, 7.6)..lineTo(19, 10.2)
        ..moveTo(18.2, 5.8)..lineTo(20.6, 8.2);
      return (traits: [anneau, tige], pleins: [anneau]);

    case Icone.sceau:
      final rond = p()..addOval(Rect.fromCircle(center: const Offset(12, 9.6), radius: 6));
      final etoile = p();
      for (var k = 0; k < 5; k++) {
        final a = -pi / 2 + k * 2 * pi / 5;
        final b = -pi / 2 + (k + 0.5) * 2 * pi / 5;
        if (k == 0) etoile.moveTo(12 + cos(a) * 3.2, 9.6 + sin(a) * 3.2);
        etoile
          ..lineTo(12 + cos(a) * 3.2, 9.6 + sin(a) * 3.2)
          ..lineTo(12 + cos(b) * 1.5, 9.6 + sin(b) * 1.5);
      }
      etoile.close();
      final rubans = p()
        ..moveTo(9, 15)..lineTo(8, 21.4)..lineTo(12, 19.4)..lineTo(16, 21.4)..lineTo(15, 15);
      return (traits: [rond, etoile, rubans], pleins: [rond]);

    case Icone.jeton:
      final billet = p()
        ..moveTo(3.4, 8)
        ..lineTo(20.6, 8)
        ..lineTo(20.6, 11)
        ..cubicTo(19, 11.4, 19, 12.6, 20.6, 13)
        ..lineTo(20.6, 16)
        ..lineTo(3.4, 16)
        ..lineTo(3.4, 13)
        ..cubicTo(5, 12.6, 5, 11.4, 3.4, 11)
        ..close();
      final pointille = p()
        ..moveTo(12, 9.4)..lineTo(12, 10.8)
        ..moveTo(12, 12.2)..lineTo(12, 13.6)
        ..moveTo(12, 15)..lineTo(12, 15.6);
      return (traits: [billet, pointille], pleins: [billet]);

    case Icone.boussole:
      final rond = p()..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 8.4));
      final aiguille = p()
        ..moveTo(15.4, 8.6)
        ..lineTo(10.6, 10.6)
        ..lineTo(8.6, 15.4)
        ..lineTo(13.4, 13.4)
        ..close();
      return (traits: [rond, aiguille], pleins: [aiguille]);

    case Icone.question:
      final cadre = p()..addRect(const Rect.fromLTWH(4, 4, 16, 16));
      final signe = p()
        ..moveTo(9.6, 9.6)
        ..cubicTo(9.6, 7.2, 14.4, 7.2, 14.4, 10)
        ..cubicTo(14.4, 12.2, 12, 12.4, 12, 14.6);
      final point = p()..addOval(Rect.fromCircle(center: const Offset(12, 17.2), radius: 0.9));
      return (traits: [cadre, signe, point], pleins: [cadre, point]);

    case Icone.encrier:
      final pot = p()
        ..moveTo(6, 12)
        ..lineTo(18, 12)
        ..lineTo(16.6, 20.6)
        ..lineTo(7.4, 20.6)
        ..close();
      final col = p()..addRect(const Rect.fromLTWH(9.6, 9.2, 4.8, 2.8));
      final plume = p()
        ..moveTo(12, 9.2)
        ..cubicTo(13.6, 6.6, 16.4, 4.6, 19.4, 3.4)
        ..cubicTo(18.6, 6.8, 16.4, 8.6, 14.2, 9.6);
      return (traits: [pot, col, plume], pleins: [pot]);

    case Icone.fleche:
      final ligne = p()
        ..moveTo(4, 12)
        ..lineTo(19, 12);
      final pointe = p()
        ..moveTo(13.6, 6.6)
        ..lineTo(19.6, 12)
        ..lineTo(13.6, 17.4);
      return (traits: [ligne, pointe], pleins: []);
  }
}
