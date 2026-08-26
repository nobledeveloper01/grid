import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../domain/services/budget_engine.dart';
import '../../../domain/value_objects/units.dart';
import '../../meter/application/meter_providers.dart';

final budgetEngineProvider =
    Provider<BudgetEngine>((ref) => const BudgetEngine());

String _amountKey(String meterId) => 'budget.$meterId.monthlyKobo';
String _payDayKey(String meterId) => 'budget.$meterId.payDay';

/// The budget for a meter, or null if none is set.
///
/// Stored as settings rather than as a fact: a budget is a preference the
/// user changes, and nothing about it is evidence.
final budgetProvider =
    StreamProvider.family<Budget?, String>((ref, meterId) async* {
  final settings = ref.watch(settingsRepositoryProvider);

  Future<Budget?> read() async {
    final kobo = int.tryParse(await settings.get(_amountKey(meterId)) ?? '');
    final day = int.tryParse(await settings.get(_payDayKey(meterId)) ?? '');
    if (kobo == null || day == null || kobo <= 0) return null;
    return Budget(monthly: Naira.fromKobo(kobo), payDayOfMonth: day);
  }

  yield await read();
  // The amount is the value that changes; the pay day rides along with it,
  // so one watch is enough and the two can never be read half-updated.
  await for (final _ in settings.watch(_amountKey(meterId))) {
    yield await read();
  }
});

class BudgetController extends Notifier<void> {
  @override
  void build() {}

  Future<void> set({
    required String meterId,
    required Naira monthly,
    required int payDayOfMonth,
  }) async {
    final settings = ref.read(settingsRepositoryProvider);
    // Pay day first: it is read alongside the amount, and the amount is what
    // the stream watches. Writing it second would emit once with the new
    // amount and the old day.
    await settings.set(_payDayKey(meterId), '$payDayOfMonth');
    await settings.set(_amountKey(meterId), '${monthly.kobo}');
  }

  Future<void> clear(String meterId) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.set(_amountKey(meterId), '0');
  }
}

final budgetControllerProvider =
    NotifierProvider<BudgetController, void>(BudgetController.new);

/// Where the household stands against its budget, or null if none is set.
final budgetOutlookProvider =
    Provider.family<BudgetOutlook?, String>((ref, meterId) {
  final budget = ref.watch(budgetProvider(meterId)).value;
  if (budget == null) return null;

  final meter = ref
      .watch(metersProvider)
      .value
      ?.where((m) => m.id == meterId)
      .firstOrNull;
  if (meter == null) return null;

  final engine = ref.watch(budgetEngineProvider);
  final now = ref.watch(clockProvider)();

  if (!meter.isPrepaid) {
    final projection = ref.watch(costProjectionProvider(meterId));
    if (projection == null) return null;
    return engine.fromProjection(
      budget: budget,
      projection: projection,
      now: now,
    );
  }

  final forecast = ref.watch(balanceForecastProvider(meterId));
  final rate = ref.watch(effectiveRateProvider(meterId));
  if (forecast == null || rate == null) return null;

  // Spend so far this cycle: what has actually been paid, which for a
  // prepaid household is the purchases and nothing else.
  final purchases = ref.watch(purchasesProvider(meterId)).value ?? const [];
  final cycleStart = DateTime(now.year, now.month);
  final spent = purchases
      .where((p) => !p.purchasedAt.isBefore(cycleStart))
      .fold<Naira>(Naira.zero, (a, p) => a + p.amount);

  return engine.fromBalance(
    budget: budget,
    forecast: forecast,
    rate: rate,
    spentThisCycle: spent,
    now: now,
  );
});
