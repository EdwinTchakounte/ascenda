import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'routes.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Les dates s'affichent en français partout : « Sam. 29 août », pas « Sat ».
  await initializeDateFormatting('fr_FR');
  runApp(const ProviderScope(child: ApplicationAscenda()));
}

class ApplicationAscenda extends ConsumerWidget {
  const ApplicationAscenda({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ASCENDA',
      debugShowCheckedModeBanner: false,
      theme: ThemeAscenda.clair,
      darkTheme: ThemeAscenda.sombre,
      // Le clair est le défaut : c'est une application de lecture. Le sombre
      // suit le réglage du téléphone.
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routeurProvider),
    );
  }
}
