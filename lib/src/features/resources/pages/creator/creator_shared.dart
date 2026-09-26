import 'package:material_ui/material_ui.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:oronbox/src/app/generated/app_localizations.dart';
import 'package:oronbox/src/app/utils/error_localization.dart';
import 'package:oronbox/src/app/widgets/markdown_style_sheet.dart';
import 'package:oronbox/src/features/resources/application/creator/creator_workspace_controller.dart';
import 'package:oronbox/src/features/resources/domain/creator_workspace.dart';
import 'package:oronbox/src/features/settings/pages/legal_documents_page.dart';

const creatorStateOrder = [
  'draft',
  'pending',
  'rejected',
  'failed',
  'approved',
  'published',
  'suspended',
  'frozen',
];

String creatorWorkspaceState(CreatorWorkspace workspace) {
  if (workspace.resource.isFrozen) return 'frozen';
  if (workspace.resource.isSuspended) return 'suspended';
  if (workspace.revisions.isEmpty) return 'draft';
  if (workspace.latestRevision?.state == 'draft') return 'draft';
  final review = workspace.review?['state']?.toString();
  if (review == 'pending' ||
      review == 'reviewing' ||
      review == 'fixed_pending_review') {
    return 'pending';
  }
  if (review == 'rejected' ||
      review == 'needs_changes' ||
      review == 'changes_requested') {
    return 'rejected';
  }
  if (workspace.publications.any(
    (publication) => publication['state'] == 'failed',
  )) {
    return 'failed';
  }
  if (workspace.publications.any(
    (publication) => publication['state'] == 'published',
  )) {
    return 'published';
  }
  return review == 'approved' ? 'approved' : 'published';
}

String creatorStateLabel(AppLocalizations l10n, String state) =>
    switch (state) {
      'draft' => l10n.drafts,
      'suspended' => l10n.creatorStateSuspended,
      'frozen' => l10n.creatorStateFrozen,
      'pending' || 'submitted' => l10n.pendingReview,
      'approved' => l10n.creatorStateApproved,
      'rejected' => l10n.creatorReviewRejected,
      'needs_changes' ||
      'changes_requested' => l10n.creatorReviewChangesRequested,
      'fixed_pending_review' => l10n.creatorReviewFixedPending,
      'closed' => l10n.creatorReviewClosed,
      'published' => l10n.published,
      'reviewing' => l10n.creatorStateExternalReview,
      'failed' => l10n.creatorStateFailed,
      'superseded' => l10n.creatorStateSuperseded,
      'cancelled' => l10n.creatorStateCancelled,
      _ => state,
    };

String creatorOperationLabel(
  AppLocalizations l10n,
  CreatorOperation? operation,
) => switch (operation) {
  CreatorOperation.refreshing => l10n.creatorOperationRefreshing,
  CreatorOperation.creating => l10n.creatorOperationCreating,
  CreatorOperation.creatingCollection =>
    l10n.creatorOperationCreatingCollection,
  CreatorOperation.saving => l10n.creatorOperationSaving,
  CreatorOperation.publishing => l10n.creatorOperationSubmitting,
  CreatorOperation.deleting => l10n.creatorOperationDeleting,
  CreatorOperation.authorizing => l10n.creatorOperationAuthorizing,
  null => l10n.creatorOperationWorking,
};

String creatorTargetLabel(AppLocalizations l10n, String target) =>
    switch (target) {
      'oronbox' => l10n.oronBox,
      'bandbbs' => l10n.bandbbs,
      'astrobox' => l10n.astroBox,
      _ => target,
    };

String creatorKindLabel(AppLocalizations l10n, CreatorResourceKind kind) =>
    kind == CreatorResourceKind.watchface ? l10n.watchface : l10n.quickApp;

String creatorWorkspaceTitle(CreatorWorkspace workspace) {
  final latest = workspace.latestRevision;
  if (latest != null && latest.name.isNotEmpty) return latest.name;
  if (workspace.resource.draftName.isNotEmpty) {
    return workspace.resource.draftName;
  }
  return workspace.resource.slug;
}

String creatorReviewNote(CreatorWorkspace workspace) =>
    workspace.review?['note']?.toString().trim() ?? '';

CreatorMedia? creatorThumbnailMedia(CreatorWorkspace workspace) {
  CreatorMedia? preview;
  for (final media in workspace.media) {
    if (media.role == 'icon' && media.sha256.isNotEmpty) return media;
    if (media.role == 'preview' &&
        media.sha256.isNotEmpty &&
        (preview == null || media.position < preview.position)) {
      preview = media;
    }
  }
  return preview;
}

void showCreatorFailure(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(localizedErrorMessage(l10n, error))));
}

String formatCreatorFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024.0;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
}

