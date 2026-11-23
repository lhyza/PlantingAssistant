import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/version.dart';
import 'downloader.dart';
import 'repo.dart';
import 'update_service.dart';

enum UpdatePhase { idle, checking, upToDate, available, downloading, verifying, ready, failed }

/// 更新状态机：检查 → 下载（系统 DownloadManager）→ 校验 → 安装。
///
/// 页面只需要监听这个 ChangeNotifier；退出 App 后下载仍在继续，
/// 下次进来调 [syncOnStart] 就能把进度接回来。
class UpdateController extends ChangeNotifier {
  UpdateController._();
  static final UpdateController instance = UpdateController._();

  static const String kSeenKey = 'update_seen_version';

  UpdatePhase phase = UpdatePhase.idle;
  UpdateInfo? info;
  String? error;
  String? apkPath;
  int downloadId = 0;
  int downloaded = 0;
  int total = 0;
  double fraction = 0;

  /// 已提示过的版本（红点/首页顶条只提示一次）
  String seenVersion = '';

  Timer? _timer;
  DateTime? _lastTick;
  int _lastBytes = 0;
  double _speed = 0;
  bool _busy = false;

  bool get hasUpdate => info != null && UpdateService.compareVersions(info!.version, kAppVersion) > 0;
  bool get downloading => phase == UpdatePhase.downloading;
  bool get busy => _busy || downloading || phase == UpdatePhase.checking || phase == UpdatePhase.verifying;
  bool get readyToInstall => phase == UpdatePhase.ready && (apkPath?.isNotEmpty ?? false);
  bool get unseen => hasUpdate && seenVersion != info!.version;

  String get speedText {
    if (_speed <= 0) return '';
    final mb = _speed / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB/s';
  }

  String get sizeText => DownloadProgress(downloaded: downloaded, total: total).sizeText;

  int get percent => total <= 0 ? 0 : (fraction * 100).round();

  // ---------------- 检查 ----------------

  /// 启动时调用：24 小时内检查过就直接用缓存，避免每次开 App 都联网。
  Future<void> syncOnStart({bool force = false}) async {
    seenVersion = await Repo.instance.setting(kSeenKey) ?? '';
    final last = await UpdateService.instance.lastCheckedAt();
    final fresh = last != null && DateTime.now().difference(last) < const Duration(hours: 24);
    if (!force && fresh) {
      info = await UpdateService.instance.cached();
      phase = hasUpdate ? _resumePhase() : UpdatePhase.idle;
      _restoreDownload();
      notifyListeners();
      return;
    }
    await check(force: force);
  }

  UpdatePhase _resumePhase() {
    // 上次已下载好（或下载中断）时，尽量恢复现场
    return UpdatePhase.available;
  }

  Future<void> check({bool force = true}) async {
    if (_busy) return;
    _busy = true;
    phase = UpdatePhase.checking;
    error = null;
    notifyListeners();
    try {
      final latest = await UpdateService.instance.fetchLatest();
      info = latest;
      phase = latest == null ? UpdatePhase.upToDate : UpdatePhase.available;
      if (latest == null) {
        await _clearDownloaded();
      }
    } on UpdateException catch (e) {
      error = e.message;
      phase = UpdatePhase.failed;
    } catch (e) {
      error = '检查更新失败：$e';
      phase = UpdatePhase.failed;
    } finally {
      _busy = false;
      notifyListeners();
    }
    if (phase == UpdatePhase.available) await _restoreDownload();
  }

  Future<void> markSeen() async {
    if (info == null) return;
    seenVersion = info!.version;
    await Repo.instance.setSetting(kSeenKey, seenVersion);
    notifyListeners();
  }

  // ---------------- 下载 ----------------

  Future<void> download() async {
    final target = info;
    if (target == null || downloading) return;
    phase = UpdatePhase.downloading;
    error = null;
    downloaded = 0;
    total = target.size;
    fraction = 0;
    _speed = 0;
    notifyListeners();

    final urls = UpdateService.mirrorUrls(target.url);
    String? last;
    for (final url in urls) {
      try {
        final r = await Downloader.start(
          url: url,
          fileName: target.fileName,
          title: '正在下载 ${kAppName} ${target.version}',
        );
        if (r.id <= 0) {
          last = '开始下载失败';
          continue;
        }
        downloadId = r.id;
        apkPath = r.path;
        await Repo.instance.setSetting('update_download_id', '${r.id}');
        await Repo.instance.setSetting('update_download_path', r.path);
        _startPolling();
        return;
      } catch (e) {
        last = '$e';
      }
    }
    phase = UpdatePhase.failed;
    error = '下载没能开始：${last ?? '未知错误'}';
    notifyListeners();
  }

