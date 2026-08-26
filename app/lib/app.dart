import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/router.dart';
import 'core/theme/theme.dart';
import 'features/splash/presentation/splash_screen.dart';

class GridApp extends ConsumerStatefulWidget {
  const GridApp({super.key});

  @override
  ConsumerState<GridApp> createState() => _GridAppState();
}

class _GridAppState extends ConsumerState<GridApp> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Grid',
      debugShowCheckedModeBanner: false,
      theme: GridTheme.light(),
      darkTheme: GridTheme.dark(),
      // Dark by default, not by system preference. This app is opened at a
      // meter, outdoors, at night more often than not — and the amber on a
      // warm black is the version of Grid that actually looks like the thing
      // it is about. Light remains fully authored for daytime use.
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      // The splash sits *over* the app rather than in front of it, so the
      // router, the database and the tariff table all initialise while it
      // plays. By the time it lifts, the first real screen is already built.
      builder: (context, child) => Stack(
        children: [
          child ?? const SizedBox.shrink(),
          if (!_splashDone)
            SplashScreen(
              onFinished: () {
                if (mounted) setState(() => _splashDone = true);
              },
            ),
        ],
      ),
    );
  }
}
