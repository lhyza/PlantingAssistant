/// 数据模型：与 docs/03 的七份 JSON 一一对应
library;

import 'dart:convert';

class CropSeason {
  CropSeason({required this.idx, this.name = '', this.start = ''});
  int idx; // 1..3
  String name; // 夏果季 / 本季
  String start; // MM-DD；一年生留空（用定植日）
  Map<String, dynamic> toMap() => {'idx': idx, 'name': name, 'start': start};
  static CropSeason fromMap(Map<String, dynamic> m) => CropSeason(
    idx: (m['idx'] as num?)?.toInt() ?? 1,
    name: (m['name'] ?? '').toString(),
    start: (m['start'] ?? '').toString(),
  );

  /// 解析 JSON 字符串或 List（兼容种子文件与 DB）
  static List<CropSeason> parse(dynamic v) {
    dynamic raw = v;
    if (raw is String) {
      if (raw.trim().isEmpty) return [];
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return [];
      }
    }
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => CropSeason.fromMap(Map<String, dynamic>.from(e)))
        .toList()
      ..sort((a, b) => a.idx.compareTo(b.idx));
  }
}

class Crop {
  Crop({
    required this.id,
    required this.name,
    this.emoji = '🌱',
    this.color = '#4A7FC0',
    this.lifeCycle = 'annual',
    this.cycleStart = '',
    List<CropSeason>? seasons,
    this.unit = '盆',
    this.isDefault = false,
    this.enabled = true,
    this.image = '',
    this.iconImage = '',
    this.sortOrder = 0,
    this.rev = 1,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  }) : seasons = seasons ?? [];

  final String id;
  String name;
  String emoji;
  String color;
  String lifeCycle; // annual | perennial
  String cycleStart; // MM-DD
  List<CropSeason> seasons; // v1.7：1~3 季
  String unit;
  bool isDefault;
  bool enabled;
  String image;

  /// 作物图标（相对路径，存进 images/ 的小图）；为空时用 emoji
  String iconImage;
  int sortOrder;
  int rev;
  String createdAt;
  String updatedAt;
  String? deletedAt;

  bool get isPerennial => lifeCycle == 'perennial';

  /// 有效的季列表：永远至少 1 季（老数据或一年生）
  List<CropSeason> get effSeasons {
    if (seasons.isNotEmpty) return seasons;
    return [CropSeason(idx: 1, name: '本季', start: cycleStart)];
  }

  int get seasonCount => effSeasons.length;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'color': color,
    'lifeCycle': lifeCycle,
    'cycleStart': cycleStart,
    'seasons': jsonEncode(seasons.map((e) => e.toMap()).toList()),
    'unit': unit,
    'isDefault': isDefault ? 1 : 0,
    'enabled': enabled ? 1 : 0,
    'image': image,
    'iconImage': iconImage,
    'sortOrder': sortOrder,
    'rev': rev,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  static Crop fromMap(Map<String, dynamic> m) => Crop(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    emoji: m['emoji'] as String? ?? '🌱',
    color: m['color'] as String? ?? '#4A7FC0',
    lifeCycle: m['lifeCycle'] as String? ?? 'annual',
    cycleStart: m['cycleStart'] as String? ?? '',
    seasons: CropSeason.parse(m['seasons']),
    unit: m['unit'] as String? ?? '盆',
    isDefault: (m['isDefault'] ?? 0) == 1,
    enabled: (m['enabled'] ?? 1) == 1,
    image: m['image'] as String? ?? '',
    iconImage: m['iconImage'] as String? ?? '',
    sortOrder: m['sortOrder'] as int? ?? 0,
    rev: m['rev'] as int? ?? 1,
    createdAt: m['createdAt'] as String? ?? '',
    updatedAt: m['updatedAt'] as String? ?? '',
    deletedAt: m['deletedAt'] as String?,
  );
}

class Variety {
  Variety({
    required this.id,
    required this.crop,
    this.name = '',
    this.category = '',
    this.characteristics = '',
    this.suitable = '',
    this.care = '',
    this.yieldText = '',
    this.taste = '',
    this.sweetness = '',
    this.sweetnessStar = 0,
    this.fruitSize = '',
    this.sizeStar = 0,
    this.heatResistance = '',
    this.heatStar = 0,
    this.image = '',
    this.imgPending = false,
    this.incomplete = false,
    this.source = '',
    this.sortOrder = 0,
    this.rev = 1,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  });

