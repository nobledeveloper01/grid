import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Reading reminders, anchored to the billing cycle.
///
/// A façade for the same reason the OCR and supply monitors have one: the
/// domain must not know what a notification plugin is, and the null
/// implementation lets every test run without a platform channel.
abstract interface class Reminders {
  /// Whether the user has granted permission. Asks if it has not been asked.
  Future<bool> request();

  /// Schedules a monthly reminder on [dayOfMonth] at [hour]. Replaces any
  /// existing one — there is deliberately only ever one.
  Future<void> schedule({required int dayOfMonth, required int hour});

  Future<void> cancel();

  /// Shows a one-off alert now, if permission has already been granted.
  ///
  /// Never asks. A band-shortfall alert that raises a permission prompt out
  /// of nowhere teaches the user to deny it, and the alert is worth less
  /// than the permission.
  Future<void> alert({required String title, required String body});

  /// Whether permission is already granted, without asking for it.
  Future<bool> isPermitted();
}

/// Does nothing, successfully. Used in tests and on any platform where the
/// plugin is not available, so no caller needs a null check.
class NullReminders implements Reminders {
  const NullReminders();

  @override
  Future<bool> request() async => false;

  @override
  Future<void> schedule({required int dayOfMonth, required int hour}) async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> alert({required String title, required String body}) async {}

  @override
  Future<bool> isPermitted() async => false;
}

class LocalReminders implements Reminders {
  LocalReminders(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  /// One id, so a reschedule replaces rather than accumulates. A user who
  /// changes their cycle date three times should not get three reminders.
  static const int _id = 1001;

  /// Separate from the reminder, so one can be silenced without the other.
  static const int _alertId = 1002;

  static const _alertChannel = AndroidNotificationDetails(
    'grid.compliance',
    'Supply alerts',
    channelDescription:
        'Raised when measured supply falls short of your band for long '
        'enough to be worth acting on.',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const _channel = AndroidNotificationDetails(
    'grid.readings',
    'Reading reminders',
    channelDescription:
        'A monthly nudge to read the meter near your billing date.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Asked for explicitly later, at a moment the user understands.
          // A permission prompt on first launch, before the app has shown
          // what it is for, is the reliable way to be denied.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<bool> request() async {
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await android?.requestNotificationsPermission();
    return granted ?? false;
  }

  @override
  Future<void> schedule({required int dayOfMonth, required int hour}) async {
    await cancel();
    await _plugin.periodicallyShowWithDuration(
      id: _id,
      title: 'Time to read your meter',
      body: 'A reading near your billing date is what makes the rest of the '
          'record hold up.',
      repeatDurationInterval: const Duration(days: 30),
      notificationDetails: const NotificationDetails(
        android: _channel,
        iOS: DarwinNotificationDetails(),
      ),
      // Inexact deliberately. An exact alarm needs a permission Android
      // grants grudgingly and revokes readily, and nothing about a monthly
      // nudge needs to land on the minute.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> cancel() => _plugin.cancel(id: _id);

  @override
  Future<bool> isPermitted() async {
    if (Platform.isIOS) {
      final settings = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.checkPermissions();
      return settings?.isAlertEnabled ?? false;
    }
    final enabled = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
    return enabled ?? false;
  }

  @override
  Future<void> alert({required String title, required String body}) async {
    if (!await isPermitted()) return;
    await _plugin.show(
      id: _alertId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: _alertChannel,
        // Stated explicitly. iOS suppresses a local notification raised
        // while the app is in the foreground unless the presentation
        // options say otherwise — and with no background execution, the
        // foreground is the only place this alert can be raised at all.
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
    );
  }
}
