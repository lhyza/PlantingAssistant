import 'package:flutter/material.dart';

import '../data/repo.dart';

/// 今天页 / 全部记录里「操作记录」批次名的颜色。
/// 只影响列表，不影响记录详情页。
///
/// 默认给两个不同深浅的橙，便于一眼区分「打了哪些 / 漏了哪些」。
const Color kDefaultAppliedColor = Color(0xFFC2410C); // 深橙
const Color kDefaultSkippedColor = Color(0xFFE0862B); // 橙

final ValueNotifier<Color> appliedNameColor =
    ValueNotifier<Color>(kDefaultAppliedColor);
final ValueNotifier<Color> skippedNameColor =
    ValueNotifier<Color>(kDefaultSkippedColor);

/// 「未施」的范围：
/// - `all`（默认）：别的作物里这次没处理的批次也算未施
/// - `crop`：只算这次参与过的作物
const String kSkipScopeAll = 'all';
const String kSkipScopeCrop = 'crop';

/// 今天页顶部选中的作物；`all` 表示「全部作物」，空串表示还没选过。
const String kTodayAll = 'all';

final ValueNotifier<String> skipScope = ValueNotifier<String>(kSkipScopeAll);

bool get skipAcrossCrops => skipScope.value != kSkipScopeCrop;

/// `#RRGGBB` / `#AARRGGBB` / 不带 # 都接受，非法返回 null。
Color? parseHexColor(String s) {
  var t = s.trim().replaceAll('#', '');
  if (t.length == 6) t = 'FF$t';
  if (t.length != 8) return null;
  final v = int.tryParse(t, radix: 16);
  return v == null ? null : Color(v);
}

String hexOfColor(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class UiPrefs {
  static Future<void> load() async {
    appliedNameColor.value =
        parseHexColor(await Repo.instance.setting('color.applied') ?? '') ??
            kDefaultAppliedColor;
    skippedNameColor.value =
        parseHexColor(await Repo.instance.setting('color.skipped') ?? '') ??
            kDefaultSkippedColor;
    final scope = await Repo.instance.setting('skip.scope');
    skipScope.value = scope == kSkipScopeCrop ? kSkipScopeCrop : kSkipScopeAll;
  }

  static Future<void> saveApplied(Color c) async {
    appliedNameColor.value = c;
    await Repo.instance.setSetting('color.applied', hexOfColor(c));
  }

  static Future<void> saveSkipped(Color c) async {
    skippedNameColor.value = c;
    await Repo.instance.setSetting('color.skipped', hexOfColor(c));
  }

  static Future<void> saveSkipScope(String scope) async {
    skipScope.value = scope == kSkipScopeCrop ? kSkipScopeCrop : kSkipScopeAll;
    await Repo.instance.setSetting('skip.scope', skipScope.value);
  }

  static Future<void> reset() async {
    await saveApplied(kDefaultAppliedColor);
    await saveSkipped(kDefaultSkippedColor);
    await saveSkipScope(kSkipScopeAll);
  }
}
