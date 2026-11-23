import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../core/version.dart';
import '../data/update_controller.dart';
import '../data/update_service.dart';
import 'common.dart';

/// 版本更新页：检查、下载（进度与通知栏同步）、校验、安装。
class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key, this.autoCheck = false});
  final bool autoCheck;

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  final UpdateController c = UpdateController.instance;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    c.markSeen();
    if (widget.autoCheck || (c.info == null && !c.busy)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.check());
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('版本更新')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _versionCard(),
          const SizedBox(height: 14),
          ..._body(),
          const SizedBox(height: 18),
          _notes(),
        ],
      ),
    );
  }

  Widget _versionCard() {
    final info = c.info;
    final hasNew = c.hasUpdate && info != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDeco(),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hasNew ? kAmberBg : kGreenBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(hasNew ? '🎉' : '✅', style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前版本 $kAppVersion ($kVersionCode)', style: tBody),
                const SizedBox(height: 3),
                Text(
                  hasNew ? '最新版本 ${info.version}' : '已经是最新版本',
                  style: tSub.copyWith(
                    color: hasNew ? kAmber : kGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body() {
    switch (c.phase) {
      case UpdatePhase.checking:
        return [const _Wait('正在检查更新…')];
      case UpdatePhase.verifying:
        return [const _Wait('正在校验安装包…')];
      case UpdatePhase.upToDate:
        return [
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => c.check(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('再检查一次'),
            ),
          ),
        ];
      case UpdatePhase.available:
        return [
          Text(
            c.info!.sizeText.isEmpty ? '有新版本可用' : '有新版本可用 · ${c.info!.sizeText}',
            style: tSub,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: c.download,
              icon: const Icon(Icons.download, size: 20),
              label: Text('下载 ${c.info?.version ?? ''}'),
            ),
          ),
        ];
      case UpdatePhase.downloading:
        return [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('下载中 ${c.percent}%', style: tBody.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    if (c.speedText.isNotEmpty) Text(c.speedText, style: tTiny),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: c.total > 0 ? c.fraction : null,
                    minHeight: 8,
                    backgroundColor: kLine,
                    color: kRed,
                  ),
                ),
                const SizedBox(height: 6),
                Text(c.sizeText, style: tTiny),
                const SizedBox(height: 4),
                Text('可以退出这个页面，下载会继续（通知栏也能看到进度）', style: tTiny),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: c.cancelDownload,
              child: const Text('取消下载'),
            ),
          ),
        ];
      case UpdatePhase.ready:
        return [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(color: kGreenBg, border: kGreen.withValues(alpha: 0.3)),
            child: Row(
              children: [
                const Icon(Icons.verified_outlined, color: kGreen, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('安装包已校验通过，可以安装了', style: tBody.copyWith(color: kGreen))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: c.install,
              icon: const Icon(Icons.system_update_alt, size: 20),
              label: const Text('安装新版本'),
            ),
          ),
          const SizedBox(height: 8),
          Text('安装时系统会弹出「是否允许安装应用」，选允许即可。', style: tTiny),
        ];
      case UpdatePhase.failed:
        return [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(color: kRedBg, border: kRed.withValues(alpha: 0.25)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.error ?? '出错了', style: tBody.copyWith(color: kRedDeep)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => c.check(),
                      child: const Text('重新检查'),
                    ),
                    if (c.info != null)
                      TextButton(
                        onPressed: c.download,
                        child: const Text('重新下载'),
                      ),
                    if (c.apkPath != null)
                      TextButton(
                        onPressed: c.install,
                        child: const Text('打开安装器'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (c.info != null) ...[
            const SizedBox(height: 10),
            Text('网络慢或一直失败时，可以复制下载链接，用浏览器打开下载：', style: tTiny),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.info!.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tTiny,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: c.info!.url));
                    if (context.mounted) toast(context, '下载链接已复制');
                  },
                  child: const Text('复制'),
                ),
              ],
            ),
          ],
        ];
      case UpdatePhase.idle:
        return [
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: () => c.check(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('检查更新'),
            ),
          ),
        ];
    }
  }

  Widget _notes() {
    final info = c.info;
    if (info == null || info.notes.trim().isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('更新说明'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: cardDeco(),
          child: SelectableText(
            info.notes.trim(),
            style: tSub.copyWith(height: 1.6),
          ),
        ),
      ],
    );
  }
}

class _Wait extends StatelessWidget {
  const _Wait(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(text, style: tSub),
        ],
      ),
    );
  }
}
