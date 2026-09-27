import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';
import 'type.dart';

abstract final class ItriTheme {
  static ThemeData dark([ItriTokens t = ItriTokens.dark]) => _build(t, Brightness.dark);
  static ThemeData light([ItriTokens t = ItriTokens.light]) => _build(t, Brightness.light);

  static ThemeData _build(ItriTokens t, Brightness b) {
    final scheme = ColorScheme(
      brightness: b,
      primary: t.gold,
      onPrimary: t.ground,
      secondary: t.up,
      onSecondary: t.ground,
      error: t.down,
      onError: t.ground,
      surface: t.ground,
      onSurface: t.text,
      outline: t.line,
      outlineVariant: t.line,
      surfaceContainerHighest: t.raised,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.ground,
      canvasColor: t.ground,
      fontFamily: Tx.sans,
      extensions: [t],
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
      textSelectionTheme: TextSelectionThemeData(cursorColor: t.gold),
      appBarTheme: AppBarTheme(
        backgroundColor: t.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: t.text,
        systemOverlayStyle: b == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      iconTheme: IconThemeData(color: t.textMuted, size: 20),
      sliderTheme: SliderThemeData(
        activeTrackColor: t.gold,
        inactiveTrackColor: t.raised,
        thumbColor: t.gold,
        overlayColor: t.goldSoft,
        trackHeight: 2,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
