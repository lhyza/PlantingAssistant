import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/images.dart';
import 'core/ui_prefs.dart';
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
    // v1.7 编辑阶段时漏传 season，可能把阶段存进了别的季：按 id 归位（幂等）
    await Repo.instance.normalizeStageSeasons();
    // v1.8.4：「喷雾（叶背）」统一成半角括号（幂等）
    await Repo.instance.normalizeMethodNames();
    // 显示设置：批次名颜色、未施范围（可在「我的 → 显示设置」改）
    await UiPrefs.load();
    // v1.9：老记录补一份「未施」快照，只跑一次
    if (await Repo.instance.setting('migrate.skipBackfill') != 'v1.9') {
      await Repo.instance.backfillOpSkipped(acrossCrops: skipAcrossCrops);
      await Repo.instance.setSetting('migrate.skipBackfill', 'v1.9');
    }
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
