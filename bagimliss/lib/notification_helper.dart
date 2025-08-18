import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _tzReady = false;

  static void _ensureTz() {
    if (_tzReady) return;
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('UTC'));
      } catch (_) {}
    }
    _tzReady = true;
  }

  static Future<void> initialize() async {
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      final initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );
      await _plugin.initialize(initSettings);
      // Zaman dilimi hazırlığı (varsayılan: Europe/Istanbul)
      _ensureTz();
    } catch (_) {
      // Plugin henüz kayıtlı değilse (hot reload/arka plan) sessizce geç.
    }
  }

  static Future<void> requestPermission() async {
    try {
      final androidImpl =
          _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      await androidImpl?.requestNotificationsPermission();
    } catch (_) {}
  }

  static Future<void> showSimple(int id, String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'goals',
      'Goal Notifications',
      channelDescription: 'Goal achievement notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    final details = const NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _plugin.show(id, title, body, details);
  }

  // Günlük tekrar eden nazik uyarı (belirli saat:dk)
  static Future<void> scheduleDailyRisk(
    int id,
    int hour,
    int minute,
    String title,
    String body,
  ) async {
    _ensureTz();
    final androidDetails = AndroidNotificationDetails(
      'risk_reminders',
      'Yüksek Risk Uyarıları',
      channelDescription: 'Kritik saatlerde nazik hatırlatma',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    final details = NotificationDetails(android: androidDetails);
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } on PlatformException catch (e) {
      if (e.code == 'exact_alarms_not_permitted') {
        // İzin yoksa inexact moda düş
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          details,
          androidScheduleMode: AndroidScheduleMode.inexact,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      } else {
        rethrow;
      }
    }
  }

  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  // Basit toplu iptal (2000-2099 aralığı)
  static Future<void> cancelAllRisk() async {
    for (var i = 2000; i < 2100; i++) {
      await _plugin.cancel(i);
    }
  }
}
