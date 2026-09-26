import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:oronbox/src/app/generated/app_localizations.dart';
import 'package:oronbox/src/app/widgets/dialog_helper.dart';
import 'package:oronbox/src/commands/command_protocol.dart';
import 'package:oronbox/src/core/logging/logging_service.dart';
import 'package:oronbox/src/core/models/bt_models.dart';
import 'package:oronbox/src/core/models/xiaomi_health_models.dart';
import 'package:oronbox/src/device/core/connect_type.dart';
import 'package:oronbox/src/device/core/device_kind.dart';
import 'package:oronbox/src/device/core/event_bus.dart';
import 'package:oronbox/src/device/zeppos/systems/zeppos_app_side_system.dart';
import 'package:oronbox/src/device/zeppos/systems/zeppos_voice_memos_system.dart';
import 'package:oronbox/src/features/accounts/models/mi_account_models.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/features/devices/services/xiaomi_screenshot_storage.dart';
import 'package:oronbox/src/features/devices/services/phone_finder.dart';
import 'package:oronbox/src/features/devices/health/health_models.dart';
import 'package:oronbox/src/device/xiaomi/components/health_system.dart';
import 'package:oronbox/src/features/devices/models/xiaomi_device_features.dart';
import 'package:oronbox/src/features/devices/controllers/interconnect_event_codec.dart';
import 'package:oronbox/src/host/application_host_provider.dart';
import 'package:oronbox/src/protocols/common/device_protocol.dart';
import 'package:oronbox/src/protocols/generated/xiaomi/wear_system.pb.dart'
    as pb_system;

class HostDeviceManager extends DeviceManager {
  static final _log = getLogger('HostDeviceManager');

  StreamSubscription<CommandEvent>? _eventSubscription;
  final _deviceEventBus = DeviceEventBus();
  bool _disposed = false;
  var _connectGeneration = 0;
  String? _pendingConnectionAddr;
  final _zmlHandlers = <int, ZeppOsZmlHookHandler>{};

  @override
  DeviceManagerState build() {
    final host = ref.watch(applicationHostProvider);
    ref.onDispose(() {
      _disposed = true;
      unawaited(_eventSubscription?.cancel());
      _deviceEventBus.dispose();
    });
    _eventSubscription = host.events.listen(_handleEvent);
    scheduleMicrotask(_refreshSnapshot);
    return const DeviceManagerState();
  }

