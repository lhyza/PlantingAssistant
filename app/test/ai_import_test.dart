import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;

import 'package:planting/core/images.dart';
import 'package:planting/data/ai_import.dart';
import 'package:planting/data/models.dart';
import 'package:planting/data/repo.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

/// 手机端豆包实际产出的那种 JSON（14 条病虫害，图片为空）
const _pestJson = <Map<String, dynamic>>[
  {
    'id': 'p01',
    'name': '白粉病',
    'category': '病害',
    'symptoms': '叶片出现白色粉状霉层',
    'cause': '通风差、湿度大',
    'treatment': '及时摘除病叶，喷施醚菌酯',
    'prevention': '保持通风，避免叶面长时间潮湿',
    'image': ''
  },
  {
    'id': 'p02',
    'name': '灰霉病',
    'category': '病害',
    'symptoms': '果实软腐并长出灰毛',
    'cause': '低温高湿',
    'treatment': '清除病果，喷施腐霉利',
    'prevention': '降低湿度，及时摘除老叶',
    'image': ''
  },
  {
    'id': 'p03',
    'name': '二斑叶螨（红蜘蛛）',
    'category': '虫害',
    'symptoms': '叶背有细小虫体，叶片失绿',
    'cause': '高温干燥',
    'treatment': '喷施联苯肼酯',
    'prevention': '增加湿度，定期检查叶背',
    'image': ''
  },
  {
    'id': 'p04',
    'name': '白粉虱',
    'category': '虫害',
    'symptoms': '叶片背面有白色小飞虫',
    'cause': '通风不良',
    'treatment': '黄板诱杀 + 喷施噻虫嗪',
    'prevention': '挂黄板，清除杂草',
    'image': ''
  },
  {
    'id': 'p05',
    'name': '蛇眼病（叶斑病）',
    'category': '病害',
    'symptoms': '叶片出现紫红色小斑点',
    'cause': '高温多雨',
    'treatment': '喷施苯醚甲环唑',
    'prevention': '避免叶面淋水',
    'image': ''
  },
  {
    'id': 'p06',
    'name': '蛴螬',
    'category': '虫害',
    'symptoms': '根部被啃食，植株萎蔫',
    'cause': '土壤中有机质多',
    'treatment': '灌根辛硫磷',
    'prevention': '配土充分腐熟',
    'image': ''
  },
];

String _wrapPestJson() => jsonEncode({
      'format': 'planting.ai',
      'schemaVersion': 1,
      'kind': 'pest',
      'crop': '草莓',
      'count': _pestJson.length,
      'items': _pestJson,
    });

