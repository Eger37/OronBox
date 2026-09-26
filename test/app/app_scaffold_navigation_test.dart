import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/app/layout/app_navigation_bar.dart';

void main() {
  testWidgets('narrow branch roots retain a scaffold below nested pages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: const MaterialApp(
          home: PrimaryBranchScaffold(child: Text('branch root')),
        ),
      ),
    );

    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('wide branch roots do not own the primary navigation scaffold', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 844)),
        child: const MaterialApp(
          home: PrimaryBranchScaffold(child: Text('branch root')),
        ),
      ),
    );

    expect(find.byType(Scaffold), findsNothing);
    expect(find.byType(AppBottomNavigationBar), findsNothing);
  });
}
