import 'package:flutter/material.dart';

const Color kRed = Color(0xFFE8354D);
const Color kRedDeep = Color(0xFFC0233B);
const Color kInk = Color(0xFF1C1917);
const Color kInk2 = Color(0xFF78716C);
const Color kInk3 = Color(0xFFA8A29E);
const Color kLine = Color(0xFFEDE9E4);
const Color kBg = Color(0xFFFAFAF9);
const Color kGreen = Color(0xFF0B8F63);
const Color kGreenBg = Color(0xFFE7F8F1);
const Color kBlue = Color(0xFF2563EB);
const Color kBlueBg = Color(0xFFEAF1FE);
const Color kAmber = Color(0xFFB45309);
const Color kAmberBg = Color(0xFFFEF3C7);
const Color kRedBg = Color(0xFFFDECEE);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: kRed,
      primary: kRed,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: kBg,
    fontFamilyFallback: const [
      'Source Han Sans SC',
      'Noto Sans CJK SC',
      'PingFang SC',
      'Microsoft YaHei',
    ],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: kInk, displayColor: kInk),
    appBarTheme: const AppBarTheme(
      backgroundColor: kBg,
      foregroundColor: kInk,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: kInk,
        fontSize: 19,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: kLine),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kRed,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kInk,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: kLine),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kRed),
      ),
      hintStyle: const TextStyle(color: kInk3, fontSize: 14),
      labelStyle: const TextStyle(color: kInk2, fontSize: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(color: kLine, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kInk,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

const TextStyle tTitle = TextStyle(fontSize: 17, fontWeight: FontWeight.w700);
const TextStyle tBody = TextStyle(fontSize: 14, color: kInk, height: 1.5);
const TextStyle tSub = TextStyle(fontSize: 12.5, color: kInk2, height: 1.5);
const TextStyle tTiny = TextStyle(fontSize: 11.5, color: kInk3, height: 1.4);

BoxDecoration cardDeco({Color? color, Color? border}) => BoxDecoration(
  color: color ?? Colors.white,
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: border ?? kLine),
);

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.count});
  final String text;
  final Widget? trailing;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: kRed,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 12.5,
                color: kInk3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.text, this.icon = '🌱'});
  final String text;
  final String icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      decoration: cardDeco(color: Colors.white),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 26)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: tSub),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.bg, this.fg, this.border});
  final String text;
  final Color? bg;
  final Color? fg;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? const Color(0xFFF5F3F0),
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          color: fg ?? kInk2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
