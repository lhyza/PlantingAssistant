import 'package:flutter/services.dart';

/// 下载进度（来自系统 DownloadManager）。
class DownloadProgress {
  const DownloadProgress({
    this.id = 0,
    this.status = 'unknown',
    this.downloaded = 0,
    this.total = 0,
    this.reason = 0,
    this.path = '',
  });

  final int id;
  final String status;
  final int downloaded;
  final int total;
  final int reason;
  final String path;

  bool get pending => status == 'pending';
  bool get running => status == 'running';
  bool get paused => status == 'paused';
  bool get successful => status == 'successful';
  bool get failed => status == 'failed';
  bool get active => pending || running || paused;

  double get fraction {
    if (total <= 0) return 0;
    final v = downloaded / total;
    return v.clamp(0.0, 1.0);
  }

  String get sizeText {
    if (total <= 0) return _mb(downloaded);
    return '${_mb(downloaded)} / ${_mb(total)}';
  }

  static String _mb(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return mb >= 100 ? '${mb.toStringAsFixed(0)} MB' : '${mb.toStringAsFixed(1)} MB';
  }
}

/// 安装包信息（读取 APK 的 manifest 与签名）。
class ApkInfo {
  const ApkInfo({
    required this.packageName,
    required this.versionCode,
    required this.versionName,
    required this.certSha256,
  });

  final String packageName;
  final int versionCode;
  final String versionName;
  final String certSha256;
}

/// 原生下载/安装桥（Android：DownloadManager + FileProvider）。
///
/// 之所以不用 Dart 下载：系统 DownloadManager 在 App 退到后台/被杀死后
/// 仍然继续下载，并且自带通知栏进度，这是用户明确要求的行为。
class Downloader {
  static const MethodChannel _ch = MethodChannel('planting/update');

  static Future<({int id, String path})> start({
    required String url,
    required String fileName,
    required String title,
    bool metered = false,
  }) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('start', {
      'url': url,
      'fileName': fileName,
      'title': title,
      'metered': metered,
    });
    return (id: (r?['id'] as int?) ?? -1, path: (r?['path'] as String?) ?? '');
  }

  static Future<DownloadProgress> progress(int id) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('progress', {'id': id});
    if (r == null) return const DownloadProgress();
    return DownloadProgress(
      id: (r['id'] as int?) ?? id,
      status: (r['status'] as String?) ?? 'unknown',
      downloaded: (r['downloaded'] as int?) ?? 0,
      total: (r['total'] as int?) ?? 0,
      reason: (r['reason'] as int?) ?? 0,
      path: (r['path'] as String?) ?? '',
    );
  }

  static Future<void> cancel(int id) async {
    if (id <= 0) return;
    await _ch.invokeMethod<bool>('cancel', {'id': id});
  }

  static Future<void> install(String path) async {
    await _ch.invokeMethod<bool>('install', {'path': path});
  }

  static Future<ApkInfo?> apkInfo(String path) async {
    final r = await _ch.invokeMapMethod<String, dynamic>('apkInfo', {'path': path});
    if (r == null) return null;
    return ApkInfo(
      packageName: (r['packageName'] as String?) ?? '',
      versionCode: (r['versionCode'] as int?) ?? 0,
      versionName: (r['versionName'] as String?) ?? '',
      certSha256: (r['certSha256'] as String?) ?? '',
    );
  }

  static Future<String> sha256(String path) async {
    final v = await _ch.invokeMethod<String>('sha256', {'path': path});
    return v ?? '';
  }

  static Future<String> selfCert() async {
    final v = await _ch.invokeMethod<String>('selfCert');
    return v ?? '';
  }

  static Future<int> freeSpace() async {
    final v = await _ch.invokeMethod<int>('freeSpace');
    return v ?? -1;
  }

  static Future<void> clear(int id) async {
    await _ch.invokeMethod<bool>('clear', {'id': id});
  }
}
