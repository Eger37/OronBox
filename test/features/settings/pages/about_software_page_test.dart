import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oronbox/src/app/generated/app_localizations.dart';
import 'package:oronbox/src/app/app_localizations_delegates.dart';
import 'package:oronbox/src/core/services/build_info_service.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/src/features/settings/pages/about_software_page.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPrefsService.instance.init();
  });

  testWidgets('runtime logs moved out of about software', (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const AboutSoftwarePage()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.textContaining('BUILD_USER: ${BuildInfoService.buildUser}'),
      findsOneWidget,
    );
    expect(find.text('打开日志文件夹'), findsNothing);
  });

  testWidgets('log disclosure can be acknowledged immediately', (tester) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const RuntimeLogsPage())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    final openLogs = find.text('打开日志文件夹');
    await tester.ensureVisible(openLogs);
    await tester.pumpAndSettle();
    await tester.tap(openLogs);
    await tester.pump();

    final confirm = find.widgetWithText(TextButton, '我知道了');
    expect(confirm, findsOneWidget);
    expect(tester.widget<TextButton>(confirm).onPressed, isNotNull);

    final cancel = find.widgetWithText(TextButton, '取消');
    expect(cancel, findsOneWidget);
    expect(tester.widget<TextButton>(cancel).onPressed, isNotNull);

    await tester.tap(cancel);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('device log pull explains the uninterrupted transfer first', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const RuntimeLogsPage())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    final pull = find.text('拉取设备日志');
    await tester.ensureVisible(pull.first);
    await tester.tap(pull.first);
    await tester.pump();

    expect(find.textContaining('请勿将应用切换到后台'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pump();
  });

  testWidgets('Android runtime logs exposes Xiaomi Fitness log sync', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (_, _) => const RuntimeLogsPage())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    final sync = find.text('读取运动健康日志');
    await tester.ensureVisible(sync.first);
    expect(find.byIcon(Icons.folder_zip_outlined), findsOneWidget);
    await tester.tap(sync.first);
    await tester.pump();

    expect(find.textContaining('连续狂点橙色圆环 logo 图标'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '扫描'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
