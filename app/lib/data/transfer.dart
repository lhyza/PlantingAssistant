import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/images.dart';
import '../core/util.dart';
import '../data/db.dart';
import 'models.dart';
import 'repo.dart';

const String kFormat = 'planting.data';
const int kSchema = 4;
const String kAppVersion = '1.0.0';

const Map<String, String> kKindNames = {
  'garden': '种植数据',
  'variety': '品种库',
  'pest': '病虫害库',
  'soil': '土肥库',
  'fertilizer': '肥料库',
  'medicine': '药品库',
  'stage': '生产阶段库',
};

class ImportDiff {
  ImportDiff(this.name, this.action, {this.detail = ''});
  final String name;
  final String action; // add / update / skip / delete
  final String detail;
}

class ImportPlan {
  ImportPlan({
    required this.fileName,
    required this.kind,
    required this.libraryId,
    required this.fileUpdatedAt,
    this.localUpdatedAt = '',
    this.idMismatch = false,
    this.error,
    this.diffs = const [],
    this.payload,
  });

  final String fileName;
  final String kind;
  final String libraryId;
  final String fileUpdatedAt;
  final String localUpdatedAt;
  final bool idMismatch;
  final String? error;
  final List<ImportDiff> diffs;
  final Map<String, dynamic>? payload;

  int get add => diffs.where((d) => d.action == 'add').length;
  int get update => diffs.where((d) => d.action == 'update').length;
  int get skip => diffs.where((d) => d.action == 'skip').length;
  int get remove => diffs.where((d) => d.action == 'delete').length;
  bool get ok => error == null;
}

class Transfer {
  Transfer._();
  static final Transfer instance = Transfer._();
  final Repo _repo = Repo.instance;