  final String id;
  String crop;
  String name;
  String category;
  String characteristics;
  String suitable;
  String care;
  String yieldText;
  String taste;
  String sweetness;
  int sweetnessStar;
  String fruitSize;
  int sizeStar;
  String heatResistance;
  int heatStar;
  String image;
  bool imgPending; // AI 导入的原始图，等用户裁剪确认
  bool incomplete;
  String source;
  int sortOrder;
  int rev;
  String createdAt;
  String updatedAt;
  String? deletedAt;

  String get code => id.replaceAll('var_', '');
  String get starText =>
      '甜度 ${'★' * sweetnessStar}${'☆' * (5 - sweetnessStar)}';

  Map<String, dynamic> toMap() => {
    'id': id,
    'crop': crop,
    'name': name,
    'category': category,
    'characteristics': characteristics,
    'suitable': suitable,
    'care': care,
    'yieldText': yieldText,
    'taste': taste,
    'sweetness': sweetness,
    'sweetnessStar': sweetnessStar,
    'fruitSize': fruitSize,
    'sizeStar': sizeStar,
    'heatResistance': heatResistance,
    'heatStar': heatStar,
    'image': image,
    'imgPending': imgPending ? 1 : 0,
    'incomplete': incomplete ? 1 : 0,
    'source': source,
    'sortOrder': sortOrder,
    'rev': rev,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  static Variety fromMap(Map<String, dynamic> m) => Variety(
    id: m['id'] as String,
    crop: m['crop'] as String? ?? 'crop_strawberry',
    name: m['name'] as String? ?? '',
    category: m['category'] as String? ?? '',
    characteristics: m['characteristics'] as String? ?? '',
    suitable: m['suitable'] as String? ?? '',
    care: m['care'] as String? ?? '',
    yieldText: m['yield'] as String? ?? '',
    taste: m['taste'] as String? ?? '',
    sweetness: m['sweetness'] as String? ?? '',
    sweetnessStar: ((m['sweetnessStar'] as num?) ?? 0).toInt(),
    fruitSize: m['fruitSize'] as String? ?? '',
    sizeStar: ((m['sizeStar'] as num?) ?? 0).toInt(),
    heatResistance: m['heatResistance'] as String? ?? '',
    heatStar: ((m['heatStar'] as num?) ?? 0).toInt(),
    image: m['image'] as String? ?? '',
    imgPending: (m['imgPending'] ?? 0) == 1,
    incomplete: (m['incomplete'] ?? 0) == 1,
    source: m['source'] as String? ?? '',
    sortOrder: m['sortOrder'] as int? ?? 0,
    rev: m['rev'] as int? ?? 1,
    createdAt: m['createdAt'] as String? ?? '',
    updatedAt: m['updatedAt'] as String? ?? '',
    deletedAt: m['deletedAt'] as String?,
  );
}

class Pest {
  Pest({
    required this.id,
    this.crop = '通用',
    this.name = '',
    this.category = '',
    this.symptoms = '',
    this.cause = '',
    this.treatment = '',
    this.prevention = '',
    this.image = '',
    this.imgPending = false,
    this.crops = const [],
    this.source = '',
    this.incomplete = false,
    this.sortOrder = 0,
    this.rev = 1,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  });

  final String id;
  String crop;
  String name;
  String category;

  /// 该病虫害影响的作物 id 列表。为空时回退到 [crop]（含「通用」）。
  List<String> crops;

  /// 是否影响某个作物：命中 list，或 crop 为「通用」。
  bool hits(String cropId) {
    if (crop == '通用') return true;
    if (crops.contains(cropId)) return true;
    return crops.isEmpty && crop == cropId;
  }

  /// 「通用」或作物名用「、」连接。
  ///
  /// [nameById] 是「作物 id → 作物名」的映射；crops 里存的是 id，
  /// 所以必须按 id 查名字，不能拿 id 去名字数组里 indexOf（历史 bug：
  /// 会直接显示成 crop_strawberry）。查不到就原样输出，兼容历史中文名。
  String cropsText(Map<String, String> nameById) {
    if (crop == '通用' || crops.isEmpty) return '通用';
    return crops.map((v) => nameById[v] ?? v).join('、');
  }

