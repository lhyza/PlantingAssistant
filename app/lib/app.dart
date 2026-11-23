import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'ui/shell.dart';

class PlantingApp extends StatelessWidget {
  const PlantingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '种植助手',
      debugShowCheckedModeBanner: false,
      // 让 TextField 的长按菜单（剪切/复制/粘贴/全选）显示中文
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(),
      home: const Shell(),
    );
  }
}
