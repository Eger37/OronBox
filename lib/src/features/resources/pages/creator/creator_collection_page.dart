import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:oronbox/src/app/generated/app_localizations.dart';
import 'package:oronbox/src/app/widgets/page_container.dart';
import 'package:oronbox/src/app/widgets/sys_app_bar.dart';
import 'package:oronbox/src/core/constants/style_constants.dart';
import 'package:oronbox/src/features/resources/application/creator/creator_workspace_controller.dart';
import 'package:oronbox/src/features/resources/domain/creator_workspace.dart';
import 'package:oronbox/src/features/resources/pages/creator/creator_resource_list.dart';
import 'package:oronbox/src/features/resources/pages/creator/creator_shared.dart';

class CreatorCollectionPage extends ConsumerStatefulWidget {
  const CreatorCollectionPage({
    super.key,
    required this.collectionId,
    this.item,
  });

  final String collectionId;
  final Map<String, Object?>? item;

  @override
  ConsumerState<CreatorCollectionPage> createState() =>
      _CreatorCollectionPageState();
}

class _CreatorCollectionPageState extends ConsumerState<CreatorCollectionPage> {
  final _name = TextEditingController();
  final _summary = TextEditingController();
  Map<String, Object?>? _item;
  var _loading = true;
  var _saving = false;
  var _creatingResource = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _seedFields();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  void _seedFields() {
    final pending = _item?['pending_revision'] as Map?;
    final current = _item?['current_revision'] as Map?;
    final metadata = pending ?? current;
    _name.text = metadata?['name']?.toString() ?? '';
    _summary.text = metadata?['summary']?.toString() ?? '';
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final controller = ref.read(creatorWorkspaceProvider.notifier);
      await controller.refresh();
      _adoptCollectionFromWorkspace();
    } catch (error) {
      if (mounted) showCreatorFailure(context, error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(creatorWorkspaceProvider.notifier)
          .updateCollection(
            collectionId: widget.collectionId,
            name: _name.text.trim(),
            summary: _summary.text.trim(),
          );
      _adoptCollectionFromWorkspace();
    } catch (error) {
      if (mounted) showCreatorFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createResource(
    CreatorResourceKind kind,
    List<CreatorWorkspace> children,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final name = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.creatorNewResource),
        content: TextField(
          controller: name,
          autofocus: true,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: l10n.creatorResourceName),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, true);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) Navigator.pop(context, true);
            },
            child: Text(l10n.creatorNewResource),
          ),
        ],
      ),
    );
    final resourceName = name.text.trim();
    name.dispose();
    if (accepted != true || !mounted) return;
    final controller = ref.read(creatorWorkspaceProvider.notifier);
    setState(() => _creatingResource = true);
    try {
      final slug = 'resource-${DateTime.now().microsecondsSinceEpoch}';
      await controller.create(slug, resourceName, kind);
      final created = ref.read(creatorWorkspaceProvider).selected;
      if (created == null) return;
      final resourceIds = [
        ...children.map((entry) => entry.resource.id),
        created.resource.id,
      ];
      await controller.setCollectionResources(
        collectionId: widget.collectionId,
        resourceIds: resourceIds,
        representativeResourceId:
            _item?['representative_resource_id']?.toString().isNotEmpty == true
            ? _item!['representative_resource_id'].toString()
            : created.resource.id,
      );
      final attached = ref
          .read(creatorWorkspaceProvider)
          .resources
          .where((entry) => entry.resource.id == created.resource.id)
          .firstOrNull;
      if (attached != null) controller.select(attached);
      if (mounted) {
        context.push('/resources/creator/resources/${created.resource.id}');
      }
    } catch (error) {
      if (mounted) showCreatorFailure(context, error);
    } finally {
      if (mounted) setState(() => _creatingResource = false);
    }
  }

  Future<void> _chooseRepresentative(List<CreatorWorkspace> children) async {
    if (children.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final selected = await showDialog<CreatorWorkspace>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.creatorCollectionRepresentative),
        children: [
          for (final workspace in children)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, workspace),
              child: Text(creatorWorkspaceTitle(workspace)),
            ),
        ],
      ),
    );
    if (selected == null) return;
    try {
      await ref
          .read(creatorWorkspaceProvider.notifier)
          .setCollectionResources(
            collectionId: widget.collectionId,
            resourceIds: children.map((item) => item.resource.id).toList(),
            representativeResourceId: selected.resource.id,
          );
      _adoptCollectionFromWorkspace();
    } catch (error) {
      if (mounted) showCreatorFailure(context, error);
    }
  }

  void _adoptCollectionFromWorkspace() {
    final item = ref
        .read(creatorWorkspaceProvider)
        .collections
        .where((entry) => entry['id']?.toString() == widget.collectionId)
        .firstOrNull;
    if (!mounted || item == null) return;
    setState(() {
      _item = item;
      _seedFields();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(creatorWorkspaceProvider);
    final controller = ref.read(creatorWorkspaceProvider.notifier);
    final kind = _item?['kind'] == 'watchface'
        ? CreatorResourceKind.watchface
        : CreatorResourceKind.quickApp;
    final candidates = state.resources
        .where((entry) => entry.resource.kind == kind)
        .toList();
    final children =
        candidates
            .where(
              (entry) => entry.resource.collectionId == widget.collectionId,
            )
            .toList()
          ..sort(
            (a, b) => a.resource.collectionPosition.compareTo(
              b.resource.collectionPosition,
            ),
          );
    final representativeId =
        _item?['representative_resource_id']?.toString() ?? '';
    final representative = candidates
        .where((entry) => entry.resource.id == representativeId)
        .firstOrNull;

    return Scaffold(
      appBar: SysAppBar(
        secondary: true,
        title: Text(_name.text.isEmpty ? l10n.creatorCollections : _name.text),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? LoadingView(message: l10n.creatorOperationRefreshing)
          : SingleChildScrollView(
              child: PageContainer(
                maxWidth: 1000,
                padding: const EdgeInsets.all(StyleConstants.pagePadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CreatorSectionTitle(
                      icon: Icons.description_outlined,
                      title: l10n.basicInfo,
                    ),
                    const SizedBox(height: 8),
                    CreatorEditorCard(
                      child: Column(
                        children: [
                          TextField(
                            controller: _name,
                            maxLength: 120,
                            decoration: InputDecoration(
                              labelText: l10n.creatorCollectionName,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _summary,
                            minLines: 3,
                            maxLines: 8,
                            decoration: InputDecoration(
                              labelText: l10n.creatorCollectionSummary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    CreatorSectionTitle(
                      icon: Icons.collections_outlined,
                      title: l10n.creatorIconCover,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _CollectionMediaCard(
                          key: ValueKey('icon-$representativeId'),
                          workspace: representative,
                          controller: controller,
                          role: 'icon',
                          title: l10n.creatorOptionalIcon,
                          width: 208,
                          onChange: children.isEmpty
                              ? null
                              : () => _chooseRepresentative(children),
                        ),
                        _CollectionMediaCard(
                          key: ValueKey('cover-$representativeId'),
                          workspace: representative,
                          controller: controller,
                          role: 'cover',
                          title: l10n.creatorOptionalCover,
                          width: 300,
                          onChange: children.isEmpty
                              ? null
                              : () => _chooseRepresentative(children),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    CreatorSectionTitle(
                      icon: Icons.inventory_2_outlined,
                      title: l10n.creatorResourceList,
                    ),
                    const SizedBox(height: 8),
                    for (final workspace in children)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: CreatorResourceCard(
                          workspace: workspace,
                          controller: controller,
                          onTap: () {
                            controller.select(workspace);
                            context.push(
                              '/resources/creator/resources/${workspace.resource.id}',
                            );
                          },
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: _creatingResource
                            ? null
                            : () => _createResource(kind, children),
                        icon: _creatingResource
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add),
                        label: Text(l10n.creatorNewResource),
                      ),
                    ),
                    const SizedBox(height: 88),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: _loading && _item == null
          ? null
          : CreatorBottomBar(
              children: [
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(l10n.save),
                ),
              ],
            ),
    );
  }
}

class _CollectionMediaCard extends StatefulWidget {
  const _CollectionMediaCard({
    super.key,
    required this.workspace,
    required this.controller,
    required this.role,
    required this.title,
    required this.width,
    this.onChange,
  });

  final CreatorWorkspace? workspace;
  final CreatorWorkspaceController controller;
  final String role;
  final String title;
  final double width;
  final VoidCallback? onChange;

  @override
  State<_CollectionMediaCard> createState() => _CollectionMediaCardState();
}

class _CollectionMediaCardState extends State<_CollectionMediaCard> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final workspace = widget.workspace;
    final media = workspace?.media
        .where((entry) => entry.role == widget.role)
        .firstOrNull;
    if (workspace == null || media == null) return;
    try {
      final bytes = await widget.controller.blob(
        workspace.resource.id,
        media.sha256,
      );
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    child: Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 184,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _bytes == null
                  ? ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Icon(Icons.image_outlined),
                    )
                  : Image.memory(_bytes!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 8),
          Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            _media() == null
                ? ' '
                : '${_mediaWidth()} × ${_mediaHeight()} · ${formatCreatorFileSize(_mediaSize())}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: widget.onChange,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: Text(
                    _media() == null
                        ? AppLocalizations.of(context)!.add
                        : AppLocalizations.of(context)!.replace,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  CreatorMedia? _media() => widget.workspace?.media
      .where((entry) => entry.role == widget.role)
      .firstOrNull;

  int _mediaWidth() => _media()?.width ?? 0;
  int _mediaHeight() => _media()?.height ?? 0;
  int _mediaSize() => _media()?.sizeBytes ?? 0;
}
