import 'package:flutter/material.dart';

import '../core/changelog.dart';
import '../core/theme.dart';
import '../data/notify.dart';
import '../data/repo.dart';
import 'common.dart';
import 'crop_manage.dart';
import 'data_manage.dart';
import 'stage_manage.dart';

const kAppName = '种植助手';
const kBuildStamp = '2026-11-23 09:45';
const kAppVersion = '1.4.0';
const kVersionCode = 5;
const kDataSchema = 4;

class MePage extends StatefulWidget {
  const MePage({super.key});
  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  Map<String, int> stats = {};
  int notifyCount = 0;
  bool notifyOn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await Repo.instance.stats();
    final rems = await Repo.instance.reminders(
      activeOnly: true,
      includeExpired: true,
    );
    final on = await Repo.instance.setting('notify');
    if (mounted) {
      setState(() {
        stats = s;
        notifyCount = rems.length;
        notifyOn = on != '0';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF2465F), Color(0xFFD92B45)],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🍓 $kAppName',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '离线单机 · 数据只在本机',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: .88),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _mini('${stats['batches'] ?? 0}', '批次'),
                    _mini('${stats['records'] ?? 0}', '记录'),
                    _mini('$notifyCount', '提醒'),
                    _mini('${stats['crops'] ?? 0}', '作物'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _group('管理', [
            _tile(
              Icons.eco_outlined,
              '作物管理',
              '${stats['crops'] ?? 0} 个作物',
              () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CropListPage()),
                );
                await _load();
              },
            ),
            _tile(
              Icons.timeline,
              '生产阶段管理',
              '${stats['stages'] ?? 0} 个阶段 · ${stats['templates'] ?? 0} 条提醒模板',
              () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StageListPage()),
                );
                await _load();
              },
            ),
            _tile(Icons.folder_open, '数据管理', '导出 / 导入 / 快照', () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DataPage()),
              );
              await _load();
            }),
          ]),
          const SizedBox(height: 14),
          _group('提醒', [
            _tile(
              Icons.notifications_none,
              '通知设置',
              notifyOn ? '每天 08:00 汇总 · 19:00 补推' : '已关闭',
              () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotifySettingsPage()),
                );
                await _load();
              },
            ),
          ]),
          const SizedBox(height: 14),
          _group('其它', [
            _tile(Icons.info_outline, '关于', kBuildStamp, () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              );
            }),
          ]),
        ],
      ),
    );
  }

  Widget _mini(String v, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            v,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: .85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 7),
          child: Text(title, style: tTiny),
        ),
        Container(
          decoration: cardDeco(),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _tile(IconData icon, String title, String sub, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 20, color: kInk2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(sub, style: tTiny),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: kInk3),
          ],
        ),
      ),
    );
  }
}

class NotifySettingsPage extends StatefulWidget {
  const NotifySettingsPage({super.key});
  @override
  State<NotifySettingsPage> createState() => _NotifySettingsPageState();
}

class _NotifySettingsPageState extends State<NotifySettingsPage> {
  bool on = true;
  bool exact = false;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await Repo.instance.setting('notify');
    final ex = await Notify.instance.canExact;
    if (mounted) {
      setState(() {
        on = v != '0';
        exact = ex;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知设置')),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: kRed))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
              children: [
                Container(
                  decoration: cardDeco(),
                  child: SwitchListTile(
                    value: on,
                    activeThumbColor: kRed,
                    title: const Text(
                      '开启提醒通知',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      '每天 08:00 汇总当天要做的事；19:00 补推还逾期的',
                      style: TextStyle(fontSize: 12, color: kInk3, height: 1.4),
                    ),
                    onChanged: (v) async {
                      setState(() => on = v);
                      await Repo.instance.setSetting('notify', v ? '1' : '0');
                      if (v) {
                        await Notify.instance.reschedule();
                      } else {
                        await Notify.instance.cancelAll();
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: cardDeco(),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.alarm,
                          size: 20,
                          color: kInk2,
                        ),
                        title: const Text(
                          '精确闹钟权限',
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          exact ? '已授权，提醒会准时' : '未授权，可能晚几分钟（国产系统常需要手动开）',
                          style: tTiny.copyWith(height: 1.4),
                        ),
                        trailing: TextButton(
                          onPressed: () async {
                            await Notify.instance.requestPermissions();
                            await _load();
                          },
                          child: const Text('去授权'),
                        ),
                      ),
                      const Divider(height: 1, indent: 14, endIndent: 14),
                      ListTile(
                        leading: const Icon(
                          Icons.notification_add_outlined,
                          size: 20,
                          color: kInk2,
                        ),
                        title: const Text(
                          '发一条测试通知',
                          style: TextStyle(fontSize: 14),
                        ),
                        onTap: () async {
                          await Notify.instance.test();
                          if (context.mounted) toast(context, '已发送，看看通知栏');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '提醒由本机定时器发出，不联网。部分国产系统（小米/华为/OPPO/vivo）需要在系统设置里允许「自启动」「后台运行」和「通知」，否则可能收不到。',
                  style: tTiny.copyWith(height: 1.6),
                ),
              ],
            ),
    );
  }
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool showMore = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          const SizedBox(height: 8),
          Center(
            child: GestureDetector(
              onLongPress: () => setState(() => showMore = true),
              child: Column(
                children: [
                  const Text('🍓', style: TextStyle(fontSize: 46)),
                  const SizedBox(height: 12),
                  const Text(
                    kAppName,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(kBuildStamp, style: tSub),
                ],
              ),
            ),
          ),
          if (showMore) ...[
            const SizedBox(height: 18),
            Center(child: Text('包名 cn.zhongzhizhushou.planting', style: tTiny)),
            Center(child: Text('版本 $kAppVersion ($kVersionCode)', style: tTiny)),
            Center(child: Text('数据格式 schemaVersion $kDataSchema', style: tTiny)),
            const Center(child: Text('离线运行 · 不含网络权限', style: tTiny)),
          ],
          const SizedBox(height: 26),
          SectionTitle('更新记录', count: kChangelog.length),
          ...kChangelog.map((r) => _releaseCard(r)),
        ],
      ),
    );
  }

  Widget _releaseCard(AppRelease r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        decoration: cardDeco(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'v${r.version}',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: kRedDeep,
                  ),
                ),
                const SizedBox(width: 8),
                Text(r.date, style: tTiny),
                const Spacer(),
                if (r.version == kAppVersion)
                  const Pill('当前版本', bg: kGreenBg, fg: kGreen),
              ],
            ),
            if (r.highlights.isNotEmpty) ...[
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: r.highlights.map((t) => Pill(t)).toList(),
              ),
            ],
            const SizedBox(height: 8),
            ...r.items.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 7),
                      child: Icon(Icons.circle, size: 4, color: kInk3),
                    ),
                    Expanded(child: Text(t, style: tBody.copyWith(height: 1.5))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