Uint8List _u8(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late String cropId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('planting_ai_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    await Images.init();
    cropId = (await Repo.instance.defaultCrop())!.id;
  });

  test('纯 JSON：手机端豆包产出的文件能直接解析', () async {
    final plan = await previewAiData(
      bytes: _u8(_wrapPestJson()),
      cropId: cropId,
      fileName: '病虫害_20261123.json',
    );
    expect(plan.ok, isTrue, reason: plan.error);
    expect(plan.kind, 'pest');
    expect(plan.cropName, '草莓');
    expect(plan.items.length, _pestJson.length);
    // 内置 8 条病虫害都是「通用」条目 → 按规则 C 跳过（别名命中的也算）
    expect(plan.skipCount, 3); // 白粉病 / 灰霉病 同名，二斑叶螨（红蜘蛛）别名命中
    expect(plan.addCount, 3);
    expect(plan.updateCount, 0);
  });

  test('JSON 容错：围栏 + 前后说明文字 + 缺 kind 用入口推断', () async {
    final text = '下面是整理好的数据：\n```json\n${_wrapPestJson()}\n```\n希望有帮助';
    final plan = await previewAiData(
      bytes: _u8(text),
      cropId: cropId,
      expectedKind: 'pest',
    );
    expect(plan.ok, isTrue, reason: plan.error);
    expect(plan.items.length, _pestJson.length);
  });

  test('JSON 容错：顶层数组也能导入', () async {
    final plan = await previewAiData(
      bytes: _u8(jsonEncode(_pestJson)),
      cropId: cropId,
      expectedKind: 'pest',
    );
    expect(plan.ok, isTrue, reason: plan.error);
    expect(plan.items.length, _pestJson.length);
  });

  test('识别不出类型时报错', () async {
    final plan = await previewAiData(
      bytes: _u8('{"items":[{"name":"测试白粉病"}]}'),
      cropId: cropId,
    );
    expect(plan.ok, isFalse);
    expect(plan.error, contains('kind'));
  });

  test('数据管理的库文件会被拒绝并引导', () async {
    final plan = await previewAiData(
      bytes: _u8('{"format":"planting.data","kind":"pest","items":[]}'),
      cropId: cropId,
    );
    expect(plan.ok, isFalse);
    expect(plan.error, contains('数据管理'));
  });

  test('坏 JSON 报错而不是崩溃', () async {
    final plan = await previewAiData(
      bytes: _u8('{"items": [{"name": "甲",},,]}'),
      cropId: cropId,
      expectedKind: 'pest',
    );
    expect(plan.ok, isFalse);
  });

  test('别名命中：合并到已有的草莓专属条目', () async {
    final p = Pest(id: 'pest_merge_src', sortOrder: 700)
      ..name = '测试天牛（星天牛）'
      ..crop = cropId
      ..crops = [cropId]
      ..category = '虫害'
      ..treatment = '旧的处理'
      ..symptoms = '旧的症状';
    await Repo.instance.savePest(p);

    final plan = await previewAiData(
      bytes: _u8(jsonEncode({
        'format': 'planting.ai',
        'kind': 'pest',
        'crop': '草莓',
        'items': [
          {
            'name': '天牛（星天牛）',
            'category': '虫害',
            'symptoms': '新症状',
            'treatment': '新的处理',
            'prevention': '通风',
          }
        ],
      })),
      cropId: cropId,
    );
    expect(plan.ok, isTrue, reason: plan.error);
    expect(plan.mergeCount, 1);
    expect(plan.items.first.reason, contains('合并'));

    final res = await applyAiPlan(plan);
    expect(res.merged, 1);
    final all = await Repo.instance.pests(cropId);
    final hit = all.where((e) => e.name == '测试天牛（星天牛）').toList();
    expect(hit.length, 1);
    expect(hit.first.treatment, '新的处理');
  });

  test('zip 带图：落盘并把条目标记为待裁剪', () async {
    final data = jsonEncode({
      'format': 'planting.ai',
      'kind': 'pest',
      'crop': '草莓',
      'items': [
        {
          'name': '测试带图虫',
          'category': '虫害',
          'symptoms': '症状',
          'treatment': '处理',
          'prevention': '预防',
          'image': 'images/a.jpg',
        }
      ],
    });

    final arc = Archive();
    final bytes = utf8.encode(data);
    arc.addFile(ArchiveFile('data.json', bytes.length, bytes));
    final img = Uint8List.fromList(List<int>.filled(64, 7));
    arc.addFile(ArchiveFile('images/a.jpg', img.length, img));
    final zip = Uint8List.fromList(ZipEncoder().encode(arc)!);

    final plan = await previewAiData(bytes: zip, cropId: cropId);
    expect(plan.ok, isTrue, reason: plan.error);
    expect(plan.addCount, 1);

    final res = await applyAiPlan(plan);
    expect(res.added, 1);
    expect(res.pending, 1);
    expect(res.images, 1);

    final all = await Repo.instance.pests(cropId);
    final hit = all.firstWhere((e) => e.name == '测试带图虫');
    expect(hit.imgPending, isTrue);
    expect(hit.image, isNotEmpty);
    expect(File(Images.pathOf(hit.image)!).existsSync(), isTrue);
  });

  test('未勾选的条目不写入', () async {
    final plan = await previewAiData(
      bytes: _u8(jsonEncode({
        'format': 'planting.ai',
        'kind': 'pest',
        'crop': '草莓',
        'items': [
          {'name': '测试未勾选', 'category': '病害', 'symptoms': 'x'},
        ],
      })),
      cropId: cropId,
    );
    plan.items.first.selected = false;
    final res = await applyAiPlan(plan);
    expect(res.added, 0);
    final all = await Repo.instance.pests(cropId);
    expect(all.where((e) => e.name == '测试未勾选'), isEmpty);
  });
}
