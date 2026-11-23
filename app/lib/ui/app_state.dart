import 'package:flutter/foundation.dart';

/// 全局刷新信号：数据变更后 bump()，各页面监听后重新加载
final ValueNotifier<int> refreshTick = ValueNotifier<int>(0);

void bump() => refreshTick.value++;