  String symptoms;
  String cause;
  String treatment;
  String prevention;
  String image;
  bool imgPending;
  String source;
  bool incomplete;
  int sortOrder;
  int rev;
  String createdAt;
  String updatedAt;
  String? deletedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'crop': crop,
    'name': name,
    'category': category,
    'symptoms': symptoms,
    'cause': cause,
    'treatment': treatment,
    'prevention': prevention,
    'image': image,
    'crops': crops.isEmpty ? null : _jsonList(crops),
    'imgPending': imgPending ? 1 : 0,
    'source': source,
    'incomplete': incomplete ? 1 : 0,
    'sortOrder': sortOrder,
    'rev': rev,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  static Pest fromMap(Map<String, dynamic> m) => Pest(
    id: m['id'] as String,
    crop: m['crop'] as String? ?? '通用',
    name: m['name'] as String? ?? '',
    category: m['category'] as String? ?? '',
    symptoms: m['symptoms'] as String? ?? '',
    cause: m['cause'] as String? ?? '',
    treatment: m['treatment'] as String? ?? '',
    prevention: m['prevention'] as String? ?? '',
    image: m['image'] as String? ?? '',
    crops: _strList(m['crops']),
    imgPending: (m['imgPending'] as int? ?? 0) == 1,
    source: m['source'] as String? ?? '',
    incomplete: (m['incomplete'] as int? ?? 0) == 1,
    sortOrder: m['sortOrder'] as int? ?? 0,
    rev: m['rev'] as int? ?? 1,
    createdAt: m['createdAt'] as String? ?? '',
    updatedAt: m['updatedAt'] as String? ?? '',
    deletedAt: m['deletedAt'] as String?,
  );
}

class Soil {
  Soil({
    required this.id,
    this.crop = '通用',
    this.name = '',
    this.category = '配土',
    this.description = '',
    this.ingredients = '',
    this.method = '',
    this.tips = '',
    this.image = '',
    this.incomplete = false,
    this.sortOrder = 0,
    this.rev = 1,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  });

  final String id;
  String crop;
  String name;
  String category;
  String description;
  String ingredients;
  String method;
  String tips;
  String image;
  bool incomplete;
  int sortOrder;
  int rev;
  String createdAt;
  String updatedAt;
  String? deletedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'crop': crop,
    'name': name,
    'category': category,
    'description': description,
    'ingredients': ingredients,
    'method': method,
    'tips': tips,
    'image': image,
    'incomplete': incomplete ? 1 : 0,
    'sortOrder': sortOrder,
    'rev': rev,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  static Soil fromMap(Map<String, dynamic> m) => Soil(
    id: m['id'] as String,
    crop: m['crop'] as String? ?? '通用',
    name: m['name'] as String? ?? '',
    category: m['category'] as String? ?? '配土',
    description: m['description'] as String? ?? '',
    ingredients: m['ingredients'] as String? ?? '',
    method: m['method'] as String? ?? '',
    tips: m['tips'] as String? ?? '',
    image: m['image'] as String? ?? '',
    incomplete: (m['incomplete'] as int? ?? 0) == 1,
    sortOrder: m['sortOrder'] as int? ?? 0,
    rev: m['rev'] as int? ?? 1,
    createdAt: m['createdAt'] as String? ?? '',
    updatedAt: m['updatedAt'] as String? ?? '',
    deletedAt: m['deletedAt'] as String?,
  );
}

class StageReminder {
  StageReminder({
    required this.id,
    required this.stageId,
    this.kind = '施肥',
    this.title = '',
    this.startOffset = 1,
    this.intervalDays = 0,
    this.repeatCount = 1,
    this.notes = '',
    this.enabled = true,
    this.sortOrder = 0,
    this.rev = 1,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  });

