import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/router.dart';
import 'core/theme/theme.dart';

class GridApp extends ConsumerWidget {
  const GridApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    );
  }
}
