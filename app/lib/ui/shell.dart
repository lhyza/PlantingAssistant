import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'batch_list.dart';
import 'knowledge.dart';
import 'me.dart';
import 'record_edit.dart';
import 'today.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          TodayPage(),
          BatchListPage(),
          KnowledgePage(),
          MePage(),
        ],
      ),
      floatingActionButton: _index <= 1
          ? SizedBox(
              height: 44,
              child: FloatingActionButton.extended(
                backgroundColor: kRed,
                foregroundColor: Colors.white,
                elevation: 2,
                extendedPadding: const EdgeInsets.symmetric(horizontal: 14),
                onPressed: () => quickRecord(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text(
                  '记一笔',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: kRedBg,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny, color: kRed),
            label: '今天',
          ),
          NavigationDestination(
            icon: Icon(Icons.yard_outlined),
            selectedIcon: Icon(Icons.yard, color: kRed),
            label: '批次',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book, color: kRed),
            label: '知识',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: kRed),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
