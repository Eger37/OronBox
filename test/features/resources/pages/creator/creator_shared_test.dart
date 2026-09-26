import 'package:flutter_test/flutter_test.dart';
import 'package:oronbox/src/app/generated/app_localizations_en.dart';
import 'package:oronbox/src/features/resources/domain/creator_workspace.dart';
import 'package:oronbox/src/features/resources/pages/creator/creator_review_list_page.dart'
    show creatorReviewMatchesFilter;
import 'package:oronbox/src/features/resources/pages/creator/creator_shared.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('creatorStateLabel', () {
    test('localizes every review state rendered by CreatorStateBadge', () {
      for (final state in const [
        'needs_changes',
        'changes_requested',
        'fixed_pending_review',
        'closed',
      ]) {
        expect(
          creatorStateLabel(l10n, state),
          isNot(state),
          reason: '$state must not render as a raw enum string',
        );
      }
      expect(
        creatorStateLabel(l10n, 'needs_changes'),
        l10n.creatorReviewChangesRequested,
      );
      expect(
        creatorStateLabel(l10n, 'fixed_pending_review'),
        l10n.creatorReviewFixedPending,
      );
      expect(creatorStateLabel(l10n, 'closed'), l10n.creatorReviewClosed);
    });
  });

  group('creatorWorkspaceState', () {
    CreatorWorkspace workspaceWithReview(String state) =>
        CreatorWorkspace.fromJson({
          'resource': {'id': 'r1', 'slug': 'slug'},
          'revisions': [
            {'id': 'v1', 'number': 1, 'state': 'published'},
          ],
          'review': {'state': state},
        });

    test('treats needs_changes like changes_requested', () {
      expect(
        creatorWorkspaceState(workspaceWithReview('needs_changes')),
        'rejected',
      );
      expect(
        creatorWorkspaceState(workspaceWithReview('changes_requested')),
        'rejected',
      );
    });

    test('maps the active review states to pending', () {
      for (final state in const [
        'pending',
        'reviewing',
        'fixed_pending_review',
      ]) {
        expect(
          creatorWorkspaceState(workspaceWithReview(state)),
          'pending',
          reason: state,
        );
      }
    });
  });

  group('creatorReviewMatchesFilter', () {
    test('the fixed_pending_review chip matches its own state', () {
      expect(
        creatorReviewMatchesFilter(
          'fixed_pending_review',
          'fixed_pending_review',
        ),
        isTrue,
      );
      expect(
        creatorReviewMatchesFilter('fixed_pending_review', 'pending'),
        isFalse,
      );
    });

    test('active spans every open state', () {
      for (final state in const [
        'pending',
        'reviewing',
        'needs_changes',
        'changes_requested',
        'fixed_pending_review',
      ]) {
        expect(
          creatorReviewMatchesFilter('active', state),
          isTrue,
          reason: state,
        );
      }
      expect(creatorReviewMatchesFilter('active', 'closed'), isFalse);
      expect(creatorReviewMatchesFilter('active', 'superseded'), isFalse);
    });

    test('unknown filters match nothing instead of everything', () {
      expect(creatorReviewMatchesFilter('nonsense', 'pending'), isFalse);
    });
  });
}
