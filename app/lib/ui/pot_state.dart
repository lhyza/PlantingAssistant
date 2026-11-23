import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';
import '../data/models.dart';
import '../data/repo.dart';
import 'app_state.dart';
import 'common.dart';

/// 逐盆标记：存活 / 僵苗 / 死亡。
class PotStatePage extends StatefulWidget {
  const PotStatePage({super.key, required this.batchId, this.batchName = ''});

  final String batchId;
  final String batchName;

  @override
  State<PotStatePage> createState() => _PotStatePageState();
}

class _PotStatePageState extends State<PotStatePage> {
  List<Pot> pots = [];
  PotStats stats = PotStats();
  bool loading = true;

  /// 已经标记过、当前折叠成状态行的盆
  final Set<String> collapsed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await Repo.instance.pots(widget.batchId);
    final st = await Repo.instance.potStats(widget.batchId);
    if (!mounted) return;
    setState(() {
      pots = list;
      stats = st;
      loading = false;
    });
  }

  Future<void> _mark(Pot p, String state) async {
    if (state == 'alive') {
      await Repo.instance.setPotState(p, 'alive');
      if (!mounted) return;
      setState(() => collapsed.remove(p.id));
      await _load();
      bump();
      return;
    }
    final note = await _askNote(p, state);
    if (note == null) return;
    await Repo.instance.setPotState(p, state, note: note);
    if (!mounted) return;
    setState(() => collapsed.add(p.id));
    await _load();
    bump();
  }

  Future<String?> _askNote(Pot p, String state) {
    final ctrl = TextEditingController(text: p.note);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${Pot.label(state)}：盆${p.idx}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state == 'dead' ? '这盆没了。记一句原因，以后翻记录能想起来。' : '这盆长势停住了。记一句当时的情况。',
              style: tSub,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '比如：积水烂根 / 晒伤 / 冻伤 / 不明原因',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: state == 'dead' ? kInk : kAmber,
            ),
            child: Text('确认${Pot.label(state)}'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('标记死亡 / 僵苗')),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: cardDeco(color: kGreenBg, border: kGreenBg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.batchName.isEmpty ? '这一批' : widget.batchName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '存活 ${stats.alive} 盆 · 僵苗 ${stats.stunted} 盆 · 死亡 ${stats.dead} 盆',
                        style: tSub,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '整批一盆活的都没有时，阶段进度才会暂停；只有部分盆死亡不影响整批。',
                        style: tTiny,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ...pots.map((p) => _potCard(p)),
              ],
            ),
    );
  }

  Widget _potCard(Pot p) {
    final state = p.state;
    final folded = state != 'alive' && collapsed.contains(p.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: cardDeco(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '盆${p.idx}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                if (state != 'alive')
                  Pill(
                    '${Pot.label(state)}：${p.changedAt}',
                    bg: p.dead ? kRedBg : kAmberBg,
                    fg: p.dead ? kRedDeep : kAmber,
                  )
                else
                  const Pill('存活', bg: kGreenBg, fg: kGreen),
                const Spacer(),
                if (folded)
                  TextButton(
                    onPressed: () => setState(() => collapsed.remove(p.id)),
                    style: TextButton.styleFrom(
                      foregroundColor: kInk2,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('修改'),
                  ),
              ],
            ),
            if (!folded) ...[
              if (p.note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(p.note, style: tSub),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _stateBtn(p, 'alive', '存活', kGreenBg, kGreen),
                  const SizedBox(width: 8),
                  _stateBtn(p, 'stunted', '僵苗', kAmberBg, kAmber),
                  const SizedBox(width: 8),
                  _stateBtn(p, 'dead', '死亡', kRedBg, kRedDeep),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                state == 'alive' ? '长得好就保持存活' : '点「存活」可以恢复这盆',
                style: tTiny,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stateBtn(
    Pot p,
    String state,
    String text,
    Color bg,
    Color fg,
  ) {
    final on = p.state == state;
    return Expanded(
      child: GestureDetector(
        onTap: on ? null : () => _mark(p, state),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: on ? bg : Colors.white,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: on ? bg : kLine),
          ),
          child: Center(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: on ? fg : kInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
