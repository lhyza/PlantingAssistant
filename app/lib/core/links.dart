import 'package:flutter/services.dart';

/// 备用下载渠道与源码地址。
///
/// 这里只放**静态文本**：App 自己不抓这些页面（没有网页解析、没有后台接口），
/// 点「打开」是把链接交给系统浏览器 / 对应 App（百度网盘、蓝奏云），
/// 点「复制」只是写进剪贴板。所以这些渠道挂了 / 改了，也不会影响 App 本身。

/// 百度网盘分享（含提取码，链接里已带 pwd）
const String kLinkBaidu =
    'https://pan.baidu.com/s/1cOum_7_tKs6HV8aL7dkKVw?pwd=t0r1';

/// 蓝奏云文件夹（需要单独输入密码）
const String kLinkLanzou = 'https://wwbvh.lanzouc.com/b01i61hhyb';

/// 蓝奏云密码
const String kLanzouPwd = 'f7we';

/// GitHub 仓库（Release 页里有 APK 与源码）
const String kLinkGithub = 'https://github.com/lhyza/PlantingAssistant';

/// 打开链接：走原生 `ACTION_VIEW`，交给系统浏览器或对应 App。
class Links {
  static const MethodChannel _ch = MethodChannel('planting/update');

  static Future<bool> open(String url) async {
    if (url.isEmpty) return false;
    try {
      final ok = await _ch.invokeMethod<bool>('open', {'url': url});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}
