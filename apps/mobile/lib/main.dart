import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api/reseau.dart';
import 'routes.dart';
import 'theme/theme.dart';
import 'widgets/exploitation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Les polices sont embarquées dans assets/google_fonts. Sans cette ligne,
  // google_fonts les téléchargerait au lancement : sans réseau, l'application
  // s'afficherait dans une police de secours.
  GoogleFonts.config.allowRuntimeFetching = false;
  await Reseau.preparer();
  // Les dates s'affichent en français partout : « Sam. 29 août », pas « Sat ».
  await initializeDateFormatting('fr_FR');
  runApp(const ProviderScope(child: ApplicationAscenda()));
}

class ApplicationAscenda extends ConsumerWidget {
  const ApplicationAscenda({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Le voile enveloppe tout, y compris les écrans d'authentification : une
    // mise à jour doit se voir avant qu'on essaie de se connecter, pas après un
    // échec inexpliqué.
    return VoileExploitation(
      enfant: MaterialApp.router(
        title: 'ASCENDA',
        debugShowCheckedModeBanner: false,
        theme: ThemeAscenda.clair,
        darkTheme: ThemeAscenda.sombre,
        // Le clair est le défaut : c'est une application de lecture. Le sombre
        // suit le réglage du téléphone.
        themeMode: ThemeMode.system,
        routerConfig: ref.watch(routeurProvider),
      ),
    );
  }
}
