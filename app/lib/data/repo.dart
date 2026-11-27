import 'dart:convert';

import 'package:sqflite/sqflite.dart' hide Batch;

import '../core/images.dart';
import '../core/util.dart';
import 'db.dart';
import 'models.dart';

class Repo {
  Repo._();
  static final Repo instance = Repo._();

  Future<Database> get _d async => Db.instance.db;

  // ---------------- 作物 ----------------
  /// 浏览用：启用的作物 + 虽然停用但还有未归档批次的作物（v1.3 需求 7）。
  Future<List<Crop>> cropsForBrowse() async {
    final d = await _d;
    final rows = await d.rawQuery(
      'SELECT * FROM crops WHERE deletedAt IS NULL AND (enabled = 1 OR id IN '
      '(SELECT crop FROM batches WHERE deletedAt IS NULL AND archived = 0)) '
      'ORDER BY sortOrder ASC, createdAt ASC',
    );
    return rows.map(Crop.fromMap).toList();
  }

  Future<List<Crop>> crops({bool includeDisabled = false}) async {
    final d = await _d;
    final rows = await d.query(
      'crops',
      where: includeDisabled
          ? 'deletedAt IS NULL'
          : 'deletedAt IS NULL AND enabled = 1',
      orderBy: 'sortOrder ASC, createdAt ASC',
    );
    return rows.map(Crop.fromMap).toList();
  }

  Future<Crop?> defaultCrop() async {
    final all = await crops();
    if (all.isEmpty) return null;
    return all.firstWhere((c) => c.isDefault, orElse: () => all.first);
  }

