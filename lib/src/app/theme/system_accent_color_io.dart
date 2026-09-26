import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:oronbox/src/core/providers/theme_locale_providers.dart';

Future<Color?> loadDesktopAccentColor(DesktopAccentColorSource source) async {
  if (Platform.isLinux) {
    return switch (source) {
      DesktopAccentColorSource.gtk => _loadGnomeAccentColor(),
      DesktopAccentColorSource.qt => _loadKdeAccentColorChain(),
      DesktopAccentColorSource.system =>
        await _loadGnomeAccentColor() ?? await _loadKdeAccentColorChain(),
    };
  }

  if (Platform.isWindows) {
    return _loadWindowsAccentColor();
  }

  if (Platform.isMacOS) {
    return _loadMacOsAccentColor();
  }

  return null;
}

Future<Color?> _loadKdeAccentColorChain() async {
  return await _loadKdeAccentColor('kreadconfig6') ??
      await _loadKdeAccentColor('kreadconfig5');
}

Future<Color?> _loadGnomeAccentColor() async {
  final result = await _run('gsettings', [
    'get',
    'org.gnome.desktop.interface',
    'accent-color',
  ]);
  if (result == null) {
    return null;
  }
  final value = result.replaceAll("'", '').replaceAll('"', '').trim();
  return _gnomeAccentColors[value];
}

Future<Color?> _loadKdeAccentColor(String executable) async {
  final result = await _run(executable, [
    '--file',
    'kdeglobals',
    '--group',
    'General',
    '--key',
    'AccentColor',
  ]);
  if (result == null) {
    return null;
  }
  return _parseColor(result.trim());
}

Future<Color?> _loadWindowsAccentColor() async {
  return await _loadWindowsRegistryColor(
        r'HKCU\Software\Microsoft\Windows\DWM',
        'AccentColor',
      ) ??
      await _loadWindowsRegistryColor(
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent',
        'AccentColorMenu',
      );
}

Future<Color?> _loadWindowsRegistryColor(String key, String valueName) async {
  final result = await _run('reg', ['query', key, '/v', valueName]);
  if (result == null) {
    return null;
  }
  final match = RegExp(
    '$valueName\\s+REG_DWORD\\s+0x([0-9a-fA-F]+)',
    caseSensitive: false,
  ).firstMatch(result);
  if (match == null) {
    return null;
  }
  final value = int.tryParse(match.group(1)!, radix: 16);
  if (value == null) {
    return null;
  }

  // Windows stores accent DWORDs as ABGR/COLORREF-style values.
  final r = value & 0xFF;
  final g = (value >> 8) & 0xFF;
  final b = (value >> 16) & 0xFF;
  return Color.fromARGB(255, r, g, b);
}

Future<Color?> _loadMacOsAccentColor() async {
  final result = await _run('defaults', ['read', '-g', 'AppleAccentColor']);
  if (result == null) {
    return null;
  }
  final value = int.tryParse(result.trim());
  if (value == null) {
    return null;
  }
  return _macOsAccentColors[value];
}

Future<String?> _run(String executable, List<String> arguments) async {
  try {
    final result = await Process.run(
      executable,
      arguments,
    ).timeout(const Duration(milliseconds: 800));
    if (result.exitCode != 0) {
      return null;
    }
    final output = result.stdout.toString().trim();
    return output.isEmpty ? null : output;
  } catch (_) {
    return null;
  }
}

Color? _parseColor(String value) {
  final hex = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(value);
  if (hex != null) {
    return Color(int.parse('0xFF${hex.group(1)}'));
  }

  final rgb = RegExp(
    r'^(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})$',
  ).firstMatch(value);
  if (rgb == null) {
    return null;
  }
  final r = int.parse(rgb.group(1)!).clamp(0, 255);
  final g = int.parse(rgb.group(2)!).clamp(0, 255);
  final b = int.parse(rgb.group(3)!).clamp(0, 255);
  return Color.fromARGB(255, r, g, b);
}

const _gnomeAccentColors = <String, Color>{
  'blue': Color(0xFF3584E4),
  'teal': Color(0xFF2190A4),
  'green': Color(0xFF3A944A),
  'yellow': Color(0xFFC88800),
  'orange': Color(0xFFED5B00),
  'red': Color(0xFFE62D42),
  'pink': Color(0xFFD56199),
  'purple': Color(0xFF9141AC),
  'slate': Color(0xFF6F8396),
};

const _macOsAccentColors = <int, Color>{
  -1: Color(0xFF8E8E93),
  0: Color(0xFFFF3B30),
  1: Color(0xFFFF9500),
  2: Color(0xFFFFCC00),
  3: Color(0xFF34C759),
  4: Color(0xFF007AFF),
  5: Color(0xFFAF52DE),
  6: Color(0xFFFF2D55),
};
