import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/app/widgets/release_notes_view.dart';

void main() {
  test('parses release-note lists without a Markdown widget', () {
    final blocks = ReleaseNotesParser.parse('''## Changes

- Fixed reconnect handling
- Preserved the complete release body

The details remain available.''');

    expect(blocks, hasLength(3));
    expect(blocks[0], isA<ReleaseNotesHeading>());
    expect(blocks[1], isA<ReleaseNotesList>());
    expect((blocks[1] as ReleaseNotesList).items, [
      'Fixed reconnect handling',
      'Preserved the complete release body',
    ]);
    expect(
      (blocks[2] as ReleaseNotesParagraph).text,
      'The details remain available.',
    );
  });

  testWidgets('renders a parsed list as selectable text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ReleaseNotesView(data: '- First\n- Second')),
    );

    expect(find.text('• First'), findsOneWidget);
    expect(find.text('• Second'), findsOneWidget);
    expect(find.byType(SelectableText), findsNWidgets(2));
  });
}
