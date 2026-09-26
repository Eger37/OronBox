import 'dart:io';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:oronbox/src/app/generated/app_localizations.dart';
import 'package:oronbox/src/app/utils/error_localization.dart';
import 'package:oronbox/src/app/widgets/smooth_linear_progress_indicator.dart';
import 'package:oronbox/src/core/constants/app_constants.dart';
import 'package:oronbox/src/core/network/github_cdn.dart';
import 'package:oronbox/src/core/providers/app_settings_providers.dart';
import 'package:oronbox/src/features/settings/services/oronbox_support_api.dart';

/// Android in-app update: resolves the APK for the device ABI, downloads it
/// through the configured GitHub CDN and hands it to the system installer.
class UpdateDownloadDialog extends ConsumerStatefulWidget {
  const UpdateDownloadDialog({super.key, required this.release});

  final AppReleaseInfo release;

  @override
  ConsumerState<UpdateDownloadDialog> createState() =>
      _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends ConsumerState<UpdateDownloadDialog> {
  static const _channel = MethodChannel('oronbox/installer');

  /// Maps an Android ABI to the asset name suffix of the matching APK.
  static const _apkSuffix = <String, String>{
    'arm64-v8a': '-android-arm64-v8a.apk',
    'armeabi-v7a': '-android-armeabi-v7a.apk',
    'x86_64': '-android-x86_64.apk',
  };

  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final abi = await _channel.invokeMethod<String>('getSupportedAbi');
      final url = await _resolveApkUrl(abi);
      if (url == null) {
        if (mounted) {
          setState(
            () => _error = AppLocalizations.of(
              context,
            )!.updateNoApkForAbi(abi ?? '-'),
          );
        }
        return;
      }
      final cdn = ref.read(appSettingsProvider).effectiveCdn;
      final downloadUrl = rewriteGithubCdnUrl(url, cdn);
      final dir = await getApplicationSupportDirectory();
      final apkDir = Directory('${dir.path}/apk');
      await apkDir.create(recursive: true);
      final path = '${apkDir.path}/oronbox.apk';
      await Dio().download(
        downloadUrl,
        path,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      if (!mounted) return;
      setState(() => _progress = 1);
      await _channel.invokeMethod('installApk', {'path': path});
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = localizedErrorMessage(AppLocalizations.of(context)!, e),
        );
      }
    }
  }

  Future<String?> _resolveApkUrl(String? abi) async {
    final response = await Dio().get<List<dynamic>>(
      '${AppConstants.githubRepoApiUrl}/releases?per_page=1',
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
    final releases = response.data;
    if (releases == null || releases.isEmpty) return null;
    final release = releases.first as Map<String, dynamic>;
    final assets =
        (release['assets'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final suffix = _apkSuffix[abi];
    for (final asset in assets) {
      final name = asset['name']?.toString() ?? '';
      final matches = suffix != null
          ? name.endsWith(suffix)
          : name.contains('-android-') && name.endsWith('.apk');
      if (matches) {
        return asset['browser_download_url']?.toString();
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final error = _error;
    return AlertDialog(
      title: Text('v${widget.release.latestVersion}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null) ...[
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(l10n.updateFailed),
            const SizedBox(height: 4),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ] else ...[
            SmoothLinearProgressIndicator(value: _progress),
            const SizedBox(height: 8),
            Text(
              _progress >= 1 ? l10n.updateInstalling : l10n.updateDownloading,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
