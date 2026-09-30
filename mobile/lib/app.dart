import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/realtime/realtime_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/feedback.dart';

class GarrixApp extends ConsumerWidget {
  const GarrixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Temps réel : connecté tant que l'utilisateur est connecté.
    ref.listen(authControllerProvider, (previous, next) {
      final realtime = ref.read(realtimeServiceProvider);
      next.isSignedIn ? realtime.start() : realtime.stop();
    });
    // Changement de serveur : on repart d'une connexion WebSocket propre.
    ref.listen(serverUrlProvider, (_, _) {
      final realtime = ref.read(realtimeServiceProvider);
      realtime.stop();
      if (ref.read(authControllerProvider).isSignedIn) realtime.start();
    });

    return MaterialApp.router(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      scaffoldMessengerKey: rootMessengerKey,
      routerConfig: ref.watch(appRouterProvider),
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