  final String id;
  String stageId;
  String kind;
  String title;
  int startOffset;
  int intervalDays;
  int repeatCount;
  String notes;
  bool enabled;
  int sortOrder;
  int rev;
  String createdAt;
  String updatedAt;
  String? deletedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'stageId': stageId,
    'kind': kind,
    'title': title,
    'startOffset': startOffset,
    'intervalDays': intervalDays,
    'repeatCount': repeatCount,
    'notes': notes,
    'enabled': enabled ? 1 : 0,
    'sortOrder': sortOrder,
    'rev': rev,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  static StageReminder fromMap(Map<String, dynamic> m) => StageReminder(
    id: m['id'] as String,
    stageId: m['stageId'] as String? ?? '',
    kind: m['kind'] as String? ?? '施肥',
    title: m['title'] as String? ?? '',
    startOffset: m['startOffset'] as int? ?? 1,
    intervalDays: m['intervalDays'] as int? ?? 0,
    repeatCount: m['repeatCount'] as int? ?? 1,
    notes: m['notes'] as String? ?? '',
    enabled: (m['enabled'] ?? 1) == 1,
    sortOrder: m['sortOrder'] as int? ?? 0,
    rev: m['rev'] as int? ?? 1,
    createdAt: m['createdAt'] as String? ?? '',
    updatedAt: m['updatedAt'] as String? ?? '',
    deletedAt: m['deletedAt'] as String?,
  );
}

class Stage {
  Stage({
    required this.id,
    required this.crop,
    this.season = 0,
    this.name = '',
    this.sortOrder = 0,
    this.startDay = 0,
    this.endDay = 0,
    this.color = '#3E9B6B',
    this.fertilizerPlan = '',
    this.pestControl = '',
    this.operationTips = '',
    this.rev = 1,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  });

  final String id;
  String crop;
  int season; // 0 起；对应 crop.effSeasons 下标
  String name;
  int sortOrder;
  int startDay;
  int endDay;
  String color;
  String fertilizerPlan;
  String pestControl;
  String operationTips;
  int rev;
  String createdAt;
  String updatedAt;
  String? deletedAt;

  int get days => endDay - startDay + 1;

  Map<String, dynamic> toMap() => {
    'id': id,
    'crop': crop,
    'season': season,
    'name': name,
    'sortOrder': sortOrder,
    'startDay': startDay,
    'endDay': endDay,
    'color': color,
    'fertilizerPlan': fertilizerPlan,
    'pestControl': pestControl,
    'operationTips': operationTips,
    'rev': rev,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  static Stage fromMap(Map<String, dynamic> m) => Stage(
    id: m['id'] as String,
    crop: m['crop'] as String? ?? '',
    season: (m['season'] as num?)?.toInt() ?? 0,
    name: m['name'] as String? ?? '',
    sortOrder: m['sortOrder'] as int? ?? 0,
    startDay: m['startDay'] as int? ?? 0,
    endDay: m['endDay'] as int? ?? 0,
    color: m['color'] as String? ?? '#3E9B6B',
    fertilizerPlan: m['fertilizerPlan'] as String? ?? '',
    pestControl: m['pestControl'] as String? ?? '',
    operationTips: m['operationTips'] as String? ?? '',
    rev: m['rev'] as int? ?? 1,
    createdAt: m['createdAt'] as String? ?? '',
    updatedAt: m['updatedAt'] as String? ?? '',
    deletedAt: m['deletedAt'] as String?,
  );
}

class Batch {
  Batch({
    required this.id,
    required this.crop,
    this.name = '',
    this.variety = '',
    this.varietyId = '',
    this.plantDate = '',
    this.cycleStartDate = '',
    this.season = 0,
    this.location = '',
    this.potCount = 1,
    this.status = '进行中',
    this.color = '#D9534F',
    this.notes = '',
    this.sortOrder = 0,
    this.growthOffsetDays = 0,
    this.stuntedSince,
    this.photoMode = 'batch',
    this.archived = false,
    this.rev = 1,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  });

  final String id;
  String crop;
  String name;
  String variety;
  String varietyId;
  String plantDate;
  String cycleStartDate;
  int season; // 0 起，对应 crop.effSeasons 下标
  String location;
  int potCount;
  String status;
  String color;
  String notes;
  int sortOrder;
  int growthOffsetDays;
  String? stuntedSince;