class CreatorBrandLogo extends StatelessWidget {
  const CreatorBrandLogo({
    super.key,
    required this.asset,
    required this.label,
    this.size = 24,
  });

  final String asset;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      semanticsLabel: label,
      colorFilter: ColorFilter.mode(
        Theme.of(context).colorScheme.onSurface,
        BlendMode.srcIn,
      ),
    );
  }
}

class CreatorOronBoxLogo extends StatelessWidget {
  const CreatorOronBoxLogo({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/images/brands/oronbox.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      Theme.of(context).colorScheme.onSurface,
      BlendMode.srcIn,
    ),
    semanticsLabel: 'OronBox',
  );
}

class CreatorEditorCard extends StatelessWidget {
  const CreatorEditorCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
  );
}

class CreatorStateBadge extends StatelessWidget {
  const CreatorStateBadge({super.key, required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (state) {
      'rejected' ||
      'failed' ||
      'frozen' => (colors.errorContainer, colors.onErrorContainer),
      'pending' => (colors.tertiaryContainer, colors.onTertiaryContainer),
      'published' ||
      'approved' => (colors.primaryContainer, colors.onPrimaryContainer),
      _ => (colors.surfaceContainerHighest, colors.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        creatorStateLabel(AppLocalizations.of(context)!, state),
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: foreground),
      ),
    );
  }
}

class CreatorModerationNotice extends StatelessWidget {
  const CreatorModerationNotice({super.key, required this.resource});

  final CreatorResource resource;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final (icon, message) = switch ((
      resource.moderationState,
      resource.moderationBy,
    )) {
      ('frozen', _) => (Icons.ac_unit_outlined, l10n.creatorFrozenNotice),
      ('suspended', 'admin') => (
        Icons.gpp_maybe_outlined,
        l10n.creatorSuspendedByAdminNotice,
      ),
      _ => (Icons.visibility_off_outlined, l10n.creatorSuspendedByOwnerNotice),
    };
    return Card(
      color: resource.isFrozen
          ? colors.errorContainer
          : colors.surfaceContainerHigh,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: resource.isFrozen
                  ? colors.onErrorContainer
                  : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    creatorStateLabel(l10n, resource.moderationState),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: resource.isFrozen
                          ? colors.onErrorContainer
                          : colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: resource.isFrozen
                          ? colors.onErrorContainer
                          : colors.onSurfaceVariant,
                    ),
                  ),
                  if (resource.moderationReason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.creatorModerationReason(resource.moderationReason),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: resource.isFrozen
                              ? colors.onErrorContainer
                              : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreatorSectionTitle extends StatelessWidget {
  const CreatorSectionTitle({
    super.key,
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class CreatorBottomBar extends StatelessWidget {
  const CreatorBottomBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: children),
        ),
      ),
    );
  }
}

/// First-time publishing rules; shown before the very first resource create.
class CreatorReviewRulesDialog extends ConsumerWidget {
  const CreatorReviewRulesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final language = Localizations.localeOf(context).languageCode == 'en'
        ? 'en'
        : 'zh';
    return Dialog.fullscreen(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: FutureBuilder<String>(
                        future: loadLegalDocument(
                          ref,
                          'review-rules',
                          language,
                        ),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return Markdown(
                            data: snapshot.data!,
                            selectable: true,
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                            styleSheet: markdownStyleSheetFromTheme(theme)
                                .copyWith(
                                  p: theme.textTheme.bodyMedium?.copyWith(
                                    height: 1.5,
                                  ),
                                  pPadding: const EdgeInsets.only(bottom: 12),
                                  h1: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  h1Padding: const EdgeInsets.only(
                                    top: 16,
                                    bottom: 8,
                                  ),
                                  h2: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                  h2Padding: const EdgeInsets.only(
                                    top: 12,
                                    bottom: 6,
                                  ),
                                ),
                            onTapLink: (_, href, _) {
                              final uri = Uri.tryParse(href ?? '');
                              if (uri != null && uri.hasScheme) {
                                launchUrl(uri);
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
          ),
          CreatorBottomBar(
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.creatorRulesAccept),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CreatorReviewFeedback extends StatelessWidget {
  const CreatorReviewFeedback({super.key, required this.review});

  final Map<String, Object?> review;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final state = review['state']?.toString() ?? '';
    final note = review['note']?.toString().trim() ?? '';
    final rejected = state == 'rejected';
    return Card(
      color: rejected ? colors.errorContainer : colors.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              rejected ? Icons.feedback_outlined : Icons.fact_check_outlined,
              color: rejected
                  ? colors.onErrorContainer
                  : colors.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rejected
                        ? l10n.creatorReviewRejected
                        : l10n.creatorReviewState(
                            creatorStateLabel(l10n, state),
                          ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${l10n.reviewNote}: $note',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
