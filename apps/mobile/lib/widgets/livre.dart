import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/couleurs.dart';
import '../theme/texte.dart';

/// Les ouvrages, dessinés comme des livres.

/// Ce qu'on peut écrire sur un dos de cette hauteur.
String titreSurDos(String titre, double hauteur) {
  final maximum = (hauteur / 4.6).round();
  if (titre.length <= maximum) return titre;
  final mots = titre.split(' ');
  final garde = <String>[];
  var n = 0;
  for (final mot in mots) {
    if (garde.isNotEmpty && n + 1 + mot.length > maximum) break;
    garde.add(mot);
    n += (garde.length > 1 ? 1 : 0) + mot.length;
  }
  return '${garde.join(' ')}…';
}

/// Le corps du titre sur un dos, en pixels.
double corpsSurDos(String titre, {required double hauteur, required double largeur}) {
  const large = 0.62;   // largeur moyenne d'un signe en Fraunces, en parts du corps
  const interligne = 1.22;
  // Le texte reste à l'intérieur du filet doré, qui court de 0,175 à 0,825 de
  // la hauteur du dos : sinon la dernière lettre chevauche le cadre.
  final dispoLigne = hauteur * 0.60;
  final dispoLignes = largeur * 0.68;
  final motLong = titre.split(RegExp(r"[ \u2019'\-]")).fold<int>(3, (m, x) => x.length > m ? x.length : m);
  for (var corps = largeur * 0.26; corps > 6; corps -= 0.5) {
    final signesParLigne = dispoLigne / (corps * large);
    if (motLong > signesParLigne) continue;
    final lignes = (titre.length / signesParLigne).ceil();
    if (lignes * corps * interligne <= dispoLignes) return corps;
  }
  return 6;
}

/// Une graine stable tirée du titre : deux lancements donnent le même volume.
int _graine(String titre) => titre.codeUnits.fold(7, (a, c) => (a * 31 + c) & 0x7fffffff);

Color teinteOuvrage(String titre, String? axeSlug) =>
    Couleurs.pole(axeSlug) ?? Couleurs.poles.values.elementAt(_graine(titre) % Couleurs.poles.length);

/// Le dos d'un volume, tel qu'il se voit sur un rayon.
class DosLivre extends StatelessWidget {
  const DosLivre({
    super.key,
    required this.titre,
    this.axeSlug,
    this.hauteur = 176,
    this.largeur,
    this.onTap,
    this.marque = false,
  });

  final String titre;
  final String? axeSlug;
  final double hauteur;

  /// Par défaut, une épaisseur tirée du titre : un rayon régulier fait faux.
  final double? largeur;
  final VoidCallback? onTap;

  /// Un signet dépasse du volume : l'ouvrage est commencé ou emporté.
  final bool marque;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final teinte = teinteOuvrage(titre, axeSlug);
    final h = _graine(titre);
    final l = largeur ?? 46 + (h % 5) * 6.0;
    final sombre = Color.lerp(teinte, Colors.black, 0.42)!;
    final clair = Color.lerp(teinte, Colors.white, 0.10)!;
    final court = titreSurDos(titre, hauteur);
    final corps = corpsSurDos(court, hauteur: hauteur, largeur: l);

