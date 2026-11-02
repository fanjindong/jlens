import 'package:flutter/material.dart';

const ink = Color(0xffe1e7f1);
const muted = Color(0xff8996ab);
const canvas = Color(0xff0e1420);
const panel = Color(0xff141d2b);
const line = Color(0xff263245);
const mint = Color(0xff70e1c4);
const codeStyle = TextStyle(
  fontFamily: 'monospace',
  fontSize: 13,
  height: 1.75,
  color: ink,
);

ThemeData buildTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: canvas,
  colorScheme: const ColorScheme.dark(
    primary: mint,
    onPrimary: Color(0xff103c32),
    surface: panel,
    onSurface: ink,
    outline: line,
  ),
  fontFamily: 'sans-serif',
  dividerColor: line,
  dividerTheme: const DividerThemeData(color: line, thickness: 1),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 13, color: ink),
    bodySmall: TextStyle(fontSize: 12, color: muted),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: canvas,
    isDense: true,
    hintStyle: const TextStyle(color: muted, fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: line),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  tooltipTheme: const TooltipThemeData(
    waitDuration: Duration(milliseconds: 400),
  ),
);

Color typeColor(String type) => switch (type) {
  'string' => mint,
  'number' => const Color(0xffffce84),
  'boolean' => const Color(0xffc6a3ff),
  'null' => const Color(0xfff49cae),
  _ => const Color(0xff89b7ff),
};

class TypeBadge extends StatelessWidget {
  const TypeBadge(this.type, {super.key});
  final String type;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: typeColor(type).withValues(alpha: .09),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      type,
      style: TextStyle(
        fontFamily: 'monospace',
        color: typeColor(type),
        fontSize: 11,
      ),
    ),
  );
}