  void _startPolling() {
    _timer?.cancel();
    _lastTick = DateTime.now();
    _lastBytes = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 700), (t) async {
      if (downloadId <= 0) {
        t.cancel();
        return;
      }
      try {
        final p = await Downloader.progress(downloadId);
        if (p.path.isNotEmpty) apkPath = p.path;
        downloaded = p.downloaded;
        if (p.total > 0) total = p.total;
        fraction = p.fraction;
        _calcSpeed(p.downloaded);
        if (p.successful) {
          t.cancel();
          await _verify();
        } else if (p.failed) {
          t.cancel();
          await _failDownload(p);
        } else {
          notifyListeners();
        }
      } catch (e) {
        t.cancel();
        phase = UpdatePhase.failed;
        error = '读取下载进度失败：$e';
        notifyListeners();
      }
    });
  }

  void _calcSpeed(int bytes) {
    final now = DateTime.now();
    final last = _lastTick;
    if (last != null) {
      final dt = now.difference(last).inMilliseconds;
      if (dt >= 400) {
        final delta = bytes - _lastBytes;
        if (delta >= 0) _speed = delta * 1000 / dt;
        _lastTick = now;
        _lastBytes = bytes;
      }
    } else {
      _lastTick = now;
      _lastBytes = bytes;
    }
  }

  Future<void> cancelDownload() async {
    _timer?.cancel();
    if (downloadId > 0) await Downloader.cancel(downloadId);
    downloadId = 0;
    _speed = 0;
    phase = hasUpdate ? UpdatePhase.available : UpdatePhase.idle;
    error = null;
    notifyListeners();
  }

  Future<void> _failDownload(DownloadProgress p) async {
    // 系统下载失败时自动换下一个镜像重试一次
    phase = UpdatePhase.failed;
    final hint = switch (p.reason) {
      1004 => '网络错误，换个网络再试',
      1006 => '文件保存失败，可能是空间不够',
      1008 => '下载被中断',
      1009 => '存储空间不足',
      1010 => '镜像拒绝了这次下载，换一个镜像再试',
      _ => '下载失败（代码 ${p.reason}）',
    };
    error = hint;
    notifyListeners();
  }

  // ---------------- 校验 ----------------

  Future<void> _verify() async {
    final target = info;
    final path = apkPath;
    phase = UpdatePhase.verifying;
    notifyListeners();
    if (target == null || path == null || path.isEmpty) {
      _fail('下载完成但找不到文件，请重新下载');
      return;
    }
    final f = File(path);
    if (!await f.exists()) {
      _fail('下载完成但文件不见了，请重新下载');
      return;
    }
    final len = await f.length();
    if (target.size > 0 && (len - target.size).abs() > 4096) {
      _fail('下载的文件大小不对（${(len / 1048576).toStringAsFixed(1)} MB，'
          '应为 ${target.sizeText}），请重新下载');
      return;
    }
    if (target.sha256.isNotEmpty) {
      final sha = await Downloader.sha256(path);
      if (sha.toLowerCase() != target.sha256) {
        _fail('文件校验失败（SHA-256 不一致），请重新下载');
        return;
      }
    }
    final apk = await Downloader.apkInfo(path);
    if (apk == null) {
      _fail('这个文件不是有效的安装包');
      return;
    }
    if (apk.packageName != kPackageName) {
      _fail('安装包包名不对（${apk.packageName}），已阻止安装');
      return;
    }
    if (apk.versionCode <= kVersionCode) {
      _fail('这个安装包的版本（${apk.versionName}）不比当前版本新，已阻止安装');
      return;
    }
    final self = await Downloader.selfCert();
    if (self.isNotEmpty && apk.certSha256.isNotEmpty && self != apk.certSha256) {
      _fail('安装包签名与当前 App 不一致，无法覆盖升级（请确认下载的是同一签名版本）');
      return;
    }
    phase = UpdatePhase.ready;
    error = null;
    notifyListeners();
  }

  void _fail(String msg) {
    phase = UpdatePhase.failed;
    error = msg;
    notifyListeners();
  }

  // ---------------- 安装 ----------------

  Future<void> install() async {
    final path = apkPath;
    if (path == null || path.isEmpty) return;
    try {
      await Downloader.install(path);
    } catch (e) {
      error = '打开安装器失败：$e';
      phase = UpdatePhase.failed;
      notifyListeners();
    }
  }

  // ---------------- 恢复现场 ----------------

  Future<void> _restoreDownload() async {
    final idStr = await Repo.instance.setting('update_download_id');
    final path = await Repo.instance.setting('update_download_path');
    final id = int.tryParse(idStr ?? '') ?? 0;
    if (id <= 0) return;
    apkPath = path;
    try {
      final p = await Downloader.progress(id);
      if (p.active) {
        downloadId = id;
        downloaded = p.downloaded;
        total = p.total > 0 ? p.total : (info?.size ?? 0);
        fraction = p.fraction;
        phase = UpdatePhase.downloading;
        _startPolling();
        notifyListeners();
      } else if (p.successful) {
        downloadId = id;
        if (p.path.isNotEmpty) apkPath = p.path;
        await _verify();
      } else if (p.failed && path != null && await File(path).exists()) {
        // 下载已完成过（例如已经校验通过但没安装），直接进入校验
        downloadId = id;
        await _verify();
      }
    } catch (_) {
      // 原生通道不可用时静默忽略
    }
  }

  Future<void> _clearDownloaded() async {
    final id = downloadId;
    _timer?.cancel();
    downloadId = 0;
    apkPath = null;
    downloaded = 0;
    total = 0;
    fraction = 0;
    if (id > 0) {
      try {
        await Downloader.clear(id);
      } catch (_) {}
    }
  }

  /// 版本更新页面打开时调用
  void ensureListenable() => notifyListeners();
}
