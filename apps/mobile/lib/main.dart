import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api/reseau.dart';
import 'etat/apparence.dart';
import 'routes.dart';
import 'theme/palette.dart';
import 'theme/theme.dart';
import 'widgets/exploitation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  await Reseau.preparer();
  await initializeDateFormatting('fr_FR');
  final theme = await ApparenceNotifier.themeEnregistre();
  runApp(ProviderScope(
    overrides: [apparenceProvider.overrideWith((ref) => ApparenceNotifier(theme))],
    child: const ApplicationAscenda(),
  ));
}

class ApplicationAscenda extends ConsumerStatefulWidget {
  const ApplicationAscenda({super.key});

  @override
  ConsumerState<ApplicationAscenda> createState() => _ApplicationAscendaState();
}

class _ApplicationAscendaState extends ConsumerState<ApplicationAscenda> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final apparence = ref.watch(apparenceProvider);
    final systeme = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final palette = apparence.palette(systeme);

    if (Palette.courante.id != palette.id) {
      Palette.courante = palette;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        void marquer(Element e) {
          e.markNeedsBuild();
          e.visitChildren(marquer);
        }
        (context as Element).visitChildren(marquer);
      });
    }

    final barres = palette.sombre ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: barres.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: palette.surface,
        systemNavigationBarIconBrightness: palette.sombre ? Brightness.light : Brightness.dark,
      ),
      child: VoileExploitation(
        enfant: MaterialApp.router(
          title: 'ASCENDA',
          debugShowCheckedModeBanner: false,
          theme: ThemeAscenda.depuis(palette),
          themeMode: ThemeMode.light,
          themeAnimationDuration: const Duration(milliseconds: 260),
          routerConfig: ref.watch(routeurProvider),
        ),
      ),
    );
  }
}