  // ---------------- 导出 ----------------
  Future<Map<String, dynamic>> buildFile(String kind) async {
    final meta = await _repo.meta(kind);
    final now = nowStamp();
    final base = <String, dynamic>{
      'format': kFormat,
      'kind': kind,
      'schemaVersion': kSchema,
      'libraryId':
          meta?['libraryId'] ?? 'lib_${kind}_${newId('x').split('_').last}',
      'name': meta?['name'] ?? kKindNames[kind],
      'updatedAt': now,
      'revision': ((meta?['revision'] as int?) ?? 1) + 1,
      'appVersion': kAppVersion,
    };
    switch (kind) {
      case 'garden':
        final batches = await _repo.batches(archived: false);
        final archived = await _repo.batches(archived: true);
        final allBatches = [...batches, ...archived];
        final recs = await _repo.records(limit: 5000);
        final rems = await _repo.reminders(
          activeOnly: false,
          includeExpired: true,
        );
        base['count'] = allBatches.length;
        base['batches'] = allBatches
            .map(
              (b) => {
                'id': b.id,
                'rev': b.rev,
                'createdAt': b.createdAt,
                'updatedAt': b.updatedAt,
                'deletedAt': b.deletedAt,
                'crop': b.crop,
                'name': b.name,
                'varietyId': b.varietyId,
                'varietyName': b.variety,
                'plantDate': b.plantDate,
                'cycleStartDate': b.cycleStartDate,
                'location': b.location,
                'potCount': b.potCount,
                'status': b.status,
                'color': b.color,
                'notes': b.notes,
                'sortOrder': b.sortOrder,
                'stuntedSince': b.stuntedSince,
                'growthOffsetDays': b.growthOffsetDays,
                'photoMode': b.photoMode,
                'archived': b.archived ? 1 : 0,
              },
            )
            .toList();
        base['records'] = recs
            .map(
              (r) => {
                'id': r.id,
                'rev': r.rev,
                'createdAt': r.createdAt,
                'updatedAt': r.updatedAt,
                'deletedAt': r.deletedAt,
                'batchId': r.batchId,
                'type': r.type,
                'date': r.date,
                'title': r.title,
                'productName': r.productName,
                'dosage': r.dosage,
                'method': r.method,
                'products': r.products.map((e) => e.toMap()).toList(),
                'images': r.images,
                'potIndex': r.potIndex,
                'imgW': r.imgW,
                'imgH': r.imgH,
                'notes': r.notes,
                'stageId': r.stageId,
              },
            )
            .toList();
        base['reminders'] = rems
            .map(
              (r) => {
                'id': r.id,
                'rev': r.rev,
                'createdAt': r.createdAt,
                'updatedAt': r.updatedAt,
                'deletedAt': r.deletedAt,
                'batchId': r.batchId,
                'kind': r.kind,
                'title': r.title,
                'intervalDays': r.intervalDays,
                'nextDueAt': r.nextDueAt,
                'lastDoneAt': r.lastDoneAt,
                'active': r.active ? 1 : 0,
                'isOneTime': r.isOneTime ? 1 : 0,
                'notes': r.notes,
                'templateId': r.templateId,
                'stageId': r.stageId,
                'groupId': r.groupId,
              },
            )
            .toList();
        final pots = <Map<String, dynamic>>[];
        for (final b in allBatches) {
          for (final p in await _repo.pots(b.id)) {
            pots.add({
              'id': p.id,
              'rev': p.rev,
              'createdAt': p.createdAt,
              'updatedAt': p.updatedAt,
              'deletedAt': p.deletedAt,
              'batchId': p.batchId,
              'idx': p.idx,
              'state': p.state,
              'note': p.note,
              'changedAt': p.changedAt,
            });
          }
        }
        base['pots'] = pots;
        break;
      case 'variety':
        final list = await _allVarieties();
        base['count'] = list.length;
        base['items'] = list.map((v) => v.toMap()).toList();
        break;
      case 'pest':
        final list = await _allPests();
        base['count'] = list.length;
        base['items'] = list
            .map((v) => {...v.toMap(), 'crops': v.crops})
            .toList();
        break;
      case 'soil':
        final list = await _allSoils();
        base['count'] = list.length;
        base['items'] = list.map((v) => v.toMap()).toList();
        break;
      case 'fertilizer':
      case 'medicine':
        final list = await _repo.materials(kind);
        base['count'] = list.length;
        base['items'] = list.map((m) => m.toMap()).toList();
        break;
      case 'stage':
        final d = await Db.instance.db;
        final crops = await _repo.crops(includeDisabled: true);
        final rows = await d.query(
          'stages',
          where: 'deletedAt IS NULL',
          orderBy: 'crop ASC, startDay ASC',
        );
        final list = rows.map(Stage.fromMap).toList();
        final items = <Map<String, dynamic>>[];
        for (final s in list) {
          final rems = await _repo.stageReminders(s.id);
          final m = s.toMap();
          m['reminders'] = rems.map((r) {
            final rm = r.toMap();
            rm.remove('stageId');
            rm.remove('deletedAt');
            return rm;
          }).toList();
          items.add(m);
        }
        base['crops'] = crops
            .map(
              (c) => {
                'id': c.id,
                'name': c.name,
                'emoji': c.emoji,
                'color': c.color,
                'lifeCycle': c.lifeCycle,
                'cycleStart': c.cycleStart,
                'unit': c.unit,
                'isDefault': c.isDefault ? 1 : 0,
                'enabled': c.enabled ? 1 : 0,
                'image': c.image,
                'sortOrder': c.sortOrder,
                'rev': c.rev,
                'createdAt': c.createdAt,
                'updatedAt': c.updatedAt,
                'deletedAt': c.deletedAt,
              },
            )
            .toList();
        base['count'] = items.length;
        base['items'] = items;
        break;
    }
    await _embedImages(base);
    return base;
  }

