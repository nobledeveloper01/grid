import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/providers.dart';
import 'core/dev/demo_seed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The only async work before first frame. Everything else — the database,
  // the tariff table, the engines — initialises lazily, so cold start stays
  // inside the 2s budget on the reference low-end device.
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  // Development and QA only, and only into an empty database. `enabled` is a
  // compile-time constant, so a release build contains no call at all.
  if (DemoSeed.enabled) {
    await DemoSeed(
      meters: container.read(meterRepositoryProvider),
      readings: container.read(readingRepositoryProvider),
      purchases: container.read(purchaseRepositoryProvider),
      supply: container.read(supplyRepositoryProvider),
      appliances: container.read(applianceRepositoryProvider),
      uuid: () => container.read(uuidProvider).v7(),
    ).run(now: container.read(clockProvider)());
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GridApp(),
    ),
  );
}
