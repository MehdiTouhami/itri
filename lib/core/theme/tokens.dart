import 'package:flutter/material.dart';

/// Design tokens. Every colour in the app comes from here — never a raw hex
/// in a widget. Colour carries meaning (zones, form); chrome stays neutral.
@immutable
class ItriTokens extends ThemeExtension<ItriTokens> {
  const ItriTokens({
    required this.ground,
    required this.surface,
    required this.raised,
    required this.line,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.gold,
    required this.goldSoft,
    required this.up,
    required this.down,
    required this.zones,
    this.stages = _stagesDark,
  });

  final Color ground; // page background
  final Color surface; // the rare contained element
  final Color raised; // empty heatmap cells, tracks
  final Color line; // hairlines, gridlines
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color gold; // Itri brand accent, shared with Itri Sleep
  final Color goldSoft;
  final Color up; // positive form / improvement
  final Color down; // negative form / regression
  final List<Color> zones; // Z1..Z5

  /// Sleep stages: deep, light, REM, awake. Separated by lightness as well as
  /// hue, and always drawn with a label.
  final List<Color> stages;

  static const _stagesDark = [Color(0xFF5566DD), Color(0xFF8FB3F0), Color(0xFFC07AD9), Color(0xFFE08A6B)];
  static const _stagesLight = [Color(0xFF3C4BC4), Color(0xFF6E97DA), Color(0xFFA24FC0), Color(0xFFC9623F)];

  /// Warm graphite. Dark-first: most training data gets read early or late.
  static const dark = ItriTokens(
    ground: Color(0xFF121110),
    surface: Color(0xFF1A1917),
    raised: Color(0xFF24221F),
    line: Color(0xFF2F2C28),
    text: Color(0xFFF1EDE6),
    textMuted: Color(0xFF9E978C),
    textFaint: Color(0xFF625D55),
    gold: Color(0xFFE9B04A),
    goldSoft: Color(0x33E9B04A),
    up: Color(0xFF7FB59A),
    down: Color(0xFFD9695A),
    zones: [
      // Validated for CVD separation; always paired with a Z1–Z5 label.
      Color(0xFF6272D6), // Z1 recovery · indigo
      Color(0xFF239B8E), // Z2 endurance · teal
      Color(0xFFA99226), // Z3 tempo · ochre
      Color(0xFFCC4B33), // Z4 threshold · vermilion
      Color(0xFFB04FB8), // Z5 VO2 max · magenta
    ],
  );

  /// Stone paper. Same roles, contrast re-balanced rather than inverted.
  static const light = ItriTokens(
    ground: Color(0xFFF3F1ED),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFE6E2DB),
    line: Color(0xFFDAD5CD),
    text: Color(0xFF1C1A17),
    textMuted: Color(0xFF6B655C),
    textFaint: Color(0xFFA39D93),
    gold: Color(0xFFB27A12),
    goldSoft: Color(0x33B27A12),
    up: Color(0xFF3E8466),
    down: Color(0xFFB8432F),
    zones: [
      Color(0xFF4C5BC0),
      Color(0xFF008A7A),
      Color(0xFF9E8414),
      Color(0xFFA8321F),
      Color(0xFFA03C9E),
    ],
    stages: _stagesLight,
  );

  /// Recovery: the same system at night. Midnight ink instead of graphite,
  /// moonlight instead of gold. Roles are identical, so every widget works
  /// in both modes unchanged. (`gold` is the accent slot, whatever its hue.)
  static const recoveryDark = ItriTokens(
    ground: Color(0xFF0D0F16),
    surface: Color(0xFF141722),
    raised: Color(0xFF1D2130),
    line: Color(0xFF262B3A),
    text: Color(0xFFE8EBF4),
    textMuted: Color(0xFF9097AA),
    textFaint: Color(0xFF595F72),
    gold: Color(0xFFA7B6FF),
    goldSoft: Color(0x33A7B6FF),
    up: Color(0xFF7FB59A),
    down: Color(0xFFD9695A),
    zones: [
      Color(0xFF6272D6),
      Color(0xFF239B8E),
      Color(0xFFA99226),
      Color(0xFFCC4B33),
      Color(0xFFB04FB8),
    ],
  );

  static const recoveryLight = ItriTokens(
    ground: Color(0xFFEEF0F6),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFDDE1EC),
    line: Color(0xFFD2D7E3),
    text: Color(0xFF161A25),
    textMuted: Color(0xFF5D6478),
    textFaint: Color(0xFF999FB2),
    gold: Color(0xFF4A5BC4),
    goldSoft: Color(0x334A5BC4),
    up: Color(0xFF3E8466),
    down: Color(0xFFB8432F),
    zones: [
      Color(0xFF4C5BC0),
      Color(0xFF008A7A),
      Color(0xFF9E8414),
      Color(0xFFA8321F),
      Color(0xFFA03C9E),
    ],
    stages: _stagesLight,
  );

  @override
  ItriTokens copyWith() => this;

  @override
  ItriTokens lerp(ItriTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return ItriTokens(
      ground: c(ground, other.ground),
      surface: c(surface, other.surface),
      raised: c(raised, other.raised),
      line: c(line, other.line),
      text: c(text, other.text),
      textMuted: c(textMuted, other.textMuted),
      textFaint: c(textFaint, other.textFaint),
      gold: c(gold, other.gold),
      goldSoft: c(goldSoft, other.goldSoft),
      up: c(up, other.up),
      down: c(down, other.down),
      zones: [for (var i = 0; i < zones.length; i++) c(zones[i], other.zones[i])],
      stages: [for (var i = 0; i < stages.length; i++) c(stages[i], other.stages[i])],
    );
  }
}

extension ItriContext on BuildContext {
  ItriTokens get tk => Theme.of(this).extension<ItriTokens>()!;
}

/// Spacing scale (4-pt).
abstract final class Sp {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 24.0, xxl = 32.0, xxxl = 48.0;
  static const gutter = 20.0;
}
