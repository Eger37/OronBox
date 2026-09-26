import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

ThemeData oledDarkTheme(ThemeData defaultDarkTheme) {
  return defaultDarkTheme.copyWith(
    scaffoldBackgroundColor: Colors.black,
    colorScheme: defaultDarkTheme.colorScheme.copyWith(
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      surface: Colors.black,
      onSurface: Colors.white,
    ),
  );
}

abstract final class AppTheme {
  static const _windowsFontFallback = <String>[
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    'DengXian',
    'SimSun',
    'Microsoft JhengHei UI',
    'Microsoft JhengHei',
    'Yu Gothic UI',
    'Malgun Gothic',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
  ];

  static final ThemeData light = buildLightTheme();
  static final ThemeData dark = buildDarkTheme();
  static final ThemeData oledDark = oledDarkTheme(dark);

  static const pageTransitionsTheme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
    },
  );

  static Widget buildPlatformPageTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic>) return child;
    final theme = Theme.of(context);
    final builder = theme.pageTransitionsTheme.builders[theme.platform];
    return builder?.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        ) ??
        child;
  }

  static ThemeData buildLightTheme({ColorScheme? colorScheme}) {
    return _buildTheme(Brightness.light, colorScheme: colorScheme);
  }

  static ThemeData buildDarkTheme({ColorScheme? colorScheme}) {
    return _buildTheme(Brightness.dark, colorScheme: colorScheme);
  }

  static ThemeData buildOledDarkTheme({ColorScheme? colorScheme}) {
    return oledDarkTheme(buildDarkTheme(colorScheme: colorScheme));
  }

  static ThemeData _buildTheme(
    Brightness brightness, {
    ColorScheme? colorScheme,
  }) {
    final effectiveColorScheme = _withLayeredSurfaces(
      colorScheme ??
          ColorScheme.fromSeed(
            seedColor: const Color(0xFF6750A4),
            brightness: brightness,
          ),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamilyFallback: defaultTargetPlatform == TargetPlatform.windows
          ? _windowsFontFallback
          : null,
      colorScheme: effectiveColorScheme,
      brightness: brightness,
      pageTransitionsTheme: pageTransitionsTheme,
      scaffoldBackgroundColor: effectiveColorScheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: effectiveColorScheme.surfaceContainerLowest,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          statusBarIconBrightness: brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: brightness,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: effectiveColorScheme.surfaceContainerHigh,
      ),
      chipTheme: ChipThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: BorderSide.none,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: effectiveColorScheme.primaryContainer,
          foregroundColor: effectiveColorScheme.onPrimaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: effectiveColorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: effectiveColorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 14,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: effectiveColorScheme.surfaceContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: effectiveColorScheme.surfaceContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
        showDragHandle: true,
        backgroundColor: effectiveColorScheme.surface,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        disabledElevation: 0,
      ),
    );
  }

  static ColorScheme _withLayeredSurfaces(ColorScheme colorScheme) {
    final light = colorScheme.brightness == Brightness.light;
    final base = colorScheme.surface;
    final tint = colorScheme.primary;
    final container = _tintedSurface(base, tint, light ? 0.035 : 0.08);
    final containerHigh = _tintedSurface(base, tint, light ? 0.065 : 0.12);
    final containerHighest = _tintedSurface(base, tint, light ? 0.095 : 0.16);

    return colorScheme.copyWith(
      surfaceContainerLowest: base,
      surfaceContainerLow: _tintedSurface(base, tint, light ? 0.02 : 0.055),
      surfaceContainer: container,
      surfaceContainerHigh: containerHigh,
      surfaceContainerHighest: containerHighest,
    );
  }

  static Color _tintedSurface(Color base, Color tint, double alpha) {
    return Color.alphaBlend(tint.withValues(alpha: alpha), base);
  }
}
