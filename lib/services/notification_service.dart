import 'dart:io';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

class NotificationService {
  NotificationService._();
  static final NotificationService I = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    tzdata.initializeTimeZones();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    _inited = true;
  }

  Future<bool> requestPermissions() async {
    await init();
    if (Platform.isAndroid) {
      final ok = await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return ok ?? false;
    } else {
      final ok = await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return ok ?? false;
    }
  }

  // ---------- LOGGING (for NotificationsPage) ----------
  static const _kKey = 'notif_log_v1';

  Future<void> _appendLog({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String kind, // 'now' | 'scheduled'
  }) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    final list = raw == null ? <Map<String, dynamic>>[] : List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map))
    );
    list.add({
      'id': id,
      'title': title,
      'body': body,
      'when': when.toIso8601String(),
      'kind': kind,
    });
    await sp.setString(_kKey, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kKey);
    if (raw == null) return const [];
    return List<Map<String, dynamic>>.from(
      (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map))
    );
  }

  Future<void> clearLogs() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kKey);
  }
  // -----------------------------------------------------

  // Instant notification for demos
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await init();
    const android = AndroidNotificationDetails(
      'tasks_channel', 'Task Reminders',
      channelDescription: 'Reminders for plot tasks',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    await _plugin.show(id, title, body, const NotificationDetails(android: android, iOS: ios), payload: payload);
    await _appendLog(id: id, title: title, body: body, when: DateTime.now(), kind: 'now');
  }

  // Scheduled (what your app already uses)
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime whenLocal,
    String? payload,
  }) async {
    await init();
    final tzTime = tz.TZDateTime.from(whenLocal, tz.local);
    const android = AndroidNotificationDetails(
      'tasks_channel', 'Task Reminders',
      channelDescription: 'Reminders for plot tasks',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      id, title, body, tzTime,
      const NotificationDetails(android: android, iOS: ios),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
    await _appendLog(id: id, title: title, body: body, when: whenLocal, kind: 'scheduled');
  }

  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  // ---------- One-tap DEMO seeding ----------
  Future<void> seedDemo() async {
    await requestPermissions();

    // 1) show instantly
    await showNow(
      id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      title: 'Demo: Instant notification',
      body: 'This proves notifications are working.',
    );

    // 2) schedule 2 more in near future (1 & 2 minutes)
    final base = DateTime.now();
    await schedule(
      id: (base.millisecondsSinceEpoch + 1) & 0x7fffffff,
      title: 'Demo: Reminder in 1 min',
      body: 'This is a scheduled notification.',
      whenLocal: base.add(const Duration(minutes: 1)),
    );
    await schedule(
      id: (base.millisecondsSinceEpoch + 2) & 0x7fffffff,
      title: 'Demo: Reminder in 2 min',
      body: 'Another scheduled notification.',
      whenLocal: base.add(const Duration(minutes: 2)),
    );
  }
}
