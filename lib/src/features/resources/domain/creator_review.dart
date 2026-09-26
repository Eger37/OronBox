class CreatorReviewCase {
  const CreatorReviewCase({
    required this.id,
    required this.resourceId,
    required this.revisionId,
    required this.resourceName,
    required this.resourceKind,
    required this.reviewType,
    required this.state,
    required this.note,
    required this.updatedAt,
    this.iconUrl = '',
  });

  final String id;
  final String resourceId;
  final String revisionId;
  final String resourceName;
  final String resourceKind;
  final String reviewType;
  final String state;
  final String note;
  final DateTime updatedAt;
  final String iconUrl;

  factory CreatorReviewCase.fromJson(Map<String, Object?> json) =>
      CreatorReviewCase(
        id: json['id']?.toString() ?? '',
        resourceId: json['resource_id']?.toString() ?? '',
        revisionId: json['revision_id']?.toString() ?? '',
        resourceName: json['resource_name']?.toString() ?? '',
        resourceKind: json['resource_kind']?.toString() ?? '',
        reviewType: json['review_type']?.toString() ?? 'normal',
        state: json['state']?.toString() ?? '',
        note: json['note']?.toString() ?? '',
        updatedAt:
            DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        iconUrl:
            ((json['icon'] as Map?)?['url'] ?? json['icon_url'])?.toString() ??
            '',
      );
}
