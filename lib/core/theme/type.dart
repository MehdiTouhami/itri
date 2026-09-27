import 'package:flutter/painting.dart';

import 'tokens.dart';

/// Type roles. Barlow Condensed for numbers people glance at mid-workout,
/// Plex Sans for reading, Plex Mono for labels and tabular data.
abstract final class Tx {
  static const display = 'BarlowCondensed';
  static const sans = 'PlexSans';
  static const mono = 'PlexMono';
  static const _tab = [FontFeature.tabularFigures()];

  /// Hero numerals (form score, headline stat).
  static TextStyle hero(ItriTokens t, {double size = 72, Color? color}) => TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w600,
        fontSize: size,
        height: 0.9,
        letterSpacing: -1,
        color: color ?? t.text,
        fontFeatures: _tab,
      );

  /// Stat readouts in grids.
  static TextStyle numeral(ItriTokens t, {double size = 28, Color? color}) => TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w500,
        fontSize: size,
        height: 1.0,
        color: color ?? t.text,
        fontFeatures: _tab,
      );

  /// Screen titles, set condensed and uppercase.
  static TextStyle pageTitle(ItriTokens t) => TextStyle(
        fontFamily: display,
        fontWeight: FontWeight.w600,
        fontSize: 34,
        height: 1.0,
        letterSpacing: 0.4,
        color: t.text,
      );

  static TextStyle title(ItriTokens t) => TextStyle(
        fontFamily: sans,
        fontWeight: FontWeight.w600,
        fontSize: 20,
        height: 1.25,
        color: t.text,
      );

  static TextStyle heading(ItriTokens t) => TextStyle(
        fontFamily: sans,
        fontWeight: FontWeight.w600,
        fontSize: 15,
        height: 1.3,
        color: t.text,
      );

  static TextStyle body(ItriTokens t, {Color? color}) => TextStyle(
        fontFamily: sans,
        fontWeight: FontWeight.w400,
        fontSize: 14,
        height: 1.45,
        color: color ?? t.text,
      );

  static TextStyle small(ItriTokens t, {Color? color}) => TextStyle(
        fontFamily: sans,
        fontWeight: FontWeight.w400,
        fontSize: 12.5,
        height: 1.35,
        color: color ?? t.textMuted,
      );

  /// Uppercase section labels. Pass text already uppercased.
  static TextStyle eyebrow(ItriTokens t, {Color? color}) => TextStyle(
        fontFamily: mono,
        fontWeight: FontWeight.w500,
        fontSize: 10.5,
        height: 1.2,
        letterSpacing: 1.3,
        color: color ?? t.textMuted,
      );

  /// Tabular data: splits, axis labels, units.
  static TextStyle data(ItriTokens t, {double size = 12, Color? color, FontWeight? weight}) => TextStyle(
        fontFamily: mono,
        fontWeight: weight ?? FontWeight.w400,
        fontSize: size,
        height: 1.3,
        color: color ?? t.text,
        fontFeatures: _tab,
      );
}