  Future<Crop?> cropById(String id) async {
    final d = await _d;
    final rows = await d.query(
      'crops',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Crop.fromMap(rows.first);
  }

  Future<void> saveCrop(Crop c) async {
    final d = await _d;
    c.updatedAt = nowStamp();
    c.rev = c.rev == 0 ? 1 : c.rev + 1;
    if (c.createdAt.isEmpty) c.createdAt = c.updatedAt;
    await d.insert(
      'crops',
      c.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDeleteCrop(String id) async {
    final d = await _d;
    final c = await cropById(id);
    if (c == null || c.isDefault) return;
    await d.update(
      'crops',
      {
        'deletedAt': nowStamp(),
        'enabled': 0,
        'updatedAt': nowStamp(),
        'rev': c.rev + 1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------- 三库 ----------------
  Future<List<Variety>> varieties(String cropId) async {
    final d = await _d;
    final rows = await d.query(
      'varieties',
      where: 'deletedAt IS NULL AND crop = ?',
      whereArgs: [cropId],
      orderBy: 'sortOrder ASC, name ASC',
    );
    return rows.map(Variety.fromMap).toList();
  }

  /// 历史数据里 pests.crops 可能存的是中文作物名（早期迁移留下的），
  /// 这里一次性归一成作物 id。幂等：没有可改的就直接返回 0。
  Future<int> normalizePestCrops() async {
    final cs = await crops(includeDisabled: true);
    if (cs.isEmpty) return 0;
    final byName = {for (final c in cs) c.name: c.id};
    final d = await Db.instance.db;
    final rows = await d.query(
      'pests',
      columns: ['id', 'crops'],
      where: 'deletedAt IS NULL',
    );
    var n = 0;
    for (final r in rows) {
      final raw = (r['crops'] as String?) ?? '';
      if (raw.isEmpty) continue;
      var s = raw;
      var changed = false;
      for (final e in byName.entries) {
        final quoted = '"${e.key}"';
        if (s.contains(quoted)) {
          s = s.replaceAll(quoted, '"${e.value}"');
          changed = true;
        }
      }
      if (!changed) continue;
      await d.update(
        'pests',
        {'crops': s, 'updatedAt': nowStamp()},
        where: 'id = ?',
        whereArgs: [r['id']],
      );
      n++;
    }
    return n;
  }

  Future<List<Pest>> pests(String cropId) async {
    final d = await _d;
    final rows = await d.query(
      'pests',
      where: "deletedAt IS NULL AND (crop = '通用' OR crops LIKE ? OR (crops IS NULL AND crop = ?))",
      whereArgs: ['%"$cropId"%', cropId],
      orderBy: 'sortOrder ASC, name ASC',
    );
    return rows.map(Pest.fromMap).toList();
  }

  Future<List<Soil>> soils(String cropId) async {
    final d = await _d;
    final rows = await d.query(
      'soils',
      where: 'deletedAt IS NULL AND (crop = ? OR crop = ?)',
      whereArgs: [cropId, '通用'],
      orderBy: 'sortOrder ASC, name ASC',
    );
    return rows.map(Soil.fromMap).toList();
  }

  Future<void> saveVariety(Variety v) async {
    final d = await _d;
    v.updatedAt = nowStamp();
    v.rev += 1;
    if (v.createdAt.isEmpty) v.createdAt = v.updatedAt;
    await d.insert(
      'varieties',
      v.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> savePest(Pest v) async {
    final d = await _d;
    v.updatedAt = nowStamp();
    v.rev += 1;
    if (v.createdAt.isEmpty) v.createdAt = v.updatedAt;
    await d.insert(
      'pests',
      v.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveSoil(Soil v) async {
    final d = await _d;
    v.updatedAt = nowStamp();
    v.rev += 1;
    if (v.createdAt.isEmpty) v.createdAt = v.updatedAt;
    await d.insert(
      'soils',
      v.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------- 肥料库 / 药品库 ----------------
  /// [cropId] 给定时会过滤掉「禁用于该作物」的条目。
  Future<List<Supply>> materials(String kind, {String? cropId}) async {
    final d = await _d;
    final rows = await d.query(
      'materials',
      where: 'deletedAt IS NULL AND kind = ?',
      whereArgs: [kind],
      orderBy: 'sortOrder ASC, name ASC',
    );
    final list = rows.map(Supply.fromMap).toList();
    if (cropId == null || cropId.isEmpty) return list;
    return list.where((m) => !m.blockedFor(cropId)).toList();
  }

  Future<Supply?> materialById(String id) async {
    final rows = await (await _d).query(
      'materials',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Supply.fromMap(rows.first);
  }

  Future<void> saveMaterial(Supply m) async {
    final d = await _d;
    m.updatedAt = nowStamp();
    m.rev += 1;
    if (m.createdAt.isEmpty) m.createdAt = m.updatedAt;
    await d.insert(
      'materials',
      m.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String table, String id) async {
    final d = await _d;
    await d.update(
      table,
      {'deletedAt': nowStamp(), 'updatedAt': nowStamp()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 自定义品种自动入库（同名复用）
  Future<Variety> ensureVariety(String cropId, String name) async {
    final list = await varieties(cropId);
    for (final v in list) {
      if (v.name == name) return v;
    }
    final v = Variety(
      id: newId('var'),
      crop: cropId,
      name: name,
      category: '',
      incomplete: true,
      source: '批次自动创建',
      sortOrder: 900,
      createdAt: nowStamp(),
      updatedAt: nowStamp(),
    );
    await saveVariety(v);
    return v;
  }

  // ---------------- 阶段 ----------------
  Future<List<Stage>> stages(
    String cropId, {
    bool all = false,
    int? season,
  }) async {
    final d = await _d;
    final rows = await d.query(
      'stages',
      where: all ? 'crop = ?' : 'crop = ? AND deletedAt IS NULL',
      whereArgs: [cropId],
      orderBy: 'startDay ASC, sortOrder ASC',
    );
    final list = rows.map(Stage.fromMap).toList();
    if (season == null) return list;
    final ofSeason = list.where((e) => e.season == season).toList();
    if (ofSeason.isNotEmpty) return ofSeason;
    // 该季还没配阶段 → 回落到第 1 季，避免「一片空白」
    return list.where((e) => e.season == 0).toList();
  }

  /// v1.7：把 from 季的阶段（含提醒模板）复制到 to 季
  /// v1.8：目标季已有同名阶段时跳过，返回 (copied, skipped)
  Future<({int copied, int skipped})> copySeasonStages(
    String cropId,
    int fromSeason,
    int toSeason,
  ) async {
    final all = await stages(cropId);
    final src = all.where((e) => e.season == fromSeason).toList();
    final exist = all
        .where((e) => e.season == toSeason)
        .map((e) => e.name.trim())
        .toSet();
    var copied = 0;
    var skipped = 0;
    for (final st in src) {
      if (exist.contains(st.name.trim())) {
        skipped++;
        continue;
      }
      final nid =
          '${cropId}_s${toSeason.toString().padLeft(2, '0')}_'
          '${copied + 1}';
      final copy = Stage.fromMap({
        ...st.toMap(),
        'id': nid,
        'season': toSeason,
        'rev': 1,
        'createdAt': nowStamp(),
        'updatedAt': nowStamp(),
      });
      await saveStage(copy);
      for (final t in await stageReminders(st.id)) {
        await saveStageReminder(
          StageReminder.fromMap({
            ...t.toMap(),
            'id': '${t.id}_c$toSeason',
            'stageId': nid,
            'createdAt': nowStamp(),
            'updatedAt': nowStamp(),
          }),
        );
      }
      exist.add(st.name.trim());
      copied++;
    }
    return (copied: copied, skipped: skipped);
  }

  /// v1.8：软删阶段 + 它的提醒模板
  Future<void> deleteStage(String stageId) async {
    final d = await _d;
    final now = nowStamp();
    await d.update(
      'stages',
      {'deletedAt': now, 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [stageId],
    );
    await d.update(
      'stage_reminders',
      {'deletedAt': now, 'updatedAt': now},
      where: 'stageId = ?',
      whereArgs: [stageId],
    );
  }

  /// v1.8：按 id 里的季序号把错位的阶段归位（v1.7 编辑时没传 season 导致）
  /// v1.8.4：把历史数据里的「喷雾（叶背）」统一成半角括号（幂等）。
  Future<int> normalizeMethodNames() async {
    const old = '喷雾（叶背）';
    const neu = '喷雾(叶背)';
    final d = await _d;
    var n = 0;
    n += await d.rawUpdate(
      "UPDATE materials SET method = REPLACE(method, ?, ?) "
      "WHERE method LIKE '%' || ? || '%'",
      [old, neu, old],
    );
    n += await d.rawUpdate(
      "UPDATE materials SET methods = REPLACE(methods, ?, ?) "
      "WHERE methods LIKE '%' || ? || '%'",
      [old, neu, old],
    );
    n += await d.rawUpdate(
      "UPDATE records SET method = REPLACE(method, ?, ?) "
      "WHERE method LIKE '%' || ? || '%'",
      [old, neu, old],
    );
    n += await d.rawUpdate(
      "UPDATE records SET products = REPLACE(products, ?, ?) "
      "WHERE products LIKE '%' || ? || '%'",
      [old, neu, old],
    );
    return n;
  }

  Future<int> normalizeStageSeasons() async {
    final d = await _d;
    final rows = await d.query(
      'stages',
      columns: ['id', 'season'],
      where: 'deletedAt IS NULL',
    );
    var n = 0;
    final re = RegExp(r'_s(\d+)_');
    for (final r in rows) {
      final id = r['id'] as String? ?? '';
      final m = re.firstMatch(id);
      if (m == null) continue;
      final want = int.tryParse(m.group(1) ?? '');
      if (want == null) continue;
      if ((r['season'] as int? ?? 0) == want) continue;
      await d.update(
        'stages',
        {'season': want, 'updatedAt': nowStamp()},
        where: 'id = ?',
        whereArgs: [id],
      );
      n++;
    }
    return n;
  }

  Future<List<StageReminder>> stageReminders(String stageId) async {
    final d = await _d;
    final rows = await d.query(
      'stage_reminders',
      where: 'stageId = ? AND deletedAt IS NULL',
      whereArgs: [stageId],
      orderBy: 'startOffset ASC, sortOrder ASC',
    );
    return rows.map(StageReminder.fromMap).toList();
  }

  Future<int> stageReminderCount(String stageId) async {
    final d = await _d;
    return Sqflite.firstIntValue(
          await d.rawQuery(
            'SELECT COUNT(*) FROM stage_reminders WHERE stageId = ? AND deletedAt IS NULL',
            [stageId],
          ),
        ) ??
        0;
  }

  Future<void> saveStage(Stage s) async {
    final d = await _d;
    s.updatedAt = nowStamp();
    s.rev += 1;
    if (s.createdAt.isEmpty) s.createdAt = s.updatedAt;
    await d.insert(
      'stages',
      s.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveStageReminder(StageReminder r) async {
    final d = await _d;
    r.updatedAt = nowStamp();
    r.rev += 1;
    if (r.createdAt.isEmpty) r.createdAt = r.updatedAt;
    await d.insert(
      'stage_reminders',
      r.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------- 批次 ----------------
  Future<List<Batch>> batches({String? cropId, bool archived = false}) async {
    final d = await _d;
    final where = StringBuffer('deletedAt IS NULL AND archived = ?');
    final args = <Object?>[archived ? 1 : 0];
    if (cropId != null) {
      where.write(' AND crop = ?');
      args.add(cropId);
    }
    final rows = await d.query(
      'batches',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'sortOrder ASC, createdAt ASC',
    );
    return rows.map(Batch.fromMap).toList();
  }

  Future<Batch?> batch(String id) async {
    final d = await _d;
    final rows = await d.query(
      'batches',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Batch.fromMap(rows.first);
  }

  Future<void> saveBatch(Batch b) async {
    final d = await _d;
    // v1.7：多季作物 → 本季起始日以季配置为准
    final crop = await cropById(b.crop);
    final seasons = crop?.effSeasons ?? const <CropSeason>[];
    if (seasons.length > 1) {
      final i = b.season.clamp(0, seasons.length - 1);
      b.season = i;
      final st = seasons[i].start;
      if (st.isNotEmpty) b.cycleStartDate = _normMmdd(st);
    }
    b.updatedAt = nowStamp();
    b.rev += 1;
    if (b.createdAt.isEmpty) b.createdAt = b.updatedAt;
    await d.insert(
      'batches',
      b.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await syncPots(b);
  }

  Future<void> softDeleteBatch(String id) async {
    final d = await _d;
    final t = nowStamp();
    await d.update(
      'batches',
      {'deletedAt': t, 'updatedAt': t},
      where: 'id = ?',
      whereArgs: [id],
    );
    await d.update(
      'records',
      {'deletedAt': t, 'updatedAt': t},
      where: 'batchId = ?',
      whereArgs: [id],
    );
    await d.update(
      'reminders',
      {'deletedAt': t, 'updatedAt': t},
      where: 'batchId = ?',
      whereArgs: [id],
    );
    await d.update(
      'pots',
      {'deletedAt': t, 'updatedAt': t},
      where: 'batchId = ?',
      whereArgs: [id],
    );
  }

  Future<void> mergeBatches(List<String> sourceIds, String targetId) async {
    final d = await _d;
    final target = await batch(targetId);
    if (target == null) return;
    var pots = target.potCount;
    for (final id in sourceIds) {
      if (id == targetId) continue;
      final b = await batch(id);
      if (b == null) continue;
      pots += b.potCount;
      await d.update(
        'records',
        {'batchId': targetId},
        where: 'batchId = ?',
        whereArgs: [id],
      );
      await d.update(
        'reminders',
        {'batchId': targetId},
        where: 'batchId = ?',
        whereArgs: [id],
      );
      await softDeleteBatch(id);
    }
    target.potCount = pots;
    await saveBatch(target);
  }

  // ---------------- 盆栽（v1.3） ----------------

  Future<List<Pot>> pots(String batchId) async {
    final d = await _d;
    final rows = await d.query(
      'pots',
      where: 'batchId = ? AND deletedAt IS NULL',
      whereArgs: [batchId],
      orderBy: 'idx ASC',
    );
    return rows.map(Pot.fromMap).toList();
  }

  /// 整盆死光的批次：所有未删除的盆都是 dead。
  Future<Set<String>> deadBatchIds() async {
    final d = await _d;
    final rows = await d.rawQuery(
      "SELECT batchId FROM pots WHERE deletedAt IS NULL "
      "GROUP BY batchId "
      "HAVING SUM(CASE WHEN state = 'dead' THEN 1 ELSE 0 END) = COUNT(*)",
    );
    return {for (final r in rows) r['batchId']! as String};
  }

  /// 「未施」候选：这次没处理到的批次。
  ///
  /// [targets] 是本次操作涉及的批次；[crops] 是参与作物；
  /// [acrossCrops] 为真时候选包含其它作物的批次（默认，见显示设置）。
  /// 整盆死光的批次永远不进候选。
  Future<List<String>> skipCandidates({
    required Set<String> targets,
    Set<String> crops = const {},
    bool acrossCrops = true,
  }) async {
    final dead = await deadBatchIds();
    final pool = <Batch>[];
    if (acrossCrops) {
      pool.addAll(await batches());
    } else {
      for (final c in crops) {
        pool.addAll(await batches(cropId: c));
      }
    }
    final out = <String>[];
    for (final b in pool) {
      if (targets.contains(b.id) || dead.contains(b.id)) continue;
      out.add(b.id);
    }
    return out;
  }

  /// 一条记录该带哪些「未施」批次。
  ///
  /// 只有 施肥/施药/浇水 才有「未施」；拍照、其他记录返回空。
  Future<List<String>> skippedForRecord({
    required String type,
    required Set<String> targets,
    Set<String> crops = const {},
    bool acrossCrops = true,
  }) async {
    final t = normRecordType(type);
    if (t != '施肥' && t != '施药' && t != '浇水') return const [];
    return skipCandidates(
      targets: targets,
      crops: crops,
      acrossCrops: acrossCrops,
    );
  }

  /// 回填 v1.9 之前的记录：老记录没有 opSkipped，按当时的批次列表补一份快照。
  ///
  /// 只处理最近 [days] 天、`opSkipped` 为空的 施肥/施药/浇水 记录；
  /// 候选批次用「创建时间不晚于记录日期」近似“当时已存在”，并排除归档与整盆死光。
  Future<int> backfillOpSkipped({
    int days = 30,
    bool acrossCrops = true,
  }) async {
    final d = await _d;
    final from = fmtDay(
      dateOnly(DateTime.now().subtract(Duration(days: days - 1))),
    );
    final rows = await d.query(
      'records',
      where:
          "deletedAt IS NULL AND date >= ? AND (opSkipped IS NULL OR opSkipped = '') "
          "AND type IN ('施肥','施药','浇水')",
      whereArgs: [from],
      orderBy: 'date ASC',
    );
    if (rows.isEmpty) return 0;

    final dead = await deadBatchIds();
    final allBatches = (await batches()).where((b) => !dead.contains(b.id));
    final byId = {for (final b in allBatches) b.id: b};

    // 同 opId 的记录属于同一次操作
    final groups = <String, List<GardenRecord>>{};
    for (final m in rows) {
      final r = GardenRecord.fromMap(m);
      final key = r.opId.isEmpty ? 'single:${r.id}' : 'op:${r.opId}';
      groups.putIfAbsent(key, () => []).add(r);
    }

    var changed = 0;
    for (final list in groups.values) {
      final targets = list.map((e) => e.batchId).toSet();
      final crops = <String>{};
      for (final id in targets) {
        final b = byId[id];
        if (b != null) crops.add(b.crop);
      }
      final day = list.first.date; // yyyy-MM-dd
      final skipped = <String>{};
      for (final b in allBatches) {
        if (targets.contains(b.id)) continue;
        if (!acrossCrops && !crops.contains(b.crop)) continue;
        final bornDay = b.createdAt.length >= 10
            ? b.createdAt.substring(0, 10)
            : '';
        if (bornDay.isNotEmpty && bornDay.compareTo(day) > 0) continue;
        skipped.add(b.id);
      }
      final value = skipped.isEmpty ? '' : _encodeSkipped(skipped);
      for (final r in list) {
        await d.update(
          'records',
          {'opSkipped': value},
          where: 'id = ?',
          whereArgs: [r.id],
        );
        changed++;
      }
    }
    return changed;
  }

  String _encodeSkipped(Set<String> ids) => jsonEncode(ids.toList());

  Future<PotStats> potStats(String batchId) async {
    final list = await pots(batchId);
    final st = PotStats(total: list.length);
    for (final p in list) {
      if (p.state == 'dead') {
        st.dead += 1;
      } else if (p.state == 'stunted') {
        st.stunted += 1;
      } else {
        st.alive += 1;
      }
    }
    return st;
  }

  /// 按 batches.potCount 补齐/停用盆。**不重排**：盆 10 永远是盆 10。
  Future<void> syncPots(Batch b) async {
    final d = await _d;
    final rows = await d.query(
      'pots',
      where: 'batchId = ? AND deletedAt IS NULL',
      whereArgs: [b.id],
      orderBy: 'idx ASC',
    );
    final exist = rows.map((r) => (r['idx'] as num).toInt()).toSet();
    final maxIdx = exist.isEmpty ? 0 : exist.reduce((a, c) => a > c ? a : c);
    final target = b.potCount < 1 ? 1 : b.potCount;
    final t = nowStamp();
    for (var i = 1; i <= target; i++) {
      if (exist.contains(i)) continue;
      await d.insert('pots', {
        'id': '${b.id}_pot_$i',
        'batchId': b.id,
        'idx': i,
        'state': 'alive',
        'note': '',
        'changedAt': '',
        'rev': 1,
        'createdAt': t,
        'updatedAt': t,
        'deletedAt': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    // 只停用「当前总数之外」的盆；中间缺号（盆 3 删了）保留
    for (var i = target + 1; i <= maxIdx; i++) {
      await d.update(
        'pots',
        {'deletedAt': t, 'updatedAt': t},
        where: 'batchId = ? AND idx = ? AND deletedAt IS NULL',
        whereArgs: [b.id, i],
      );
    }
  }

  Future<void> setPotState(Pot pot, String state, {String note = ''}) async {
    final d = await _d;
    final t = nowStamp();
    await d.update(
      'pots',
      {'state': state, 'note': note, 'changedAt': todayStr(), 'updatedAt': t},
      where: 'id = ?',
      whereArgs: [pot.id],
    );
    await reevaluateStunt(pot.batchId);
  }

  /// 整批进度：只有「一盆活的都没有」时才暂停。
  Future<void> reevaluateStunt(String batchId) async {
    final b = await batch(batchId);
    if (b == null) return;
    final st = await potStats(batchId);
    if (st.allGone && b.stuntedSince == null) {
      b.stuntedSince = todayStr();
      await saveBatch(b);
    } else if (!st.allGone && b.stuntedSince != null) {
      final now = dateOnly(DateTime.now());
      final since = parseDay(b.stuntedSince) ?? now;
      b.growthOffsetDays += daysBetween(since, now);
      b.stuntedSince = null;
      await saveBatch(b);
    }
  }

  /// 每盆最近一张照片（键为盆号，0 表示批次级）
  Future<Map<int, GardenRecord>> latestPhotoByPot(String batchId) async {
    final d = await _d;
    final rows = await d.query(
      'records',
      where: "batchId = ? AND deletedAt IS NULL AND type = '拍照'",
      whereArgs: [batchId],
      orderBy: 'date DESC, createdAt DESC, id DESC',
    );
    final out = <int, GardenRecord>{};
    for (final r in rows) {
      final rec = GardenRecord.fromMap(r);
      out.putIfAbsent(rec.potIndex, () => rec);
    }
    return out;
  }

  Future<Map<int, int>> photoCountByPot(String batchId) async {
    final d = await _d;
    final rows = await d.rawQuery(
      "SELECT potIndex AS i, COUNT(*) AS n FROM records "
      "WHERE batchId = ? AND deletedAt IS NULL AND type = '拍照' GROUP BY potIndex",
      [batchId],
    );
    return {
      for (final r in rows)
        ((r['i'] as num?)?.toInt() ?? 0): (r['n'] as num?)?.toInt() ?? 0,
    };
  }

  Future<void> deleteRecord(String id) async {
    final r = await _d.then(
      (d) => d.query('records', where: 'id = ?', whereArgs: [id]),
    );
    if (r.isNotEmpty) {
      final rec = GardenRecord.fromMap(r.first);
      for (final img in rec.images) {
        await Images.remove(img);
      }
    }
    await softDelete('records', id);
  }

  /// 删除整次操作：同一个 opId 下的所有批次记录一起软删，图片一并清掉。
  /// opId 为空（老数据、拍照记录）时只删这一条，返回删除条数。
  Future<int> deleteOp(String opId) async {
    if (opId.isEmpty) return 0;
    final d = await _d;
    final rows = await d.query(
      'records',
      columns: ['id'],
      where: 'opId = ? AND deletedAt IS NULL',
      whereArgs: [opId],
    );
    var n = 0;
    for (final m in rows) {
      await deleteRecord(m['id']! as String);
      n++;
    }
    return n;
  }

  // ---------------- 记录 ----------------
  Future<List<GardenRecord>> records({
    String? batchId,
    String? type,
    bool photo = false,
    int limit = 200,
    int offset = 0,
  }) async {
    final d = await _d;
    final where = <String>['deletedAt IS NULL'];
    final args = <Object?>[];
    if (batchId != null) {
      where.add('batchId = ?');
      args.add(batchId);
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type);
    }
    if (photo) {
      where.add("type = '拍照'");
    } else {
      where.add("type <> '拍照'");
    }
    final rows = await d.query(
      'records',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC, createdAt DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(GardenRecord.fromMap).toList();
  }

  Future<int> recordCount({String? batchId, bool photo = false}) async {
    final d = await _d;
    final where = <String>['deletedAt IS NULL'];
    final args = <Object?>[];
    if (batchId != null) {
      where.add('batchId = ?');
      args.add(batchId);
    }
    if (photo) {
      where.add("type = '拍照'");
    } else {
      where.add("type <> '拍照'");
    }
    final r = await d.rawQuery(
      'SELECT COUNT(*) AS n FROM records WHERE ${where.join(' AND ')}',
      args,
    );
    return (r.first['n'] as num?)?.toInt() ?? 0;
  }

  Future<void> saveRecord(GardenRecord r) async {
    final d = await _d;
    r.updatedAt = nowStamp();
    r.rev += 1;
    if (r.createdAt.isEmpty) r.createdAt = r.updatedAt;
    final row = r.toMap();
    row['images'] = jsonEncode(r.images);
    row['products'] = jsonEncode(r.products.map((e) => e.toMap()).toList());
    await d.insert(
      'records',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------- 提醒 ----------------
  Future<List<Reminder>> reminders({
    String? batchId,
    bool activeOnly = true,
    bool includeExpired = false,
  }) async {
    final d = await _d;
    final where = StringBuffer('deletedAt IS NULL');
    final args = <Object?>[];
    if (activeOnly) where.write(' AND active = 1');
    if (batchId != null) {
      where.write(' AND batchId = ?');
      args.add(batchId);
    }
    final rows = await d.query(
      'reminders',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'nextDueAt ASC',
    );
    return rows.map(Reminder.fromMap).toList();
  }

  Future<Reminder?> reminder(String id) async {
    final d = await _d;
    final rows = await d.query(
      'reminders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Reminder.fromMap(rows.first);
  }

  Future<void> saveReminder(Reminder r) async {
    final d = await _d;
    r.updatedAt = nowStamp();
    r.rev += 1;
    if (r.createdAt.isEmpty) r.createdAt = r.updatedAt;
    await d.insert(
      'reminders',
      r.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDeleteReminder(String id) async {
    final d = await _d;
    await d.update(
      'reminders',
      {'deletedAt': nowStamp(), 'updatedAt': nowStamp()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 同一个 groupId 下的全部提醒（多批次一起建的那组）
  Future<List<Reminder>> reminderGroup(String groupId) async {
    if (groupId.isEmpty) return [];
    final d = await _d;
    final rows = await d.query(
      'reminders',
      where: 'groupId = ? AND deletedAt IS NULL',
      whereArgs: [groupId],
      orderBy: 'nextDueAt ASC',
    );
    return rows.map(Reminder.fromMap).toList();
  }

  /// 一次保存多条（多批次新建提醒时用），共用同一个 groupId
  Future<void> saveReminderBatch(List<Reminder> list) async {
    final d = await _d;
    final batch = d.batch();
    for (final r in list) {
      r.updatedAt = nowStamp();
      r.rev += 1;
      if (r.createdAt.isEmpty) r.createdAt = r.updatedAt;
      batch.insert(
        'reminders',
        r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 取消提醒：不再提醒，但数据留着（软删除，可恢复）
  Future<void> cancelReminder(Reminder r, {bool wholeGroup = false}) async {
    final d = await _d;
    final stamp = nowStamp();
    if (wholeGroup && r.groupId.isNotEmpty) {
      await d.update(
        'reminders',
        {'active': 0, 'deletedAt': stamp, 'updatedAt': stamp},
        where: 'groupId = ?',
        whereArgs: [r.groupId],
      );
      return;
    }
    await d.update(
      'reminders',
      {'active': 0, 'deletedAt': stamp, 'updatedAt': stamp},
      where: 'id = ?',
      whereArgs: [r.id],
    );
  }

  /// 完成一次提醒：循环提醒下次到期 = 完成日 + 间隔；单次提醒直接停用
  Future<DateTime> completeReminder(Reminder r, {DateTime? doneAt}) async {
    final done = dateOnly(doneAt ?? DateTime.now());
    if (r.isOneTime) {
      r.active = false;
      r.lastDoneAt = fmtDay(done);
      await saveReminder(r);
      return done;
    }
    final next = done.add(Duration(days: r.intervalDays));
    r.lastDoneAt = fmtDay(done);
    r.nextDueAt = fmtDay(next);
    r.active = true;
    await saveReminder(r);
    return next;
  }

  // ---------------- 提醒历史（v2.0.3） ----------------

  /// 写一条历史：一次「完成」动作只写一条，批次是快照
  Future<void> logReminderDone({
    required List<Reminder> items,
    required DateTime done,
    String? nextDueAt,
  }) async {
    if (items.isEmpty) return;
    final d = await _d;
    final names = await batchNames();
    final seen = <String>{};
    final batches = <Map<String, String>>[];
    for (final r in items) {
      if (seen.add(r.batchId)) {
        batches.add({'id': r.batchId, 'name': names[r.batchId] ?? '未命名批次'});
      }
    }
    final head = items.first;
    await d.insert('reminder_logs', {
      'id': newId('rlog'),
      'groupId': head.groupId,
      'kind': normKind(head.kind),
      'title': head.title,
      'notes': head.notes,
      'doneAt': fmtDay(dateOnly(done)),
      'nextDueAt': nextDueAt ?? '',
      'batches': jsonEncode(batches),
      'createdAt': nowStamp(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ReminderLog>> reminderLogs({
    int limit = 50,
    int offset = 0,
  }) async {
    final d = await _d;
    final rows = await d.query(
      'reminder_logs',
      orderBy: 'doneAt DESC, createdAt DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(ReminderLog.fromMap).toList();
  }

  Future<int> reminderLogCount() async {
    final d = await _d;
    final rows = await d.rawQuery('SELECT COUNT(*) AS c FROM reminder_logs');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> deleteReminderLog(String id) async {
    final d = await _d;
    await d.delete('reminder_logs', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------- 阶段推算 ----------------
  DateTime batchBaseDate(Batch b, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final c = b.crop;
    if (c.endsWith('_strawberry') ||
        b.plantDate.isNotEmpty && b.cycleStartDate.isEmpty) {
      return parseDay(b.plantDate) ?? dateOnly(now);
    }
    var base = _cycleStartOfYear(b.cycleStartDate, now.year);
    if (base.isAfter(dateOnly(now))) {
      base = _cycleStartOfYear(b.cycleStartDate, now.year - 1);
    }
    return base;
  }

  DateTime _cycleStartOfYear(String mmdd, int year) {
    final parts = mmdd.split('-');
    if (parts.length != 2) return DateTime(year, 3, 1);
    final m = int.tryParse(parts[0]) ?? 3;
    final d = int.tryParse(parts[1]) ?? 1;
    return DateTime(year, m, d);
  }

  int dayInCycle(Batch b, {DateTime? today}) {
    final now = dateOnly(today ?? DateTime.now());
    final anchor = b.stuntedSince == null
        ? now
        : (parseDay(b.stuntedSince) ?? now);
    final base = batchBaseDate(b, today: now);
    return daysBetween(base, anchor) + 1 - b.growthOffsetDays;
  }

  /// 日历苗龄：从定植日 / 萌芽日算起，不含生长偏移；仅用于界面展示。
  int plantedDays(Batch b, {DateTime? today}) {
    final now = dateOnly(today ?? DateTime.now());
    final base = batchBaseDate(b, today: now);
    final n = daysBetween(base, now) + 1;
    return n < 1 ? 1 : n; // 定植日在未来时不显示 0 / 负数
  }

  Future<StageSnapshot> snapshot(Batch b, {DateTime? today}) async {
    final list = await stages(b.crop, season: b.season);
    final day = dayInCycle(b, today: today);
    if (list.isEmpty)
      return StageSnapshot(stage: null, dayInCycle: day, dayInStage: 0);
    Stage? found;
    for (final s in list) {
      if (day >= s.startDay && day <= s.endDay) {
        found = s;
        break;
      }
    }
    if (found == null) {
      found = day < list.first.startDay ? list.first : list.last;
    }
    final inStage = day - found.startDay + 1;
    return StageSnapshot(stage: found, dayInCycle: day, dayInStage: inStage);
  }

  /// 一键生成当前阶段的提醒（按 templateId 幂等）
  Future<int> generateStageReminders(Batch b) async {
    final snap = await snapshot(b);
    final stage = snap.stage;
    if (stage == null) return 0;
    final templates = await stageReminders(stage.id);
    if (templates.isEmpty) return 0;
    final existing = await reminders(batchId: b.id, activeOnly: false);
    final existed = existing
        .map((e) => e.templateId)
        .where((e) => e.isNotEmpty)
        .toSet();
    final base = batchBaseDate(b);
    final today = dateOnly(DateTime.now());
    var created = 0;
    for (final t in templates) {
      if (!t.enabled) continue;
      for (var i = 0; i < (t.repeatCount <= 0 ? 1 : t.repeatCount); i++) {
        final tid = '${t.id}#${i + 1}';
        if (existed.contains(tid)) continue;
        final due = dateOnly(
          base.add(
            Duration(
              days:
                  stage.startDay +
                  t.startOffset -
                  1 +
                  i * (t.intervalDays <= 0 ? 0 : t.intervalDays),
            ),
          ),
        );
        if (due.isBefore(today)) continue;
        final r = Reminder(
          id: newId('rem'),
          batchId: b.id,
          kind: normKind(t.kind),
          title: t.title,
          intervalDays: t.intervalDays,
          nextDueAt: fmtDay(due),
          active: true,
          isOneTime: t.repeatCount <= 1 || t.intervalDays <= 0,
          notes: t.notes,
          templateId: tid,
          stageId: stage.id,
          createdAt: nowStamp(),
          updatedAt: nowStamp(),
        );
        await saveReminder(r);
        created++;
      }
    }
    return created;
  }

  Future<void> startStunt(Batch b) async {
    b.stuntedSince = todayStr();
    await saveBatch(b);
  }

  Future<void> resumeStunt(Batch b) async {
    if (b.stuntedSince == null) return;
    final now = dateOnly(DateTime.now());
    final since = parseDay(b.stuntedSince) ?? now;
    b.growthOffsetDays += daysBetween(since, now);
    b.stuntedSince = null;
    await saveBatch(b);
  }

  /// v1.7：开启新一季（单季作物 = 原来的「开启新一年」）
  Future<void> nextSeason(Batch b, {int? season}) async {
    final now = dateOnly(DateTime.now());
    final crop = await cropById(b.crop);
    final seasons = crop?.effSeasons ?? const <CropSeason>[];
    if (seasons.length > 1) {
      final next = season ?? (b.season + 1) % seasons.length;
      b.season = next.clamp(0, seasons.length - 1);
      final st = seasons[b.season].start;
      b.cycleStartDate = st.isEmpty ? b.cycleStartDate : _normMmdd(st);
    } else {
      final mmdd = b.cycleStartDate.isEmpty ? '03-01' : b.cycleStartDate;
      b.cycleStartDate = _normMmdd(mmdd);
    }
    b.growthOffsetDays = 0;
    b.stuntedSince = null;
    await saveBatch(b);
    final active = await reminders(batchId: b.id);
    for (final r in active) {
      if (r.isOneTime) {
        r.active = false;
        await saveReminder(r);
      }
    }
    final label = seasons.length > 1 ? seasons[b.season].name : '新一年';
    final day = daysBetween(batchBaseDate(b, today: now), now) + 1;
    if (day > 0) {
      await saveRecord(
        GardenRecord(
          id: newId('rec'),
          batchId: b.id,
          type: '其他',
          date: fmtDay(now),
          title: seasons.length > 1 ? '开启$label' : '开启新一年',
          notes: seasons.length > 1
              ? '基准日重置为 $label，阶段从第 1 天重新推算'
              : '本年度萌芽日重置，阶段从第 1 天重新推算',
          createdAt: nowStamp(),
          updatedAt: nowStamp(),
        ),
      );
    }
  }

  Future<void> newYear(Batch b) => nextSeason(b);

  String _normMmdd(String v) {
    final parts = v.split('-');
    if (parts.length != 2) return v;
    final m = int.tryParse(parts[0]);
    final d = int.tryParse(parts[1]);
    if (m == null || d == null) return v;
    return '${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  // ---------------- 近 7 天记录（v1.7） ----------------
  Future<List<GardenRecord>> recordsSince(
    int days, {
    bool photo = false,
    int limit = 200,
  }) async {
    final d = await _d;
    final from = fmtDay(
      dateOnly(DateTime.now().subtract(Duration(days: days - 1))),
    );
    final rows = await d.query(
      'records',
      where: photo
          ? "deletedAt IS NULL AND type = '拍照' AND date >= ?"
          : "deletedAt IS NULL AND type <> '拍照' AND date >= ?",
      whereArgs: [from],
      orderBy: 'date DESC, createdAt DESC',
      limit: limit,
    );
    return rows.map(GardenRecord.fromMap).toList();
  }

  /// id → 名称（一次查回，避免 N 次查询）
  Future<Map<String, String>> batchNames() async {
    final d = await _d;
    final rows = await d.query(
      'batches',
      columns: ['id', 'name', 'variety'],
      where: 'deletedAt IS NULL',
    );
    return {
      for (final r in rows) r['id'] as String: (r['name'] ?? '').toString(),
    };
  }

  Future<List<GardenRecord>> recordsByOp(String opId) async {
    final d = await _d;
    final rows = await d.query(
      'records',
      where: 'deletedAt IS NULL AND opId = ?',
      whereArgs: [opId],
      orderBy: 'createdAt ASC',
    );
    return rows.map(GardenRecord.fromMap).toList();
  }

  // ---------------- 元信息与统计 ----------------
  Future<Map<String, dynamic>?> meta(String kind) async {
    final d = await _d;
    final rows = await d.query(
      'lib_meta',
      where: 'kind = ?',
      whereArgs: [kind],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setMeta(
    String kind,
    String libraryId,
    String name,
    String updatedAt,
    int revision,
  ) async {
    final d = await _d;
    await d.insert('lib_meta', {
      'kind': kind,
      'libraryId': libraryId,
      'name': name,
      'updatedAt': updatedAt,
      'revision': revision,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> count(String table) async {
    final d = await _d;
    return Sqflite.firstIntValue(
          await d.rawQuery(
            'SELECT COUNT(*) FROM $table WHERE deletedAt IS NULL',
          ),
        ) ??
        0;
  }

  Future<Map<String, int>> stats() async {
    final d = await _d;
    Future<int> c(String sql) async =>
        Sqflite.firstIntValue(await d.rawQuery(sql)) ?? 0;
    return {
      'batches': await c(
        'SELECT COUNT(*) FROM batches WHERE deletedAt IS NULL',
      ),
      'records': await c(
        'SELECT COUNT(*) FROM records WHERE deletedAt IS NULL',
      ),
      'reminders': await c(
        'SELECT COUNT(*) FROM reminders WHERE deletedAt IS NULL AND active = 1',
      ),
      'varieties': await c(
        'SELECT COUNT(*) FROM varieties WHERE deletedAt IS NULL',
      ),
      'pests': await c('SELECT COUNT(*) FROM pests WHERE deletedAt IS NULL'),
      'soils': await c('SELECT COUNT(*) FROM soils WHERE deletedAt IS NULL'),
      'materials': await c(
        'SELECT COUNT(*) FROM materials WHERE deletedAt IS NULL',
      ),
      'stages': await c('SELECT COUNT(*) FROM stages WHERE deletedAt IS NULL'),
      'templates': await c(
        'SELECT COUNT(*) FROM stage_reminders WHERE deletedAt IS NULL',
      ),
      'crops': await c('SELECT COUNT(*) FROM crops WHERE deletedAt IS NULL'),
    };
  }

  Future<String?> setting(String k) async {
    final d = await _d;
    final rows = await d.query(
      'settings',
      where: 'k = ?',
      whereArgs: [k],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['v'] as String?;
  }

  Future<String> exportPath() => Db.instance.exportDir();

  Future<Variety?> varietyById(String id) async {
    final rows = await (await _d).query(
      'varieties',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Variety.fromMap(rows.first);
  }

  Future<Pest?> pestById(String id) async {
    final rows = await (await _d).query(
      'pests',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Pest.fromMap(rows.first);
  }

  Future<Soil?> soilById(String id) async {
    final rows = await (await _d).query(
      'soils',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Soil.fromMap(rows.first);
  }

  Future<Stage?> stageById(String id) async {
    final rows = await (await _d).query(
      'stages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Stage.fromMap(rows.first);
  }

  Future<void> setSetting(String k, String v) async {
    final d = await _d;
    await d.insert('settings', {
      'k': k,
      'v': v,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
