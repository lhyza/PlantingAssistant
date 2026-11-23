import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/util.dart';
import 'repo.dart';

class Notify {
  Notify._();
  static final Notify instance = Notify._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool enabled = true;

  static const AndroidNotificationDetails _detail = AndroidNotificationDetails(
    'planting_reminders',
    '种植提醒',
    channelDescription: '施肥、用药、浇水等农事提醒',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (r) {},
    );
    _ready = true;
    enabled = await Repo.instance.setting('notify') != '0';
  }

  Future<void> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
  }

  /// 重新排程：每天 08:00 汇总 + 每条提醒到期日 09:00 + 每天 19:00 逾期补推
  Future<void> reschedule() async {
    if (!_ready) return;
    await cancelAll();
    if (!enabled) return;
    const details = NotificationDetails(android: _detail);
    const mode = AndroidScheduleMode.exactAllowWhileIdle;

    // 08:00 每日汇总
    await _plugin.zonedSchedule(
      id: 1000,
      scheduledDate: _next(8, 0),
      notificationDetails: details,
      androidScheduleMode: mode,
      title: '今天要做的农事',
      body: await _summaryBody(),
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'today',
    );

    // 19:00 逾期补推
    await _plugin.zonedSchedule(
      id: 1001,
      scheduledDate: _next(19, 0),
      notificationDetails: details,
      androidScheduleMode: mode,
      title: '还有农事没做',
      body: await _overdueBody(),
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'today',
    );

    // 每条提醒：到期日 09:00（未来 30 天内）
    final today = dateOnly(DateTime.now());
    final list = await Repo.instance.reminders(
      activeOnly: true,
      includeExpired: false,
    );
    final batches = {for (final b in await Repo.instance.batches()) b.id: b};
    for (final r in list) {
      final due = parseDay(r.nextDueAt);
      if (due == null) continue;
      if (due.isBefore(today)) continue;
      if (due.difference(today).inDays > 30) continue;
      final b = batches[r.batchId];
      await _plugin.zonedSchedule(
        id: 2000 + _hash(r.id),
        scheduledDate: tz.TZDateTime(
          tz.local,
          due.year,
          due.month,
          due.day,
          9,
          0,
        ),
        notificationDetails: details,
        androidScheduleMode: mode,
        title: r.title,
        body:
            '${b?.name ?? '批次'} · ${r.kind}${r.intervalDays > 1 ? ' · 每 ${r.intervalDays} 天' : ''}',
        payload: 'batch:${r.batchId}',
      );
    }
  }

  Future<String> _summaryBody() async {
    final repo = Repo.instance;
    final today = todayStr();
    final all = await repo.reminders(activeOnly: true, includeExpired: false);
    final overdue = all.where((r) => r.nextDueAt.compareTo(today) < 0).length;
    final due = all.where((r) => r.nextDueAt == today).length;
    if (overdue == 0 && due == 0) return '今天没有到期的农事，去看看吧';
    final parts = <String>[];
    if (due > 0) parts.add('今天到期 $due 件');
    if (overdue > 0) parts.add('已逾期 $overdue 件');
    return parts.join('，');
  }

  Future<String> _overdueBody() async {
    final today = todayStr();
    final all = await Repo.instance.reminders(
      activeOnly: true,
      includeExpired: false,
    );
    final overdue = all.where((r) => r.nextDueAt.compareTo(today) < 0).toList();
    if (overdue.isEmpty) return '今天的农事都完成了 🌿';
    if (overdue.length == 1) return '${overdue.first.title} 还没做';
    return '${overdue.first.title} 等 ${overdue.length} 件还没做';
  }

  tz.TZDateTime _next(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!d.isAfter(now)) d = d.add(const Duration(days: 1));
    return d;
  }

  int _hash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h % 100000;
  }

  Future<void> test() async {
    if (!_ready) return;
    await _plugin.show(
      id: 1999,
      title: '通知测试',
      body: '如果你看到这条，说明通知正常 🍓',
      notificationDetails: const NotificationDetails(android: _detail),
    );
  }

  Future<bool> get canExact async {
    if (!Platform.isAndroid) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.canScheduleExactNotifications() ?? false;
  }
}
