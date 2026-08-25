import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The only async work before first frame. Everything else — the database,
  // the tariff table, the engines — initialises lazily, so cold start stays
  // inside the 2s budget on the reference low-end device.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const GridApp(),
    ),
  );
}
