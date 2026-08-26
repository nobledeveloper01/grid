import 'dart:convert';

import '../../domain/services/forecast_engine.dart';
import '../../domain/value_objects/enums.dart';

/// What a home-screen widget shows, and how it gets there.
///
/// Feature F14. The exit gate is one sentence and it is the whole design:
///
/// > **The widget reads from shared storage and never blocks on the app
/// > process being alive.**
///
/// A widget is drawn by the system, on the system's schedule, in a process
/// that is not Grid. It cannot open Drift, it cannot run the forecast engine,
/// and it cannot wait for anything. So the app computes the glance whenever it
/// has reason to, writes a small flat snapshot into shared storage, and the
/// widget renders whatever is there — including when what is there is old,
/// which it says rather than hides.
///
/// This file is the snapshot and its rules. The native extensions that read it
/// — a WidgetKit target on iOS, an App Widget provider on Android — are not
/// built; see the phase 10 note in `docs/ROADMAP.md`.
class Glance {
  const Glance({
    required this.meterLabel,
    required this.headline,
    required this.detail,
    required this.supply,
    required this.updatedAt,
    this.isEstimate = false,
  });

  final String meterLabel;

  /// The one figure. Already formatted, because the widget has no access to
  /// the formatters and must not reimplement naira rendering — two
  /// implementations of that is how the sign ends up orphaned in one of them.
  final String headline;

  final String detail;

  /// Supply right now, so the widget can show state without colour alone.
  final SupplyState supply;

  final DateTime updatedAt;

  /// True when the headline is modelled rather than measured. Carried so the
  /// widget can mark it — the measured/modelled rule does not stop at the edge
  /// of the app.
  final bool isEstimate;

  /// Beyond this, the widget says how old the figure is instead of presenting
  /// it as current.
  ///
  /// A widget showing yesterday's depletion date as though it were today's is
  /// the same failure as interpolating unobserved supply: a figure presented
  /// with more confidence than its provenance supports.
  static const Duration staleAfter = Duration(hours: 12);

  bool isStale(DateTime now) => now.difference(updatedAt) > staleAfter;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'meter': meterLabel,
        'headline': headline,
        'detail': detail,
        'supply': supply.name,
        'estimate': isEstimate,
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Reads a snapshot, tolerating anything.
  ///
  /// Returns null rather than throwing on absent, malformed or
  /// newer-than-understood data. A widget that crashes is a blank rectangle on
  /// somebody's home screen with no way to report itself, so every failure
  /// here has to be a quiet nothing.
  static Glance? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['v'] != 1) return null;

      final updatedAt = DateTime.tryParse(decoded['updatedAt'] as String? ?? '');
      if (updatedAt == null) return null;

      return Glance(
        meterLabel: decoded['meter'] as String? ?? '',
        headline: decoded['headline'] as String? ?? '',
        detail: decoded['detail'] as String? ?? '',
        supply: SupplyState.values.firstWhere(
          (s) => s.name == decoded['supply'],
          orElse: () => SupplyState.unknown,
        ),
        isEstimate: decoded['estimate'] as bool? ?? false,
        updatedAt: updatedAt,
      );
    } on Object {
      return null;
    }
  }
}

/// Builds the snapshot from whatever the app already knows.
///
/// Pure, and deliberately so: the widget's content is decided by the same
/// sealed results every screen renders, rather than by a second set of rules
/// that could disagree with the app the user opens a moment later.
class GlanceBuilder {
  const GlanceBuilder();

  Glance build({
    required String meterLabel,
    required bool isPrepaid,
    required BalanceForecast? balance,
    required CostProjection? cost,
    required SupplyState supply,
    required DateTime now,
  }) {
    if (isPrepaid) {
      return switch (balance) {
        BalanceKnown(:final depletesOn, :final isRough) => Glance(
            meterLabel: meterLabel,
            headline: _days(depletesOn, now),
            detail: isRough
                ? 'roughly, on what Grid has so far'
                : 'until your units finish',
            supply: supply,
            updatedAt: now,
            isEstimate: isRough,
          ),
        _ => Glance(
            meterLabel: meterLabel,
            headline: '—',
            detail: 'log a reading',
            supply: supply,
            updatedAt: now,
          ),
      };
    }

    return switch (cost) {
      CostProjected(:final projectedCost, :final isRough) => Glance(
          meterLabel: meterLabel,
          headline: projectedCost.format(),
          detail: 'this month',
          supply: supply,
          updatedAt: now,
          isEstimate: isRough,
        ),
      _ => Glance(
          meterLabel: meterLabel,
          headline: '—',
          detail: 'log a reading',
          supply: supply,
          updatedAt: now,
        ),
    };
  }

  /// Whole days, floored.
  ///
  /// A widget saying "3 days" when 3.9 remain is safe; one saying "4" when 3.1
  /// remain sends somebody to bed on units that run out overnight. Rounding
  /// down is the direction that fails safe, and it is the opposite of what
  /// `round()` would have done.
  String _days(DateTime depletesOn, DateTime now) {
    final remaining = depletesOn.difference(now);
    if (remaining.isNegative) return '0 days';
    final days = remaining.inHours ~/ 24;
    return days == 1 ? '1 day' : '$days days';
  }
}

/// Where the snapshot lives.
///
/// One key, one string. The app writes; the widget reads. Nothing negotiates,
/// nothing waits, and there is no schema for the two sides to disagree about
/// beyond the version tag.
abstract interface class GlanceStore {
  Future<void> write(Glance glance);
  Future<Glance?> read();
  Future<void> clear();
}

/// The key both sides agree on.
///
/// iOS reads it from the App Group's shared `UserDefaults`; Android from the
/// same-named `SharedPreferences`. Written here rather than in two native
/// files so a rename cannot silently break one platform.
const String glanceStorageKey = 'grid.glance.v1';

/// The App Group / shared-preferences container the widget reads from.
const String glanceAppGroup = 'group.com.gridapp.grid';

/// Does nothing, successfully. Used until the native targets exist, and in
/// tests — a glance that fails to write must never take a screen down with it.
class NullGlanceStore implements GlanceStore {
  const NullGlanceStore();

  @override
  Future<void> write(Glance glance) async {}

  @override
  Future<Glance?> read() async => null;

  @override
  Future<void> clear() async {}
}
