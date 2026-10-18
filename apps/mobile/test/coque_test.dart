
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ascenda/ecrans/coque.dart';
import 'package:ascenda/theme/palette.dart';
import 'package:ascenda/theme/theme.dart';

const _hauteur = 780.0;

Widget _sous({String depart = '/un'}) {
  final routeur = GoRouter(
    initialLocation: depart,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (c, s, coque) => CoqueAscenda(coque: coque),
        branches: [
          for (final nom in ['un', 'deux', 'trois', 'quatre'])
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/$nom',
                builder: (c, s) => Center(key: Key('ecran-$nom'), child: Text(nom)),
              ),
            ]),
        ],
      ),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: ThemeAscenda.depuis(Palette.ivoire),
      routerConfig: routeur,
    ),
  );
}

void main() {
  testWidgets("l'écran occupe la hauteur que la barre lui laisse", (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(_sous());
    await t.pumpAndSettle();

    final barre = t.getSize(find.byType(NavigationBar));
    expect(barre.height, lessThan(140),
        reason: 'la barre doit tenir en bas, pas occuper l\'écran');

    final corps = t.getSize(find.byKey(const Key('ecran-un')));
    expect(corps.height, greaterThan(_hauteur - 200),
        reason: "l'écran doit recevoir la hauteur restante");
  });

  testWidgets('changer d\'onglet change d\'écran', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(_sous());
    await t.pumpAndSettle();
    expect(find.byKey(const Key('ecran-un')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('onglet-2')));
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(const Key('ecran-trois'))).height,
        greaterThan(_hauteur - 200));
  });
}