  /// batch = 整批拍；pot = 按盆拍
  String photoMode;
  bool archived;
  int rev;
  String createdAt;
  String updatedAt;
  String? deletedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'crop': crop,
    'name': name,
    'variety': variety,
    'varietyId': varietyId,
    'plantDate': plantDate,
    'cycleStartDate': cycleStartDate,
    'season': season,
    'location': location,
    'potCount': potCount,
    'status': status,
    'color': color,
    'notes': notes,
    'sortOrder': sortOrder,
    'growthOffsetDays': growthOffsetDays,
    'stuntedSince': stuntedSince,
    'photoMode': photoMode,
    'archived': archived ? 1 : 0,
    'rev': rev,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  static Batch fromMap(Map<String, dynamic> m) => Batch(
    id: m['id'] as String,
    crop: m['crop'] as String? ?? '',
    name: m['name'] as String? ?? '',
    variety: m['variety'] as String? ?? '',
    varietyId: m['varietyId'] as String? ?? '',
    plantDate: m['plantDate'] as String? ?? '',
    cycleStartDate: m['cycleStartDate'] as String? ?? '',
    season: (m['season'] as num?)?.toInt() ?? 0,
    location: m['location'] as String? ?? '',
    potCount: m['potCount'] as int? ?? 1,
    status: m['status'] as String? ?? '进行中',
    color: m['color'] as String? ?? '#D9534F',
    notes: m['notes'] as String? ?? '',
    sortOrder: m['sortOrder'] as int? ?? 0,
    growthOffsetDays: m['growthOffsetDays'] as int? ?? 0,
    stuntedSince: m['stuntedSince'] as String?,
    photoMode: m['photoMode'] as String? ?? 'batch',
    archived: (m['archived'] ?? 0) == 1,
    rev: m['rev'] as int? ?? 1,
    createdAt: m['createdAt'] as String? ?? '',
    updatedAt: m['updatedAt'] as String? ?? '',
    deletedAt: m['deletedAt'] as String?,
  );
}

class GardenRecord {
  GardenRecord({
    required this.id,
    required this.batchId,
    this.type = '其他',
    this.date = '',
    this.title = '',
    this.productName = '',
    this.dosage = '',
    this.method = '',
    this.products = const [],
    this.images = const [],
    this.potIndex = 0,
    this.imgW = 0,
    this.imgH = 0,
    this.notes = '',
    this.stageId = '',
    this.opId = '',
    List<String>? opSkipped,
    this.rev = 1,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  }) : opSkipped = opSkipped ?? [];

  final String id;
  String batchId;
  String type;
  String date;
  String title;
  String productName;
  String dosage;
  String method;
  List<RecordProduct> products;
  List<String> images;

  /// 0 = 批次级照片；>=1 = 第几盆
  int potIndex;
  int imgW;
  int imgH;
  String notes;
  String stageId;

  /// v1.7：同一次「记一笔」写出的多条记录共用一个 opId
  String opId;

  /// v1.7：这次没有勾选的批次 id 快照（「未施」名单）
  List<String> opSkipped;

  /// 本次操作的施用方式：优先记录级，旧记录回落到第一个产品的方式。
  String get effMethod {
    final m = method.trim();
    if (m.isNotEmpty) return m;
    for (final p in products) {
      final pm = p.effMethods;
      if (pm.isNotEmpty) return pm.first;
    }
    return '';
  }

  int rev;
  String createdAt;
  String updatedAt;
  String? deletedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'batchId': batchId,
    'type': type,
    'date': date,
    'title': title,
    'productName': productName,
    'dosage': dosage,
    'method': method,
    'products': products.map((e) => e.toMap()).toList(),
    'images': images,
    'potIndex': potIndex,
    'imgW': imgW,
    'imgH': imgH,
    'notes': notes,
    'stageId': stageId,
    'opId': opId,
    'opSkipped': opSkipped.isEmpty ? '' : jsonEncode(opSkipped),
    'rev': rev,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  static GardenRecord fromMap(Map<String, dynamic> m) => GardenRecord(
    id: m['id'] as String,
    batchId: m['batchId'] as String? ?? '',
    type: m['type'] as String? ?? '其他',
    date: m['date'] as String? ?? '',
    title: m['title'] as String? ?? '',
    productName: m['productName'] as String? ?? '',
    dosage: m['dosage'] as String? ?? '',
    method: m['method'] as String? ?? '',
    products: _productsOf(m['products']),
    images: _imagesOf(m['images']),
    potIndex: (m['potIndex'] as num?)?.toInt() ?? 0,
    imgW: (m['imgW'] as num?)?.toInt() ?? 0,
    imgH: (m['imgH'] as num?)?.toInt() ?? 0,
    notes: m['notes'] as String? ?? '',
    stageId: m['stageId'] as String? ?? '',
    opId: m['opId'] as String? ?? '',
    opSkipped: _strList(m['opSkipped']),
    rev: m['rev'] as int? ?? 1,
    createdAt: m['createdAt'] as String? ?? '',
    updatedAt: m['updatedAt'] as String? ?? '',
    deletedAt: m['deletedAt'] as String?,
  );
}

class Reminder {
  Reminder({
    required this.id,
    required this.batchId,
    this.kind = '浇水',
    this.title = '',
    this.intervalDays = 1,
    this.nextDueAt = '',
    this.lastDoneAt = '',
    this.active = true,
    this.isOneTime = false,
    this.notes = '',
    this.templateId = '',
    this.stageId = '',
    this.groupId = '',
    this.rev = 1,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  });

