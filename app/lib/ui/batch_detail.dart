import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/reminder_group.dart';
import '../data/repo.dart';
import 'app_state.dart';
import 'batch_edit.dart';
import 'common.dart';
import 'image_tile.dart';
import 'record_edit.dart';
import 'photo_wall.dart';
import 'pot_state.dart';
import 'record_list.dart';
import 'reminder_edit.dart';
import 'reminder_sheet.dart';
import 'today.dart' show kindEmoji;

class BatchDetailPage extends StatefulWidget {
  const BatchDetailPage({super.key, required this.batchId});
  final String batchId;
  @override
  State<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<BatchDetailPage> {
  final Repo repo = Repo.instance;
  Batch? b;
  Crop? crop;
  StageSnapshot? snap;
  List<Reminder> reminders = [];
  List<GardenRecord> opRecords = [];
  List<GardenRecord> photoRecords = [];
  int opTotal = 0;
  int photoTotal = 0;
  PotStats potStats = PotStats();
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final batch = await repo.batch(widget.batchId);
    if (batch == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final c = await repo.cropById(batch.crop);
    final s = await repo.snapshot(batch);
    final rs = await repo.reminders(batchId: batch.id);
    final ops = await repo.records(batchId: batch.id, limit: 5);
    final photos = await repo.records(
      batchId: batch.id,
      photo: true,
      limit: 5,
    );
    final opN = await repo.recordCount(batchId: batch.id);
    final photoN = await repo.recordCount(batchId: batch.id, photo: true);
    final ps = await repo.potStats(batch.id);
    if (!mounted) return;
    setState(() {
      b = batch;
      crop = c;
      snap = s;
      reminders = rs;
      opRecords = ops;
      photoRecords = photos;
      opTotal = opN;
      photoTotal = photoN;
      potStats = ps;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading || b == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: kRed)),
      );
    }
    final batch = b!;
    final stage = snap?.stage;
    return Scaffold(
      appBar: AppBar(
        title: Text(batch.name),
        actions: [
          IconButton(
            tooltip: '编辑批次',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BatchEditPage(batchId: batch.id),
                ),
              );
              _load();
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                final ok = await confirm(
                  context,
                  '删除这个批次？',
                  body: '记录和提醒会一起删除，无法撤销。',
                );
                if (ok) {
                  await repo.softDeleteBatch(batch.id);
                  bump();
                  if (mounted) Navigator.pop(context);
                }
              } else if (v == 'newyear') {
                final ok = await confirm(
                  context,
                  '开启新一年？',
                  body: '会把「本年度开始日」重置为今天，阶段从第 1 天重新算，旧的记录保留。',
                  danger: false,
                );
                if (ok) {
                  await repo.newYear(batch);
                  bump();
                  _load();
                }
              }
            },
            itemBuilder: (_) => [
              if (crop?.isPerennial == true)
                const PopupMenuItem(value: 'newyear', child: Text('开启新一年')),
              const PopupMenuItem(value: 'delete', child: Text('删除批次')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      crop?.emoji ?? '🌱',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      crop?.name ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kInk2,
                      ),
                    ),
                    const Spacer(),
                    if (batch.stuntedSince != null)
                      const Pill('僵苗暂停中', bg: kAmberBg, fg: kAmber),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${batch.variety.isEmpty ? '未填品种' : batch.variety} · ${batch.potCount} ${crop?.unit ?? '盆'}'
                  '${batch.location.isEmpty ? '' : ' · ${batch.location}'}',
                  style: tBody,
                ),
                if (potStats.dead > 0 || potStats.stunted > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (potStats.dead > 0) ...[
                        Text(
                          '已死亡 ${potStats.dead} 盆',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kRedDeep,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (potStats.stunted > 0)
                        Text(
                          '僵苗 ${potStats.stunted} 盆',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kAmber,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  crop?.isPerennial == true
                      ? '本年度第 ${snap?.dayInCycle ?? 0} 天 · 萌芽日 ${batch.cycleStartDate}'
                      : '种植第 ${snap?.dayInCycle ?? 0} 天 · 定植 ${batch.plantDate}',
                  style: tSub,
                ),
                if (batch.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(batch.notes, style: tSub),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (stage != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kGreen.withValues(alpha: 0.09), kGreenBg],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kGreen.withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${stage.name}（${stage.days} 天）',
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: kGreen,
                          ),
                        ),
                      ),
                      Pill(
                        '第 ${snap!.dayInStage}/${stage.days} 天',
                        bg: Colors.white,
                        fg: kGreen,
                        border: kGreen.withValues(alpha: 0.25),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (snap!.dayInStage / stage.days).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.75),
                      valueColor: const AlwaysStoppedAnimation(kGreen),
                    ),
                  ),
                  if (stage.fertilizerPlan.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _planRow('🌾', '施肥方案', stage.fertilizerPlan),
                  ],
                  if (stage.pestControl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _planRow('🧴', '病虫害预防', stage.pestControl),
                  ],
                  if (stage.operationTips.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _planRow('💡', '操作要点', stage.operationTips),
                  ],
                ],
              ),
            )
          else
            EmptyHint(text: '这个作物还没配置生产阶段，去「知识 → 生产阶段管理」加一个吧'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PotStatePage(
                          batchId: batch.id,
                          batchName: batch.name,
                        ),
                      ),
                    );
                    _load();
                  },
                  icon: const Icon(Icons.local_florist_outlined, size: 18),
                  label: const Text('标记死亡/僵苗'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final n = await repo.generateStageReminders(batch);
                    bump();
                    _load();
                    if (mounted) {
                      toast(
                        context,
                        n == 0 ? '当前阶段的提醒都已经在列表里了' : '按阶段生成了 $n 条提醒',
                      );
                    }
                  },
                  icon: const Icon(Icons.auto_awesome, size: 17),
                  label: const Text('生成阶段提醒'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                ),
              ),
            ],
          ),
          SectionTitle(
            '进行中的安排',
            count: reminders.length,
            trailing: TextButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReminderEditPage(batchId: batch.id),
                  ),
                );
                _load();
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加'),
              style: TextButton.styleFrom(
                foregroundColor: kRed,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          if (reminders.isEmpty)
            const EmptyHint(text: '还没有安排。点「生成阶段提醒」可以按当前阶段一键排好。')
          else
            ...reminders.map((r) => _reminderTile(r, b!.name)),
          const SectionTitle('记一笔 · 我做了什么'),
          Row(
            children: ['施肥', '施药', '浇水', '拍照', '其他'].map((t) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              RecordEditPage(batchIds: [batch.id], type: t),
                        ),
                      );
                      _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: cardDeco(),
                      child: Column(
                        children: [
                          Text(
                            kindEmoji(t),
                            style: const TextStyle(fontSize: 17),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            t,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          SectionTitle(
            '操作记录',
            count: opTotal,
            trailing: opTotal > 5
                ? TextButton(
                    onPressed: () => _openAll(batch.id, photo: false),
                    style: TextButton.styleFrom(
                      foregroundColor: kRed,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('更多'),
                  )
                : null,
          ),
          if (opRecords.isEmpty)
            const EmptyHint(text: '还没有记录，做完一次施肥/用药就在这里记一笔')
          else
            ..._recTiles(opRecords, photo: false),
          SectionTitle(
            '拍照记录',
            count: photoTotal,
            trailing: photoTotal > 5
                ? TextButton(
                    onPressed: () => _openWall(batch),
                    style: TextButton.styleFrom(
                      foregroundColor: kRed,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('更多'),
                  )
                : null,
          ),
          if (photoRecords.isEmpty)
            InkWell(
              onTap: () => _openWall(batch),
              child: const EmptyHint(text: '还没有照片。点上面「拍照」拍一张，看图比文字直观'),
            )
          else
            ..._photoTiles(batch, photoRecords),
        ],
      ),
    );
  }

  Widget _planRow(String emoji, String label, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: kGreen,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF3F6355),
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }

  Widget _reminderTile(Reminder r, String batchName) {
    final overdue = r.nextDueAt.compareTo(todayStr()) < 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openReminderSheet(
          context,
          ReminderGroup([r]),
          batchName: (_) => batchName,
          onChanged: _load,
        ),
        child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: cardDeco(),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: kindBgOf(r.kind),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Center(
                child: Text(
                  kindEmoji(r.kind),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${r.kind}${r.intervalDays > 1 ? ' · 每 ${r.intervalDays} 天' : ''} · 下次 ${r.nextDueAt}',
                    style: tSub,
                  ),
                ],
              ),
            ),
            if (overdue)
              const Pill('已逾期', bg: kRedBg, fg: kRedDeep)
            else if (r.nextDueAt == todayStr())
              const Pill('今天', bg: kAmberBg, fg: kAmber),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.check_circle_outline,
                color: kGreen,
                size: 21,
              ),
              onPressed: () async {
                await finishReminder(context, r);
                _load();
              },
            ),
          ],
        ),
        ),
      ),
    );
  }

  Future<void> _openAll(String batchId, {required bool photo}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordListPage(batchId: batchId, photo: photo),
      ),
    );
    _load();
  }

  Future<void> _openWall(Batch batch) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoWallPage(
          batchId: batch.id,
          photoMode: batch.photoMode,
          potCount: batch.potCount,
        ),
      ),
    );
    _load();
  }

  /// 批次详情里的照片小卡：按原始比例显示，点开进图片墙。
  List<Widget> _photoTiles(Batch batch, List<GardenRecord> list) {
    return [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.92,
        children: [
          for (final r in list)
            GestureDetector(
              onTap: () => _openWall(batch),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (r.images.isNotEmpty)
                      LocalImage(ref: r.images.first, fit: BoxFit.cover)
                    else
                      Container(
                        color: kBg,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          color: kInk3,
                        ),
                      ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          r.potIndex > 0 ? '盆${r.potIndex}' : r.date,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
    ];
  }

  List<Widget> _recTiles(List<GardenRecord> list, {required bool photo}) {
    return List.generate(list.length, (i) {
      final r = list[i];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecordDetailPage(
                items: list,
                index: i,
                photo: photo,
              ),
            ),
          ),
          child: RecordTile(record: r),
        ),
      );
    });
  }
}