  /// 导出时把本地图片转成 base64 内嵌（换手机/重装也能带走图）
  Future<void> _embedImages(Map<String, dynamic> base) async {
    Future<void> run(List? list) async {
      if (list == null) return;
      for (final raw in list) {
        if (raw is! Map) continue;
        final ref = raw['image']?.toString() ?? '';
        if (ref.isEmpty || ref.startsWith('data:')) continue;
        final uri = await Images.dataUri(ref);
        if (uri != null) raw['image'] = uri;
      }
    }

    await run(base['items'] as List?);
    await run(base['crops'] as List?);
  }

  /// 导入前把 base64 图片落盘，字段换成相对路径
  Future<void> _decodeImages(Map<String, dynamic> payload) async {
    Future<void> run(List? list) async {
      if (list == null) return;
      for (final raw in list) {
        if (raw is! Map) continue;
        final ref = raw['image']?.toString() ?? '';
        if (!ref.startsWith('data:')) continue;
        final saved = await Images.saveDataUri(ref);
        raw['image'] = saved;
      }
    }

    await run(payload['items'] as List?);
    await run(payload['crops'] as List?);
  }

  Future<List<Variety>> _allVarieties() async {
    final d = await Db.instance.db;
    final rows = await d.query(
      'varieties',
      where: 'deletedAt IS NULL',
      orderBy: 'crop ASC, sortOrder ASC',
    );
    return rows.map(Variety.fromMap).toList();
  }

  Future<List<Pest>> _allPests() async {
    final d = await Db.instance.db;
    final rows = await d.query(
      'pests',
      where: 'deletedAt IS NULL',
      orderBy: 'sortOrder ASC',
    );
    return rows.map(Pest.fromMap).toList();
  }

  Future<List<Soil>> _allSoils() async {
    final d = await Db.instance.db;
    final rows = await d.query(
      'soils',
      where: 'deletedAt IS NULL',
      orderBy: 'sortOrder ASC',
    );
    return rows.map(Soil.fromMap).toList();
  }

  Future<String> writeFile(String kind, Map<String, dynamic> data) async {
    final dir = await Db.instance.exportDir();
    final stamp = DateTime.now();
    final name =
        'strawberry-$kind-${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}.json';
    final f = File(p.join(dir, name));
    const encoder = JsonEncoder.withIndent('  ');
    await f.writeAsString(encoder.convert(data));
    return f.path;
  }

  // ---------------- 导入 ----------------
  Future<ImportPlan> analyze(String path, String fileName) async {
    Map<String, dynamic> data;
    try {
      final text = await File(path).readAsString();
      data = jsonDecode(text) as Map<String, dynamic>;
    } catch (e) {
      return ImportPlan(
        fileName: fileName,
        kind: '',
        libraryId: '',
        fileUpdatedAt: '',
        error: '不是有效的 JSON 文件',
      );
    }
    if (data['format'] != kFormat) {
      return ImportPlan(
        fileName: fileName,
        kind: '',
        libraryId: '',
        fileUpdatedAt: '',
        error: '不是种植助手的数据文件（format 不符）',
      );
    }
    final kind = data['kind'] as String? ?? '';
    if (!kKindNames.containsKey(kind)) {
      return ImportPlan(
        fileName: fileName,
        kind: kind,
        libraryId: '',
        fileUpdatedAt: '',
        error: '未知的数据类型：$kind',
      );
    }
    final ver = data['schemaVersion'] as int? ?? 1;
    if (ver > kSchema) {
      return ImportPlan(
        fileName: fileName,
        kind: kind,
        libraryId: '',
        fileUpdatedAt: '',
        error: '文件版本 $ver 高于当前 App（$kSchema），请先升级 App',
      );
    }
    final libraryId = data['libraryId'] as String? ?? '';
    final fileUpdated = data['updatedAt'] as String? ?? '';
    final local = await _repo.meta(kind);
    final localUpdated = local?['updatedAt'] as String? ?? '';
    final localId = local?['libraryId'] as String? ?? '';

    if (kind == 'garden') {
      return _planGarden(
        data,
        fileName,
        libraryId,
        fileUpdated,
        localUpdated,
        localId,
      );
    }
    return _planLibrary(
      data,
      fileName,
      kind,
      libraryId,
      fileUpdated,
      localUpdated,
      localId,
    );
  }