  final String id;
  String batchId;
  String kind;
  String title;
  int intervalDays;
  String nextDueAt;
  String lastDoneAt;
  bool active;
  bool isOneTime;
  String notes;
  String templateId;
  String stageId;

  /// 同一次"多批次"创建的提醒共享同一个 groupId（单批次为空串）
  String groupId;
  int rev;
  String createdAt;
  String updatedAt;
  String? deletedAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'batchId': batchId,
    'kind': kind,
    'title': title,
    'intervalDays': intervalDays,
    'nextDueAt': nextDueAt,
    'lastDoneAt': lastDoneAt,
    'active': active ? 1 : 0,
    'isOneTime': isOneTime ? 1 : 0,
    'notes': notes,
    'templateId': templateId,
    'stageId': stageId,
    'groupId': groupId,
    'rev': rev,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  static Reminder fromMap(Map<String, dynamic> m) => Reminder(
    id: m['id'] as String,
    batchId: m['batchId'] as String? ?? '',
    kind: m['kind'] as String? ?? '浇水',
    title: m['title'] as String? ?? '',
    intervalDays: m['intervalDays'] as int? ?? 1,
    nextDueAt: m['nextDueAt'] as String? ?? '',
    lastDoneAt: m['lastDoneAt'] as String? ?? '',
    active: (m['active'] ?? 1) == 1,
    isOneTime: (m['isOneTime'] ?? 0) == 1,
    notes: m['notes'] as String? ?? '',
    templateId: m['templateId'] as String? ?? '',
    stageId: m['stageId'] as String? ?? '',
    groupId: m['groupId'] as String? ?? '',
    rev: m['rev'] as int? ?? 1,
    createdAt: m['createdAt'] as String? ?? '',
    updatedAt: m['updatedAt'] as String? ?? '',
    deletedAt: m['deletedAt'] as String?,
  );
}

/// 某批次当前所处的阶段
class StageSnapshot {
  StageSnapshot({
    required this.stage,
    required this.dayInCycle,
    required this.dayInStage,
  });
  final Stage? stage;
  final int dayInCycle;
  final int dayInStage;

  String get label => stage?.name ?? '未配置阶段';
}

/// 记一笔里的一个产品（复配时有多行）
class RecordProduct {
  RecordProduct({
    this.name = '',
    this.dosage = '',
    this.method = '灌根',
    List<String>? methods,
  }) : methods = methods ?? [];

  String name;
  String dosage;

  /// 旧字段：第一个方式
  String method;

  /// v1.7：可多选
  List<String> methods;

  List<String> get effMethods {
    final m = methods.where((e) => e.trim().isNotEmpty).toList();
    if (m.isNotEmpty) return m;
    return method.trim().isEmpty ? const [] : [method];
  }

  String get methodsText => effMethods.join('、');

