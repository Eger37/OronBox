import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:oronbox/src/app/widgets/sys_app_bar.dart';
import 'package:oronbox/src/app/widgets/markdown_style_sheet.dart';
import 'package:oronbox/src/core/constants/style_constants.dart';
import 'package:oronbox/src/features/resources/widgets/resource_external_link.dart';

Future<String> loadLegalDocument(
  WidgetRef ref,
  String id,
  String language,
) async {
  return rootBundle.loadString('assets/legal/$id.$language.md', cache: false);
}

String legalDocumentLanguage(Locale locale) {
  return locale.languageCode == 'zh' ? 'zh' : 'en';
}

class LegalDocumentPage extends ConsumerWidget {
  const LegalDocumentPage({super.key, required this.id, required this.title});

  final String id;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: SysAppBar(secondary: true, title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(StyleConstants.cardRadius),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(StyleConstants.cardRadius),
                child: FutureBuilder<String>(
                  future: loadLegalDocument(
                    ref,
                    id,
                    legalDocumentLanguage(Localizations.localeOf(context)),
                  ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(48),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return Markdown(
                      data: snapshot.data!,
                      selectable: true,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      styleSheet: markdownStyleSheetFromTheme(theme).copyWith(
                        p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                        pPadding: const EdgeInsets.only(bottom: 12),
                        h1: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        h1Padding: const EdgeInsets.only(top: 16, bottom: 8),
                        h2: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        h2Padding: const EdgeInsets.only(top: 12, bottom: 6),
                      ),
                      onTapLink: (_, href, _) {
                        final uri = Uri.tryParse(href ?? '');
                        if (uri != null && uri.hasScheme) {
                          openResourceExternalLink(context, uri);
                        }
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
