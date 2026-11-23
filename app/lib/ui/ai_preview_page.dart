import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/ai_import.dart';

/// 导入预览：先看清"新增 / 更新 / 合并 / 跳过"，确认后才写库
class AiPreviewPage extends StatefulWidget {
  const AiPreviewPage({super.key, required this.plan});

  final AiImportPlan plan;

  @override
  State<AiPreviewPage> createState() => _AiPreviewPageState();
}

class _AiPreviewPageState extends State<AiPreviewPage> {
  bool busy = false;

  AiImportPlan get p => widget.plan;

  int get _importable => p.importable;

  void _toggleAll(bool on) {
    setState(() {
      for (final it in p.items) {
        if (it.action != AiAction.skip) it.selected = on;
      }
    });
  }

  Future<void> _confirm() async {
    setState(() => busy = true);
    final res = await applyAiPlan(p);
    if (!mounted) return;
    setState(() => busy = false);
    Navigator.pop(context, res);
  }

  @override
  Widget build(BuildContext context) {
    final total = p.items.length;
    return Scaffold(
      appBar: AppBar(title: const Text('导入预览')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _header(),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('逐条确认', style: tBody),
              const Spacer(),
              TextButton(
                onPressed: () => _toggleAll(false),
                child: const Text('全不选'),
              ),
              TextButton(
                onPressed: () => _toggleAll(true),
                child: const Text('全选'),
              ),
            ],
          ),
          for (final it in p.items) _tile(it),
          if (total == 0) const EmptyHint(text: '没有解析到条目'),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: busy || _importable == 0 ? null : _confirm,
          child: Text(busy ? '正在写入…' : '确认导入 $_importable 条'),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 18, color: kInk2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.fileName.isEmpty ? 'AI 数据包' : p.fileName,
                  style: tBody,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('${p.kindLabel} · ${p.cropName}', style: tSub),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (p.addCount > 0) Pill('新增 ${p.addCount}', bg: kGreenBg, fg: kGreen),
              if (p.updateCount > 0) Pill('更新 ${p.updateCount}', bg: kBlueBg, fg: kBlue),
              if (p.mergeCount > 0) Pill('合并 ${p.mergeCount}', bg: kAmberBg, fg: kAmber),
              if (p.skipCount > 0) Pill('跳过 ${p.skipCount}', bg: const Color(0xFFF2F0ED), fg: kInk2),
            ],
          ),
          if (p.warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final w in p.warnings) Text('· $w', style: tTiny),
          ],
          if (p.items.any((i) => i.action != AiAction.skip)) ...[
            const SizedBox(height: 10),
            const Text(
              '未勾选的条目不会写入；「合并」会把内容更新到已有的同名条目上。',
              style: tTiny,
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile(AiPlanItem it) {
    final skip = it.action == AiAction.skip;
    final color = switch (it.action) {
      AiAction.add => kGreen,
      AiAction.update => kBlue,
      AiAction.merge => kAmber,
      AiAction.skip => kInk3,
    };
    final label = switch (it.action) {
      AiAction.add => '新增',
      AiAction.update => '更新',
      AiAction.merge => '合并',
      AiAction.skip => '跳过',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: cardDeco(),
      child: CheckboxListTile(
        value: skip ? false : it.selected,
        onChanged: skip ? null : (v) => setState(() => it.selected = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: kRed,
        title: Row(
          children: [
            Expanded(child: Text(it.name, style: tBody)),
            Pill(label, bg: color.withValues(alpha: .10), fg: color),
          ],
        ),
        subtitle: Text(it.reason, style: tTiny),
        dense: true,
      ),
    );
  }
}