  Map<String, dynamic> toMap() => {
    'name': name,
    'dosage': dosage,
    'method': method,
    'methods': methods,
  };
  static RecordProduct fromMap(Map<String, dynamic> m) => RecordProduct(
    name: (m['name'] ?? '').toString(),
    dosage: (m['dosage'] ?? '').toString(),
    method: (m['method'] ?? '灌根').toString(),
    methods: _strList(m['methods']),
  );
}

List<String> _cropListOf(dynamic raw) {
  dynamic v = raw;
  if (v is String) {
    if (v.isEmpty) return const [];
    try {
      v = jsonDecode(v);
    } catch (_) {
      return const [];
    }
  }
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

List<String> _imagesOf(dynamic raw) {
  dynamic v = raw;
  if (v is String) {
    if (v.isEmpty) return const [];
    try {
      v = jsonDecode(v);
    } catch (_) {
      return const [];
    }
  }
  if (v is List) {
    return v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

List<RecordProduct> _productsOf(dynamic raw) {
  dynamic v = raw;
  if (v is String) {
    if (v.isEmpty) return const [];
    try {
      v = jsonDecode(v);
    } catch (_) {
      return const [];
    }
  }
  if (v is List) {
    return v
        .whereType<Map>()
        .map((e) => RecordProduct.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }
  return const [];
}

/// 肥料库 / 药品库
class Supply {
  Supply({
    required this.id,
    this.kind = 'fertilizer',
    this.name = '',
    this.ratio = '',
    this.method = '灌根',
    List<String>? methods,
    this.notes = '',
    this.image = '',
    this.scope = 'common',
    List<String>? disabledCrops,
    this.incomplete = false,
    this.source = 'manual',
    this.sortOrder = 0,
    this.rev = 1,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  }) : disabledCrops = disabledCrops ?? [],
       methods = methods ?? [];

  final String id;
  String kind;
  String name;
  String ratio;

  /// 旧字段：第一个方式（兼容老数据/导出）
  String method;

  /// v1.7：施用方式可多选（灌根 / 喷雾 / 喷雾(叶背)）
  List<String> methods;
  String notes;
  String image;
  String scope;
  List<String> disabledCrops;
  bool incomplete;
  String source;
  int sortOrder;
  int rev;
  String createdAt;
  String updatedAt;
  String? deletedAt;

  static const kMethods = ['灌根', '喷雾', '喷雾(叶背)'];

  /// 有效方式：methods 优先，空则回落到 method
  List<String> get effMethods {
    final m = methods.where((e) => e.trim().isNotEmpty).toList();
    if (m.isNotEmpty) return m;
    return method.trim().isEmpty ? const ['灌根'] : [method];
  }

  String get methodsText => effMethods.join('、');

  bool blockedFor(String cropId) =>
      scope == 'disabled' && disabledCrops.contains(cropId);

  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': kind,
    'name': name,
    'ratio': ratio,
    'method': method,
    'methods': jsonEncode(methods),
    'notes': notes,
    'image': image,
    'scope': scope,
    'disabledCrops': jsonEncode(disabledCrops),
    'incomplete': incomplete ? 1 : 0,
    'source': source,
    'sortOrder': sortOrder,
    'rev': rev,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  static Supply fromMap(Map<String, dynamic> m) => Supply(
    id: m['id'] as String,
    kind: m['kind'] as String? ?? 'fertilizer',
    name: m['name'] as String? ?? '',
    ratio: m['ratio'] as String? ?? '',
    method: m['method'] as String? ?? '灌根',
    methods: _strList(m['methods']),
    notes: m['notes'] as String? ?? '',
    image: m['image'] as String? ?? '',
    scope: m['scope'] as String? ?? 'common',
    disabledCrops: _cropListOf(m['disabledCrops']),
    incomplete: (m['incomplete'] ?? 0) == 1 || m['incomplete'] == true,
    source: m['source'] as String? ?? 'manual',
    sortOrder: m['sortOrder'] as int? ?? 0,
    rev: m['rev'] as int? ?? 1,
    createdAt: m['createdAt'] as String? ?? '',
    updatedAt: m['updatedAt'] as String? ?? '',
    deletedAt: m['deletedAt'] as String?,
  );
}

/// 一盆：编号、状态（存活 / 僵苗 / 死亡）与备注。
class Pot {
  Pot({
    required this.id,
    required this.batchId,
    required this.idx,
    this.state = 'alive',
    this.note = '',
    this.changedAt = '',
    this.rev = 1,
    this.createdAt = '',
    this.updatedAt = '',
    this.deletedAt,
  });

  final String id;
  String batchId;
  int idx;
  String state; // alive | stunted | dead
  String note;
  String changedAt;
  int rev;
  String createdAt;
  String updatedAt;
  String? deletedAt;

  bool get alive => state == 'alive';
  bool get dead => state == 'dead';
  bool get stunted => state == 'stunted';
  bool get aliveOrStunted => state != 'dead';

  static const kStates = ['alive', 'stunted', 'dead'];
  static String label(String state) => switch (state) {
    'stunted' => '僵苗',
    'dead' => '死亡',
    _ => '存活',
  };

  Map<String, dynamic> toMap() => {
    'id': id,
    'batchId': batchId,
    'idx': idx,
    'state': state,
    'note': note,
    'changedAt': changedAt,
    'rev': rev,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
  };

  static Pot fromMap(Map<String, dynamic> m) => Pot(
    id: m['id'] as String,
    batchId: m['batchId'] as String? ?? '',
    idx: (m['idx'] as num?)?.toInt() ?? 1,
    state: m['state'] as String? ?? 'alive',
    note: m['note'] as String? ?? '',
    changedAt: m['changedAt'] as String? ?? '',
    rev: (m['rev'] as num?)?.toInt() ?? 1,
    createdAt: m['createdAt'] as String? ?? '',
    updatedAt: m['updatedAt'] as String? ?? '',
    deletedAt: m['deletedAt'] as String?,
  );
}

/// 一批的盆状态汇总。
class PotStats {
  PotStats({this.alive = 0, this.stunted = 0, this.dead = 0, this.total = 0});
  int alive;
  int stunted;
  int dead;
  int total;
  int get notAlive => total - alive;
  bool get allGone => total > 0 && alive == 0;

  String get shortText {
    final parts = <String>[];
    if (dead > 0) parts.add('已死亡 $dead 盆');
    if (stunted > 0) parts.add('僵苗 $stunted 盆');
    return parts.join(' · ');
  }
}

String? _jsonList(List<String> v) => jsonEncode(v);

List<String> _strList(dynamic v) {
  if (v == null) return const [];
  if (v is List) return v.map((e) => e.toString()).toList();
  final t = v.toString().trim();
  if (t.isEmpty) return const [];
  try {
    final d = jsonDecode(t);
    if (d is List) return d.map((e) => e.toString()).toList();
  } catch (_) {}
  return [t];
}

/// 提醒历史：一次「完成」动作写一条（不管涉及几个批次）
class ReminderLog {
  ReminderLog({
    required this.id,
    this.groupId = '',
    this.kind = '其他',
    this.title = '',
    this.notes = '',
    this.doneAt = '',
    this.nextDueAt = '',
    this.batches = const [],
    this.createdAt = '',
  });

  final String id;
  final String groupId;
  final String kind;
  final String title;
  final String notes;

  /// 完成日 yyyy-MM-dd
  final String doneAt;

  /// 完成后顺延到的日期；一次性提醒为空
  final String nextDueAt;

  /// 快照：[{"id":"b1","name":"阳台花架"}]
  final List<Map<String, String>> batches;
  final String createdAt;

  String get batchNames => batches.map((e) => e['name'] ?? '').join('、');

  bool get isOneTime => nextDueAt.isEmpty;

  Map<String, dynamic> toMap() => {
    'id': id,
    'groupId': groupId,
    'kind': kind,
    'title': title,
    'notes': notes,
    'doneAt': doneAt,
    'nextDueAt': nextDueAt,
    'batches': batches,
    'createdAt': createdAt,
  };

  static List<Map<String, String>> batchesOf(dynamic v) {
    if (v is List) {
      return [
        for (final e in v)
          if (e is Map)
            {
              'id': (e['id'] ?? '').toString(),
              'name': (e['name'] ?? '').toString(),
            },
      ];
    }
    if (v is String && v.trim().isNotEmpty) {
      try {
        final list = (const JsonDecoder().convert(v) as List);
        return batchesOf(list);
      } catch (_) {
        return const [];
      }
    }
    return const [];
  }

  factory ReminderLog.fromMap(Map<String, dynamic> m) => ReminderLog(
    id: (m['id'] ?? '').toString(),
    groupId: (m['groupId'] ?? '').toString(),
    kind: (m['kind'] ?? '其他').toString(),
    title: (m['title'] ?? '').toString(),
    notes: (m['notes'] ?? '').toString(),
    doneAt: (m['doneAt'] ?? '').toString(),
    nextDueAt: (m['nextDueAt'] ?? '').toString(),
    batches: batchesOf(m['batches']),
    createdAt: (m['createdAt'] ?? '').toString(),
  );
}
