import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/ai_import.dart';
import '../data/ai_prompt.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'ai_preview_page.dart';
import 'common.dart';

/// AI 模板页：选作物 → 贴链接 → 生成提示词 → 复制给 AI → 回来导入 zip。
class AiTemplatePage extends StatefulWidget {
  const AiTemplatePage({super.key, required this.cropId, this.kind = 'variety'});
  final String cropId;
  final String kind; // variety | pest

  @override
  State<AiTemplatePage> createState() => _AiTemplatePageState();
}

class _AiTemplatePageState extends State<AiTemplatePage> {
  final _links = TextEditingController();
  List<Crop> crops = const [];
  late String cropId = widget.cropId;
  late String kind = widget.kind;
  String prompt = '';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _links.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cs = await Repo.instance.crops();
    if (mounted) setState(() => crops = cs);
  }

  Crop? get _crop {
    for (final c in crops) {
      if (c.id == cropId) return c;
    }
    return crops.isEmpty ? null : crops.first;
  }

  void _generate() {
    final links = _links.text
        .split(RegExp(r'[\n\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    setState(() {
      prompt = buildAiPrompt(
        cropName: _crop?.name ?? '草莓',
        kind: kind,
        links: links,
      );
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: prompt));
    if (mounted) toast(context, '已复制，粘贴给豆包/DeepSeek 等 AI');
  }

  Future<void> _share() async {
    await SharePlus.instance.share(
      ShareParams(text: prompt, subject: '种植助手 · AI 提示词'),
    );
  }

  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip', 'json'],
    );
    if (picked == null || picked.isEmpty) return;
    final f = picked.first;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    setState(() => busy = true);
    final plan = await previewAiData(
      bytes: bytes,
      cropId: cropId,
      expectedKind: kind,
      fileName: f.name,
    );
    if (!mounted) return;
    setState(() => busy = false);

    if (!plan.ok) {
      await _errorDialog('${plan.error}\n\n$kAiPackHint');
      return;
    }
    if (plan.importable == 0) {
      await _errorDialog(
        '这个文件里没有可导入的条目。\n\n'
        '新增 ${plan.addCount} · 更新 ${plan.updateCount} · '
        '合并 ${plan.mergeCount} · 跳过 ${plan.skipCount}',
      );
      return;
    }
    final res = await Navigator.push<AiImportResult>(
      context,
      MaterialPageRoute(builder: (_) => AiPreviewPage(plan: plan)),
    );
    if (res == null || !mounted) return;
    await _resultDialog(res);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _errorDialog(String msg) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入失败'),
          content: SingleChildScrollView(child: Text(msg)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );

  Future<void> _resultDialog(AiImportResult res) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入完成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${aiKindName(res.kind)} · ${res.cropName}'),
              const SizedBox(height: 8),
              Text('新增 ${res.added} 条 · 更新 ${res.updated} 条 · 合并 ${res.merged} 条'),
              if (res.skipped > 0) Text('跳过 ${res.skipped} 条'),
              if (res.failed > 0) Text('失败 ${res.failed} 条'),
              if (res.pending > 0)
                Text('保存了 ${res.images} 张图片，列表里带「!」的点开可以裁剪'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('好'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 模板')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
            decoration: cardDeco(color: kGreenBg, border: const Color(0xFFCBE7DA)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, size: 17, color: kGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '把下面的提示词复制给豆包、DeepSeek 等 AI，让它读你给的链接并生成数据包；'
                    'AI 给你 zip 后回到这里导入。App 本身不联网，只是读你保存的文件。',
                    style: tSub.copyWith(color: const Color(0xFF2C6B52), height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const FormLabel('作物'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: crops.map((c) {
              final on = c.id == cropId;
              final col = colorOf(c.color);
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => cropId = c.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: on ? col.withValues(alpha: .12) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: on ? col.withValues(alpha: .45) : kLine,
                    ),
                  ),
                  child: Text(
                    '${c.emoji} ${c.name}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                      color: on ? col : kInk2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          const FormLabel('知识类型'),
          ChoiceRow(
            options: const ['品种', '病虫害'],
            value: aiKindName(kind),
            onChanged: (v) => setState(() => kind = v == '病虫害' ? 'pest' : 'variety'),
          ),
          const SizedBox(height: 14),
          const FormLabel('资料链接'),
          TextField(
            controller: _links,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: '一行一个链接，可以贴 1 个或多个\nhttps://…',
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _generate,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('生成提示词'),
          ),
          if (prompt.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                const Text(
                  '提示词',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('复制'),
                  style: TextButton.styleFrom(foregroundColor: kRed),
                ),
                TextButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.ios_share, size: 15),
                  label: const Text('分享'),
                  style: TextButton.styleFrom(foregroundColor: kInk2),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
              decoration: cardDeco(color: const Color(0xFFFBFBFA)),
              child: SelectableText(
                prompt,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.55,
                  color: kInk2,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '提示词里已经写明「最多 20 条、必须给 zip、data.json 的结构」，'
              'AI 照着做就能直接被本 App 识别。',
              style: tTiny,
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: busy ? null : _import,
            icon: busy
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_zip_outlined, size: 18),
            label: Text(busy ? '正在导入…' : '导入 AI 数据包（zip）'),
          ),
          const SizedBox(height: 6),
          const Text(kAiPackHint, style: tTiny),
        ],
      ),
    );
  }
}
