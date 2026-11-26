import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/notify.dart';
import '../data/repo.dart';
import 'app_state.dart';
import 'common.dart';
import 'image_tile.dart';
import 'record_edit.dart' show kindEmojiOf;

/// 完成一次提醒：选择完成日期 → 滚动到下次到期
Future<void> finishReminder(BuildContext context, Reminder r) async {
  if (!r.active) {
    await toast(context, '这条提醒已经结束了');
    return;
  }
  var done = DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setD) => AlertDialog(
        title: Text(
          r.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('完成日期', style: tSub),
            const SizedBox(height: 6),
            InkWell(
              onTap: () async {
                final d = await pickDate(ctx2, done);
                if (d != null) setD(() => done = d);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: kLine),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(fmtDay(done), style: const TextStyle(fontSize: 14)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              r.isOneTime
                  ? '这是一次性提醒，完成后会结束。'
                  : '完成后，下次到期日 = ${fmtDay(done)} + ${r.intervalDays} 天。',
              style: tTiny,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx2, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx2, true),
            child: const Text(
              '完成',
              style: TextStyle(fontWeight: FontWeight.w700, color: kGreen),
            ),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  await Repo.instance.completeReminder(r, doneAt: done);
  await Repo.instance.logReminderDone(
    items: [r],
    done: done,
    nextDueAt: r.isOneTime ? '' : r.nextDueAt,
  );
  await Notify.instance.reschedule();
  bump();
  if (context.mounted) {
    toast(context, r.isOneTime ? '已完成' : '完成，下次 ${r.nextDueAt}');
  }
}

class ReminderEditPage extends StatefulWidget {
  const ReminderEditPage({
    super.key,
    this.reminderId,
    this.batchId,
    this.groupId,
  });

  final String? reminderId;

  /// 新建时预选的批次
  final String? batchId;

  /// 编辑一组（多批次一起建）的提醒时传 groupId
  final String? groupId;

  @override
  State<ReminderEditPage> createState() => _ReminderEditPageState();
}

class _ReminderEditPageState extends State<ReminderEditPage> {
  final Repo repo = Repo.instance;
  final _title = TextEditingController();
  final _interval = TextEditingController(text: '7');
  final _notes = TextEditingController();

  List<Batch> batches = [];
  List<Crop> crops = [];
  final Set<String> selected = {};
  List<Reminder> groupItems = [];
  String kind = '施肥';
  String nextDue = todayStr();
  bool oneTime = false;
  bool active = true;
  bool loading = true;
  Reminder? origin;

  bool get isNew => widget.reminderId == null;
  bool get isGroup => widget.groupId != null && widget.groupId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _interval.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    batches = await repo.batches();
    crops = await repo.crops();
    if (widget.reminderId != null) {
      origin = await repo.reminder(widget.reminderId!);
      if (origin != null) {
        kind = origin!.kind;
        nextDue = origin!.nextDueAt.isEmpty ? todayStr() : origin!.nextDueAt;
        oneTime = origin!.isOneTime;
        active = origin!.active;
        _title.text = origin!.title;
        _notes.text = origin!.notes;
        _interval.text =
            '${origin!.intervalDays <= 0 ? 7 : origin!.intervalDays}';
        selected.add(origin!.batchId);
        if (isGroup) {
          groupItems = await repo.reminderGroup(widget.groupId!);
        }
      }
    } else if (widget.batchId != null && widget.batchId!.isNotEmpty) {
      selected.add(widget.batchId!);
    } else if (batches.isNotEmpty) {
      selected.add(batches.first.id);
    }
    if (!mounted) return;
    setState(() => loading = false);
  }

  String _cropName(String id) {
    for (final c in crops) {
      if (c.id == id) return c.name;
    }
    return '未分类';
  }

  Crop? _cropOf(String id) {
    for (final c in crops) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      await toast(context, '写个标题吧，比如「高磷促花肥」');
      return;
    }
    if (isNew && selected.isEmpty) {
      await toast(context, '至少选一个批次');
      return;
    }
    final interval = int.tryParse(_interval.text.trim()) ?? 0;
    if (!oneTime && interval <= 0) {
      await toast(context, '间隔天数要大于 0');
      return;
    }

    if (isGroup) {
      for (final r in groupItems) {
        r.kind = normKind(kind);
        r.title = title;
        r.intervalDays = oneTime ? 0 : interval;
        r.nextDueAt = nextDue;
        r.isOneTime = oneTime;
        r.notes = _notes.text.trim();
        r.active = true;
      }
      await repo.saveReminderBatch(groupItems);
    } else if (!isNew) {
      final r = origin!;
      r.kind = normKind(kind);
      r.title = title;
      r.intervalDays = oneTime ? 0 : interval;
      r.nextDueAt = nextDue;
      r.isOneTime = oneTime;
      r.active = active || true;
      r.notes = _notes.text.trim();
      await repo.saveReminder(r);
    } else {
      final groupId = selected.length > 1 ? newId('rg') : '';
      final list = <Reminder>[];
      for (final bid in selected) {
        list.add(
          Reminder(
            id: newId('rem'),
            batchId: bid,
            kind: normKind(kind),
            title: title,
            intervalDays: oneTime ? 0 : interval,
            nextDueAt: nextDue,
            isOneTime: oneTime,
            notes: _notes.text.trim(),
            groupId: groupId,
          ),
        );
      }
      await repo.saveReminderBatch(list);
    }
    await Notify.instance.reschedule();
    bump();
    if (!mounted) return;
    Navigator.pop(context, true);
    await toast(
      context,
      isNew && selected.length > 1
          ? '已为 ${selected.length} 个批次创建提醒'
          : '已保存',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '新建提醒' : (isGroup ? '编辑这组提醒' : '编辑提醒')),
        actions: [
          if (origin != null)
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () async {
                final ok = await confirm(context, '删除这条提醒？');
                if (ok) {
                  await repo.softDeleteReminder(origin!.id);
                  await Notify.instance.reschedule();
                  bump();
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          TextButton(
            onPressed: loading ? null : _save,
            child: const Text(
              '保存',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
              children: [
                const FormLabel('类型'),
                ChoiceRow(
                  options: const ['施肥', '施药', '浇水', '其他'],
                  value: kind,
                  onChanged: (v) => setState(() => kind = v),
                ),
                if (kind.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('${kindEmojiOf(kind)} $kind', style: tTiny),
                  ),
                const FormLabel('标题', required: true),
                TextField(
                  controller: _title,
                  decoration: const InputDecoration(hintText: '高磷促花肥 / 白粉病预防'),
                ),
                const FormLabel('批次', required: true),
                if (isNew) ...[_batchPicker()] else _batchFixed(),
                const FormLabel('下次到期日', required: true),
                PickTile(
                  label: '',
                  value: nextDue,
                  onTap: () async {
                    final d = await pickDate(
                      context,
                      parseDay(nextDue) ?? DateTime.now(),
                    );
                    if (d != null) setState(() => nextDue = fmtDay(d));
                  },
                ),
                const FormLabel('重复'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _interval,
                        keyboardType: TextInputType.number,
                        enabled: !oneTime,
                        decoration: const InputDecoration(suffixText: '天一次'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => oneTime = !oneTime),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: oneTime ? kAmberBg : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: oneTime ? kAmber : kLine),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                oneTime
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                size: 18,
                                color: oneTime ? kAmber : kInk3,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                '只做一次',
                                style: TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  oneTime
                      ? '一次性提醒：完成后自动结束，不再提醒。'
                      : '循环提醒：每完成一次，下次到期日 = 完成日 + 间隔天数。',
                  style: tTiny,
                ),
                const FormLabel('备注'),
                AutoField(controller: _notes, hint: '剂量、注意事项…', minLines: 2),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: _save,
                  child: Text(
                    isNew
                        ? (selected.length > 1
                              ? '为 ${selected.length} 个批次添加提醒'
                              : '添加提醒')
                        : '保存',
                  ),
                ),
                if (origin != null && !isGroup) ...[
                  const SizedBox(height: 8),
                  Text(
                    '上次完成：${origin!.lastDoneAt.isEmpty ? '还没完成过' : origin!.lastDoneAt}',
                    style: tTiny,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _batchFixed() {
    final list = isGroup ? groupItems : (origin == null ? <Reminder>[] : [origin!]);
    final names = <String>[];
    for (final r in list) {
      for (final b in batches) {
        if (b.id == r.batchId) names.add(b.name);
      }
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 15, color: kInk3),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              names.isEmpty ? '—' : names.join('、'),
              style: const TextStyle(fontSize: 13.5, color: kInk2),
            ),
          ),
          if (names.length > 1)
            Pill('${names.length} 个批次', bg: kBlueBg, fg: kBlue),
        ],
      ),
    );
  }

  Widget _batchPicker() {
    if (batches.isEmpty) {
      return const Text('还没有批次，先去「批次」里建一个', style: TextStyle(color: kRed));
    }
    // 按作物分组，没有批次的作物不显示
    final byCrop = <String, List<Batch>>{};
    for (final b in batches) {
      byCrop.putIfAbsent(b.crop, () => []).add(b);
    }
    final sections = <Widget>[];
    for (final entry in byCrop.entries) {
      final list = entry.value;
      final ids = list.map((b) => b.id).toSet();
      final allOn = ids.every(selected.contains);
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Row(
            children: [
              if (_cropOf(entry.key) == null)
                Text(
                  '🌿 ${_cropName(entry.key)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kInk2,
                  ),
                )
              else
                cropLabel(
                  _cropOf(entry.key)!,
                  size: 17,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kInk2,
                  ),
                ),
              const SizedBox(width: 6),
              Text('${list.length}', style: tTiny),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (allOn) {
                      selected.removeAll(ids);
                    } else {
                      selected.addAll(ids);
                    }
                  });
                },
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  allOn ? '取消全选' : '全选',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      );
      for (final b in list) {
        final on = selected.contains(b.id);
        sections.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  if (on) {
                    selected.remove(b.id);
                  } else {
                    selected.add(b.id);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: on ? kRedBg.withValues(alpha: 0.6) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: on ? kRed.withValues(alpha: 0.5) : kLine,
                    width: on ? 1.3 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      on ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 19,
                      color: on ? kRed : kInk3,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        b.name,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                          color: on ? kInk : kInk2,
                        ),
                      ),
                    ),
                    Text('${b.potCount} 盆', style: tTiny),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('已选 ${selected.length} 个', style: tTiny),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() {
                if (selected.length == batches.length) {
                  selected.clear();
                } else {
                  selected
                    ..clear()
                    ..addAll(batches.map((b) => b.id));
                }
              }),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                selected.length == batches.length ? '清空' : '全选所有',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
        ...sections,
      ],
    );
  }
}
