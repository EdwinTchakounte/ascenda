import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../etat/apparence.dart';
import '../theme/palette.dart';
import '../theme/texte.dart';

/// Le choix du thème : cinq échantillons de papier, chacun un aperçu de son
/// ambiance.
///
/// Une pastille ronde ne dit rien du papier qu'on choisit. Ici chaque vignette
/// est une petite page : le fond du thème, quelques lignes de texte à l'encre,
/// le bandeau profond des cartes de mise en avant et le point d'or. On choisit
/// une matière, pas une couleur.
class SelecteurTheme extends ConsumerWidget {
  const SelecteurTheme({super.key, this.compact = false});

  /// Dans le tiroir : échantillons plus petits, sur une ligne.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choix = ref.watch(apparenceProvider).theme;
    final options = [
      (id: Apparence.automatique, nom: 'Auto', clair: Palette.ivoire, sombre: Palette.nuit),
      for (final p in Palette.tous) (id: p.id, nom: p.nom, clair: p, sombre: p),
    ];
    final taille = compact ? 40.0 : 50.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final o in options)
          _Echantillon(
            nom: o.nom,
            clair: o.clair,
            sombre: o.sombre,
            taille: taille,
            actif: choix == o.id,
            onTap: () => ref.read(apparenceProvider.notifier).choisir(o.id),
          ),
      ],
    );
  }
}

class _Echantillon extends StatelessWidget {
  const _Echantillon({
    required this.nom,
    required this.clair,
    required this.sombre,
    required this.taille,
    required this.actif,
    required this.onTap,
  });

  final String nom;
  final Palette clair;
  final Palette sombre;
  final double taille;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final auto = clair.id != sombre.id;
    return Semantics(
      label: 'Thème $nom',
      selected: actif,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: taille,
              // La proportion d'une page, pas celle d'un jeton.
              height: taille * 1.3,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: Rayons.petit,
                color: actif ? p.accent.withValues(alpha: 0.16) : Colors.transparent,
                border: Border.all(
                  color: actif ? p.accent : p.encre.withValues(alpha: p.sombre ? 0.30 : 0.20),
                  width: actif ? 1.8 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(6)),
                child: CustomPaint(
                  painter: _Feuille(clair: clair, sombre: sombre, auto: auto),
                  child: actif
                      ? Center(
                          child: Icon(
                            Icons.check_rounded,
                            size: taille * 0.42,
                            color: auto ? clair.accentTexte : clair.accentSurHeros,
                            shadows: [
                              BoxShadow(color: clair.herosFin.withValues(alpha: 0.6), blurRadius: 6),
                            ],
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 7),
            // Le nom ne déborde jamais de son échantillon : sur un écran
            // étroit ou en grande police, cinq vignettes tiennent la ligne.
            SizedBox(
              width: taille,
              child: Texte(
                nom,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: actif ? p.encre : p.attenue,
                      fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
                      letterSpacing: actif ? 0.4 : 0.2,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une page du thème : son papier, ses lignes d'encre, son bandeau profond et
/// son point d'or. Pour « Auto », la feuille est déchirée en diagonale, moitié
/// Ivoire, moitié Nuit.
class _Feuille extends CustomPainter {
  _Feuille({required this.clair, required this.sombre, required this.auto});
  final Palette clair;
  final Palette sombre;
  final bool auto;

  @override
  void paint(Canvas canvas, Size s) {
    if (auto) {
      _page(canvas, s, clair);
      final moitie = Path()
        ..moveTo(s.width, 0)
        ..lineTo(s.width, s.height)
        ..lineTo(0, s.height)
        ..close();
      canvas.save();
      canvas.clipPath(moitie);
      _page(canvas, s, sombre);
      canvas.restore();
      return;
    }
    _page(canvas, s, clair);
  }

  /// Le rendu d'une page dans une palette donnée, à l'échelle de la vignette.
  void _page(Canvas canvas, Size s, Palette p) {
    canvas.drawRect(Offset.zero & s, Paint()..color = p.fond);

    // Trois lignes de texte à l'encre, la dernière plus courte : la page est
    // écrite, on ne cherche pas à la lire.
    final encre = Paint()
      ..color = p.texte.withValues(alpha: 0.55)
      ..strokeWidth = s.height * 0.035
      ..strokeCap = StrokeCap.round;
    final marge = s.width * 0.16;
    for (var i = 0; i < 3; i++) {
      final y = s.height * (0.16 + i * 0.13);
      final fin = s.width - marge * (i == 2 ? 2.4 : 1);
      canvas.drawLine(Offset(marge, y), Offset(fin, y), encre);
    }

    // Le bandeau profond du bas : la carte de mise en avant du thème.
    final bandeau = Rect.fromLTWH(0, s.height * 0.58, s.width, s.height * 0.42);
    canvas.drawRect(bandeau, Paint()..shader = p.degradeHeros.createShader(bandeau));

    // Le point d'or, posé sur le bandeau comme sur la carte.
    canvas.drawCircle(
      Offset(s.width * 0.28, s.height * 0.79),
      s.width * 0.11,
      Paint()..color = p.accentSurHeros,
    );
    canvas.drawLine(
      Offset(s.width * 0.46, s.height * 0.79),
      Offset(s.width * 0.80, s.height * 0.79),
      Paint()
        ..color = p.surHerosDoux.withValues(alpha: 0.8)
        ..strokeWidth = s.height * 0.032
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _Feuille autre) =>
      autre.clair != clair || autre.sombre != sombre || autre.auto != auto;
}