  ImportPlan _planLibrary(
    Map<String, dynamic> data,
    String fileName,
    String kind,
    String libraryId,
    String fileUpdated,
    String localUpdated,
    String localId,
  ) {
    final diffs = <ImportDiff>[];
    final idMismatch =
        localId.isNotEmpty && libraryId.isNotEmpty && localId != libraryId;
    final older =
        localUpdated.isNotEmpty &&
        fileUpdated.isNotEmpty &&
        fileUpdated.compareTo(localUpdated) <= 0;
    final items = (data['items'] as List? ?? const []).cast<Map>();
    final localItems = <String, Map<String, dynamic>>{};
    // 由调用方填充（异步）——使用 payload 延迟
    return ImportPlan(
      fileName: fileName,
      kind: kind,
      libraryId: libraryId,
      fileUpdatedAt: fileUpdated,
      localUpdatedAt: localUpdated,
      idMismatch: idMismatch,
      diffs: diffs,
      payload: {
        ...data,
        '_older': older,
        '_local': localItems,
        '_forcedSkip': older && !idMismatch,
        '_count': items.length,
      },
    );
  }

  ImportPlan _planGarden(
    Map<String, dynamic> data,
    String fileName,
    String libraryId,
    String fileUpdated,
    String localUpdated,
    String localId,
  ) {
    return ImportPlan(
      fileName: fileName,
      kind: 'garden',
      libraryId: libraryId,
      fileUpdatedAt: fileUpdated,
      localUpdatedAt: localUpdated,
      idMismatch:
          localId.isNotEmpty && libraryId.isNotEmpty && localId != libraryId,
      payload: data,
    );
  }

  /// 计算逐条差异（需要查库，单独异步调用以便 UI 先显示 loading）
  Future<ImportPlan> diff(ImportPlan plan) async {
    if (!plan.ok) return plan;
    final diffs = <ImportDiff>[];
    if (plan.kind == 'garden') {
      final data = plan.payload!;
      final batches = (data['batches'] as List? ?? const []).cast<Map>();
      final recs = (data['records'] as List? ?? const []).cast<Map>();
      final rems = (data['reminders'] as List? ?? const []).cast<Map>();
      final localBatches = await _repo.batches();
      final localMap = {for (final b in localBatches) b.id: b};
      for (final m in batches) {
        final id = m['id'] as String? ?? '';
        final name = m['name'] as String? ?? '未命名批次';
        final local = localMap[id];
        if (local == null) {
          diffs.add(ImportDiff(name, 'add', detail: '本地没有'));
        } else {
          final fu = m['updatedAt'] as String? ?? '';
          if (fu.compareTo(local.updatedAt) > 0) {
            diffs.add(ImportDiff(name, 'update', detail: '文件更新更晚'));
          } else {
            diffs.add(ImportDiff(name, 'skip', detail: '本地更新更晚或一致'));
          }
        }
      }
      diffs.add(ImportDiff('记录 ${recs.length} 条', 'add', detail: '随批次合并'));
      diffs.add(ImportDiff('提醒 ${rems.length} 条', 'add', detail: '随批次合并'));
      final pots = (data['pots'] as List? ?? const []);
      if (pots.isNotEmpty) {
        diffs.add(ImportDiff('盆状态 ${pots.length} 条', 'add', detail: '随批次合并'));
      }
      return ImportPlan(
        fileName: plan.fileName,
        kind: plan.kind,
        libraryId: plan.libraryId,
        fileUpdatedAt: plan.fileUpdatedAt,
        localUpdatedAt: plan.localUpdatedAt,
        idMismatch: plan.idMismatch,
        diffs: diffs,
        payload: plan.payload,
      );
    }

    final items = (plan.payload!['items'] as List? ?? const []).cast<Map>();
    final existing = await _existingFor(plan.kind);
    final forcedSkip = plan.payload!['_forcedSkip'] == true;
    for (final m in items) {
      final id = m['id'] as String? ?? '';
      final name = (m['name'] as String? ?? m['title'] as String? ?? id);
      final local = existing[id];
      if (forcedSkip) {
        diffs.add(ImportDiff(name, 'skip', detail: '文件比本地旧'));
        continue;
      }
      if (local == null) {
        diffs.add(ImportDiff(name, 'add', detail: '本地没有'));
      } else {
        final fu = m['updatedAt'] as String? ?? '';
        final lu = local['updatedAt'] as String? ?? '';
        if (fu.compareTo(lu) > 0) {
          diffs.add(ImportDiff(name, 'update', detail: '文件更新更晚'));
        } else {
          diffs.add(ImportDiff(name, 'skip', detail: '本地更新更晚或一致'));
        }
      }
    }
    return ImportPlan(
      fileName: plan.fileName,
      kind: plan.kind,
      libraryId: plan.libraryId,
      fileUpdatedAt: plan.fileUpdatedAt,
      localUpdatedAt: plan.localUpdatedAt,
      idMismatch: plan.idMismatch,
      diffs: diffs,
      payload: plan.payload,
    );
  }

