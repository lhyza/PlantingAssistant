import 'package:flutter_test/flutter_test.dart';
import 'package:planting/core/changelog.dart';
import 'package:planting/core/version.dart';
import 'package:planting/data/models.dart';
import 'package:planting/data/update_service.dart';

void main() {
  group('版本号比较', () {
    test('数字段逐段比较，不受位数影响', () {
      expect(UpdateService.compareVersions('1.6.0', '1.5.0'), greaterThan(0));
      expect(UpdateService.compareVersions('1.10.0', '1.9.2'), greaterThan(0));
      expect(UpdateService.compareVersions('v1.6.0', '1.6.0'), 0);
      expect(UpdateService.compareVersions('1.5.0', '1.6.0'), lessThan(0));
      expect(UpdateService.compareVersions('2.0', '1.9.9'), greaterThan(0));
    });

    test('带 +build 的版本只看前半段', () {
      expect(UpdateService.compareVersions('1.6.0+7', '1.6.0'), 0);
    });
  });

  group('下载镜像', () {
    test('镜像优先，直连垫底，且都保留原始地址', () {
      const url =
          'https://github.com/lhyza/PlantingAssistant/releases/download/v1.5.0/PlantingAssistant-1.5.0-release.apk';
      final list = UpdateService.mirrorUrls(url);
      expect(list.length, UpdateService.kMirrors.length + 1);
      expect(list.first, 'https://ghfast.top/$url');
      expect(list.last, url);
    });
  });

  group('病虫害影响作物文案', () {
    test('存的是作物 id 时显示中文名', () {
      final pest = Pest(
        id: 'p1',
        crop: 'crop_strawberry',
        name: '测试病',
        crops: const ['crop_strawberry', 'crop_lemon'],
      );
      final text = pest.cropsText(const {
        'crop_strawberry': '草莓',
        'crop_lemon': '柠檬',
      });
      expect(text, '草莓、柠檬');
    });

    test('存的是中文名（历史数据）时原样显示，不出现 crop_ 前缀', () {
      final pest = Pest(id: 'p2', crop: '草莓', name: '测试病', crops: const ['草莓']);
      final text = pest.cropsText(const {'crop_strawberry': '草莓'});
      expect(text, '草莓');
      expect(text.contains('crop_'), isFalse);
    });

    test('没有条目时返回「通用」，不再兜底成空串', () {
      final pest = Pest(id: 'p3', crop: '通用', name: '通用病');
      expect(pest.cropsText(const {}), '通用');
    });
  });

  group('更新记录', () {
    test('最新一条就是当前版本，且版本号不重复', () {
      expect(kChangelog, isNotEmpty);
      expect(kChangelog.first.version, kAppVersion);
      final versions = kChangelog.map((r) => r.version).toList();
      expect(versions.toSet().length, versions.length);
    });

    test('每条都写了要点', () {
      for (final r in kChangelog) {
        expect(r.items, isNotEmpty, reason: '${r.version} 没有写更新要点');
      }
    });
  });
}
