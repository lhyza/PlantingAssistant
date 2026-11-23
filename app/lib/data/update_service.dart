import 'dart:convert';
import 'dart:io';

import '../core/version.dart';
import 'repo.dart';

/// 更新检查失败（消息可直接展示给用户）。
class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 一条 GitHub Release 里我们关心的信息。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.url,
    required this.fileName,
    required this.size,
    required this.sha256,
    this.publishedAt,
  });

  /// 去掉前缀 v 的版本号，如 1.5.0
  final String version;
  final String tag;
  final String notes;
  final String url;
  final String fileName;
  final int size;

  /// 小写十六进制；Release 没提供摘要时为空串
  final String sha256;
  final DateTime? publishedAt;

  String get sizeText {
    if (size <= 0) return '';
    final mb = size / (1024 * 1024);
    return mb >= 100 ? '${mb.toStringAsFixed(0)} MB' : '${mb.toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'tag': tag,
        'notes': notes,
        'url': url,
        'fileName': fileName,
        'size': size,
        'sha256': sha256,
        'publishedAt': publishedAt?.toIso8601String(),
      };

  static UpdateInfo fromJson(Map<String, dynamic> m) => UpdateInfo(
        version: (m['version'] as String?) ?? '',
        tag: (m['tag'] as String?) ?? '',
        notes: (m['notes'] as String?) ?? '',
        url: (m['url'] as String?) ?? '',
        fileName: (m['fileName'] as String?) ?? '',
        size: (m['size'] as int?) ?? 0,
        sha256: (m['sha256'] as String?) ?? '',
        publishedAt: DateTime.tryParse((m['publishedAt'] as String?) ?? ''),
      );
}

/// 检查更新 + 缓存 + 镜像选择。
///
/// 说明：日常功能完全离线，只有「检查更新 / 下载新版本」这两步联网，
/// 数据不会因为更新功能上传到任何地方。
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String kApi = 'https://api.github.com/repos/$kRepoSlug/releases/latest';

  /// 直连 github.com 在国内经常超时，按顺序优先用镜像。
  static const List<String> kMirrors = [
    'https://ghfast.top/',
    'https://gh-proxy.com/',
  ];

  static const String kCacheKey = 'update_latest';
  static const String kCheckedAtKey = 'update_checked_at';

  /// 同一个下载地址的候选列表：镜像优先，最后才是直连。
  static List<String> mirrorUrls(String url) => [
        for (final m in kMirrors) '$m$url',
        url,
      ];

  /// 版本号比较：a>b 返回正数，相等 0，a<b 负数。只按数字段比较。
  static int compareVersions(String a, String b) {
    int at(String v) => v.indexOf('+') > 0 ? v.indexOf('+') : v.length;
    final pa = _parts(a.substring(0, at(a)));
    final pb = _parts(b.substring(0, at(b)));
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  static List<int> _parts(String v) => v
      .replaceAll(RegExp(r'^v', caseSensitive: false), '')
      .split(RegExp(r'[.-]'))
      .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();

  /// 有比当前版本更新的版本时返回它，否则 null。
  Future<UpdateInfo?> fetchLatest({Duration timeout = const Duration(seconds: 15)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.parse(kApi)).timeout(timeout);
      req.headers.set(HttpHeaders.userAgentHeader, 'PlantingAssistant/$kAppVersion (Android)');
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(timeout);
      if (res.statusCode == 404) {
        throw UpdateException('GitHub 上还没有发布版本');
      }
      if (res.statusCode == 403 || res.statusCode == 429) {
        throw UpdateException('检查更新太频繁，被 GitHub 限流了，请过一会儿再试');
      }
      if (res.statusCode != 200) {
        throw UpdateException('检查更新失败（HTTP ${res.statusCode}）');
      }
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      final info = _parse(jsonDecode(body));
      await saveCache(info);
      return compareVersions(info.version, kAppVersion) > 0 ? info : null;
    } on UpdateException {
      rethrow;
    } on SocketException {
      throw UpdateException('网络连接失败，请检查手机网络后重试');
    } on HandshakeException {
      throw UpdateException('连接 GitHub 失败，请稍后重试或换个网络');
    } on FormatException {
      throw UpdateException('GitHub 返回的数据看不懂，请稍后重试');
    } catch (e) {
      throw UpdateException('检查更新失败：$e');
    } finally {
      client.close(force: true);
    }
  }

  UpdateInfo _parse(dynamic data) {
    if (data is! Map) throw UpdateException('GitHub 返回的数据格式不对');
    final tag = (data['tag_name'] as String?) ?? '';
    final version = tag.replaceAll(RegExp(r'^v', caseSensitive: false), '');
    if (version.isEmpty) throw UpdateException('这个 Release 没有版本号');

    final assets = (data['assets'] as List?) ?? const [];
    Map? apk;
    for (final a in assets) {
      if (a is! Map) continue;
      final name = (a['name'] as String?) ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        apk = a;
        break;
      }
    }
    if (apk == null) throw UpdateException('这个 Release 里没有 APK 文件');

    final digest = (apk['digest'] as String?) ?? '';
    final sha = digest.toLowerCase().startsWith('sha256:') ? digest.substring(7) : digest;
    return UpdateInfo(
      version: version,
      tag: tag,
      notes: (data['body'] as String?) ?? '',
      url: (apk['browser_download_url'] as String?) ?? '',
      fileName: (apk['name'] as String?) ?? 'PlantingAssistant-$version-release.apk',
      size: (apk['size'] as int?) ?? 0,
      sha256: sha.trim().toLowerCase(),
      publishedAt: DateTime.tryParse((data['published_at'] as String?) ?? ''),
    );
  }

  // ---------------- 缓存 ----------------

  Future<UpdateInfo?> cached() async {
    final raw = await Repo.instance.setting(kCacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      return UpdateInfo.fromJson(m.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCache(UpdateInfo info) async {
    await Repo.instance.setSetting(kCacheKey, jsonEncode(info.toJson()));
    await Repo.instance.setSetting(kCheckedAtKey, DateTime.now().toIso8601String());
  }

  Future<DateTime?> lastCheckedAt() async {
    final v = await Repo.instance.setting(kCheckedAtKey);
    return v == null ? null : DateTime.tryParse(v);
  }
}