  void _handleEvent(CommandEvent event) {
    final interconnect = decodeInterconnectEvent(event);
    if (interconnect != null) {
      emitInterconnectMessage(interconnect);
      return;
    }
    if (event.event == 'device.zeppos.xiaoai.opus') {
      final raw = event.data['frame'];
      if (raw is List) {
        emitXiaoAiOpusFrame(
          Uint8List.fromList(
            raw.whereType<num>().map((value) => value.toInt() & 0xff).toList(),
          ),
        );
      }
      return;
    }
    if (event.event == 'device.xiaomi.screenshot.received') {
      final raw = event.data['bytes'];
      if (raw is List) {
        final bytes = Uint8List.fromList(
          raw.whereType<num>().map((value) => value.toInt() & 0xff).toList(),
        );
        _log.info(
          'received Xiaomi screenshot event (${bytes.length} bytes); '
          'saving to Pictures/WatchScreenshots',
        );
        unawaited(_saveXiaomiScreenshot(bytes));
      }
      return;
    }
    if (event.event == XiaomiGnssAccountRequired.commandEvent) {
      final context = OronBoxDialog.observer.scaffoldContext;
      if (context != null && context.mounted) {
        final l10n = AppLocalizations.of(context);
        if (l10n != null) {
          OronBoxDialog.showToast(
            context: context,
            message: l10n.xiaomiAccountRequiredForEphemeris,
            duration: const Duration(seconds: 4),
          );
        }
      }
      return;
    }
    if (event.event == PassiveReconnectStatus.commandEvent) {
      final phase = PassiveReconnectPhase.values
          .where((value) => value.name == event.data['phase']?.toString())
          .firstOrNull;
      if (phase != null) {
        _deviceEventBus.emit(
          PassiveReconnectStatus(
            deviceId: event.data['deviceId']?.toString() ?? '',
            phase: phase,
            attempt: (event.data['attempt'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      return;
    }
    if (event.event == 'device.zeppos.zml.hook') {
      unawaited(_dispatchZmlHook(event.data));
      return;
    }
    if (event.event == 'host.disconnected') {
      if (!_disposed) {
        state = state.copyWith(
          connecting: false,
          protocolState: ProtocolState.disconnected,
          clearHealth: true,
          error: 'daemon_disconnected',
        );
      }
      return;
    }
    if (event.event == 'host.connected') {
      unawaited(_refreshSnapshot());
      for (final appId in _zmlHandlers.keys.toList(growable: false)) {
        unawaited(_attachZmlOnHost(appId));
      }
      return;
    }
    if (event.event != 'device.state') return;
    final raw = event.data['state'];
    if (raw is Map) _applyState(raw.cast<String, Object?>());
  }

  @override
  Stream<DeviceEvent> get deviceEvents => _deviceEventBus.stream;

  Future<void> _saveXiaomiScreenshot(Uint8List bytes) async {
    try {
      final path = await saveXiaomiScreenshot(bytes);
      if (path != null) {
        _log.info('saved Xiaomi screenshot to $path');
        final context = OronBoxDialog.observer.scaffoldContext;
        if (context != null && context.mounted) {
          final l10n = AppLocalizations.of(context);
          if (l10n != null) {
            OronBoxDialog.showToast(
              context: context,
              message: l10n.xiaomiScreenshotSaved(path),
            );
          }
        }
      } else {
        _log.warning(
          'Xiaomi screenshot received but no storage path was available',
        );
      }
    } catch (error, stackTrace) {
      _log.warning('saving Xiaomi screenshot failed', error, stackTrace);
    }
  }

  Future<void> _dispatchZmlHook(Map<String, Object?> data) async {
    final appId = (data['appId'] as num?)?.toInt();
    final requestId = data['requestId']?.toString() ?? '';
    final handler = appId == null ? null : _zmlHandlers[appId];
    if (handler == null || requestId.isEmpty) return;
    Object? result;
    try {
      result = await handler(data['hook']?.toString() ?? '', data['payload']);
    } catch (error) {
      _log.warning('ZML hook handler failed for appId $appId', error);
    }
    try {
      await _execute(
        OronBoxCommand(
          method: 'device.zeppos.zml.respond',
          params: {'requestId': requestId, 'result': result},
        ),
      );
    } catch (error) {
      _log.warning('ZML hook response lost for appId $appId', error);
    }
  }

  Future<CommandResult> _execute(OronBoxCommand command) async {
    final result = await ref.read(applicationHostProvider).execute(command);
    if (!result.ok) {
      final error = result.error;
      if (error == null) {
        throw StateError('Daemon command failed without error details');
      }
      throw error;
    }
    return result;
  }

  Future<void> _refreshSnapshot() async {
    try {
      final result = await _execute(
        const OronBoxCommand(method: 'device.snapshot'),
      );
      final raw = result.value;
      if (raw is Map) _applyState(raw.cast<String, Object?>());
    } catch (error) {
      if (!_disposed) state = state.copyWith(error: error.toString());
    }
  }

  void _applyState(Map<String, Object?> raw) {
    if (_disposed) return;
    final previousProtocol = state.protocolState;
    final previousDevice = state.currentDevice;
    final wasConnected = previousDevice != null && !previousDevice.disconnected;
    final rawConnectionTarget = raw['connectionTargetAddr']?.toString();
    final pendingConnectionAddr = _pendingConnectionAddr;
    if (pendingConnectionAddr != null &&
        state.connecting &&
        rawConnectionTarget != pendingConnectionAddr) {
      return;
    }
    final current = raw['currentDevice'];
    final battery = raw['battery'];
    final health = raw['health'];
    final systemInfo = raw['systemInfo'];
    state = DeviceManagerState(
      currentDevice: current is Map
          ? MiWearState.fromJson(current.cast<String, dynamic>())
          : null,
      pairedDevices: _modelList(raw['pairedDevices'], MiWearState.fromJson),
      scannedDevices: _modelList(raw['scannedDevices'], BTDeviceInfo.fromJson),
      scanning: raw['scanning'] == true,
      connecting: raw['connecting'] == true,
      connectionTargetAddr: rawConnectionTarget,
      connectionTargetName: raw['connectionTargetName']?.toString(),
      connectionPhase: DeviceConnectionPhase.values
          .where((value) => value.name == raw['connectionPhase']?.toString())
          .firstOrNull,
      connectStatus: (raw['connectStatus'] as num?)?.toInt() ?? 0,
      protocolState: ProtocolState.values.firstWhere(
        (value) => value.name == raw['protocolState']?.toString(),
        orElse: () => ProtocolState.disconnected,
      ),
      battery: battery is Map
          ? BatteryStatus.fromJson(battery.cast<String, dynamic>())
          : null,
      health: health is Map
          ? XiaomiHealthState.fromJson(health.cast<String, dynamic>())
          : null,
      systemInfo: systemInfo is Map
          ? SystemInfo.fromJson(systemInfo.cast<String, dynamic>())
          : null,
      apps: _modelList(raw['apps'], AppInfo.fromJson),
      watchfaces: _modelList(raw['watchfaces'], WatchfaceInfo.fromJson),
      xiaoAiActive: raw['xiaoAiActive'] == true,
      xiaoAiFrameCount: (raw['xiaoAiFrameCount'] as num?)?.toInt() ?? 0,
      xiaoAiCapabilities: raw['xiaoAiCapabilities'] is Map
          ? (raw['xiaoAiCapabilities'] as Map).cast<String, Object?>()
          : const {},
      findingXiaomiWearable: raw['findingXiaomiWearable'] == true,
      uploadBytesPerSecond:
          (raw['uploadBytesPerSecond'] as num?)?.toDouble() ?? 0,
      downloadBytesPerSecond:
          (raw['downloadBytesPerSecond'] as num?)?.toDouble() ?? 0,
      error: raw['error']?.toString(),
    );
    final connectedDevice = state.currentDevice;
    final isConnected =
        connectedDevice != null && !connectedDevice.disconnected;
    if (state.protocolState != previousProtocol ||
        isConnected != wasConnected) {
      logDiagnostic(
        _log,
        Level.INFO,
        'Device connection state changed',
        fields: {
          'protocol': state.protocolState.name,
          'connected': isConnected,
          if (connectedDevice != null) 'device': connectedDevice.name,
          if (connectedDevice != null) 'addr': connectedDevice.addr,
        },
      );
    }
  }

  List<T> _modelList<T>(
    Object? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) => raw is List
      ? raw
            .whereType<Map>()
            .map((item) => fromJson(item.cast<String, dynamic>()))
            .toList()
      : <T>[];

  Future<Map<String, Object?>> _executeState(String method) async {
    final result = await _execute(OronBoxCommand(method: method));
    final raw = (result.value as Map).cast<String, Object?>();
    _applyState(raw);
    return raw;
  }

  @override
  Future<void> startBluetoothScan({
    ConnectType connectType = ConnectType.ble,
  }) async {
    state = state.copyWith(
      scanning: true,
      scannedDevices: const [],
      clearError: true,
    );
    try {
      await _execute(
        OronBoxCommand(
          method: 'device.scan.start',
          params: {'connectType': connectType.name},
        ),
      );
    } catch (error, stackTrace) {
      _log.severe('start remote scan failed', error, stackTrace);
      if (!_disposed) {
        state = state.copyWith(scanning: false, error: error.toString());
      }
    }
  }

  @override
  Future<void> stopBluetoothScan() async {
    await _executeState('device.scan.stop');
  }

  @override
  Future<void> connect(
    String addr,
    String name,
    String authKey, {
    DeviceKind kind = DeviceKind.xiaomi,
    String connectType = 'ble',
  }) async {
    final generation = ++_connectGeneration;
    _pendingConnectionAddr = addr;
    // The auth key must never appear in logs.
    logDiagnostic(
      _log,
      Level.INFO,
      'Device connect requested',
      fields: {
        'addr': addr,
        'name': name,
        'kind': kind.name,
        'connectType': connectType,
      },
    );
    state = state.copyWith(
      connecting: true,
      connectionTargetAddr: addr,
      connectionTargetName: name,
      connectionPhase: DeviceConnectionPhase.preparing,
      // Mirror the backend's connect-start contract. Without this, a stale
      // connectStatus=3 from a previous failure survives into the new
      // attempt and lets listeners mistake any connecting->idle transition
      // for a fresh failure (the premature input-field error).
      connectStatus: 1,
      protocolState: ProtocolState.connecting,
      clearBattery: true,
      clearHealth: true,
      clearSystemInfo: true,
      apps: const [],
      watchfaces: const [],
      xiaoAiActive: false,
      xiaoAiFrameCount: 0,
      xiaoAiCapabilities: const {},
      clearError: true,
    );
    try {
      await importSharedDevice(
        MiWearState(
          name: name,
          addr: addr,
          connectType: connectType,
          authkey: authKey,
          disconnected: true,
        ),
      );
      if (generation != _connectGeneration) return;
      await _execute(
        OronBoxCommand(method: 'device.connect', params: {'device': addr}),
      );
      if (generation != _connectGeneration) return;
      await _refreshSnapshot();
      if (generation == _connectGeneration) _pendingConnectionAddr = null;
    } catch (error, stackTrace) {
      if (generation != _connectGeneration) return;
      _pendingConnectionAddr = null;
      _log.severe('remote connect to $addr failed', error, stackTrace);
      if (!_disposed) {
        state = state.copyWith(
          connecting: false,
          connectStatus: 3,
          protocolState: ProtocolState.error,
          // The daemon usually pushes the underlying failure through
          // device.state before this command error arrives; keep that
          // original error so one failure is not reported as two
          // differently-worded errors.
          error: state.error ?? error.toString(),
        );
      }
    }
  }

  @override
  Future<void> disconnect([String? address]) async {
    _connectGeneration += 1;
    _pendingConnectionAddr = null;
    logDiagnostic(
      _log,
      Level.INFO,
      'Device disconnect requested',
      fields: {if (address != null) 'addr': address},
    );
    await _execute(
      OronBoxCommand(
        method: 'device.disconnect',
        params: {if (address != null) 'device': address},
      ),
    );
    await _refreshSnapshot();
  }

  @override
  Future<void> cancelConnect() async {
    if (!state.connecting) return;
    _connectGeneration += 1;
    _pendingConnectionAddr = null;
    await _execute(const OronBoxCommand(method: 'device.connect.cancel'));
    await _refreshSnapshot();
  }

  @override
  Future<void> removeDevice(String addr) async {
    await _execute(
      OronBoxCommand(method: 'device.remove', params: {'device': addr}),
    );
    await _refreshSnapshot();
  }

  var _batteryRefreshPaused = false;

  @override
  bool get batteryRefreshPaused => _batteryRefreshPaused;

  @override
  Future<void> setBatteryRefreshPaused(bool paused) async {
    await _execute(
      OronBoxCommand(
        method: 'debug.batterySync.set',
        params: {'paused': paused},
      ),
    );
    _batteryRefreshPaused = paused;
  }

  @override
  Future<void> refreshBattery() async {
    await _executeState('device.refresh.battery');
  }

  @override
  Future<void> syncTime() async {
    await _execute(const OronBoxCommand(method: 'device.sync.time'));
  }

  @override
  Future<void> syncDevice() {
    final deviceId = state.currentDevice?.addr;
    return runExclusiveDeviceSync(() async {
      await _executeState('device.sync');
      await recordSuccessfulDeviceSync(deviceId);
    });
  }

  @override
  Future<void> refreshDeviceData() async {
    await _executeState('device.refresh.all');
  }

  @override
  Future<void> setFindingZeppOsDevice(bool finding) async {
    await _execute(
      OronBoxCommand(
        method: 'device.zeppos.find',
        params: {'finding': finding},
      ),
    );
  }

  @override
  Future<void> setFindingXiaomiPhone(bool finding) async {
    await _execute(
      OronBoxCommand(
        method: 'device.xiaomi.findPhone',
        params: {'finding': finding},
      ),
    );
    if (!finding) await PhoneFinder.setFinding(false);
  }

  @override
  Future<void> setFindingXiaomiWearable(bool finding) async {
    await _execute(
      OronBoxCommand(
        method: 'device.xiaomi.findWearable',
        params: {'finding': finding},
      ),
    );
  }

  @override
  Future<void> sendXiaoAiReply(String text) async {
    await _execute(
      OronBoxCommand(
        method: 'device.zeppos.xiaoai.reply',
        params: {'text': text},
      ),
    );
  }

  @override
  Future<void> setXiaoAiContinuousCapture(bool enabled) async {
    await _execute(
      OronBoxCommand(
        method: 'device.zeppos.xiaoai.continuous',
        params: {'enabled': enabled},
      ),
    );
  }

  @override
  Future<void> setXiaoAiEndpoint(int endpoint) async {
    await _execute(
      OronBoxCommand(
        method: 'device.zeppos.xiaoai.endpoint',
        params: {'endpoint': endpoint},
      ),
    );
  }

  @override
  Future<void> fetchSystemInfo() async {
    await _executeState('device.refresh.system');
  }

  @override
  Future<void> fetchStorageInfo() async {
    await _executeState('device.refresh.storage');
  }

  @override
  Future<void> fetchApps() async {
    await _execute(const OronBoxCommand(method: 'app.list'));
    await _refreshSnapshot();
  }

  @override
  Future<List<AppInfo>> loadXiaomiAppOrder() async {
    final result = await _execute(
      const OronBoxCommand(method: 'device.xiaomi.appOrder.list'),
    );
    return (result.value as List)
        .whereType<Map>()
        .map(
          (row) => AppInfo(
            packageName: row['packageName']?.toString() ?? '',
            appName: row['name']?.toString() ?? '',
            versionCode: (row['versionCode'] as num?)?.toInt() ?? 0,
            canRemove: row['canRemove'] as bool? ?? false,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> setXiaomiAppOrder(List<AppInfo> apps) async {
    await _execute(
      OronBoxCommand(
        method: 'device.xiaomi.appOrder.set',
        params: {
          'apps': apps
              .map(
                (app) => {
                  'packageName': app.packageName,
                  'name': app.appName,
                  'versionCode': app.versionCode,
                  'canRemove': app.canRemove,
                },
              )
              .toList(growable: false),
        },
      ),
    );
  }

  @override
  Future<List<XiaomiAlarm>> loadXiaomiAlarms() async {
    final result = await _execute(
      const OronBoxCommand(method: 'device.xiaomi.alarm.list'),
    );
    return (result.value as List)
        .whereType<Map>()
        .map((row) => XiaomiAlarm.fromJson(row.cast<String, Object?>()))
        .toList(growable: false);
  }

  @override
  Future<void> addXiaomiAlarm(XiaomiAlarm alarm) => _execute(
    OronBoxCommand(method: 'device.xiaomi.alarm.add', params: alarm.toJson()),
  );

  @override
  Future<void> updateXiaomiAlarm(XiaomiAlarm alarm) => _execute(
    OronBoxCommand(
      method: 'device.xiaomi.alarm.update',
      params: alarm.toJson(),
    ),
  );

  @override
  Future<void> removeXiaomiAlarm(int id) => _execute(
    OronBoxCommand(method: 'device.xiaomi.alarm.remove', params: {'id': id}),
  );

  @override
  Future<void> setXiaomiAlarmEnabled(int id, bool enabled) => _execute(
    OronBoxCommand(
      method: 'device.xiaomi.alarm.enable',
      params: {'id': id, 'enabled': enabled},
    ),
  );

  @override
  Future<void> syncXiaomiWeather(XiaomiWeatherData weather) => _execute(
    OronBoxCommand(
      method: 'device.xiaomi.weather.sync',
      params: weather.toJson(),
    ),
  );

  @override
  Future<void> fetchWatchfaces() async {
    await _execute(const OronBoxCommand(method: 'watchface.list'));
    await _refreshSnapshot();
  }

  @override
  Future<void> openApp(AppInfo app, {String page = ''}) async {
    await _execute(
      OronBoxCommand(
        method: 'app.launch',
        params: {'package': app.packageName, if (page.isNotEmpty) 'page': page},
      ),
    );
  }

  @override
  Future<void> sendInterconnectMessage(
    String packageName,
    Uint8List payload,
  ) async {
    await _execute(
      OronBoxCommand(
        method: 'device.interconnect.send',
        params: {
          'package': packageName,
          'payload': payload.toList(growable: false),
        },
      ),
    );
  }

  @override
  Future<void> sendRaw(Uint8List payload) async {
    await _execute(
      OronBoxCommand(
        method: 'device.raw.send',
        params: {'payload': payload.toList(growable: false)},
      ),
    );
  }

  @override
  Future<Uint8List> requestRaw(
    Uint8List payload, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final value = await _execute(
      OronBoxCommand(
        method: 'device.raw.request',
        params: {
          'payload': payload.toList(growable: false),
          'timeoutMs': timeout.inMilliseconds,
        },
      ),
    );
    return Uint8List.fromList(
      (value as List)
          .whereType<num>()
          .map((byte) => byte.toInt() & 0xff)
          .toList(growable: false),
    );
  }

  @override
  Future<Uint8List> requestZeppOsScreenshot() async {
    final result = await _execute(
      const OronBoxCommand(method: 'device.zeppos.screenshot'),
    );
    return Uint8List.fromList(
      (result.value as List).map((value) => (value as num).toInt()).toList(),
    );
  }

  @override
  Future<List<ZeppOsVoiceMemo>> downloadZeppOsVoiceMemos({
    void Function(int completed, int total)? onProgress,
  }) async {
    final result = await _execute(
      const OronBoxCommand(method: 'device.zeppos.voice_memos.download'),
    );
    final rows = (result.value as List).cast<Map>();
    final memos = rows
        .map(
          (row) => ZeppOsVoiceMemo(
            filename: row['filename'].toString(),
            size: (row['size'] as num).toInt(),
            durationMs: (row['durationMs'] as num).toInt(),
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              (row['timestamp'] as num).toInt(),
            ),
            bytes: Uint8List.fromList(
              (row['bytes'] as List)
                  .map((value) => (value as num).toInt())
                  .toList(),
            ),
          ),
        )
        .toList(growable: false);
    onProgress?.call(memos.length, memos.length);
    return memos;
  }

  @override
  Future<void> uploadZeppOsMap(
    Uint8List bytes, {
    required String fileName,
    void Function(double progress)? onProgress,
  }) => _installBytes(bytes, 'map', 'zip', onProgress);

  @override
  Future<void> uploadZeppOsMusic(
    Uint8List bytes, {
    required String fileName,
    required String title,
    required String artist,
    void Function(double progress)? onProgress,
  }) => _installBytes(
    bytes,
    'music',
    'mp3',
    onProgress,
    extraParams: {'fileName': fileName, 'title': title, 'artist': artist},
  );

  @override
  Future<void> uploadXiaomiMusic(
    Uint8List bytes, {
    required String title,
    required String artist,
    void Function(double progress)? onProgress,
  }) async {
    StreamSubscription<CommandEvent>? progressSubscription;
    try {
      progressSubscription = ref.read(applicationHostProvider).events.listen((
        event,
      ) {
        if (event.event != 'progress') return;
        final value = event.data['progress'];
        if (value is num) onProgress?.call(value.toDouble());
      });
      await _execute(
        OronBoxCommand(
          method: 'device.xiaomi.music.upload',
          params: {
            'bytes': bytes.toList(growable: false),
            'title': title,
            'artist': artist,
          },
        ),
      );
      onProgress?.call(1);
    } finally {
      await progressSubscription?.cancel();
    }
  }

  @override
  Future<DeviceMusicLibrary> loadXiaomiMusicLibrary() async {
    final result = await _execute(
      const OronBoxCommand(method: 'device.xiaomi.music.library'),
    );
    return DeviceMusicLibrary.fromJson((result.value as Map).cast());
  }

  @override
  Future<XiaomiHealthData> loadXiaomiHealthData() async {
    final result = await _execute(
      const OronBoxCommand(method: 'device.xiaomi.health.data'),
    );
    return XiaomiHealthData.fromJson((result.value as Map).cast());
  }

  @override
  Future<XiaomiHealthSyncResult> syncXiaomiHealth() async {
    final result = await _execute(
      const OronBoxCommand(method: 'device.xiaomi.health.sync'),
    );
    return XiaomiHealthSyncResult.fromJson((result.value as Map).cast());
  }

  @override
  Future<XiaomiHealthData> replayXiaomiHealthSnapshot(
    String deviceId,
    List<XiaomiActivityRawFile> files,
  ) async {
    final result = await _execute(
      OronBoxCommand(
        method: 'device.xiaomi.health.snapshot.replay',
        params: {
          'deviceId': deviceId,
          'files': files
              .map((file) => {'id': file.id, 'data': base64Encode(file.data)})
              .toList(growable: false),
        },
      ),
    );
    return XiaomiHealthData.fromJson((result.value as Map).cast());
  }

  @override
  Future<pb_system.AppLayout> loadXiaomiAppLayout() async {
    final result = await _execute(
      const OronBoxCommand(method: 'device.xiaomi.appLayout.get'),
    );
    final value = (result.value as Map).cast<String, Object?>();
    return pb_system.AppLayout(
      layout: pb_system.AppLayout_Layout.valueOf(
        (value['layout'] as num?)?.toInt() ?? 0,
      ),
      supportLayouts: (value['supportLayouts'] as num?)?.toInt(),
    );
  }

  @override
  Future<void> setXiaomiAppLayout(pb_system.AppLayout_Layout layout) async {
    await _execute(
      OronBoxCommand(
        method: 'device.xiaomi.appLayout.set',
        params: {'layout': layout.value},
      ),
    );
  }

  Future<void> _musicCommand(String method, Map<String, Object?> params) async {
    await _execute(OronBoxCommand(method: method, params: params));
  }

  @override
  Future<void> createXiaomiMusicPlaylist(String name) =>
      _musicCommand('device.xiaomi.music.playlist.create', {'name': name});

  @override
  Future<void> renameXiaomiMusicPlaylist(int id, String name) => _musicCommand(
    'device.xiaomi.music.playlist.rename',
    {'id': id, 'name': name},
  );

  @override
  Future<void> removeXiaomiMusicPlaylist(int id) =>
      _musicCommand('device.xiaomi.music.playlist.remove', {'id': id});

  @override
  Future<void> removeXiaomiMusicSong(List<int> id) =>
      _musicCommand('device.xiaomi.music.song.remove', {'id': id});

  @override
  Future<void> setXiaomiMusicSongInPlaylist({
    required int playlistId,
    required List<int> songId,
    required bool included,
  }) => _musicCommand('device.xiaomi.music.song.playlist.set', {
    'playlistId': playlistId,
    'songId': songId,
    'included': included,
  });

  @override
  Future<List<DeviceRecording>> downloadXiaomiRecordings({
    void Function(int completed, int total, String fileName)? onProgress,
    void Function(DeviceRecordingPullProgress progress)? onDetailedProgress,
  }) async {
    StreamSubscription<CommandEvent>? subscription;
    try {
      subscription = ref.read(applicationHostProvider).events.listen((event) {
        if (event.event != 'progress') return;
        final completed = event.data['completed'];
        final total = event.data['total'];
        if (completed is num && total is num) {
          onProgress?.call(
            completed.toInt(),
            total.toInt(),
            event.data['fileName']?.toString() ?? '',
          );
        }
        final currentIndex = event.data['currentIndex'];
        final totalFiles = event.data['totalFiles'];
        final progress = event.data['progress'];
        if (currentIndex is num && totalFiles is num && progress is num) {
          onDetailedProgress?.call(
            DeviceRecordingPullProgress(
              progress: progress.toDouble().clamp(0, 1),
              currentIndex: currentIndex.toInt(),
              totalFiles: totalFiles.toInt(),
              fileName: event.data['fileName']?.toString() ?? '',
              currentPart: (event.data['currentPart'] as num?)?.toInt() ?? 0,
              totalParts: (event.data['totalParts'] as num?)?.toInt() ?? 0,
              bytesDone: (event.data['bytesDone'] as num?)?.toInt(),
              bytesTotal: (event.data['bytesTotal'] as num?)?.toInt(),
            ),
          );
        }
      });
      final result = await _execute(
        const OronBoxCommand(method: 'device.xiaomi.recordings.download'),
      );
      return (result.value as List)
          .map((row) => DeviceRecording.fromJson((row as Map).cast()))
          .toList(growable: false);
    } finally {
      await subscription?.cancel();
    }
  }

  @override
  Future<void> cancelRecordingSync() async {
    await _execute(const OronBoxCommand(method: 'device.recordings.cancel'));
  }

  @override
  Future<DeviceLogPullResult> pullDeviceLogs({
    void Function(double progress, String fileName)? onProgress,
    void Function(DeviceLogPullProgress progress)? onDetailedProgress,
    void Function(String stage)? onStage,
  }) async {
    // Device log progress is emitted by the daemon while the long-running
    // command is active.  Forward it just like recording synchronization so
    // the GUI does not remain at an indeterminate 0% state when using the
    // split frontend/daemon runtime.
    final subscription = ref.read(applicationHostProvider).events.listen((
      event,
    ) {
      if (event.event != 'device.log.progress') return;
      final stage = event.data['stage']?.toString();
      if (stage != null) onStage?.call(stage);
      final progress = (event.data['progress'] as num?)?.toDouble();
      if (progress == null) return;
      onProgress?.call(
        progress.clamp(0, 1),
        event.data['fileName']?.toString() ?? '',
      );
      onDetailedProgress?.call(
        DeviceLogPullProgress(
          progress: progress.clamp(0, 1).toDouble(),
          fileName: event.data['fileName']?.toString() ?? '',
          channel: (event.data['channel'] as num?)?.toInt() ?? 0,
          currentPart: (event.data['currentPart'] as num?)?.toInt() ?? 0,
          totalParts: (event.data['totalParts'] as num?)?.toInt() ?? 0,
        ),
      );
    });
    try {
      final result = await _execute(
        const OronBoxCommand(method: 'device.logs.pull'),
      );
      final value = (result.value as Map).cast<String, Object?>();
      return DeviceLogPullResult(
        fileName: value['name']?.toString() ?? '',
        data: Uint8List.fromList(
          (value['bytes'] as List? ?? const [])
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false),
        ),
        currentLog: value['currentLogBytes'] is List
            ? Uint8List.fromList(
                (value['currentLogBytes'] as List)
                    .whereType<num>()
                    .map((value) => value.toInt())
                    .toList(growable: false),
              )
            : null,
      );
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> cancelDeviceLogPull() async {
    await _execute(const OronBoxCommand(method: 'device.logs.cancel'));
  }

  @override
  Future<List<int>> listZeppOsAppSides() async {
    final result = await _execute(
      const OronBoxCommand(method: 'device.zeppos.appside.list'),
    );
    return (result.value as List)
        .map((value) => (value as num).toInt())
        .toList();
  }

  @override
  Future<List<int>> observedZeppOsAppSideIds() async {
    final result = await _execute(
      const OronBoxCommand(method: 'device.zeppos.appside.observed'),
    );
    return (result.value as List)
        .map((value) => (value as num).toInt())
        .toList();
  }

  @override
  Future<List<ZeppOsAppSideSessionInfo>> zeppOsAppSideSessions() async {
    final result = await _execute(
      const OronBoxCommand(method: 'device.zeppos.appside.sessions'),
    );
    return (result.value as List)
        .whereType<Map>()
        .map((raw) {
          final value = raw.cast<String, Object?>();
          return ZeppOsAppSideSessionInfo(
            appId: (value['appId'] as num).toInt(),
            version: (value['version'] as num).toInt(),
            port1: (value['port1'] as num).toInt(),
            port2: (value['port2'] as num).toInt(),
            extra: (value['extra'] as num).toInt(),
            watchSessionOpen: value['watchSessionOpen'] == true,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<ZeppOsAppSideDebugEvent>> zeppOsAppSideEvents(int appId) async {
    final result = await _execute(
      OronBoxCommand(
        method: 'device.zeppos.appside.events',
        params: {'appId': appId},
      ),
    );
    return (result.value as List)
        .whereType<Map>()
        .map((raw) {
          final value = raw.cast<String, Object?>();
          final payload = value['payload'];
          return ZeppOsAppSideDebugEvent(
            timestamp: DateTime.parse(value['timestamp'].toString()),
            type: value['type'].toString(),
            message: value['message'].toString(),
            direction: value['direction']?.toString(),
            source: value['source']?.toString(),
            payload: payload is List
                ? Uint8List.fromList(
                    payload
                        .whereType<num>()
                        .map((byte) => byte.toInt())
                        .toList(),
                  )
                : null,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> clearZeppOsAppSideEvents(int appId) => _execute(
    OronBoxCommand(
      method: 'device.zeppos.appside.events.clear',
      params: {'appId': appId},
    ),
  );

  @override
  Future<void> startZeppOsAppSide(int appId) => _execute(
    OronBoxCommand(
      method: 'device.zeppos.appside.start',
      params: {'appId': appId},
    ),
  );

  @override
  Future<void> stopZeppOsAppSide(int appId) => _execute(
    OronBoxCommand(
      method: 'device.zeppos.appside.stop',
      params: {'appId': appId},
    ),
  );

  @override
  Future<void> injectZeppOsAppSideMessage(int appId, Uint8List payload) =>
      _execute(
        OronBoxCommand(
          method: 'device.zeppos.appside.inject',
          params: {'appId': appId, 'payload': payload.toList()},
        ),
      );

  @override
  Future<void> sendZeppOsAppSideMessage(int appId, Uint8List payload) =>
      _execute(
        OronBoxCommand(
          method: 'device.zeppos.appside.send',
          params: {'appId': appId, 'payload': payload.toList()},
        ),
      );

  @override
  Future<void> attachZeppOsZml(int appId, ZeppOsZmlHookHandler hookHandler) {
    _zmlHandlers[appId] = hookHandler;
    return _attachZmlOnHost(appId).onError((error, stackTrace) {
      _zmlHandlers.remove(appId);
      throw error!;
    });
  }

  Future<void> _attachZmlOnHost(int appId) async {
    await _execute(
      OronBoxCommand(
        method: 'device.zeppos.zml.attach',
        params: {'appId': appId},
      ),
    );
  }

  @override
  Future<Object?> invokeZeppOsZml(
    int appId,
    String method,
    List<Object?> arguments,
  ) async {
    final result = await _execute(
      OronBoxCommand(
        method: 'device.zeppos.zml.invoke',
        params: {'appId': appId, 'method': method, 'arguments': arguments},
      ),
    );
    return result.value;
  }

  @override
  Future<void> uninstallApp(AppInfo app) async {
    await _execute(
      OronBoxCommand(
        method: 'app.uninstall',
        params: {'package': app.packageName},
      ),
    );
    await _refreshSnapshot();
  }

  @override
  Future<void> uninstallWatchface(WatchfaceInfo watchface) async {
    await _execute(
      OronBoxCommand(method: 'watchface.remove', params: {'id': watchface.id}),
    );
    await _refreshSnapshot();
  }

  @override
  Future<void> setWatchface(WatchfaceInfo watchface) async {
    await _execute(
      OronBoxCommand(method: 'watchface.set', params: {'id': watchface.id}),
    );
    await _refreshSnapshot();
  }

  Future<void> _installBytes(
    Uint8List bytes,
    String type,
    String extension,
    void Function(double progress)? onProgress, {
    Map<String, Object?> extraParams = const {},
  }) async {
    if (kIsWeb) {
      final operationId = DateTime.now().microsecondsSinceEpoch.toString();
      StreamSubscription<CommandEvent>? progressSubscription;
      try {
        progressSubscription = ref.read(applicationHostProvider).events.listen((
          event,
        ) {
          if (event.event != 'progress' ||
              event.data['operationId']?.toString() != operationId) {
            return;
          }
          final value = event.data['progress'];
          if (value is num) onProgress?.call(value.toDouble());
        });
        await _execute(
          OronBoxCommand(
            method: 'install.local',
            params: {
              'type': type,
              'payloadMode': 'memory',
              'bytes': bytes,
              'fileName': 'oronbox_web.$extension',
              'operationId': operationId,
              ...extraParams,
            },
          ),
        );
        await _refreshSnapshot();
      } finally {
        await progressSubscription?.cancel();
      }
      return;
    }

    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/oronbox_gui_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    StreamSubscription<CommandEvent>? progressSubscription;
    try {
      final queued = await _execute(
        OronBoxCommand(
          method: 'task.enqueue',
          params: {
            'command': OronBoxCommand(
              method: 'install.local',
              params: {
                'type': type,
                'path': file.path,
                'deleteAfter': true,
                ...extraParams,
              },
            ).toJson(),
          },
        ),
      );
      final taskId = (queued.value as Map)['taskId']?.toString();
      if (taskId == null) throw StateError('Daemon did not return a task ID');
      progressSubscription = ref.read(applicationHostProvider).events.listen((
        event,
      ) {
        if (event.event != 'task' || event.data['id']?.toString() != taskId) {
          return;
        }
        final value = event.data['progress'];
        if (value is num) onProgress?.call(value.toDouble());
      });
      final completed = await _execute(
        OronBoxCommand(method: 'queue.wait', params: {'id': taskId}),
      );
      final task = (completed.value as Map).cast<String, Object?>();
      final nested = task['result'];
      if (nested is Map) {
        final result = CommandResult.fromJson(nested.cast<String, Object?>());
        if (!result.ok) {
          throw result.error!;
        }
      }
      await _refreshSnapshot();
    } finally {
      await progressSubscription?.cancel();
    }
  }

  @override
  Future<void> installApp(
    Uint8List packageBytes, {
    required String packageName,
    void Function(double progress)? onProgress,
    void Function()? onAppSideMissing,
  }) => _installBytes(packageBytes, 'quickapp', 'rpk', onProgress);

  @override
  Future<void> installWatchface(
    Uint8List watchfaceBytes, {
    required String watchfaceId,
    void Function(double progress)? onProgress,
  }) => _installBytes(watchfaceBytes, 'watchface', 'bin', onProgress);

  @override
  Future<void> installFirmware(
    Uint8List firmwareBytes, {
    void Function(double progress)? onProgress,
  }) => _installBytes(firmwareBytes, 'firmware', 'bin', onProgress);

  @override
  Future<void> importSharedDevice(MiWearState device) async {
    await _execute(
      OronBoxCommand(
        method: 'device.import',
        params: {'device': device.toJson()},
      ),
    );
    await _refreshSnapshot();
  }

  @override
  Future<int> importMiCloudDevices(List<MiCloudDevice> devices) async {
    var imported = 0;
    for (final device in devices) {
      final address = resolveMiCloudDeviceAddress(
        device,
        state.pairedDevices.map((item) => item.addr),
      );
      if (address == null) continue;
      await importSharedDevice(
        MiWearState(
          name: device.name.trim().isEmpty ? device.model : device.name.trim(),
          addr: address,
          connectType: ConnectType.spp.name,
          authkey: device.authKey.trim(),
          disconnected: true,
        ),
      );
      imported += 1;
    }
    return imported;
  }

  @override
  Set<String> get connectedAddresses {
    return state.pairedDevices
        .where((device) => !device.disconnected)
        .map((device) => device.addr)
        .toSet();
  }
}
