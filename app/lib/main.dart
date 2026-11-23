import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/images.dart';
import 'data/notify.dart';
import 'data/repo.dart';
import 'data/update_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 中文日期（M月d日 星期X）
  try {
    await initializeDateFormatting('zh_CN');
  } catch (_) {}

  // 图片目录（知识库配图、作物默认图）
  try {
    await Images.init();
  } catch (e) {
    debugPrint('images init failed: $e');
  }

  // 首次启动会建库并从 assets/seeds 灌入内置数据
  try {
    await Repo.instance.crops();
    // 历史数据里的 pests.crops 可能存了中文作物名，归一成 id（幂等）
    await Repo.instance.normalizePestCrops();
  } catch (e, st) {
    debugPrint('db init failed: $e\n$st');
  }

  // 本地通知（失败不影响主流程，部分机型没授精确闹钟权限）
  try {
    await Notify.instance.init();
    final on = await Repo.instance.setting('notify');
    if (on != '0') await Notify.instance.reschedule();
  } catch (e) {
    debugPrint('notify init failed: $e');
  }

  // 更新检查不阻塞启动：24 小时内只查一次，失败静默
  unawaited(UpdateController.instance.syncOnStart());

  runApp(const PlantingApp());
}
