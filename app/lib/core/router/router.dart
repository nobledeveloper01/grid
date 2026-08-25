import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/meter/application/meter_providers.dart';
import '../../features/onboarding/presentation/meter_type_screen.dart';
import '../../features/onboarding/presentation/disco_screen.dart';
import '../../features/onboarding/presentation/tariff_band_screen.dart';
import '../../features/onboarding/presentation/first_value_screen.dart';
import '../../features/reading/presentation/manual_entry_screen.dart';
import '../../features/reading/presentation/reading_history_screen.dart';
import '../../features/reading/presentation/purchase_entry_screen.dart';
import '../../features/supply/presentation/supply_timeline_screen.dart';

/// Route names, referenced rather than typed as strings at call sites.
abstract final class Routes {
  static const onboardingMeterType = '/onboarding';
  static const onboardingDisco = '/onboarding/disco';
  static const onboardingBand = '/onboarding/band';
  static const onboardingFirstValue = '/onboarding/first-value';

  static const home = '/';
  static const manualEntry = '/reading/manual';
  static const readingHistory = '/reading/history';
  static const purchaseEntry = '/reading/purchase';
  static const supplyTimeline = '/supply';
}

/// Bridges a Riverpod provider to GoRouter's [Listenable]-based refresh.
///
/// Without this the redirect below evaluates once, before the meters stream
/// has produced its first value, and never runs again — leaving the app on a
/// blank home screen. Notifying on every meters change makes the redirect
/// re-evaluate as soon as the local database answers.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(metersProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      // Onboarding is not a wall — it is simply what you see when there is
      // no meter yet. There is no account, no login, and nothing to skip.
      final meters = ref.read(metersProvider);

      // Until the local database has answered, hold position rather than
      // guessing. It answers in milliseconds; there is no network involved.
      if (!meters.hasValue) return null;

      final hasMeter = (meters.value ?? const []).isNotEmpty;
      final onOnboarding = state.matchedLocation.startsWith('/onboarding');

      if (!hasMeter && !onOnboarding) return Routes.onboardingMeterType;
      if (hasMeter && state.matchedLocation == Routes.onboardingMeterType) {
        return Routes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.onboardingMeterType,
        builder: (context, state) => const MeterTypeScreen(),
        routes: [
          GoRoute(
            path: 'disco',
            builder: (context, state) => const DiscoScreen(),
          ),
          GoRoute(
            path: 'band',
            builder: (context, state) => const TariffBandScreen(),
          ),
          GoRoute(
            path: 'first-value',
            builder: (context, state) => const FirstValueScreen(),
          ),
        ],
      ),
      GoRoute(
        path: Routes.manualEntry,
        builder: (context, state) => const ManualEntryScreen(),
      ),
      GoRoute(
        path: Routes.readingHistory,
        builder: (context, state) => const ReadingHistoryScreen(),
      ),
      GoRoute(
        path: Routes.purchaseEntry,
        builder: (context, state) => const PurchaseEntryScreen(),
      ),
      GoRoute(
        path: Routes.supplyTimeline,
        builder: (context, state) => const SupplyTimelineScreen(),
      ),
    ],
  );
});
