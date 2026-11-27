import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../core/ui_prefs.dart';
import 'common.dart';

/// 我的 → 显示设置：操作记录里批次名的颜色 + 未施范围。
class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('显示设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: cardDeco(color: kGreenBg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: kGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '颜色用于今天页「近 15 天操作」和「全部记录」里的批次名，'
                    '记录详情页不受影响。',
                    style: tSub.copyWith(color: kGreen, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SectionTitle('操作记录'),
          ValueListenableBuilder<Color>(
            valueListenable: appliedNameColor,
            builder: (_, c, __) => _row(
              '施用批次名称',
              '打了药/肥/水的批次',
              c,
              () => _pick(isApplied: true),
              () => _reset(isApplied: true),
            ),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<Color>(
            valueListenable: skippedNameColor,
            builder: (_, c, __) => _row(
              '未施批次名称',
              '这次漏掉的批次',
              c,
              () => _pick(isApplied: false),
              () => _reset(isApplied: false),
            ),
          ),
          const SizedBox(height: 18),
          const SectionTitle('记录偏好'),
          ValueListenableBuilder<bool>(
            valueListenable: showSkippedRecords,
            builder: (_, on, __) => Container(
              decoration: cardDeco(),
              child: SwitchListTile(
                value: on,
                activeThumbColor: kRed,
                contentPadding: const EdgeInsets.fromLTRB(14, 2, 8, 2),
                title: Text(
                  '显示「未施」批次',
                  style: tBody.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '关闭后，操作记录列表、详情和记一笔预览都不显示未施批次；数据仍会照常记录。',
                  style: tTiny.copyWith(color: kInk3),
                ),
                onChanged: (v) async {
                  await UiPrefs.saveShowSkipped(v);
                  if (!mounted) return;
                  setState(() {});
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: cardDeco(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '未施范围',
                  style: tBody.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  '记一笔施肥/施药/浇水时，「未施」要算上哪些批次',
                  style: tTiny.copyWith(color: kInk3),
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<String>(
                  valueListenable: skipScope,
                  builder: (_, v, __) => ChoiceRow(
                    options: const ['算上其它作物', '仅同作物'],
                    value: v == kSkipScopeCrop ? '仅同作物' : '算上其它作物',
                    compact: true,
                    onChanged: (s) async {
                      await UiPrefs.saveSkipScope(
                        s == '仅同作物' ? kSkipScopeCrop : kSkipScopeAll,
                      );
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '只影响之后新记的记录，已经记过的不会变。',
                  style: tTiny.copyWith(color: kInk3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () async {
              await UiPrefs.reset();
              if (!mounted) return;
              setState(() {});
              toast(context, '已恢复默认设置');
            },
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('全部恢复默认'),
          ),
        ],
      ),
    );
  }

  Widget _row(
    String title,
    String sub,
    Color color,
    VoidCallback onTap,
    VoidCallback onReset,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: cardDeco(),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tBody.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$sub · ${hexOfColor(color)}',
                    style: tTiny.copyWith(color: kInk3),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '恢复默认',
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt, size: 18, color: kInk3),
            ),
            const Icon(Icons.chevron_right, size: 18, color: kInk3),
          ],
        ),
      ),
    );
  }

  Future<void> _reset({required bool isApplied}) async {
    final def = isApplied ? kDefaultAppliedColor : kDefaultSkippedColor;
    if (isApplied) {
      await UiPrefs.saveApplied(def);
    } else {
      await UiPrefs.saveSkipped(def);
    }
    if (!mounted) return;
    setState(() {});
    toast(context, '已恢复默认颜色');
  }

  Future<void> _pick({required bool isApplied}) async {
    final cur = isApplied ? appliedNameColor.value : skippedNameColor.value;
    final picked = await showModalBottomSheet<Color>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _PickSheet(
        initial: cur,
        defaultColor: isApplied ? kDefaultAppliedColor : kDefaultSkippedColor,
      ),
    );
    if (picked == null) return;
    if (isApplied) {
      await UiPrefs.saveApplied(picked);
    } else {
      await UiPrefs.saveSkipped(picked);
    }
    if (!mounted) return;
    setState(() {});
  }
}

class _PickSheet extends StatefulWidget {
  const _PickSheet({required this.initial, required this.defaultColor});
  final Color initial;
  final Color defaultColor;

  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  late Color value = widget.initial;
  late final TextEditingController ctrl = TextEditingController(
    text: hexOfColor(widget.initial),
  );

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _set(Color c) {
    setState(() {
      value = c;
      ctrl.text = hexOfColor(c);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: kLine,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '选择颜色',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('深色底色浅一点更清楚，也可能和类型徽章撞色', style: tTiny),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in [
                  ...kColors.map(colorOf),
                  kDefaultSkippedColor,
                  kDefaultAppliedColor,
                ])
                  GestureDetector(
                    onTap: () => _set(c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: c.toARGB32() == value.toARGB32()
                              ? kInk
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: value,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kLine),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      labelText: '自定义色值',
                      hintText: '#C2410C',
                    ),
                    onChanged: (v) {
                      final c = parseHexColor(v);
                      if (c != null) setState(() => value = c);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _set(widget.defaultColor),
                    child: const Text('默认'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, value),
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