    return Semantics(
      label: titre,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: l,
          height: hauteur,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(3), topRight: Radius.circular(3),
                    bottomLeft: Radius.circular(3), bottomRight: Radius.circular(3),
                  ),
                  gradient: LinearGradient(
                    colors: [sombre, clair, teinte, sombre],
                    stops: const [0, 0.14, 0.72, 1],
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.26), blurRadius: 10, offset: const Offset(3, 6)),
                  ],
                ),
                child: CustomPaint(
                  painter: _Dos(teinte: teinte, graine: h),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: l * 0.16, vertical: hauteur * 0.16),
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Center(
                          // Le corps suit la longueur du titre
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: hauteur * 0.60,
                              child: Text(
                                court,
                                maxLines: 3,
                                textAlign: TextAlign.center,
                                style: t.textTheme.titleMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  fontSize: corps,
                                  height: 1.18,
                                  letterSpacing: 0,
                                  shadows: [Shadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 2)],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ),
                ),
              ),
              if (marque)
                Positioned(
                  top: -6,
                  right: l * 0.22,
                  child: Container(
                    width: 8,
                    height: hauteur * 0.34,
                    decoration: BoxDecoration(
                      color: Couleurs.or,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Les nerfs du dos, la pièce de titre et le filet doré.
class _Dos extends CustomPainter {
  _Dos({required this.teinte, required this.graine});
  final Color teinte;
  final int graine;

  @override
  void paint(Canvas canvas, Size t) {
    final or = const Color(0xFFE8C070).withValues(alpha: 0.75);
    final nerf = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..strokeWidth = max(1.2, t.width * 0.035);
    final filet = Paint()
      ..color = or
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    // Deux nerfs en tête, deux en pied : la reliure d'un volume relié.
    for (final y in [t.height * 0.10, t.height * 0.135, t.height * 0.865, t.height * 0.90]) {
      canvas.drawLine(Offset(0, y), Offset(t.width, y), nerf);
    }
    // Le filet d'or qui borde le dos.
    canvas.drawRect(
      Rect.fromLTWH(t.width * 0.12, t.height * 0.175, t.width * 0.76, t.height * 0.65),
      filet,
    );
    // Un fleuron discret en pied, différent d'un volume à l'autre.
    final y = t.height * 0.935;
    final motif = graine % 3;
    final p = Paint()
      ..color = or
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    if (motif == 0) {
      canvas.drawCircle(Offset(t.width / 2, y), t.width * 0.10, p);
    } else if (motif == 1) {
      canvas.drawRect(Rect.fromCenter(center: Offset(t.width / 2, y), width: t.width * 0.2, height: t.width * 0.2), p);
    } else {
      canvas.drawLine(Offset(t.width * 0.3, y), Offset(t.width * 0.7, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _Dos a) => a.teinte != teinte || a.graine != graine;
}

/// Le plat d'un volume, pour la fiche d'un ouvrage : toile teintée, titre
/// frappé à l'or, filet d'encadrement.
class CouvertureLivre extends StatelessWidget {
  const CouvertureLivre({
    super.key,
    required this.titre,
    this.auteurs,
    this.axeSlug,
    this.hauteur = 260,
  });

  final String titre;
  final String? auteurs;
  final String? axeSlug;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final teinte = teinteOuvrage(titre, axeSlug);
    final largeur = hauteur * 0.68;
    final or = const Color(0xFFE8C070);

    return SizedBox(
      width: largeur,
      height: hauteur,
      child: Stack(
        children: [
          // La tranche, à gauche : le volume a une épaisseur.
          Positioned(
            left: 0, top: 4, bottom: 4, width: 14,
            child: Container(
              decoration: BoxDecoration(
                color: Color.lerp(teinte, Colors.black, 0.45),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
              ),
            ),
          ),
          Positioned(
            left: 12, right: 0, top: 0, bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(teinte, Colors.white, 0.12)!, teinte, Color.lerp(teinte, Colors.black, 0.3)!],
                ),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 18, offset: const Offset(6, 10)),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.all(hauteur * 0.07),
                child: Container(
                  decoration: BoxDecoration(border: Border.all(color: or.withValues(alpha: 0.6), width: 1.2)),
                  padding: EdgeInsets.all(hauteur * 0.05),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Le titre s'ajuste au cadre : sur une couverture, un mot
                      // coupé en deux se voit comme une faute d'impression.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: largeur - hauteur * 0.24),
                            child: Texte(
                              titre,
                              textAlign: TextAlign.center,
                              maxLines: 5,
                              style: t.textTheme.titleLarge?.copyWith(
                                color: or,
                                fontSize: hauteur * 0.075,
                                height: 1.18,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (auteurs != null && auteurs!.isNotEmpty) ...[
                        SizedBox(height: hauteur * 0.05),
                        SizedBox(
                          width: hauteur * 0.2,
                          child: Container(height: 1, color: or.withValues(alpha: 0.6)),
                        ),
                        SizedBox(height: hauteur * 0.05),
                        Texte(
                          auteurs!,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.textTheme.labelSmall?.copyWith(
                            color: or.withValues(alpha: 0.85),
                            fontSize: hauteur * 0.042,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un rayon : des volumes posés sur une tablette, qui défilent.
class Rayon extends StatelessWidget {
  const Rayon({
    super.key,
    required this.volumes,
    this.hauteur = 176,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  /// (titre, raccourci d'axe, ouvrage emporté ou commencé, action)
  final List<({String titre, String? axeSlug, bool marque, VoidCallback? onTap})> volumes;
  final double hauteur;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: hauteur + 26,
      child: Stack(
        children: [
          // La tablette : un trait épais et son ombre portée.
          Positioned(
            left: padding.left * 0.4, right: padding.right * 0.4, bottom: 12,
            child: Column(
              children: [
                Container(height: 3, color: p.encre.withValues(alpha: p.sombre ? 0.4 : 0.28)),
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [p.encre.withValues(alpha: 0.16), p.encre.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0, right: 0, bottom: 15,
            child: SizedBox(
              height: hauteur,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: padding,
                clipBehavior: Clip.none,
                itemCount: volumes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 5),
                itemBuilder: (_, i) {
                  final v = volumes[i];
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: DosLivre(
                      titre: v.titre,
                      axeSlug: v.axeSlug,
                      hauteur: hauteur - (i % 3) * 8,
                      marque: v.marque,
                      onTap: v.onTap,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
