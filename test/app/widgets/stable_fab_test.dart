import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/app/widgets/stable_fab.dart';

void main() {
  testWidgets('switches FAB content with opacity only', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: StableFabSwitcher(child: Text('one', key: ValueKey('one'))),
        ),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: StableFabSwitcher(child: Text('two', key: ValueKey('two'))),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 90));

    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(ScaleTransition), findsNothing);
    expect(find.byType(RotationTransition), findsNothing);
  });

  testWidgets('uses a tonal surface for secondary actions', (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: Scaffold(
          floatingActionButton: StableExtendedFab(
            heroTag: 'secondary',
            onPressed: () {},
            icon: const Icon(Icons.undo),
            label: const Text('Undo'),
            secondary: true,
          ),
        ),
      ),
    );

    final button = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(button.backgroundColor, scheme.secondaryContainer);
    expect(button.foregroundColor, scheme.onSecondaryContainer);
  });
}
