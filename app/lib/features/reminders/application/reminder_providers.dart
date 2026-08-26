import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/platform/reminders.dart';
import '../../meter/application/meter_providers.dart';

final remindersProvider = Provider<Reminders>((ref) {
  final plugin = FlutterLocalNotificationsPlugin();
  final reminders = LocalReminders(plugin);
  // Fire and forget: initialisation is idempotent and nothing downstream
  // waits on it. A screen that awaited a notification plugin before drawing
  // would be a screen that awaits the platform, which this app does not do.
  reminders.init();
  return reminders;
});

const _onKey = 'reminders.on';
const _dayKey = 'reminders.day';
const _askedKey = 'reminders.asked';

/// Whether a monthly reading reminder is scheduled.
final reminderOnProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(settingsRepositoryProvider)
      .watch(_onKey)
      .map((v) => v == 'true');
});

/// The day of the month it fires on.
final reminderDayProvider = StreamProvider<int>((ref) {
  return ref
      .watch(settingsRepositoryProvider)
      .watch(_dayKey)
      .map((v) => int.tryParse(v ?? '') ?? 1);
});

/// Whether the user has been asked about reminders at all.
///
/// Answering either way is final: the offer is made once. An app that asks
/// again next week has not taken the first answer seriously.
final reminderAskedProvider = StreamProvider<bool>((ref) {
  return ref
      .watch(settingsRepositoryProvider)
      .watch(_askedKey)
      .map((v) => v == 'true');
});

/// Whether to offer reminders on the home screen right now.
///
/// After the second reading, not before. The offer only makes sense once the
/// user has done the thing twice and can see what it is for.
final shouldOfferReminderProvider = Provider<bool>((ref) {
  final meter = ref.watch(selectedMeterProvider);
  if (meter == null) return false;
  if (ref.watch(reminderAskedProvider).value ?? true) return false;
  final readings = ref.watch(readingsProvider(meter.id)).value ?? const [];
  return readings.length >= 2;
});

class ReminderController extends Notifier<void> {
  @override
  void build() {}

  /// Turns reminders on, asking for permission first. Returns false if the
  /// user or the platform refused, so the caller can say so rather than
  /// showing a switch that silently does nothing.
  Future<bool> enable({required int dayOfMonth}) async {
    final settings = ref.read(settingsRepositoryProvider);
    await settings.set(_askedKey, 'true');

    final granted = await ref.read(remindersProvider).request();
    if (!granted) {
      await settings.set(_onKey, 'false');
      return false;
    }

    await ref
        .read(remindersProvider)
        .schedule(dayOfMonth: dayOfMonth, hour: 8);
    await settings.set(_dayKey, '$dayOfMonth');
    await settings.set(_onKey, 'true');
    return true;
  }

  Future<void> disable() async {
    final settings = ref.read(settingsRepositoryProvider);
    await ref.read(remindersProvider).cancel();
    await settings.set(_onKey, 'false');
    await settings.set(_askedKey, 'true');
  }

  /// Records that the offer was declined, so it is never made again.
  Future<void> declineOffer() =>
      ref.read(settingsRepositoryProvider).set(_askedKey, 'true');
}

final reminderControllerProvider =
    NotifierProvider<ReminderController, void>(ReminderController.new);

const _lastAlertKey = 'compliance.lastAlertedAt';

/// Raises a band-shortfall alert, at most once per cooldown.
///
/// Watched by the home screen. Alerting is a side effect of the compliance
/// figure changing, and the hysteresis lives in `ComplianceEngine` where it
/// is tested — a figure that hovers around the threshold must not produce a
/// notification every day, or the user turns notifications off and the one
/// alert that mattered never arrives.
final complianceAlertProvider = FutureProvider.family<void, String>(
  (ref, meterId) async {
    final result = ref.watch(complianceProvider(meterId));
    if (result == null || !result.canRaiseAlert) return;

    final settings = ref.watch(settingsRepositoryProvider);
    final stored = await settings.get(_lastAlertKey);
    final lastAlertedAt =
        stored == null ? null : DateTime.tryParse(stored);

    final now = ref.read(clockProvider)();
    final engine = ref.read(complianceEngineProvider);
    if (!engine.shouldAlert(
      result: result,
      now: now,
      lastAlertedAt: lastAlertedAt,
    )) {
      return;
    }

    // Recorded before the alert is shown, not after. If showing throws, the
    // cooldown has still started — better a missed alert than a loop that
    // retries on every rebuild.
    await settings.set(_lastAlertKey, now.toIso8601String());

    final hours = result.summary.rollingAverageHours.toStringAsFixed(1);
    await ref.read(remindersProvider).alert(
          title: 'Your supply is short of Band ${result.band.label}',
          body: 'Band ${result.band.label} promises '
              '${result.band.committedHours} hours a day. Over the last 30 '
              'days you have averaged $hours. Grid can build the pack.',
        );
  },
);
