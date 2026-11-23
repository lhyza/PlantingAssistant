import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/util.dart';

/// 顶部小标题
class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key, this.required = false});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 14),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: kInk2,
            ),
          ),
          if (required)
            const Text(
              ' *',
              style: TextStyle(
                color: kRed,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

/// 表单里的只读行（点开选择）
class PickTile extends StatelessWidget {
  const PickTile({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.hint = '请选择',
    this.icon,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;
  final String hint;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kLine),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: kInk2),
              const SizedBox(width: 8),
            ],
            Text(
              value.isEmpty ? hint : value,
              style: value.isEmpty
                  ? tSub
                  : const TextStyle(fontSize: 14, color: kInk),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 18, color: kInk3),
          ],
        ),
      ),
    );
  }
}

/// 一排单选胶囊
class ChoiceRow extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.colors,
    this.compact = false,
  });
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, Color>? colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final on = o == value;
        final c = colors?[o];
        return GestureDetector(
          onTap: () => onChanged(o),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: compact ? 6 : 9,
            ),
            decoration: BoxDecoration(
              color: on ? (c ?? kRed).withValues(alpha: 0.10) : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: on ? (c ?? kRed) : kLine,
                width: on ? 1.4 : 1,
              ),
            ),
            child: Text(
              o,
              style: TextStyle(
                fontSize: compact ? 12.5 : 13.5,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? (c ?? kRed) : kInk2,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

Future<void> toast(BuildContext c, String msg) async {
  final m = ScaffoldMessenger.maybeOf(c);
  m?.showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1600)),
  );
}

Future<bool> confirm(
  BuildContext c,
  String title, {
  String? body,
  String ok = '确定',
  bool danger = true,
}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: body == null ? null : Text(body, style: tBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            ok,
            style: TextStyle(
              color: danger ? kRed : kInk,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<DateTime?> pickDate(
  BuildContext c,
  DateTime init, {
  String help = '选择日期',
}) async {
  final d = await showDatePicker(
    context: c,
    initialDate: init,
    firstDate: DateTime(2015),
    lastDate: DateTime(2100),
    helpText: help,
    builder: (ctx, child) => Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: kRed),
      ),
      child: child!,
    ),
  );
  return d == null ? null : dateOnly(d);
}

/// 日期显示
String dayText(String s) {
  final d = parseDay(s);
  if (d == null) return '未设置';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 简易文本域，带自动高度
class AutoField extends StatelessWidget {
  const AutoField({
    super.key,
    required this.controller,
    this.hint,
    this.minLines = 3,
    this.maxLines = 8,
  });
  final TextEditingController controller;
  final String? hint;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      style: tBody,
      decoration: InputDecoration(hintText: hint),
    );
  }
}
