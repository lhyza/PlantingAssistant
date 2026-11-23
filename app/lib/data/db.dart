import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/util.dart';

class Db {
  Db._();
  static final Db instance = Db._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'planting.db');
    _db = await openDatabase(
      path,
      version: 8,
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) {
          await d.execute('ALTER TABLE crops ADD COLUMN image TEXT');
        }
        if (oldV < 3) {
          try {
            await d.execute('ALTER TABLE records ADD COLUMN products TEXT');
          } catch (_) {}
          await d.execute('''CREATE TABLE IF NOT EXISTS materials(
        id TEXT PRIMARY KEY, kind TEXT, name TEXT, ratio TEXT, method TEXT,
        notes TEXT, image TEXT, scope TEXT, disabledCrops TEXT,
        incomplete INTEGER DEFAULT 0, source TEXT,
        sortOrder INTEGER DEFAULT 0, rev INTEGER DEFAULT 1,
        createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''');
          await d.execute(
            'CREATE INDEX IF NOT EXISTS idx_mat_kind ON materials(kind)',
          );
        }
        if (oldV < 4) {
          try {
            await d.execute('ALTER TABLE materials ADD COLUMN scope TEXT');
          } catch (_) {}
          try {
            await d.execute(
              'ALTER TABLE materials ADD COLUMN disabledCrops TEXT',
            );
          } catch (_) {}
        }
        if (oldV < 5) {
          try {
            await d.execute(
              "ALTER TABLE batches ADD COLUMN photoMode TEXT DEFAULT 'batch'",
            );
          } catch (_) {}
          try {
            await d.execute(
              'ALTER TABLE records ADD COLUMN potIndex INTEGER DEFAULT 0',
            );
          } catch (_) {}
          try {
            await d.execute(
              'ALTER TABLE records ADD COLUMN imgW INTEGER DEFAULT 0',
            );
          } catch (_) {}
          try {
            await d.execute(
              'ALTER TABLE records ADD COLUMN imgH INTEGER DEFAULT 0',
            );
          } catch (_) {}
          await d.execute('''CREATE TABLE IF NOT EXISTS pots(
        id TEXT PRIMARY KEY, batchId TEXT, idx INTEGER DEFAULT 1,
        state TEXT DEFAULT 'alive', note TEXT, changedAt TEXT,
        rev INTEGER DEFAULT 1, createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''');
          await d.execute(
            'CREATE INDEX IF NOT EXISTS idx_pot_batch ON pots(batchId)',
          );
          // 老批次：按 potCount 补齐盆；历史"整批僵苗"落到每盆
          final bs = await d.query('batches');
          for (final b in bs) {
            final n = (b['potCount'] as num?)?.toInt() ?? 1;
            final stunted = (b['stuntedSince'] as String?) ?? '';
            for (var i = 1; i <= n; i++) {
              await d.insert('pots', {
                'id': '${b['id']}_pot_$i',
                'batchId': b['id'],
                'idx': i,
                'state': stunted.isEmpty ? 'alive' : 'stunted',
                'note': '',
                'changedAt': stunted,
                'rev': 1,
                'createdAt': nowStamp(),
                'updatedAt': nowStamp(),
                'deletedAt': null,
              });
            }
          }
        }
        if (oldV < 6) {
          try {
            await d.execute(
              "ALTER TABLE reminders ADD COLUMN groupId TEXT DEFAULT ''",
            );
          } catch (_) {}
          try {
            await d.execute(
              'CREATE INDEX IF NOT EXISTS idx_rem_group ON reminders(groupId)',
            );
          } catch (_) {}
        }
        if (oldV < 8) {
          try {
            await d.execute('ALTER TABLE pests ADD COLUMN crops TEXT');
          } catch (_) {}
          for (final t in ['varieties', 'pests']) {
            try {
              await d.execute(
                'ALTER TABLE $t ADD COLUMN imgPending INTEGER DEFAULT 0',
              );
            } catch (_) {}
          }
          // 老数据：把单一 crop 升级成 crops 数组
          await d.execute(
            "UPDATE pests SET crops = '[\"' || crop || '\"]' "
            "WHERE (crops IS NULL OR crops = '') AND crop IS NOT NULL",
          );
        }
      },
      onConfigure: (d) async {
        await d.execute('PRAGMA foreign_keys = OFF');
      },
      onCreate: (d, v) async {
        await _createSchema(d);
      },
    );
    await _seedIfEmpty();
    return _db!;
  }

  Future<void> _createSchema(Database d) async {
    const sql = [
      '''CREATE TABLE crops(
        id TEXT PRIMARY KEY, name TEXT, emoji TEXT, color TEXT,
        lifeCycle TEXT, cycleStart TEXT, unit TEXT, isDefault INTEGER DEFAULT 0,
        enabled INTEGER DEFAULT 1, image TEXT, sortOrder INTEGER DEFAULT 0, rev INTEGER DEFAULT 1,
        createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''',
      '''CREATE TABLE varieties(
        id TEXT PRIMARY KEY, crop TEXT, name TEXT, category TEXT, characteristics TEXT,
        suitable TEXT, care TEXT, yieldText TEXT, taste TEXT, sweetness TEXT,
        sweetnessStar INTEGER DEFAULT 0, fruitSize TEXT, sizeStar INTEGER DEFAULT 0,
        heatResistance TEXT, heatStar INTEGER DEFAULT 0, image TEXT,
        imgPending INTEGER DEFAULT 0,
        incomplete INTEGER DEFAULT 0, source TEXT, sortOrder INTEGER DEFAULT 0,
        rev INTEGER DEFAULT 1, createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''',
      '''CREATE TABLE pests(
        id TEXT PRIMARY KEY, crop TEXT, name TEXT, category TEXT, symptoms TEXT,
        cause TEXT, treatment TEXT, prevention TEXT, image TEXT, crops TEXT,
        imgPending INTEGER DEFAULT 0,
        incomplete INTEGER DEFAULT 0, source TEXT, sortOrder INTEGER DEFAULT 0,
        rev INTEGER DEFAULT 1, createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''',
      '''CREATE TABLE soils(
        id TEXT PRIMARY KEY, crop TEXT, name TEXT, category TEXT, description TEXT,
        ingredients TEXT, method TEXT, tips TEXT, image TEXT,
        incomplete INTEGER DEFAULT 0, source TEXT, sortOrder INTEGER DEFAULT 0,
        rev INTEGER DEFAULT 1, createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''',
      '''CREATE TABLE stages(
        id TEXT PRIMARY KEY, crop TEXT, name TEXT, sortOrder INTEGER DEFAULT 0,
        startDay INTEGER DEFAULT 0, endDay INTEGER DEFAULT 0, color TEXT,
        fertilizerPlan TEXT, pestControl TEXT, operationTips TEXT,
        rev INTEGER DEFAULT 1, createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''',
      '''CREATE TABLE stage_reminders(
        id TEXT PRIMARY KEY, stageId TEXT, kind TEXT, title TEXT,
        startOffset INTEGER DEFAULT 1, intervalDays INTEGER DEFAULT 0,
        repeatCount INTEGER DEFAULT 1, notes TEXT, enabled INTEGER DEFAULT 1,
        sortOrder INTEGER DEFAULT 0, rev INTEGER DEFAULT 1,
        createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''',
      '''CREATE TABLE batches(
        id TEXT PRIMARY KEY, crop TEXT, name TEXT, variety TEXT, varietyId TEXT,
        plantDate TEXT, cycleStartDate TEXT, location TEXT, potCount INTEGER DEFAULT 1,
        status TEXT, color TEXT, notes TEXT, sortOrder INTEGER DEFAULT 0,
        growthOffsetDays INTEGER DEFAULT 0, stuntedSince TEXT,
        photoMode TEXT DEFAULT 'batch', archived INTEGER DEFAULT 0,
        rev INTEGER DEFAULT 1, createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''',
      '''CREATE TABLE records(
        id TEXT PRIMARY KEY, batchId TEXT, type TEXT, date TEXT, title TEXT,
        productName TEXT, dosage TEXT, method TEXT, products TEXT, images TEXT,
        potIndex INTEGER DEFAULT 0, imgW INTEGER DEFAULT 0, imgH INTEGER DEFAULT 0,
        notes TEXT, stageId TEXT, reminderId TEXT, rev INTEGER DEFAULT 1,
        createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''',
      '''CREATE TABLE reminders(
        id TEXT PRIMARY KEY, batchId TEXT, kind TEXT, title TEXT,
        intervalDays INTEGER DEFAULT 1, nextDueAt TEXT, lastDoneAt TEXT,
        active INTEGER DEFAULT 1, isOneTime INTEGER DEFAULT 0, notes TEXT,
        templateId TEXT, stageId TEXT, groupId TEXT DEFAULT '',
        rev INTEGER DEFAULT 1, createdAt TEXT, updatedAt TEXT,
        deletedAt TEXT)''',
      '''CREATE TABLE materials(
        id TEXT PRIMARY KEY, kind TEXT, name TEXT, ratio TEXT, method TEXT,
        notes TEXT, image TEXT, scope TEXT, disabledCrops TEXT,
        incomplete INTEGER DEFAULT 0, source TEXT,
        sortOrder INTEGER DEFAULT 0, rev INTEGER DEFAULT 1,
        createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''',
      '''CREATE TABLE pots(
        id TEXT PRIMARY KEY, batchId TEXT, idx INTEGER DEFAULT 1,
        state TEXT DEFAULT 'alive', note TEXT, changedAt TEXT,
        rev INTEGER DEFAULT 1, createdAt TEXT, updatedAt TEXT, deletedAt TEXT)''',
      '''CREATE TABLE lib_meta(
        kind TEXT PRIMARY KEY, libraryId TEXT, name TEXT, updatedAt TEXT,
        revision INTEGER DEFAULT 1)''',
      '''CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)''',
      'CREATE INDEX idx_stage_crop ON stages(crop)',
      'CREATE INDEX idx_rem_stage ON stage_reminders(stageId)',
      'CREATE INDEX idx_batch_crop ON batches(crop)',
      'CREATE INDEX idx_rec_batch ON records(batchId)',
      'CREATE INDEX idx_mat_kind ON materials(kind)',
      'CREATE INDEX idx_pot_batch ON pots(batchId)',
      'CREATE INDEX idx_rem_batch ON reminders(batchId)',
    ];
    for (final s in sql) {
      await d.execute(s);
    }
  }

  Future<bool> _seedIfEmpty() async {
    final d = _db!;
    final n =
        Sqflite.firstIntValue(await d.rawQuery('SELECT COUNT(*) FROM crops')) ??
        0;
    if (n > 0) return false;
    await seedFromAssets(d);
    return true;
  }

  Future<void> seedFromAssets(Database d) async {
    final seed = jsonDecode(
      await _assetText('assets/seeds/strawberry-stages.json'),
    ) as Map<String, dynamic>;
    final vars = jsonDecode(
      await _assetText('assets/seeds/strawberry-varieties.json'),
    ) as Map<String, dynamic>;
    final pests = jsonDecode(
      await _assetText('assets/seeds/strawberry-pests.json'),
    ) as Map<String, dynamic>;
    final soils = jsonDecode(
      await _assetText('assets/seeds/strawberry-soil.json'),
    ) as Map<String, dynamic>;
    final garden = jsonDecode(
      await _assetText('assets/seeds/strawberry-garden.json'),
    ) as Map<String, dynamic>;

    for (final m in [seed, vars, pests, soils]) {
      await _writeMeta(d, m);
    }
    await _writeMeta(d, garden);

    for (final raw in (seed['crops'] as List? ?? const [])) {
      final c = Map<String, dynamic>.from(raw as Map);
      await d.insert(
        'crops',
        _cropRow(c),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final raw in (seed['items'] as List? ?? const [])) {
      await _insertStage(d, Map<String, dynamic>.from(raw as Map));
    }
    for (final raw in (vars['items'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await d.insert(
        'varieties',
        _varietyRow(m),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final raw in (pests['items'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await d.insert(
        'pests',
        _pestRow(m),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final raw in (soils['items'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await d.insert(
        'soils',
        _soilRow(m),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final cropIndex = await cropNameIndex(d);
    for (final raw in (garden['batches'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      final row = _batchRow(m, cropIndex);
      await d.insert(
        'batches',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final raw in (garden['records'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await d.insert(
        'records',
        _recordRow(m),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    for (final raw in (garden['reminders'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await d.insert(
        'reminders',
        _reminderRow(m),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await normalizeCropRefs(d);
  }

  /// 把种子/导入文件里的中文作物名统一成 crops.id（'通用' 保持不动）
  Future<void> normalizeCropRefs(DatabaseExecutor d) async {
    for (final t in const [
      'varieties',
      'pests',
      'soils',
      'stages',
      'batches',
    ]) {
      await d.rawUpdate(
        'UPDATE $t SET crop = (SELECT id FROM crops WHERE crops.name = $t.crop) '
        'WHERE crop IN (SELECT name FROM crops)',
      );
    }
  }

  Future<void> _insertStage(Database d, Map<String, dynamic> m) async {
    await d.insert(
      'stages',
      _stageRow(m),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    for (final raw in (m['reminders'] as List? ?? const [])) {
      final r = Map<String, dynamic>.from(raw as Map);
      r['stageId'] = m['id'];
      await d.insert(
        'stage_reminders',
        _stageReminderRow(r),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<String> _assetText(String key) async {
    return rootBundle.loadString(key);
  }

  Future<void> _writeMeta(Database d, Map<String, dynamic> m) async {
    await d.insert('lib_meta', {
      'kind': m['kind'] ?? '',
      'libraryId': m['libraryId'] ?? '',
      'name': m['name'] ?? '',
      'updatedAt': m['updatedAt'] ?? '',
      'revision': m['revision'] ?? 1,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> cropNameIndex(Database d) async {
    final rows = await d.query('crops');
    final map = <String, String>{};
    for (final r in rows) {
      map[r['name'] as String? ?? ''] = r['id'] as String;
      map[r['id'] as String] = r['id'] as String;
    }
    map['通用'] = '通用';
    return map;
  }

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

  Map<String, dynamic> _varietyRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'crop': m['crop'] ?? '',
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
    'imgPending': m['imgPending'] == true || m['imgPending'] == 1 ? 1 : 0,
    'incomplete': m['incomplete'] == true || m['incomplete'] == 1 ? 1 : 0,
    'source': m['source'] ?? '',
    'sortOrder': m['sortOrder'] ?? 0,
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _pestRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'crop': m['crop'] ?? '通用',
    'name': m['name'] ?? '',
    'category': m['category'] ?? '',
    'symptoms': m['symptoms'] ?? '',
    'cause': m['cause'] ?? '',
    'treatment': m['treatment'] ?? '',
    'prevention': m['prevention'] ?? '',
    'image': m['image'] ?? '',
    'crops': _cropsJson(m['crops']),
    'imgPending': m['imgPending'] == true || m['imgPending'] == 1 ? 1 : 0,
    'incomplete': m['incomplete'] == true || m['incomplete'] == 1 ? 1 : 0,
    'source': m['source'] ?? '',
    'sortOrder': m['sortOrder'] ?? 0,
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _soilRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'crop': m['crop'] ?? '通用',
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

  Map<String, dynamic> _stageRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'crop': m['crop'] ?? '',
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
    'kind': m['kind'] ?? '施肥',
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

  Map<String, dynamic> _batchRow(
    Map<String, dynamic> m,
    Map<String, String> cropIndex,
  ) => {
    'id': m['id'],
    'crop': cropIndex[m['crop']?.toString()] ?? (m['crop'] ?? ''),
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

  Map<String, dynamic> _potRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'batchId': m['batchId'] ?? '',
    'idx': ((m['idx'] as num?) ?? 1).toInt(),
    'state': m['state'] ?? 'alive',
    'note': m['note'] ?? '',
    'changedAt': m['changedAt'] ?? '',
    'rev': ((m['rev'] as num?) ?? 1).toInt(),
    'createdAt': m['createdAt'] ?? nowStamp(),
    'updatedAt': m['updatedAt'] ?? nowStamp(),
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _recordRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'batchId': m['batchId'] ?? '',
    'type': m['type'] ?? '其他',
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

  Map<String, dynamic> _materialRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'kind': m['kind'] ?? 'fertilizer',
    'name': m['name'] ?? '',
    'ratio': m['ratio'] ?? '',
    'method': m['method'] ?? '灌根',
    'notes': m['notes'] ?? '',
    'image': m['image'] ?? '',
    'scope': m['scope'] ?? 'common',
    'disabledCrops': m['disabledCrops'] is String
        ? m['disabledCrops']
        : jsonEncode(m['disabledCrops'] ?? const []),
    'incomplete': m['incomplete'] == true || m['incomplete'] == 1 ? 1 : 0,
    'source': m['source'] ?? 'manual',
    'sortOrder': m['sortOrder'] ?? 0,
    'rev': m['rev'] ?? 1,
    'createdAt': m['createdAt'] ?? '',
    'updatedAt': m['updatedAt'] ?? '',
    'deletedAt': m['deletedAt'],
  };

  Map<String, dynamic> _reminderRow(Map<String, dynamic> m) => {
    'id': m['id'],
    'batchId': m['batchId'] ?? '',
    'kind': m['kind'] ?? '浇水',
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

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<String> appDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> exportDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory(p.join(dir.path, 'export'));
    if (!await out.exists()) await out.create(recursive: true);
    return out.path;
  }
}

String? _cropsJson(dynamic v) {
  if (v == null) return null;
  if (v is List) {
    final list = v.map((e) => e.toString()).toList();
    return list.isEmpty ? null : jsonEncode(list);
  }
  final t = v.toString().trim();
  return t.isEmpty ? null : t;
}