  Future<Map<String, Map<String, dynamic>>> _existingFor(String kind) async {
    final d = await Db.instance.db;
    final table = {
      'variety': 'varieties',
      'pest': 'pests',
      'soil': 'soils',
      'fertilizer': 'materials',
      'medicine': 'materials',
      'stage': 'stages',
    }[kind]!;
    final rows = kind == 'fertilizer' || kind == 'medicine'
        ? await d.query(table, where: 'kind = ?', whereArgs: [kind])
        : await d.query(table);
    return {for (final r in rows) r['id'] as String: r};
  }

  /// 执行导入（单事务）；返回 (新增, 更新, 跳过)
  Future<List<int>> apply(ImportPlan plan, {Set<String>? selected}) async {
    final d = await Db.instance.db;
    var added = 0;
    var updated = 0;
    var skipped = 0;
    final cropIndex = await _cropIndex();
    await _decodeImages(plan.payload!);
    await d.transaction((txn) async {
      if (plan.kind == 'garden') {
        final data = plan.payload!;
        for (final raw in (data['batches'] as List? ?? const [])) {
          final m = Map<String, dynamic>.from(raw as Map);
          final existing = await txn.query(
            'batches',
            where: 'id = ?',
            whereArgs: [m['id']],
            limit: 1,
          );
          final fu = m['updatedAt'] as String? ?? '';
          if (existing.isEmpty) {
            await txn.insert(
              'batches',
              _batchRow(m, cropIndex),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            added++;
          } else if (fu.compareTo(
                existing.first['updatedAt'] as String? ?? '',
              ) >
              0) {
            await txn.insert(
              'batches',
              _batchRow(m, cropIndex),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            updated++;
          } else {
            skipped++;
          }
        }
        for (final raw in (data['records'] as List? ?? const [])) {
          final m = Map<String, dynamic>.from(raw as Map);
          await txn.insert(
            'records',
            _recordRow(m),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (final raw in (data['pots'] as List? ?? const [])) {
          final m = Map<String, dynamic>.from(raw as Map);
          await txn.insert(
            'pots',
            _potRow(m),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (final raw in (data['reminders'] as List? ?? const [])) {
          final m = Map<String, dynamic>.from(raw as Map);
          await txn.insert(
            'reminders',
            _reminderRow(m),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } else {
        final table = {
          'variety': 'varieties',
          'pest': 'pests',
          'soil': 'soils',
          'fertilizer': 'materials',
          'medicine': 'materials',
          'stage': 'stages',
        }[plan.kind]!;
        final forcedSkip = plan.payload!['_forcedSkip'] == true;
        for (final raw in (plan.payload!['items'] as List? ?? const [])) {
          final m = Map<String, dynamic>.from(raw as Map);
          final id = m['id'] as String? ?? '';
          if (id.isEmpty) continue;
          if (selected != null && !selected.contains(id)) {
            skipped++;
            continue;
          }
          final existing = await txn.query(
            table,
            where: 'id = ?',
            whereArgs: [id],
            limit: 1,
          );
          final fu = m['updatedAt'] as String? ?? '';
          if (forcedSkip) {
            skipped++;
            continue;
          }
          if (existing.isEmpty) {
            await txn.insert(
              table,
              _rowFor(plan.kind, m, cropIndex),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            added++;
            if (plan.kind == 'stage') {
              for (final rr in (m['reminders'] as List? ?? const [])) {
                final rm = Map<String, dynamic>.from(rr as Map);
                rm['stageId'] = id;
                await txn.insert(
                  'stage_reminders',
                  _stageReminderRow(rm),
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
              }
            }
          } else if (fu.compareTo(
                existing.first['updatedAt'] as String? ?? '',
              ) >
              0) {
            await txn.insert(
              table,
              _rowFor(plan.kind, m, cropIndex),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            updated++;
            if (plan.kind == 'stage') {
              for (final rr in (m['reminders'] as List? ?? const [])) {
                final rm = Map<String, dynamic>.from(rr as Map);
                rm['stageId'] = id;
                await txn.insert(
                  'stage_reminders',
                  _stageReminderRow(rm),
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
              }
            }
          } else {
            skipped++;
          }
        }
        if (plan.kind == 'stage') {
          for (final raw in (plan.payload!['crops'] as List? ?? const [])) {
            final m = Map<String, dynamic>.from(raw as Map);
            final id = m['id'] as String? ?? '';
            if (id.isEmpty) continue;
            final existing = await txn.query(
              'crops',
              where: 'id = ?',
              whereArgs: [id],
              limit: 1,
            );
            final fu = m['updatedAt'] as String? ?? '';
            if (existing.isEmpty) {
              await txn.insert(
                'crops',
                _cropRow(m),
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            } else if (fu.compareTo(
                  existing.first['updatedAt'] as String? ?? '',
                ) >
                0) {
              await txn.insert(
                'crops',
                _cropRow(m),
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
          }
        }
      }
      final meta = await txn.query(
        'lib_meta',
        where: 'kind = ?',
        whereArgs: [plan.kind],
        limit: 1,
      );
      final revision =
          ((meta.isEmpty ? 0 : (meta.first['revision'] as int? ?? 1)) + 1);
      await txn.insert('lib_meta', {
        'kind': plan.kind,
        'libraryId': plan.libraryId,
        'name': meta.isEmpty ? kKindNames[plan.kind] : meta.first['name'],
        'updatedAt': plan.fileUpdatedAt,
        'revision': revision,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    return [added, updated, skipped];
  }

  Future<Map<String, String>> _cropIndex() async {
    final d = await Db.instance.db;
    final rows = await d.query('crops');
    final map = <String, String>{};
    for (final r in rows) {
      map[r['name'] as String] = r['id'] as String;
      map[r['id'] as String] = r['id'] as String;
    }
    map['通用'] = '通用';
    return map;
  }

  Map<String, dynamic> _rowFor(
    String kind,
    Map<String, dynamic> m,
    Map<String, String> cropIndex,
  ) {
    switch (kind) {
      case 'variety':
        return _varietyRow(m, cropIndex);
      case 'pest':
        return _pestRow(m, cropIndex);
      case 'soil':
        return _soilRow(m, cropIndex);
      case 'fertilizer':
      case 'medicine':
        return _materialRow(m, kind);
      case 'stage':
        return _stageRow(m, cropIndex);
    }
    return m;
  }

  String _crop(Map<String, dynamic> m, Map<String, String> idx) {
    final v = m['crop']?.toString() ?? '';
    return idx[v] ?? (v.contains('crop_') ? v : 'crop_strawberry');
  }

  Map<String, dynamic> _varietyRow(
    Map<String, dynamic> m,
    Map<String, String> idx,
  ) => {
    'id': m['id'],
    'crop': _crop(m, idx),
    'name': m['name'] ?? '',
    'category': m['category'] ?? '',
    'characteristics': m['characteristics'] ?? '',
    'suitable': m['suitable'] ?? '',
    'care': m['care'] ?? '',
    'yieldText': m['yield'] ?? m['yieldText'] ?? '',
    'taste': m['taste'] ?? '',
    'sweetness': m['sweetness'] ?? '',
    'sweetnessStar': m['sweetnessStar'] ?? 0,
    'fruitSize': m['fruitSize'] ?? '',
    'sizeStar': m['sizeStar'] ?? 0,
    'heatResistance': m['heatResistance'] ?? '',
    'heatStar': m['heatStar'] ?? 0,
    'image': m['image'] ?? '',
    'incomplete': m['incomplete'] == true || m['incomplete'] == 1 ? 1 : 0,
    'source': m['source'] ?? '',
    'sortOrder': m['sortOrder'] ?? 0,
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _pestRow(
    Map<String, dynamic> m,
    Map<String, String> idx,
  ) => {
    'id': m['id'],
    'crop': m['crop']?.toString() == '通用' ? '通用' : _crop(m, idx),
    'name': m['name'] ?? '',
    'category': m['category'] ?? '',
    'symptoms': m['symptoms'] ?? '',
    'cause': m['cause'] ?? '',
    'treatment': m['treatment'] ?? '',
    'prevention': m['prevention'] ?? '',
    'image': m['image'] ?? '',
    'incomplete': m['incomplete'] == true || m['incomplete'] == 1 ? 1 : 0,
    'source': m['source'] ?? '',
    'sortOrder': m['sortOrder'] ?? 0,
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _soilRow(
    Map<String, dynamic> m,
    Map<String, String> idx,
  ) => {
    'id': m['id'],
    'crop': m['crop']?.toString() == '通用' ? '通用' : _crop(m, idx),
    'name': m['name'] ?? '',
    'category': m['category'] ?? '配土',
    'description': m['description'] ?? '',
    'ingredients': m['ingredients'] ?? '',
    'method': m['method'] ?? '',
    'tips': m['tips'] ?? '',
    'image': m['image'] ?? '',
    'incomplete': m['incomplete'] == true || m['incomplete'] == 1 ? 1 : 0,
    'source': m['source'] ?? '',
    'sortOrder': m['sortOrder'] ?? 0,
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _stageRow(
    Map<String, dynamic> m,
    Map<String, String> idx,
  ) => {
    'id': m['id'],
    'crop': _crop(m, idx),
    'name': m['name'] ?? '',
    'sortOrder': m['sortOrder'] ?? 0,
    'startDay': m['startDay'] ?? 0,
    'endDay': m['endDay'] ?? 0,
    'color': m['color'] ?? '#3E9B6B',
    'fertilizerPlan': m['fertilizerPlan'] ?? '',
    'pestControl': m['pestControl'] ?? '',
    'operationTips': m['operationTips'] ?? '',
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _stageReminderRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'stageId': m['stageId'] ?? '',
    'kind': normKind(m['kind'] as String?),
    'title': m['title'] ?? '',
    'startOffset': m['startOffset'] ?? 1,
    'intervalDays': m['intervalDays'] ?? 0,
    'repeatCount': m['repeatCount'] ?? 1,
    'notes': m['notes'] ?? '',
    'enabled': m['enabled'] == false ? 0 : 1,
    'sortOrder': m['sortOrder'] ?? 0,
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _cropRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'name': m['name'] ?? '',
    'emoji': m['emoji'] ?? '🌱',
    'color': m['color'] ?? '#4A7FC0',
    'lifeCycle': m['lifeCycle'] ?? 'annual',
    'cycleStart': m['cycleStart'] ?? '',
    'unit': m['unit'] ?? '盆',
    'isDefault': m['isDefault'] == true || m['isDefault'] == 1 ? 1 : 0,
    'enabled': m['enabled'] == false ? 0 : 1,
    'image': m['image'] ?? '',
    'sortOrder': m['sortOrder'] ?? 0,
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _batchRow(
    Map<String, dynamic> m,
    Map<String, String> idx,
  ) => {
    'id': m['id'],
    'crop': _crop(m, idx),
    'name': m['name'] ?? '',
    'variety': m['varietyName'] ?? m['variety'] ?? '',
    'varietyId': m['varietyId'] ?? '',
    'plantDate': m['plantDate'] ?? '',
    'cycleStartDate': m['cycleStartDate'] ?? '',
    'location': m['location'] ?? '',
    'potCount': m['potCount'] ?? 1,
    'status': m['status'] ?? '进行中',
    'color': m['color'] ?? '#D9534F',
    'notes': m['notes'] ?? '',
    'sortOrder': m['sortOrder'] ?? 0,
    'growthOffsetDays': m['growthOffsetDays'] ?? 0,
    'stuntedSince': m['stuntedSince'],
    'photoMode': m['photoMode'] ?? 'batch',
    'archived': m['archived'] == true || m['archived'] == 1 ? 1 : 0,
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _materialRow(Map<String, dynamic> m, String kind) => {
    'id': m['id'],
    'kind': kind,
    'name': m['name'] ?? '',
    'ratio': m['ratio'] ?? '',
    'method': m['method'] ?? '灌根',
    'notes': m['notes'] ?? '',
    'image': m['image'] ?? '',
    'incomplete': m['incomplete'] == true || m['incomplete'] == 1 ? 1 : 0,
    'source': m['source'] ?? '',
    'sortOrder': m['sortOrder'] ?? 0,
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _potRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'batchId': m['batchId'] ?? '',
    'idx': (m['idx'] as num?)?.toInt() ?? 1,
    'state': m['state'] ?? 'alive',
    'note': m['note'] ?? '',
    'changedAt': m['changedAt'] ?? '',
    'rev': (m['rev'] as num?)?.toInt() ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _recordRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'batchId': m['batchId'] ?? '',
    'type': normRecordType(m['type'] as String?),
    'date': m['date'] ?? '',
    'title': m['title'] ?? '',
    'productName': m['productName'] ?? '',
    'dosage': m['dosage'] ?? '',
    'method': m['method'] ?? '',
    'products': jsonEncode(m['products'] ?? const []),
    'images': jsonEncode(m['images'] ?? const []),
    'potIndex': (m['potIndex'] as num?)?.toInt() ?? 0,
    'imgW': (m['imgW'] as num?)?.toInt() ?? 0,
    'imgH': (m['imgH'] as num?)?.toInt() ?? 0,
    'notes': m['notes'] ?? '',
    'stageId': m['stageId'] ?? '',
    'reminderId': m['reminderId'] ?? '',
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _reminderRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'batchId': m['batchId'] ?? '',
    'kind': normKind(m['kind'] as String?),
    'title': m['title'] ?? '',
    'intervalDays': m['intervalDays'] ?? 1,
    'nextDueAt': m['nextDueAt'] ?? '',
    'lastDoneAt': m['lastDoneAt'] ?? '',
    'active': m['active'] == false ? 0 : 1,
    'isOneTime': m['isOneTime'] == true || m['isOneTime'] == 1 ? 1 : 0,
    'notes': m['notes'] ?? '',
    'templateId': m['templateId'] ?? '',
    'stageId': m['stageId'] ?? '',
    'groupId': m['groupId'] ?? '',
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };
}
