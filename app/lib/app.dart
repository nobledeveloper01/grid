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
      // Dark is the system default at night by preference, which is when
      // people read meters.
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
