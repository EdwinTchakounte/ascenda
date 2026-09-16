import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../etat/apparence.dart';
import '../theme/palette.dart';
import '../theme/texte.dart';

/// Le choix du thème : cinq vignettes, chacune un aperçu de son ambiance.
class SelecteurTheme extends ConsumerWidget {
  const SelecteurTheme({super.key, this.compact = false});

  /// Dans le tiroir : vignettes plus petites, sur une ligne.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choix = ref.watch(apparenceProvider).theme;
    final options = [
      (id: Apparence.automatique, nom: 'Auto', clair: Palette.ivoire, sombre: Palette.nuit),
      for (final p in Palette.tous) (id: p.id, nom: p.nom, clair: p, sombre: p),
    ];
    final taille = compact ? 46.0 : 58.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final o in options)
          _Vignette(
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

class _Vignette extends StatelessWidget {
  const _Vignette({
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
              width: taille,
              height: taille,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: actif ? p.accent : p.trait, width: actif ? 2.4 : 1.2),
              ),
              child: ClipOval(
                child: CustomPaint(
                  painter: _Apercu(clair: clair, sombre: sombre, auto: auto),
                  child: Center(
                    child: actif
                        ? Icon(Icons.check_rounded, size: taille * 0.36, color: auto ? clair.accent : sombre.accentSurHeros)
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Texte(
              nom,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: actif ? p.encre : p.attenue,
                    fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un disque : le fond du thème, sa carte profonde en diagonale, un point d'or.
/// Pour « Auto », une moitié Ivoire et une moitié Nuit.
class _Apercu extends CustomPainter {
  _Apercu({required this.clair, required this.sombre, required this.auto});
  final Palette clair;
  final Palette sombre;
  final bool auto;

  @override
  void paint(Canvas canvas, Size s) {
    final r = Offset.zero & s;
    if (auto) {
      canvas.drawRect(r, Paint()..color = clair.fond);
      final moitie = Path()
        ..moveTo(s.width, 0)
        ..lineTo(s.width, s.height)
        ..lineTo(0, s.height)
        ..close();
      canvas.drawPath(moitie, Paint()..color = sombre.fond);
    } else {
      canvas.drawRect(r, Paint()..color = clair.fond);
      final diag = Path()
        ..moveTo(s.width * 0.35, s.height)
        ..lineTo(s.width, s.height * 0.35)
        ..lineTo(s.width, s.height)
        ..close();
      canvas.drawPath(diag, Paint()..shader = clair.degradeHeros.createShader(r));
    }
    canvas.drawCircle(Offset(s.width * 0.3, s.height * 0.3), s.width * 0.09, Paint()..color = clair.accent);
  }

  @override
  bool shouldRepaint(covariant _Apercu old) => old.clair != clair || old.sombre != sombre;
}
