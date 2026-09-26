import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:oronbox/src/core/logging/logging_service.dart';
import 'package:oronbox/src/core/models/bt_models.dart' as models;
import 'package:oronbox/src/core/models/xiaomi_health_models.dart';
import 'package:oronbox/src/device/core/event_bus.dart';
import 'package:oronbox/src/device/xiaomi/system/xiaomi_system.dart';
import 'package:oronbox/src/protocols/generated/xiaomi/wear.pb.dart' as pb;
import 'package:oronbox/src/protocols/generated/xiaomi/wear_fitness.pb.dart'
    as pb_fitness;
import 'package:oronbox/src/protocols/generated/xiaomi/wear_system.pb.dart'
    as pb_system;
import 'package:oronbox/src/protocols/common/device_protocol.dart';
import 'package:oronbox/src/protocols/xiaomi/packet/l2_packet.dart';

/// A single activity file that could not be completely synchronized.
///
/// A failed file must not discard the other files returned by the wearable.
/// The error is kept as text so callers can log or present it without making
/// the protocol exception types part of the health model API.
class XiaomiActivityFileFailure {
  const XiaomiActivityFileFailure({
    required this.id,
    required this.attempts,
    required this.error,
  });

  final String id;
  final int attempts;
  final String error;
}

/// A CRC-validated activity file returned by the wearable.
///
/// Keeping the file id together with the bytes makes diagnostics useful even
/// when the current parser does not recognize the file type yet.
class XiaomiActivityRawFile {
  const XiaomiActivityRawFile({required this.id, required this.data});

  final String id;
  final Uint8List data;
}

class XiaomiActivityFileSyncResult {
  const XiaomiActivityFileSyncResult({
    required this.daily,
    required this.samples,
    required this.sleep,
    required this.workouts,
    required this.filesReceived,
    this.abnormalHealthRecords = const [],
    this.rawFiles = const [],
    this.failedFiles = const [],
    this.filesSkipped = 0,
  });

  final List<XiaomiActivityDailyRecord> daily;
  final List<XiaomiActivitySampleRecord> samples;
  final List<XiaomiActivitySleepRecord> sleep;
  final List<XiaomiActivityWorkoutRecord> workouts;
  final List<XiaomiActivityAbnormalHealthRecord> abnormalHealthRecords;
  final List<XiaomiActivityRawFile> rawFiles;
  final int filesReceived;

  /// Files for which all transfer attempts or the final acknowledgement
  /// failed. Other files in the same sync are still usable.
  final List<XiaomiActivityFileFailure> failedFiles;

  /// Empty/placeholder files advertised by the device and intentionally
  /// ignored because they contain no health payload.
  final int filesSkipped;
}

class XiaomiActivityDailyRecord {
  const XiaomiActivityDailyRecord({
    required this.date,
    this.steps,
    this.activeCalories,
    this.calories,
    this.restingHeartRate,
    this.minHeartRate,
    this.minHeartRateAt,
    this.maxHeartRate,
    this.maxHeartRateAt,
    this.averageHeartRate,
    this.minStress,
    this.maxStress,
    this.averageStress,
    this.standingBitmap,
    this.minBloodOxygen,
    this.maxBloodOxygen,
    this.averageBloodOxygen,
    this.currentBloodOxygen,
    this.minBloodOxygenAt,
    this.maxBloodOxygenAt,
    this.floorsClimbed,
    this.remainingRecoveryHours,
    this.trainingLoadToday,
    this.trainingLoadLast7Days,
    this.trainingLoadLevel,
    this.vitalityIncreaseLight,
    this.vitalityIncreaseModerate,
    this.vitalityIncreaseHigh,
    this.vitalityCurrent,
    this.vitalityLast7Days,
    this.vitalityNextTargetType,
    this.vitalityNextTargetMinutes,
    this.fitnessBalance,
    this.fitnessLevel,
    this.fatigueLevel,
    this.trainingStressScore,
  });

  final DateTime date;
  final int? steps;
  final int? activeCalories;
  final int? calories;
  final int? restingHeartRate;
  final int? minHeartRate;
  final DateTime? minHeartRateAt;
  final int? maxHeartRate;
  final DateTime? maxHeartRateAt;
  final int? averageHeartRate;
  final int? minStress;
  final int? maxStress;
  final int? averageStress;
  final int? standingBitmap;
  final int? minBloodOxygen;
  final int? maxBloodOxygen;
  final int? averageBloodOxygen;
  final int? currentBloodOxygen;
  final DateTime? minBloodOxygenAt;
  final DateTime? maxBloodOxygenAt;
  final int? floorsClimbed;
  final int? remainingRecoveryHours;
  final int? trainingLoadToday;
  final int? trainingLoadLast7Days;
  final int? trainingLoadLevel;
  final int? vitalityIncreaseLight;
  final int? vitalityIncreaseModerate;
  final int? vitalityIncreaseHigh;
  final int? vitalityCurrent;
  final int? vitalityLast7Days;
  final int? vitalityNextTargetType;
  final int? vitalityNextTargetMinutes;
  final int? fitnessBalance;
  final int? fitnessLevel;
  final int? fatigueLevel;
  final int? trainingStressScore;
}

class XiaomiActivitySampleRecord {
  const XiaomiActivitySampleRecord({
    required this.timestamp,
    this.activityType,
    this.activityStrength,
    this.sportType,
    this.steps,
    this.activeCalories,
    this.distanceMeters,
    this.heartRate,
    this.energy,
    this.caloriesDelta,
    this.energyStatus,
    this.energyStatusValue,
    this.bloodOxygen,
    this.pressure,
    this.lightSensation,
    this.volumeMomentum,
    this.floors,
    this.stress,
  });

  final DateTime timestamp;
  final int? activityType;
  final int? activityStrength;
  final int? sportType;
  final int? steps;
  final int? activeCalories;
  final int? distanceMeters;
  final int? heartRate;
  final int? energy;

  /// Per-record increment from `daily_activity/record`, not the daily total.
  /// The daily total lives in the separate `daily_activity/report` file.
  final int? caloriesDelta;
  final int? energyStatus;
  final int? energyStatusValue;
  final int? bloodOxygen;
  final int? pressure;
  final int? lightSensation;
  final int? volumeMomentum;
  final int? floors;
  final int? stress;
}

enum XiaomiActivityAbnormalHealthKind {
  highHeartRate,
  lowHeartRate,
  lowBloodOxygen,
  highStress,
  irregularHeartbeat,
}

/// One event from the Vela daily-type-9 abnormal-health file.
///
/// Mi Fitness maps types 1/2/3/4 to high/low heart rate, low blood oxygen,
/// and high stress. Type 5 is the separate heart-health irregular-heartbeat
/// (ABNORMAL_FIB) event and has no sample value or configured threshold.
class XiaomiActivityAbnormalHealthRecord {
  const XiaomiActivityAbnormalHealthRecord({
    required this.timestamp,
    required this.kind,
    this.value,
    this.threshold,
    this.startedAt,
    this.endedAt,
  });

  final DateTime timestamp;
  final XiaomiActivityAbnormalHealthKind kind;
  final int? value;
  final int? threshold;
  final DateTime? startedAt;
  final DateTime? endedAt;
}

/// Compatibility view for callers that only consume high/low heart-rate
/// alerts. New code should use [XiaomiActivityAbnormalHealthRecord].
enum XiaomiActivityAbnormalHeartRateKind { high, low }

/// One sample from the Vela daily-type-9 abnormal-health file.
///
/// The file contains a segment header (start/end, type, configured threshold)
/// followed by timestamp/value pairs. Keeping the segment bounds here makes it
/// possible to reproduce Mi Fitness' event list without treating every value
/// as an independently detected event.
class XiaomiActivityAbnormalHeartRateRecord {
  const XiaomiActivityAbnormalHeartRateRecord({
    required this.timestamp,
    required this.value,
    required this.kind,
    required this.threshold,
    this.startedAt,
    this.endedAt,
  });

  final DateTime timestamp;
  final int value;
  final XiaomiActivityAbnormalHeartRateKind kind;
  final int threshold;
  final DateTime? startedAt;
  final DateTime? endedAt;
}

class XiaomiActivitySleepRecord {
  const XiaomiActivitySleepRecord({
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    this.averageHeartRate,
    this.averageBloodOxygen,
    this.minimumHeartRate,
    this.maximumHeartRate,
    this.minimumBloodOxygen,
    this.maximumBloodOxygen,
    this.quality,
    this.sleepEfficiency,
    this.bedDurationSeconds,
    this.goBedAt,
    this.leaveBedAt,
    this.awakeDurationSeconds,
    this.lightSleepDurationSeconds,
    this.deepSleepDurationSeconds,
    this.remSleepDurationSeconds,
    this.averageHrv,
    this.hrvMin,
    this.hrvMax,
    this.hrvBaselineMin,
    this.hrvBaselineMax,
    this.hrvStandardDeviation,
    this.hrvMedian,
    this.hrvLowerQuantile,
    this.hrvMiddleQuantile,
    this.hrvUpperQuantile,
    this.hrvTimestamp,
    this.sleepIndex,
    this.wakeCount,
    this.hasRem,
    this.hasStage,
    this.sleepScoreVersion,
    this.hrvPoints = const [],
    this.heartRatePoints = const [],
    this.bloodOxygenPoints = const [],
    this.stages = const [],
  });

  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;
  final int? averageHeartRate;
  final int? averageBloodOxygen;
  final int? minimumHeartRate;
  final int? maximumHeartRate;
  final int? minimumBloodOxygen;
  final int? maximumBloodOxygen;
  final int? quality;
  final int? sleepEfficiency;
  final int? bedDurationSeconds;
  final DateTime? goBedAt;
  final DateTime? leaveBedAt;
  final int? awakeDurationSeconds;
  final int? lightSleepDurationSeconds;
  final int? deepSleepDurationSeconds;
  final int? remSleepDurationSeconds;
  final int? averageHrv;
  final int? hrvMin;
  final int? hrvMax;
  final int? hrvBaselineMin;
  final int? hrvBaselineMax;
  final int? hrvStandardDeviation;
  final int? hrvMedian;
  final int? hrvLowerQuantile;
  final int? hrvMiddleQuantile;
  final int? hrvUpperQuantile;
  final DateTime? hrvTimestamp;

  /// The device-provided sleep summary index.  Mi Fitness prefers index 1 as
  /// the main night when a report contains more than one sleep segment.
  final int? sleepIndex;
  final int? wakeCount;
  final bool? hasRem;
  final bool? hasStage;
  final int? sleepScoreVersion;
  final List<XiaomiActivitySleepHrvPoint> hrvPoints;
  final List<XiaomiActivitySleepVitalPoint> heartRatePoints;
  final List<XiaomiActivitySleepVitalPoint> bloodOxygenPoints;
  final List<XiaomiActivitySleepStageRecord> stages;

  XiaomiActivitySleepRecord copyWith({
    DateTime? startedAt,
    DateTime? endedAt,
    int? durationSeconds,
    int? averageHeartRate,
    int? averageBloodOxygen,
    int? minimumHeartRate,
    int? maximumHeartRate,
    int? minimumBloodOxygen,
    int? maximumBloodOxygen,
    int? quality,
    int? sleepEfficiency,
    int? bedDurationSeconds,
    DateTime? goBedAt,
    DateTime? leaveBedAt,
    int? awakeDurationSeconds,
    int? lightSleepDurationSeconds,
    int? deepSleepDurationSeconds,
    int? remSleepDurationSeconds,
    int? averageHrv,
    int? hrvMin,
    int? hrvMax,
    int? hrvBaselineMin,
    int? hrvBaselineMax,
    int? hrvStandardDeviation,
    int? hrvMedian,
    int? hrvLowerQuantile,
    int? hrvMiddleQuantile,
    int? hrvUpperQuantile,
    DateTime? hrvTimestamp,
    int? sleepIndex,
    int? wakeCount,
    bool? hasRem,
    bool? hasStage,
    int? sleepScoreVersion,
    List<XiaomiActivitySleepHrvPoint>? hrvPoints,
    List<XiaomiActivitySleepVitalPoint>? heartRatePoints,
    List<XiaomiActivitySleepVitalPoint>? bloodOxygenPoints,
    List<XiaomiActivitySleepStageRecord>? stages,
  }) => XiaomiActivitySleepRecord(
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    averageHeartRate: averageHeartRate ?? this.averageHeartRate,
    averageBloodOxygen: averageBloodOxygen ?? this.averageBloodOxygen,
    minimumHeartRate: minimumHeartRate ?? this.minimumHeartRate,
    maximumHeartRate: maximumHeartRate ?? this.maximumHeartRate,
    minimumBloodOxygen: minimumBloodOxygen ?? this.minimumBloodOxygen,
    maximumBloodOxygen: maximumBloodOxygen ?? this.maximumBloodOxygen,
    quality: quality ?? this.quality,
    sleepEfficiency: sleepEfficiency ?? this.sleepEfficiency,
    bedDurationSeconds: bedDurationSeconds ?? this.bedDurationSeconds,
    goBedAt: goBedAt ?? this.goBedAt,
    leaveBedAt: leaveBedAt ?? this.leaveBedAt,
    awakeDurationSeconds: awakeDurationSeconds ?? this.awakeDurationSeconds,
    lightSleepDurationSeconds:
        lightSleepDurationSeconds ?? this.lightSleepDurationSeconds,
    deepSleepDurationSeconds:
        deepSleepDurationSeconds ?? this.deepSleepDurationSeconds,
    remSleepDurationSeconds:
        remSleepDurationSeconds ?? this.remSleepDurationSeconds,
    averageHrv: averageHrv ?? this.averageHrv,
    hrvMin: hrvMin ?? this.hrvMin,
    hrvMax: hrvMax ?? this.hrvMax,
    hrvBaselineMin: hrvBaselineMin ?? this.hrvBaselineMin,
    hrvBaselineMax: hrvBaselineMax ?? this.hrvBaselineMax,
    hrvStandardDeviation: hrvStandardDeviation ?? this.hrvStandardDeviation,
    hrvMedian: hrvMedian ?? this.hrvMedian,
    hrvLowerQuantile: hrvLowerQuantile ?? this.hrvLowerQuantile,
    hrvMiddleQuantile: hrvMiddleQuantile ?? this.hrvMiddleQuantile,
    hrvUpperQuantile: hrvUpperQuantile ?? this.hrvUpperQuantile,
    hrvTimestamp: hrvTimestamp ?? this.hrvTimestamp,
    sleepIndex: sleepIndex ?? this.sleepIndex,
    wakeCount: wakeCount ?? this.wakeCount,
    hasRem: hasRem ?? this.hasRem,
    hasStage: hasStage ?? this.hasStage,
    sleepScoreVersion: sleepScoreVersion ?? this.sleepScoreVersion,
    hrvPoints: hrvPoints ?? this.hrvPoints,
    heartRatePoints: heartRatePoints ?? this.heartRatePoints,
    bloodOxygenPoints: bloodOxygenPoints ?? this.bloodOxygenPoints,
    stages: stages ?? this.stages,
  );
}

class XiaomiActivitySleepHrvPoint {
  const XiaomiActivitySleepHrvPoint({
    required this.timestamp,
    required this.value,
  });

  final DateTime timestamp;
  final int value;
}

class XiaomiActivitySleepVitalPoint {
  const XiaomiActivitySleepVitalPoint({
    required this.timestamp,
    required this.value,
  });

  final DateTime timestamp;
  final int value;
}

class XiaomiActivitySleepStageRecord {
  const XiaomiActivitySleepStageRecord({
    required this.timestamp,
    required this.stage,
    this.endedAt,
  });

  final DateTime timestamp;

  /// Xiaomi's display-stage values: 2 deep, 3 light, 4 REM, 5 awake.
  ///
  /// The native packet decoder can also preserve 0/1 for undocumented or
  /// algorithm-only states; the UI intentionally omits those states.
  final int stage;

  /// The device's stage stream may provide the end of a stage as a duration.
  /// Older compact files only expose a start point and leave this null.
  final DateTime? endedAt;
}

class XiaomiActivityWorkoutRecord {
  const XiaomiActivityWorkoutRecord({
    required this.startedAt,
    required this.endedAt,
    required this.activityType,
    this.distanceMeters,
    this.calories,
    this.averageHeartRate,
    this.maximumHeartRate,
    this.minimumHeartRate,
    this.subSportType,
    this.totalDurationSeconds,
    this.effectiveDurationSeconds,
    this.activeCalories,
    this.averagePaceSecondsPerKilometer,
    this.bestPaceSecondsPerKilometer,
    this.worstPaceSecondsPerKilometer,
    this.averageSpeedKph,
    this.bestSpeedKph,
    this.totalSteps,
    this.averageStrideCentimeters,
    this.averageCadence,
    this.maximumCadence,
    this.averageBloodOxygen,
    this.maximumBloodOxygen,
    this.minimumBloodOxygen,
    this.averageStress,
    this.maximumStress,
    this.minimumStress,
    this.totalAscentMeters,
    this.totalDescentMeters,
    this.averageAltitudeMeters,
    this.maximumAltitudeMeters,
    this.minimumAltitudeMeters,
    this.aerobicTrainingEffect,
    this.anaerobicTrainingEffect,
    this.peakTrainingEffect,
    this.vo2Max,
    this.bodyEnergyConsumption,
    this.expectedRecoveryHours,
    this.trainingLoad,
    this.earnedVitality,
    this.heartRateZoneMethod,
    this.heartRateZones = const [],
    this.averagePowerWatts,
    this.maximumPowerWatts,
    this.totalArmPulls,
    this.mainSwimmingStroke,
    this.averageStrokeFrequency,
    this.maximumStrokeFrequency,
    this.turnCount,
    this.averageSwolf,
    this.bestSwolf,
    this.poolWidthMeters,
    this.totalJumps,
    this.averageJumpFrequency,
    this.bestJumpFrequency,
    this.tripCount,
    this.setCount,
    this.totalStrokes,
    this.averageRowingFrequency,
    this.bestRowingFrequency,
    this.samples = const [],
    this.route = const [],
    this.recovery,
  });

  final DateTime startedAt;
  final DateTime endedAt;
  final int activityType;
  final int? distanceMeters;
  final int? calories;
  final int? averageHeartRate;
  final int? maximumHeartRate;
  final int? minimumHeartRate;
  final int? subSportType;
  final int? totalDurationSeconds;
  final int? effectiveDurationSeconds;
  final int? activeCalories;
  final int? averagePaceSecondsPerKilometer;
  final int? bestPaceSecondsPerKilometer;
  final int? worstPaceSecondsPerKilometer;
  final double? averageSpeedKph;
  final double? bestSpeedKph;
  final int? totalSteps;
  final int? averageStrideCentimeters;
  final int? averageCadence;
  final int? maximumCadence;
  final int? averageBloodOxygen;
  final int? maximumBloodOxygen;
  final int? minimumBloodOxygen;
  final int? averageStress;
  final int? maximumStress;
  final int? minimumStress;
  final double? totalAscentMeters;
  final double? totalDescentMeters;
  final double? averageAltitudeMeters;
  final double? maximumAltitudeMeters;
  final double? minimumAltitudeMeters;
  final double? aerobicTrainingEffect;
  final double? anaerobicTrainingEffect;
  final double? peakTrainingEffect;
  final int? vo2Max;
  final int? bodyEnergyConsumption;
  final int? expectedRecoveryHours;
  final int? trainingLoad;
  final int? earnedVitality;
  final int? heartRateZoneMethod;
  final List<XiaomiWorkoutHeartRateZone> heartRateZones;
  final int? averagePowerWatts;
  final int? maximumPowerWatts;
  final int? totalArmPulls;
  final int? mainSwimmingStroke;
  final int? averageStrokeFrequency;
  final int? maximumStrokeFrequency;
  final int? turnCount;
  final int? averageSwolf;
  final int? bestSwolf;
  final int? poolWidthMeters;
  final int? totalJumps;
  final int? averageJumpFrequency;
  final int? bestJumpFrequency;
  final int? tripCount;
  final int? setCount;
  final int? totalStrokes;
  final int? averageRowingFrequency;
  final int? bestRowingFrequency;
  final List<XiaomiWorkoutSampleRecord> samples;
  final List<XiaomiWorkoutRoutePoint> route;
  final XiaomiWorkoutHeartRateRecovery? recovery;
}

class XiaomiWorkoutHeartRateZone {
  const XiaomiWorkoutHeartRateZone({
    required this.zone,
    required this.durationSeconds,
    this.lowerLimit,
  });

  final int zone;
  final int durationSeconds;
  final int? lowerLimit;
}

class XiaomiWorkoutSampleRecord {
  const XiaomiWorkoutSampleRecord({
    required this.timestamp,
    this.heartRate,
    this.bloodOxygen,
    this.stress,
    this.calories,
    this.steps,
    this.distanceMeters,
    this.altitudeMeters,
    this.paceSecondsPerKilometer,
    this.speedKph,
    this.cadence,
    this.powerWatts,
    this.strideCentimeters,
    this.jumpFrequency,
    this.jumpHeightCentimeters,
    this.strokeFrequency,
    this.swimmingStroke,
    this.swolf,
    this.swimmingPaceSecondsPer100Meters,
  });

  final DateTime timestamp;
  final int? heartRate;
  final int? bloodOxygen;
  final int? stress;
  final int? calories;
  final int? steps;
  final int? distanceMeters;
  final double? altitudeMeters;
  final int? paceSecondsPerKilometer;
  final double? speedKph;
  final int? cadence;
  final int? powerWatts;
  final int? strideCentimeters;
  final int? jumpFrequency;
  final int? jumpHeightCentimeters;
  final int? strokeFrequency;
  final int? swimmingStroke;
  final int? swolf;
  final int? swimmingPaceSecondsPer100Meters;
}

class XiaomiWorkoutRoutePoint {
  const XiaomiWorkoutRoutePoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
    this.speedMetersPerSecond,
    this.horizontalAccuracyMeters,
  });

  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? altitudeMeters;
  final double? speedMetersPerSecond;
  final double? horizontalAccuracyMeters;
}

class XiaomiWorkoutHeartRateRecovery {
  const XiaomiWorkoutHeartRateRecovery({
    required this.startedAt,
    this.recoveredHeartRate,
    this.recoveryRate,
    this.heartRates = const [],
  });

  final DateTime startedAt;
  final int? recoveredHeartRate;
  final int? recoveryRate;
  final List<int> heartRates;
}

/// Xiaomi's health domain, including both real-time wearable state and the
/// historical/measurement messages carried by the FITNESS packet type.
///
/// The wire protocol puts the real-time snapshot and delta reports under
/// SYSTEM (78/79), while the rest of the health data is under FITNESS.  They
/// intentionally live in one system because this is the domain exposed by
/// XMS NodeApi, not because they share a protobuf type.
class XiaomiHealthSystem extends XiaomiPbSystem {
  XiaomiHealthSystem() : _log = getLogger('XiaomiHealthSystem');

  static const _activityFileMaxAttempts = 2;
  static const _activityFileRetryDelay = Duration(milliseconds: 150);

  final Logger _log;
  final _fitnessPackets = StreamController<pb_fitness.Fitness>.broadcast();
  XiaomiHealthState _state = const XiaomiHealthState();
  Future<XiaomiActivityFileSyncResult>? _activitySyncFuture;
  Completer<Uint8List>? _activityFileCompleter;
  BytesBuilder? _activityFileBuffer;
  Timer? _activityWatchdog;
  int _activityTotalChunks = 0;
  int _activityNextChunk = 1;
  final _pendingActivityFiles = <String, Uint8List>{};
  BytesBuilder? _pendingActivityFileBuffer;
  int _pendingActivityTotalChunks = 0;
  int _pendingActivityNextChunk = 1;
  int? _activityTimezoneOffset15Min;

  XiaomiHealthState get state => _state;

  Stream<pb_fitness.Fitness> get fitnessPackets => _fitnessPackets.stream;

  @override
  Future<void> dispose() async {
    _activityWatchdog?.cancel();
    _activityWatchdog = null;
    final completer = _activityFileCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        StateError('Xiaomi health system disposed during activity transfer'),
      );
    }
    _activityFileCompleter = null;
    _activityFileBuffer = null;
    _pendingActivityFiles.clear();
    _pendingActivityFileBuffer = null;
    await _fitnessPackets.close();
    await super.dispose();
  }

  Stream<pb_fitness.BasicData> get basicDataReports => fitnessPackets
      .where((packet) => packet.hasBasicData())
      .map((packet) => packet.basicData);

  Stream<pb_fitness.VitalityData_List> get vitalityReports => fitnessPackets
      .where((packet) => packet.hasVitalityDataList())
      .map((packet) => packet.vitalityDataList);

  Stream<pb_fitness.BestSportData_List> get bestSportReports => fitnessPackets
      .where((packet) => packet.hasSportDataList())
      .map((packet) => packet.sportDataList);

  Stream<pb_fitness.PhoneSportData> get phoneSportReports => fitnessPackets
      .where((packet) => packet.hasPhoneSportData())
      .map((packet) => packet.phoneSportData);

  Stream<pb_fitness.PhoneSportDataV2A> get phoneSportReportsV2a =>
      fitnessPackets
          .where((packet) => packet.hasPhoneSportDataV2a())
          .map((packet) => packet.phoneSportDataV2a);

  Stream<pb_fitness.PhoneSportDataV2D> get phoneSportLocationReports =>
      fitnessPackets
          .where((packet) => packet.hasPhoneSportDataV2d())
          .map((packet) => packet.phoneSportDataV2d);

  Stream<pb_fitness.SleepResult> get sleepResults => fitnessPackets
      .where((packet) => packet.hasSleepResult())
      .map((packet) => packet.sleepResult);

  Stream<pb_fitness.WearSportData> get sportReports => fitnessPackets
      .where((packet) => packet.hasWearSportData())
      .map((packet) => packet.wearSportData);

  Stream<pb_fitness.WearSportDataV2A> get sportReportsV2 => fitnessPackets
      .where((packet) => packet.hasWearSportDataV2a())
      .map((packet) => packet.wearSportDataV2a);

  Stream<pb_fitness.WearSensorData> get sensorReports => fitnessPackets
      .where((packet) => packet.hasWearSensorData())
      .map((packet) => packet.wearSensorData);

  Stream<pb_fitness.ECGData> get ecgReports => fitnessPackets
      .where((packet) => packet.hasEcgData())
      .map((packet) => packet.ecgData);

  Stream<pb_fitness.ECGStatus> get ecgStatusReports => fitnessPackets
      .where((packet) => packet.hasEcgStatus())
      .map((packet) => packet.ecgStatus);

  /// Heart-rate samples emitted by the aggregate, sport, and ECG payloads.
  ///
  /// The Xiaomi protocol does not define one standalone heart-rate packet
  /// type.  Keeping the extraction here means callers do not need to know
  /// which firmware-specific FITNESS payload carried the sample.
  Stream<int> get heartRateReports => fitnessPackets.expand((packet) {
    final values = <int>[];
    if (packet.hasBasicData() && packet.basicData.hasHeartRate()) {
      values.add(packet.basicData.heartRate);
    }
    if (packet.hasWearSportData() && packet.wearSportData.hasHeartRate()) {
      values.add(packet.wearSportData.heartRate);
    }
    if (packet.hasWearSportDataV2a() &&
        packet.wearSportDataV2a.hasHeartRate()) {
      values.add(packet.wearSportDataV2a.heartRate);
    }
    if (packet.hasEcgData() && packet.ecgData.hasHeartRate()) {
      values.add(packet.ecgData.heartRate);
    }
    if (packet.hasSleepResult()) {
      for (final section in packet.sleepResult.sectionList) {
        if (section.hasAverageHeartRate()) {
          values.add(section.averageHeartRate);
        }
      }
    }
    return values;
  });

  /// Blood-oxygen samples currently exposed by the device protocol.
  ///
  /// Xiaomi exposes blood oxygen measurements as part of sleep sections,
  /// rather than as a separate measurement packet.
  Stream<int> get bloodOxygenReports => sleepResults.expand(
    (result) => result.sectionList
        .where((section) => section.hasAverageBloodOxygen())
        .map((section) => section.averageBloodOxygen),
  );

  Stream<pb_fitness.WomenHealth> get womenHealthReports => fitnessPackets
      .where((packet) => packet.hasWomenHealth())
      .map((packet) => packet.womenHealth);

  Stream<pb_fitness.WomenHealth_Section_List> get womenHealthSectionReports =>
      fitnessPackets
          .where((packet) => packet.hasSectionList())
          .map((packet) => packet.sectionList);

  Stream<pb_fitness.SleepRegularity> get sleepRegularityReports =>
      fitnessPackets
          .where((packet) => packet.hasSleepRegularity())
          .map((packet) => packet.sleepRegularity);

  Stream<pb_fitness.SleepDisorder> get sleepDisorderReports => fitnessPackets
      .where((packet) => packet.hasSleepDisorder())
      .map((packet) => packet.sleepDisorder);

  Stream<pb_fitness.SportStatus> get sportStatusReports => fitnessPackets
      .where((packet) => packet.hasSportStatus())
      .map((packet) => packet.sportStatus);

  Stream<pb_fitness.SportResponse> get sportResponses => fitnessPackets
      .where((packet) => packet.hasSportResponse())
      .map((packet) => packet.sportResponse);

  /// Returns the latest basic daily aggregate reported by the device.
  Future<pb_fitness.BasicData> fetchBasicData() => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.GET_BASIC_DATA,
    payload: pb_fitness.Fitness(),
    responseIds: {
      pb_fitness.Fitness_FitnessID.GET_BASIC_DATA.value,
      pb_fitness.Fitness_FitnessID.REPORT_BASIC_DATA.value,
    },
    hasResponse: (fitness) => fitness.hasBasicData(),
    response: (fitness) => fitness.basicData,
  );

  /// Returns the IDs of today's or historical fitness records.
  Future<Uint8List> fetchFitnessIds({bool history = false}) => _requestBytes(
    id: history
        ? pb_fitness.Fitness_FitnessID.GET_HISTORY_FITNESS_IDS
        : pb_fitness.Fitness_FitnessID.GET_TODAY_FITNESS_IDS,
    payload: history
        ? pb_fitness.Fitness()
        : pb_fitness.Fitness(syncParam: pb_fitness.SyncParam(reason: 0)),
    timeout: const Duration(seconds: 30),
    hasResponse: (_) => true,
  );

  Future<Uint8List> requestFitnessIds(Uint8List ids) => _requestBytes(
    id: pb_fitness.Fitness_FitnessID.REQUEST_FITNESS_IDS,
    payload: pb_fitness.Fitness(ids: ids),
  );

  Future<void> requestFitnessId(Uint8List id) => _sendFitness(
    pb_fitness.Fitness_FitnessID.REQUEST_FITNESS_ID,
    payload: pb_fitness.Fitness(id: id),
  );

  Future<void> confirmFitnessId(Uint8List id) => _sendFitness(
    pb_fitness.Fitness_FitnessID.CONFIRM_FITNESS_ID,
    payload: pb_fitness.Fitness(id: id),
  );

  /// Synchronizes the activity files used by Xiaomi's stable health protocol.
  ///
  /// The newer aggregate requests (41/44) are not implemented by all Vela
  /// firmwares.  Activity files are the compatible path used by the wearable
  /// protocol:
  /// request ids, request each seven-byte file, receive a separate fitness
  /// channel stream, then acknowledge the file.
  ///
  /// Health synchronization can be started by the device page, the health
  /// page, or the command bus.  All three entry points share the same
  /// protocol system, so concurrent calls must join the active transfer
  /// instead of interleaving request IDs and file chunks.
  Future<XiaomiActivityFileSyncResult> syncActivityFiles() {
    final active = _activitySyncFuture;
    if (active != null) {
      _log.fine('[${entity.id}] joining active Xiaomi health file sync');
      return active;
    }

    _log.info('[${entity.id}] Xiaomi health file sync started');
    final sync = _syncActivityFiles();
    _activitySyncFuture = sync;
    sync.then<void>(
      (result) {
        _log.info(
          '[${entity.id}] Xiaomi health file sync completed: '
          'files=${result.filesReceived}, skipped=${result.filesSkipped}, '
          'failed=${result.failedFiles.length}',
        );
        if (identical(_activitySyncFuture, sync)) _activitySyncFuture = null;
      },
      onError: (Object error, StackTrace stackTrace) {
        _log.warning(
          '[${entity.id}] Xiaomi health file sync failed',
          error,
          stackTrace,
        );
        if (identical(_activitySyncFuture, sync)) _activitySyncFuture = null;
      },
    );
    return sync;
  }

  Future<XiaomiActivityFileSyncResult> _syncActivityFiles() async {
    final daily = <XiaomiActivityDailyRecord>[];
    final samples = <XiaomiActivitySampleRecord>[];
    final sleep = <XiaomiActivitySleepRecord>[];
    final workouts = <XiaomiActivityWorkoutRecord>[];
    final abnormalHealthRecords = <XiaomiActivityAbnormalHealthRecord>[];
    final rawFiles = <XiaomiActivityRawFile>[];
    final failedFiles = <XiaomiActivityFileFailure>[];
    var received = 0;
    var skipped = 0;

    // Start draining today's IDs before asking for history, then add the
    // historical IDs into the same priority queue as soon as they arrive.
    // This mirrors Gadgetbridge's fetcher: it keeps one file in flight while
    // the past-ID query runs, and chooses the next file from a sorted queue.
    final listedIds = <String>{};
    final queuedIds = SplayTreeSet<Uint8List>(_compareActivityIds);
    final completedIds = <String>{};
    final attemptsById = <String, int>{};
    final retrievalFailures = <String, XiaomiActivityFileFailure>{};
    final historyIdsReceived = Completer<void>();

    Future<Uint8List?> fetchIds({required bool history}) async {
      try {
        final ids = await fetchFitnessIds(history: history);
        _log.fine(
          '[${entity.id}] Xiaomi ${history ? 'history' : 'today'} '
          'activity id list received: ${ids.length} bytes',
        );
        return ids;
      } catch (error, stackTrace) {
        _log.warning(
          '[${entity.id}] Xiaomi ${history ? 'history' : 'today'} activity '
          'id list unavailable; continuing with the other source',
          error,
          stackTrace,
        );
        return null;
      }
    }

    void enqueueIds(Uint8List? raw, {required bool history}) {
      if (raw == null) return;
      if (raw.length % 7 != 0) {
        _log.warning(
          '[${entity.id}] invalid Xiaomi ${history ? 'history' : 'today'} '
          'activity id list length ${raw.length}; skipping this source',
        );
        return;
      }

      for (var offset = 0; offset < raw.length; offset += 7) {
        final id = Uint8List.fromList(raw.sublist(offset, offset + 7));
        final timestamp = ByteData.sublistView(id).getUint32(0, Endian.little);
        if (timestamp == 0 && id[5] == 0) {
          skipped++;
          _log.warning('[${entity.id}] ignoring empty Xiaomi activity file id');
          continue;
        }
        final key = _activityIdKey(id);
        if (listedIds.add(key)) queuedIds.add(id);
      }
    }

    Future<void> confirmFile(Uint8List id, String key, int attempts) async {
      try {
        await confirmFitnessId(id);
      } catch (error, stackTrace) {
        failedFiles.add(
          XiaomiActivityFileFailure(
            id: key,
            attempts: attempts,
            error: 'confirmation failed: $error',
          ),
        );
        _log.warning(
          '[${entity.id}] Xiaomi activity file $key was received but '
          'could not be confirmed; continuing',
          error,
          stackTrace,
        );
      }
    }

    Future<void> drainFileQueue() async {
      while (true) {
        if (queuedIds.isEmpty) {
          if (historyIdsReceived.isCompleted) return;
          await historyIdsReceived.future;
          continue;
        }

        final id = queuedIds.first;
        final key = _activityIdKey(id);
        queuedIds.remove(id);
        if (completedIds.contains(key)) continue;

        final attempts = (attemptsById[key] ?? 0) + 1;
        attemptsById[key] = attempts;
        try {
          final file = await _requestActivityFile(id);
          final actualId = Uint8List.fromList(file.sublist(0, 7));
          final actualKey = _activityIdKey(actualId);
          if (completedIds.add(actualKey)) {
            retrievalFailures.remove(actualKey);
            rawFiles.add(
              XiaomiActivityRawFile(
                id: actualKey,
                data: Uint8List.fromList(file),
              ),
            );
            // Gadgetbridge confirms the validated file before parsing it.
            await confirmFile(actualId, actualKey, attempts);
            if (file.length == 11) {
              skipped++;
            } else {
              try {
                final parsed = _parseActivityFile(file);
                if (parsed.daily != null) daily.add(parsed.daily!);
                samples.addAll(parsed.samples);
                sleep.addAll(parsed.sleep);
                workouts.addAll(parsed.workouts);
                abnormalHealthRecords.addAll(parsed.abnormalHealthRecords);
                received++;
              } catch (error, stackTrace) {
                failedFiles.add(
                  XiaomiActivityFileFailure(
                    id: actualKey,
                    attempts: attempts,
                    error: 'parse failed: $error',
                  ),
                );
                _log.warning(
                  '[${entity.id}] could not parse Xiaomi activity file '
                  '$actualKey; raw bytes were retained',
                  error,
                  stackTrace,
                );
              }
            }
          } else {
            // ACK duplicates so the watch can advance, but parse each ID once.
            await confirmFile(actualId, actualKey, attempts);
          }
          if (actualKey == key) {
            retrievalFailures.remove(key);
          } else {
            retrievalFailures[key] = XiaomiActivityFileFailure(
              id: key,
              attempts: attempts,
              error: 'requested $key but received $actualKey',
            );
            _log.warning(
              '[${entity.id}] requested Xiaomi activity file $key but '
              'received $actualKey; processed and confirmed the payload ID',
            );
          }
        } catch (error, stackTrace) {
          retrievalFailures[key] = XiaomiActivityFileFailure(
            id: key,
            attempts: attempts,
            error: error.toString(),
          );
          _log.warning(
            '[${entity.id}] Xiaomi activity file $key failed on attempt '
            '$attempts/$_activityFileMaxAttempts',
            error,
            stackTrace,
          );
        }

        // A mismatched but valid file is already retained/confirmed above.
        // Retry only the ID that is still missing, and let it re-enter the
        // shared priority queue alongside any history IDs that arrived meanwhile.
        if (!completedIds.contains(key)) {
          if (attempts < _activityFileMaxAttempts) {
            await Future<void>.delayed(_activityFileRetryDelay);
            queuedIds.add(id);
          } else {
            _log.warning(
              '[${entity.id}] giving up Xiaomi activity file $key after '
              '$attempts attempts; continuing with the next file',
              retrievalFailures[key]?.error,
            );
          }
        }
      }
    }

    // Install the first file receiver before sending the history query; some
    // firmware starts the file stream immediately after today's first request.
    final todayRaw = await fetchIds(history: false);
    enqueueIds(todayRaw, history: false);
    final drainFuture = drainFileQueue();
    final historyFuture = fetchIds(history: true)
        .then((historyRaw) {
          enqueueIds(historyRaw, history: true);
        })
        // Even a failed history query must release the drain loop, which
        // waits on this completer; the error itself still reaches the
        // Future.wait below.
        .whenComplete(historyIdsReceived.complete);
    await Future.wait([drainFuture, historyFuture]);
    failedFiles.addAll(retrievalFailures.values);

    return XiaomiActivityFileSyncResult(
      daily: daily,
      samples: samples,
      sleep: sleep,
      workouts: _mergeWorkoutRecords(workouts),
      abnormalHealthRecords: abnormalHealthRecords,
      rawFiles: List.unmodifiable(rawFiles),
      filesReceived: received,
      failedFiles: List.unmodifiable(failedFiles),
      filesSkipped: skipped,
    );
  }

  String _activityIdKey(Uint8List id) =>
      id.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

  /// Matches Gadgetbridge's XiaomiActivityFileId priority order: signed
  /// timestamp, signed timezone, type, subtype, fetch order, signed version.
  int _compareActivityIds(Uint8List left, Uint8List right) {
    int fetchOrder(int detail) => switch (detail) {
      1 => 0, // Summary first, so workout summaries precede GPS tracks.
      0 => 1,
      2 => 2,
      _ => 3,
    };

    final leftFlags = left[6];
    final rightFlags = right[6];
    final leftTimestamp = ByteData.sublistView(left).getInt32(0, Endian.little);
    final rightTimestamp = ByteData.sublistView(right)
        .getInt32(0, Endian.little);
    var comparison = leftTimestamp.compareTo(rightTimestamp);
    if (comparison != 0) return comparison;
    comparison = left[4].toSigned(8).compareTo(right[4].toSigned(8));
    if (comparison != 0) return comparison;
    comparison = ((leftFlags >> 7) & 1).compareTo((rightFlags >> 7) & 1);
    if (comparison != 0) return comparison;
    comparison = ((leftFlags & 0x7f) >> 2).compareTo((rightFlags & 0x7f) >> 2);
    if (comparison != 0) return comparison;
    comparison = fetchOrder(leftFlags & 0x03)
        .compareTo(fetchOrder(rightFlags & 0x03));
    if (comparison != 0) return comparison;
    return left[5].toSigned(8).compareTo(right[5].toSigned(8));
  }

  Future<Uint8List> _requestActivityFile(Uint8List id) async {
    if (_activityFileCompleter != null) {
      throw StateError('Xiaomi activity file request already in progress');
    }
    final key = _activityIdKey(id);
    final pending = _pendingActivityFiles.remove(key);
    if (pending != null) {
      _log.fine(
        '[${entity.id}] consuming buffered Xiaomi activity file while '
        'requesting $key',
      );
      return pending;
    }
    final completer = Completer<Uint8List>();
    _log.fine('[${entity.id}] requesting Xiaomi activity file $key');
    _activityFileCompleter = completer;
    _activityFileBuffer = BytesBuilder(copy: false);
    _activityTotalChunks = 0;
    _activityNextChunk = 1;
    _armActivityWatchdog();
    try {
      await requestFitnessId(id);
      return await completer.future;
    } finally {
      _activityWatchdog?.cancel();
      _activityWatchdog = null;
      _activityFileCompleter = null;
      _activityFileBuffer = null;
    }
  }

  void _armActivityWatchdog() {
    _activityWatchdog?.cancel();
    final waitingForFirstChunk = _activityNextChunk == 1;
    _activityWatchdog = Timer(
      waitingForFirstChunk
          ? const Duration(seconds: 45)
          : const Duration(seconds: 10),
      () {
        final completer = _activityFileCompleter;
        if (completer == null || completer.isCompleted) return;
        _log.warning(
          '[${entity.id}] Xiaomi activity file transfer timed out: '
          'chunk=${_activityNextChunk - 1}/$_activityTotalChunks',
        );
        completer.completeError(
          ProtocolException(
            waitingForFirstChunk
                ? 'Xiaomi activity file preparation timed out before the first chunk'
                : 'Xiaomi activity file transfer stalled at chunk '
                      '${_activityNextChunk - 1}/$_activityTotalChunks',
          ),
        );
      },
    );
  }

  /// Receives one raw activity-file chunk from SPP activity or L2 fileFitness.
  void onActivityPayload(Uint8List payload) {
    final completer = _activityFileCompleter;
    if (completer == null || completer.isCompleted) {
      _bufferUnsolicitedActivityPayload(payload);
      return;
    }
    if (payload.length < 4) {
      _log.warning(
        '[${entity.id}] dropping Xiaomi activity chunk shorter than header '
        '(${payload.length} bytes)',
      );
      completer.completeError(
        ProtocolException('Xiaomi activity chunk too short'),
      );
      return;
    }
    final view = ByteData.sublistView(payload);
    final total = view.getUint16(0, Endian.little);
    final number = view.getUint16(2, Endian.little);
    if (total == 0 || number == 0 || number > total) {
      _log.warning(
        '[${entity.id}] dropping invalid Xiaomi activity chunk '
        '$number/$total',
      );
      completer.completeError(
        ProtocolException('Invalid Xiaomi activity chunk $number/$total'),
      );
      return;
    }
    if (number == 1) {
      _activityFileBuffer = BytesBuilder(copy: false);
      _activityTotalChunks = total;
      _activityNextChunk = 1;
    }
    if (total != _activityTotalChunks || number != _activityNextChunk) {
      _log.warning(
        '[${entity.id}] unexpected Xiaomi activity chunk '
        '$number/$total, expected $_activityNextChunk/$_activityTotalChunks',
      );
      completer.completeError(
        ProtocolException(
          'Unexpected Xiaomi activity chunk $number/$total '
          '(expected $_activityNextChunk/$_activityTotalChunks)',
        ),
      );
      return;
    }
    _activityFileBuffer!.add(payload.sublist(4));
    _activityNextChunk++;
    _armActivityWatchdog();
    _log.fine(
      '[${entity.id}] Xiaomi activity chunk $number/$total '
      '(${payload.length - 4} bytes)',
    );
    if (number == total) {
      final data = _activityFileBuffer!.toBytes();
      _log.fine(
        '[${entity.id}] Xiaomi activity file transfer completed: '
        '$number/$total chunks, ${data.length} bytes',
      );
      try {
        completer.complete(_normalizeActivityFile(data));
      } catch (error, stackTrace) {
        _log.warning(
          '[${entity.id}] Xiaomi activity file validation failed',
          error,
          stackTrace,
        );
        completer.completeError(error, stackTrace);
      }
    }
  }

  /// Xiaomi can emit the first file chunk in the interval between the file
  /// request and the next request. Mi Fitness keeps an assembler
  /// alive for that stream; dropping it here made the first health sync depend
  /// on a retry. A completed file is retained only after header and CRC
  /// validation, then bounded by the number of pending files.
  void _bufferUnsolicitedActivityPayload(Uint8List payload) {
    if (payload.length < 4) {
      _log.fine(
        '[${entity.id}] dropping unsolicited Xiaomi activity payload '
        'shorter than header (${payload.length} bytes)',
      );
      return;
    }
    final view = ByteData.sublistView(payload);
    final total = view.getUint16(0, Endian.little);
    final number = view.getUint16(2, Endian.little);
    if (total == 0 || number == 0 || number > total) {
      _pendingActivityFileBuffer = null;
      _pendingActivityTotalChunks = 0;
      _pendingActivityNextChunk = 1;
      _log.fine(
        '[${entity.id}] dropping invalid unsolicited Xiaomi activity '
        'chunk $number/$total',
      );
      return;
    }
    if (number == 1) {
      _pendingActivityFileBuffer = BytesBuilder(copy: false);
      _pendingActivityTotalChunks = total;
      _pendingActivityNextChunk = 1;
    }
    if (_pendingActivityFileBuffer == null ||
        total != _pendingActivityTotalChunks ||
        number != _pendingActivityNextChunk) {
      _pendingActivityFileBuffer = null;
      _pendingActivityTotalChunks = 0;
      _pendingActivityNextChunk = 1;
      _log.fine(
        '[${entity.id}] dropping out-of-order unsolicited Xiaomi activity '
        'chunk $number/$total',
      );
      return;
    }
    _pendingActivityFileBuffer!.add(payload.sublist(4));
    _pendingActivityNextChunk++;
    if (number != total) return;

    final data = _pendingActivityFileBuffer!.toBytes();
    _pendingActivityFileBuffer = null;
    _pendingActivityTotalChunks = 0;
    _pendingActivityNextChunk = 1;
    try {
      final normalized = _normalizeActivityFile(data);
      final key = _activityIdKey(Uint8List.sublistView(normalized, 0, 7));
      _cachePendingActivityFile(key, normalized);
      _log.fine(
        '[${entity.id}] buffered unsolicited Xiaomi activity file '
        '$key (${normalized.length} bytes)',
      );
    } catch (error, stackTrace) {
      _log.fine(
        '[${entity.id}] dropping invalid unsolicited Xiaomi activity file',
        error,
        stackTrace,
      );
    }
  }

  void _cachePendingActivityFile(String key, Uint8List normalized) {
    _pendingActivityFiles[key] = normalized;
    while (_pendingActivityFiles.length > 8) {
      _pendingActivityFiles.remove(_pendingActivityFiles.keys.first);
    }
  }

  /// Validates the raw file emitted on the Xiaomi activity-file channel.
  ///
  /// Mi Fitness removes the trailing CRC and the seven-byte
  /// FitnessDataId before handing the buffer to its generated server-data
  /// parser. OronBox parses the device file directly, so this method keeps
  /// both the raw file ID and its CRC-validated contents intact.
  Uint8List _normalizeActivityFile(Uint8List data) {
    // The shortest valid transfer is a seven-byte FitnessDataId followed by
    // its four-byte CRC. It intentionally contains no parseable data body.
    if (data.length < 11) {
      throw ProtocolException('Xiaomi activity file is too short');
    }
    final view = ByteData.sublistView(data);
    final expected = view.getUint32(data.length - 4, Endian.little);
    final actual = _crc32(Uint8List.sublistView(data, 0, data.length - 4));
    if (expected == actual) return data;
    throw ProtocolException(
      'Xiaomi activity CRC mismatch: ${actual.toRadixString(16)} != '
      '${expected.toRadixString(16)}',
    );
  }

  /// Parses a sleep activity file for protocol tests and diagnostics.
  @visibleForTesting
  XiaomiActivitySleepRecord? parseActivitySleepFileForTesting(Uint8List data) {
    return _primarySleepRecord(parseActivitySleepFilesForTesting(data));
  }

  /// Parses every sleep summary in a device activity file. This is kept
  /// public for protocol tests and diagnostics; normal sync uses the same list
  /// through [XiaomiActivityFileSyncResult.sleep].
  @visibleForTesting
  List<XiaomiActivitySleepRecord> parseActivitySleepFilesForTesting(
    Uint8List data,
  ) {
    final parsed = _parseActivityFile(_normalizeActivityFile(data));
    return parsed.sleep;
  }

  /// Parses workout reports for protocol tests and debug tooling. The public
  /// sync path uses the same decoder; exposing the result makes it possible to
  /// lock the legacy/new-schema compatibility behavior to a real file sample.
  @visibleForTesting
  List<XiaomiActivityWorkoutRecord> parseActivityWorkoutFilesForTesting(
    Uint8List data,
  ) {
    final parsed = _parseActivityFile(_normalizeActivityFile(data));
    return parsed.workouts;
  }

  /// Parses Vela's historical daily-type-9 abnormal heart-rate file.
  @visibleForTesting
  List<XiaomiActivityAbnormalHealthRecord>
  parseActivityAbnormalHealthFileForTesting(Uint8List data) {
    return _parseActivityFile(_normalizeActivityFile(data))
        .abnormalHealthRecords;
  }

  List<XiaomiActivityAbnormalHeartRateRecord>
  parseActivityAbnormalHeartRateFileForTesting(Uint8List data) {
    return parseActivityAbnormalHealthFileForTesting(data)
        .where(
          (record) =>
              record.kind == XiaomiActivityAbnormalHealthKind.highHeartRate ||
              record.kind == XiaomiActivityAbnormalHealthKind.lowHeartRate,
        )
        .where((record) => record.value != null && record.threshold != null)
        .map(
          (record) => XiaomiActivityAbnormalHeartRateRecord(
            timestamp: record.timestamp,
            value: record.value!,
            kind: record.kind == XiaomiActivityAbnormalHealthKind.highHeartRate
                ? XiaomiActivityAbnormalHeartRateKind.high
                : XiaomiActivityAbnormalHeartRateKind.low,
            threshold: record.threshold!,
            startedAt: record.startedAt,
            endedAt: record.endedAt,
          ),
        )
        .toList(growable: false);
  }

  /// Replays CRC-validated activity files without touching the wearable.
  ///
  /// The health debug page uses this to test parser changes against files
  /// captured during a real synchronization.  A parse failure is isolated to
  /// its file so one unsupported format does not hide the other records.
  XiaomiActivityFileSyncResult parseActivityFilesForDebug(
    Iterable<XiaomiActivityRawFile> files,
  ) {
    final daily = <XiaomiActivityDailyRecord>[];
    final samples = <XiaomiActivitySampleRecord>[];
    final sleep = <XiaomiActivitySleepRecord>[];
    final workouts = <XiaomiActivityWorkoutRecord>[];
    final abnormalHealthRecords = <XiaomiActivityAbnormalHealthRecord>[];
    final rawFiles = <XiaomiActivityRawFile>[];
    final failedFiles = <XiaomiActivityFileFailure>[];
    var received = 0;
    for (final raw in files) {
      try {
        // Imported archives are user supplied. Re-run the same length/CRC
        // validation as the live transfer before handing bytes to a parser;
        // captures written by the synchronizer already satisfy this check.
        final normalized = _normalizeActivityFile(raw.data);
        rawFiles.add(
          XiaomiActivityRawFile(
            id: raw.id,
            data: Uint8List.fromList(normalized),
          ),
        );
        final parsed = _parseActivityFile(normalized);
        if (parsed.daily != null) daily.add(parsed.daily!);
        samples.addAll(parsed.samples);
        sleep.addAll(parsed.sleep);
        workouts.addAll(parsed.workouts);
        abnormalHealthRecords.addAll(parsed.abnormalHealthRecords);
        received++;
      } catch (error, stackTrace) {
        failedFiles.add(
          XiaomiActivityFileFailure(
            id: raw.id,
            attempts: 0,
            error: 'parse failed: $error',
          ),
        );
        _log.warning(
          'could not replay Xiaomi activity file ${raw.id}',
          error,
          stackTrace,
        );
      }
    }
    return XiaomiActivityFileSyncResult(
      daily: daily,
      samples: samples,
      sleep: sleep,
      workouts: _mergeWorkoutRecords(workouts),
      abnormalHealthRecords: abnormalHealthRecords,
      rawFiles: List.unmodifiable(rawFiles),
      filesReceived: received,
      failedFiles: List.unmodifiable(failedFiles),
    );
  }

  List<XiaomiActivityWorkoutRecord> _mergeWorkoutRecords(
    List<XiaomiActivityWorkoutRecord> values,
  ) {
    final sorted = [...values]
      ..sort((left, right) => left.startedAt.compareTo(right.startedAt));
    final merged = <XiaomiActivityWorkoutRecord>[];
    for (final value in sorted) {
      final index = merged.indexWhere(
        (candidate) => _sameWorkoutRecord(candidate, value),
      );
      if (index < 0) {
        merged.add(value);
      } else {
        merged[index] = _mergeWorkoutRecord(merged[index], value);
      }
    }
    return merged;
  }

  bool _sameWorkoutRecord(
    XiaomiActivityWorkoutRecord left,
    XiaomiActivityWorkoutRecord right,
  ) {
    if (left.activityType != right.activityType ||
        (_isWorkoutSummary(left) && _isWorkoutSummary(right))) {
      return false;
    }
    // Report, record, GPS and recovery files for one session normally share
    // the file timestamp. A resumed record can start a few minutes later, so
    // also accept overlapping intervals, but never collapse two adjacent
    // sessions solely because they are within an arbitrary ten-minute window.
    final startsClose =
        left.startedAt.difference(right.startedAt).abs() <=
        const Duration(minutes: 1);
    final overlaps =
        left.startedAt.isBefore(right.endedAt) &&
        right.startedAt.isBefore(left.endedAt);
    return startsClose || overlaps;
  }

  XiaomiActivityWorkoutRecord _mergeWorkoutRecord(
    XiaomiActivityWorkoutRecord left,
    XiaomiActivityWorkoutRecord right,
  ) {
    final leftSummary = _isWorkoutSummary(left);
    final rightSummary = _isWorkoutSummary(right);
    final primary = rightSummary && !leftSummary ? right : left;
    final secondary = identical(primary, left) ? right : left;
    final samples = [...left.samples, ...right.samples]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final route = [...left.route, ...right.route]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return XiaomiActivityWorkoutRecord(
      startedAt: left.startedAt.isBefore(right.startedAt)
          ? left.startedAt
          : right.startedAt,
      endedAt: left.endedAt.isAfter(right.endedAt)
          ? left.endedAt
          : right.endedAt,
      activityType: primary.activityType,
      subSportType: primary.subSportType ?? secondary.subSportType,
      distanceMeters: primary.distanceMeters ?? secondary.distanceMeters,
      calories: primary.calories ?? secondary.calories,
      averageHeartRate: primary.averageHeartRate ?? secondary.averageHeartRate,
      maximumHeartRate: primary.maximumHeartRate ?? secondary.maximumHeartRate,
      minimumHeartRate: primary.minimumHeartRate ?? secondary.minimumHeartRate,
      totalDurationSeconds:
          primary.totalDurationSeconds ?? secondary.totalDurationSeconds,
      effectiveDurationSeconds:
          primary.effectiveDurationSeconds ??
          secondary.effectiveDurationSeconds,
      activeCalories: primary.activeCalories ?? secondary.activeCalories,
      averagePaceSecondsPerKilometer:
          primary.averagePaceSecondsPerKilometer ??
          secondary.averagePaceSecondsPerKilometer,
      bestPaceSecondsPerKilometer:
          primary.bestPaceSecondsPerKilometer ??
          secondary.bestPaceSecondsPerKilometer,
      worstPaceSecondsPerKilometer:
          primary.worstPaceSecondsPerKilometer ??
          secondary.worstPaceSecondsPerKilometer,
      averageSpeedKph: primary.averageSpeedKph ?? secondary.averageSpeedKph,
      bestSpeedKph: primary.bestSpeedKph ?? secondary.bestSpeedKph,
      totalSteps: primary.totalSteps ?? secondary.totalSteps,
      averageStrideCentimeters:
          primary.averageStrideCentimeters ??
          secondary.averageStrideCentimeters,
      averageCadence: primary.averageCadence ?? secondary.averageCadence,
      maximumCadence: primary.maximumCadence ?? secondary.maximumCadence,
      averageBloodOxygen:
          primary.averageBloodOxygen ?? secondary.averageBloodOxygen,
      maximumBloodOxygen:
          primary.maximumBloodOxygen ?? secondary.maximumBloodOxygen,
      minimumBloodOxygen:
          primary.minimumBloodOxygen ?? secondary.minimumBloodOxygen,
      averageStress: primary.averageStress ?? secondary.averageStress,
      maximumStress: primary.maximumStress ?? secondary.maximumStress,
      minimumStress: primary.minimumStress ?? secondary.minimumStress,
      totalAscentMeters:
          primary.totalAscentMeters ?? secondary.totalAscentMeters,
      totalDescentMeters:
          primary.totalDescentMeters ?? secondary.totalDescentMeters,
      averageAltitudeMeters:
          primary.averageAltitudeMeters ?? secondary.averageAltitudeMeters,
      maximumAltitudeMeters:
          primary.maximumAltitudeMeters ?? secondary.maximumAltitudeMeters,
      minimumAltitudeMeters:
          primary.minimumAltitudeMeters ?? secondary.minimumAltitudeMeters,
      aerobicTrainingEffect:
          primary.aerobicTrainingEffect ?? secondary.aerobicTrainingEffect,
      anaerobicTrainingEffect:
          primary.anaerobicTrainingEffect ?? secondary.anaerobicTrainingEffect,
      peakTrainingEffect:
          primary.peakTrainingEffect ?? secondary.peakTrainingEffect,
      vo2Max: primary.vo2Max ?? secondary.vo2Max,
      bodyEnergyConsumption:
          primary.bodyEnergyConsumption ?? secondary.bodyEnergyConsumption,
      expectedRecoveryHours:
          primary.expectedRecoveryHours ?? secondary.expectedRecoveryHours,
      trainingLoad: primary.trainingLoad ?? secondary.trainingLoad,
      earnedVitality: primary.earnedVitality ?? secondary.earnedVitality,
      heartRateZoneMethod:
          primary.heartRateZoneMethod ?? secondary.heartRateZoneMethod,
      heartRateZones: primary.heartRateZones.isNotEmpty
          ? primary.heartRateZones
          : secondary.heartRateZones,
      averagePowerWatts:
          primary.averagePowerWatts ?? secondary.averagePowerWatts,
      maximumPowerWatts:
          primary.maximumPowerWatts ?? secondary.maximumPowerWatts,
      totalArmPulls: primary.totalArmPulls ?? secondary.totalArmPulls,
      mainSwimmingStroke:
          primary.mainSwimmingStroke ?? secondary.mainSwimmingStroke,
      averageStrokeFrequency:
          primary.averageStrokeFrequency ?? secondary.averageStrokeFrequency,
      maximumStrokeFrequency:
          primary.maximumStrokeFrequency ?? secondary.maximumStrokeFrequency,
      turnCount: primary.turnCount ?? secondary.turnCount,
      averageSwolf: primary.averageSwolf ?? secondary.averageSwolf,
      bestSwolf: primary.bestSwolf ?? secondary.bestSwolf,
      poolWidthMeters: primary.poolWidthMeters ?? secondary.poolWidthMeters,
      totalJumps: primary.totalJumps ?? secondary.totalJumps,
      averageJumpFrequency:
          primary.averageJumpFrequency ?? secondary.averageJumpFrequency,
      bestJumpFrequency:
          primary.bestJumpFrequency ?? secondary.bestJumpFrequency,
      tripCount: primary.tripCount ?? secondary.tripCount,
      setCount: primary.setCount ?? secondary.setCount,
      totalStrokes: primary.totalStrokes ?? secondary.totalStrokes,
      averageRowingFrequency:
          primary.averageRowingFrequency ?? secondary.averageRowingFrequency,
      bestRowingFrequency:
          primary.bestRowingFrequency ?? secondary.bestRowingFrequency,
      samples: samples,
      route: route,
      recovery: primary.recovery ?? secondary.recovery,
    );
  }

  bool _isWorkoutSummary(XiaomiActivityWorkoutRecord value) =>
      value.distanceMeters != null ||
      value.calories != null ||
      value.averageHeartRate != null ||
      value.totalDurationSeconds != null ||
      value.heartRateZones.isNotEmpty;

  XiaomiActivitySleepRecord? _primarySleepRecord(
    List<XiaomiActivitySleepRecord> records,
  ) {
    if (records.isEmpty) return null;
    final indexed = records.where((value) => value.sleepIndex == 1);
    final candidates = indexed.isEmpty ? records : indexed;
    return candidates.reduce(
      (left, right) =>
          left.durationSeconds >= right.durationSeconds ? left : right,
    );
  }

  _ParsedActivityFile _parseActivityFile(Uint8List data) {
    if (data.length < 11) {
      throw ProtocolException('Xiaomi activity file is too short to parse');
    }
    final view = ByteData.sublistView(data);
    final timestamp = view.getUint32(0, Endian.little);
    final previousTimezoneOffset = _activityTimezoneOffset15Min;
    _activityTimezoneOffset15Min = data[4].toSigned(8);
    final version = data[5];
    final flags = data[6];
    final type = (flags >> 7) & 1;
    final subtype = (flags & 0x7f) >> 2;
    final detail = flags & 3;
    try {
      if (type == 0 && subtype == 0 && detail == 1) {
        return _ParsedActivityFile(
          daily: _parseDaily(data, timestamp, version),
        );
      }
      if (type == 0 && subtype == 0 && detail == 0) {
        return _ParsedActivityFile(
          samples: _parseDailyDetails(data, timestamp, version),
        );
      }
      // Mi Fitness routes dailyType=6 to ManualMeasureParser.  These files are
      // the source of the manually measured heart-rate, SpO2 and stress points;
      // they are separate from the minute-level daily detail file above.
      if (type == 0 && subtype == 6) {
        return _ParsedActivityFile(
          samples: _parseManualMeasures(data, timestamp, version),
        );
      }
      if (type == 0 && (subtype == 3 || subtype == 8)) {
        return _ParsedActivityFile(
          sleep: _parseSleep(data, timestamp, version, subtype),
        );
      }
      if (type == 0 && subtype == 9) {
        return _ParsedActivityFile(
          abnormalHealthRecords: _parseAbnormalHealth(data, version),
        );
      }
      if (type == 1 && detail == 1) {
        final workout = _parseWorkoutSummary(data, timestamp, subtype, version);
        return _ParsedActivityFile(
          workouts: workout == null ? const [] : [workout],
        );
      }
      if (type == 1 && detail == 0) {
        final workout = _parseWorkoutSamples(data, timestamp, subtype, version);
        return _ParsedActivityFile(
          workouts: workout == null ? const [] : [workout],
        );
      }
      if (type == 1 && detail == 2) {
        final workout = _parseWorkoutRoute(data, timestamp, subtype, version);
        return _ParsedActivityFile(
          workouts: workout == null ? const [] : [workout],
        );
      }
      if (type == 1 && detail == 3) {
        final workout = _parseWorkoutRecovery(
          data,
          timestamp,
          subtype,
          version,
        );
        return _ParsedActivityFile(
          workouts: workout == null ? const [] : [workout],
        );
      }
      _log.fine(
        'unsupported Xiaomi activity file '
        'type=$type subtype=$subtype detail=$detail version=$version',
      );
      return const _ParsedActivityFile();
    } finally {
      _activityTimezoneOffset15Min = previousTimezoneOffset;
    }
  }

  DateTime _activityTimestamp(int seconds) => xiaomiActivityTimestamp(
    seconds,
    timezoneOffset15Min: _activityTimezoneOffset15Min,
  );

  XiaomiActivityWorkoutRecord? _parseWorkoutSamples(
    Uint8List data,
    int fileTimestamp,
    int subtype,
    int version,
  ) {
    if ((subtype == 9 || subtype == 10) && version == 3) {
      return _parseSwimmingSamples(data, fileTimestamp, subtype);
    }
    final layout = _workoutRecordLayout(subtype, version);
    if (layout == null) return null;
    final limit = data.length - 4;
    var offset = 8 + layout.validityBytes;
    if (offset + layout.segmentHeaderBytes > limit) return null;
    final view = ByteData.sublistView(data);
    final validity = data.sublist(8, 8 + layout.validityBytes);
    bool bit(int index) =>
        index ~/ 8 < validity.length &&
        (validity[index ~/ 8] & (1 << (7 - index % 8))) != 0;
    final activeFields = layout.pointFields
        .where((field) => bit(field.existsBit))
        .toList(growable: false);
    final pointBytes = activeFields.fold<int>(
      0,
      (total, field) => total + field.byteSize,
    );
    if (pointBytes == 0) return null;

    final samples = <XiaomiWorkoutSampleRecord>[];
    var cumulativeCalories = 0;
    var cumulativeSteps = 0;
    var cumulativeDistanceTenths = 0;
    double? cumulativeAltitude;
    while (offset + layout.segmentHeaderBytes <= limit) {
      final segmentOffset = offset;
      final count = view.getUint32(
        segmentOffset + layout.recordCountOffset,
        Endian.little,
      );
      final resumeSeconds = view.getUint32(
        segmentOffset + layout.resumeTimestampOffset,
        Endian.little,
      );
      final initialAltitudeOffset = layout.initialAltitudeOffset;
      if (initialAltitudeOffset != null) {
        final initial = view.getFloat32(
          segmentOffset + initialAltitudeOffset,
          Endian.little,
        );
        if (initial.isFinite) cumulativeAltitude = initial;
      }
      if (count == 0 || count > 24 * 60 * 60) break;
      offset += layout.segmentHeaderBytes;
      if (offset + count * pointBytes > limit) break;
      for (var index = 0; index < count; index++) {
        int? heartRate;
        int? bloodOxygen;
        int? stress;
        int? stride;
        int? pace;
        double? speed;
        double? altitude;
        int? cadence;
        int? power;
        int? jumpFrequency;
        int? jumpHeight;
        int? strokeFrequency;
        for (final field in activeFields) {
          final valueOffset = offset;
          offset += field.byteSize;
          final fieldValid = bit(field.validBit);
          switch (field.kind) {
            case _WorkoutPointKind.caloriesAndSteps:
              final packed = view.getUint8(valueOffset);
              if (fieldValid) cumulativeCalories += packed >> 4;
              if (bit(field.validBit + 1)) cumulativeSteps += packed & 0x0f;
            case _WorkoutPointKind.calories:
              if (fieldValid) cumulativeCalories += view.getUint8(valueOffset);
            case _WorkoutPointKind.heartRate:
              if (fieldValid) heartRate = view.getUint8(valueOffset);
            case _WorkoutPointKind.bloodOxygen:
              if (fieldValid) bloodOxygen = view.getUint8(valueOffset);
            case _WorkoutPointKind.stress:
              if (fieldValid) stress = view.getUint8(valueOffset);
            case _WorkoutPointKind.altitudeInt10:
              if (fieldValid) {
                altitude = view.getInt32(valueOffset, Endian.little) / 10;
              }
            case _WorkoutPointKind.altitudeFloat:
              if (fieldValid) {
                altitude = view.getFloat32(valueOffset, Endian.little);
              }
            case _WorkoutPointKind.altitudeDeltaTenths:
              if (fieldValid) {
                final packed = view.getUint8(valueOffset);
                final delta = (packed & 0x3f) / 10;
                cumulativeAltitude =
                    (cumulativeAltitude ?? 0) +
                    ((packed & 0x40) == 0 ? -delta : delta);
                altitude = cumulativeAltitude;
              }
            case _WorkoutPointKind.distance8:
              if (fieldValid) {
                cumulativeDistanceTenths += view.getUint8(valueOffset) * 10;
              }
            case _WorkoutPointKind.distance8Tenths:
              if (fieldValid) {
                cumulativeDistanceTenths += view.getUint8(valueOffset);
              }
            case _WorkoutPointKind.distance15:
              if (fieldValid) {
                cumulativeDistanceTenths +=
                    (view.getUint16(valueOffset, Endian.little) & 0x7fff) * 10;
              }
            case _WorkoutPointKind.stride:
              if (fieldValid) stride = view.getUint8(valueOffset);
            case _WorkoutPointKind.cadence:
              if (fieldValid) cadence = view.getUint8(valueOffset);
            case _WorkoutPointKind.pace:
              if (fieldValid) {
                pace = view.getUint16(valueOffset, Endian.little);
              }
            case _WorkoutPointKind.speed:
              if (fieldValid) {
                speed = view.getUint16(valueOffset, Endian.little) / 10;
              }
            case _WorkoutPointKind.power:
              if (fieldValid) {
                power = view.getUint16(valueOffset, Endian.little);
              }
            case _WorkoutPointKind.jumpFrequency:
              if (fieldValid) {
                jumpFrequency = view.getUint16(valueOffset, Endian.little);
              }
            case _WorkoutPointKind.jumpHeight:
              if (fieldValid) jumpHeight = view.getUint8(valueOffset);
            case _WorkoutPointKind.strokeFrequency:
              if (fieldValid) strokeFrequency = view.getUint8(valueOffset);
            case _WorkoutPointKind.skip:
              break;
          }
        }
        final sampleTimestamp = resumeSeconds == 0
            ? fileTimestamp + index
            : resumeSeconds + index;
        samples.add(
          XiaomiWorkoutSampleRecord(
            timestamp: _activityTimestamp(sampleTimestamp),
            heartRate: heartRate,
            bloodOxygen: bloodOxygen,
            stress: stress,
            calories: cumulativeCalories == 0 ? null : cumulativeCalories,
            steps: cumulativeSteps == 0 ? null : cumulativeSteps,
            distanceMeters: cumulativeDistanceTenths == 0
                ? null
                : (cumulativeDistanceTenths / 10).round(),
            altitudeMeters: altitude,
            paceSecondsPerKilometer: pace,
            speedKph: speed,
            cadence: cadence,
            powerWatts: power,
            strideCentimeters: stride,
            jumpFrequency: jumpFrequency,
            jumpHeightCentimeters: jumpHeight,
            strokeFrequency: strokeFrequency,
          ),
        );
      }
    }
    if (samples.isEmpty) return null;
    return XiaomiActivityWorkoutRecord(
      startedAt: samples.first.timestamp,
      endedAt: samples.last.timestamp.add(const Duration(seconds: 1)),
      activityType: subtype,
      samples: samples,
    );
  }

  _WorkoutRecordLayout? _workoutRecordLayout(int subtype, int version) =>
      switch ((subtype, version)) {
        (22, 5) => _outdoorFootRecordV5,
        (22, 8) => _outdoorFootRecordV8,
        (22, 9) => _outdoorFootRecordV9,
        (23, 5) => _outdoorNonFootRecordV5,
        (23, 6) => _outdoorNonFootRecordV6,
        (23, 7) => _outdoorNonFootRecordV7,
        (3, 9) => _indoorRunRecordV9,
        (3, 10) => _indoorRunRecordV10,
        (7, 6) => _indoorCyclingRecordV6,
        (8, 4) => _freeTrainingRecordV4,
        (8, 5) => _freeTrainingRecordV5,
        (8, 6) => _freeTrainingRecordV6,
        (11, 3) => _ellipticalRecordV3,
        (13, 4) => _rowingRecordV4,
        (14, 6) => _ropeSkippingRecordV6,
        _ => null,
      };

  XiaomiActivityWorkoutRecord? _parseSwimmingSamples(
    Uint8List data,
    int fileTimestamp,
    int subtype,
  ) {
    const validityBytes = 3;
    final limit = data.length - 4;
    var offset = 8 + validityBytes;
    if (offset + 8 > limit) return null;
    final view = ByteData.sublistView(data);
    final validity = data.sublist(8, 8 + validityBytes);
    bool valid(int index) =>
        (validity[index ~/ 8] & (1 << (7 - index % 8))) != 0;
    final samples = <XiaomiWorkoutSampleRecord>[];
    while (offset + 8 <= limit) {
      final recordCount = view.getUint32(offset, Endian.little);
      final resumeSeconds = view.getUint32(offset + 4, Endian.little);
      offset += 8;
      if (recordCount == 0 || recordCount > 10000) break;
      for (var recordIndex = 0; recordIndex < recordCount; recordIndex++) {
        if (offset + 10 > limit) break;
        final dataType = view.getUint8(offset);
        final endSeconds = view.getUint32(offset + 1, Endian.little);
        final stroke = view.getUint8(offset + 5);
        final pace = view.getUint16(offset + 6, Endian.little);
        final swolf = view.getUint16(offset + 8, Endian.little);
        offset += 10;
        int? distance;
        int? activeCalories;
        int? strokeFrequency;
        var heartRateCount = 0;
        if (dataType == 0) {
          if (offset + 25 > limit) return null;
          distance = view.getUint16(offset, Endian.little);
          activeCalories = view.getUint16(offset + 2, Endian.little);
          strokeFrequency = view.getUint8(offset + 8);
          heartRateCount = view.getUint32(offset + 21, Endian.little);
          offset += 25;
          if (heartRateCount > 24 * 60 * 60 ||
              offset + heartRateCount > limit) {
            return null;
          }
        }
        final endTimestamp = endSeconds == 0
            ? _activityTimestamp(resumeSeconds + recordIndex)
            : _activityTimestamp(endSeconds);
        samples.add(
          XiaomiWorkoutSampleRecord(
            timestamp: endTimestamp,
            calories: valid(5) ? activeCalories : null,
            distanceMeters: valid(4) ? distance : null,
            strokeFrequency: valid(8) ? strokeFrequency : null,
            swimmingStroke: valid(1) ? stroke : null,
            swolf: valid(3) ? swolf : null,
            swimmingPaceSecondsPer100Meters: valid(2) ? pace : null,
          ),
        );
        for (
          var heartRateIndex = 0;
          heartRateIndex < heartRateCount;
          heartRateIndex++
        ) {
          final heartRate = view.getUint8(offset++);
          samples.add(
            XiaomiWorkoutSampleRecord(
              timestamp: endTimestamp.subtract(
                Duration(seconds: heartRateCount - heartRateIndex - 1),
              ),
              // Zero is a source value, not a parser error. Keep it in the
              // raw workout series so the chart can show an explicit zero
              // sample and let summary/statistics decide whether it is
              // physiologically usable.
              heartRate: heartRate,
            ),
          );
        }
      }
    }
    if (samples.isEmpty) return null;
    samples.sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return XiaomiActivityWorkoutRecord(
      startedAt: _activityTimestamp(fileTimestamp),
      endedAt: samples.last.timestamp,
      activityType: subtype,
      samples: samples,
    );
  }

  XiaomiActivityWorkoutRecord? _parseWorkoutRoute(
    Uint8List data,
    int fileTimestamp,
    int subtype,
    int version,
  ) {
    if (version == 2) {
      return _parseWorkoutRouteV2(data, subtype);
    }
    final validityBytes = switch ((subtype, version)) {
      (22, 5) => 2,
      (22, 3) || (22, 4) || (23, 3) || (23, 4) || (9, 3) || (10, 3) => 1,
      _ => null,
    };
    if (validityBytes == null) return null;
    final limit = data.length - 4;
    final bodyOffset = 8 + validityBytes;
    if (bodyOffset + 4 > limit) return null;
    final view = ByteData.sublistView(data);
    final count = view.getUint32(bodyOffset, Endian.little);
    final hasRunway = subtype == 22 && version == 5;
    final pointBytes = hasRunway ? 27 : 26;
    if (count > 100000 || bodyOffset + 4 + count * pointBytes > limit) {
      return null;
    }
    final route = <XiaomiWorkoutRoutePoint>[];
    var offset = bodyOffset + 4;
    for (var index = 0; index < count; index++) {
      final seconds = view.getUint32(offset, Endian.little);
      final longitude = view.getFloat32(offset + 4, Endian.little);
      final latitude = view.getFloat32(offset + 8, Endian.little);
      final accuracy = view.getFloat32(offset + 12, Endian.little);
      final speedAndSource = view.getUint16(offset + 16, Endian.little);
      final altitude = view.getFloat32(offset + 18, Endian.little);
      if (seconds != 0 &&
          latitude.isFinite &&
          longitude.isFinite &&
          latitude.abs() <= 90 &&
          longitude.abs() <= 180) {
        route.add(
          XiaomiWorkoutRoutePoint(
            timestamp: _activityTimestamp(seconds),
            latitude: latitude,
            longitude: longitude,
            altitudeMeters: altitude.isFinite ? altitude : null,
            speedMetersPerSecond: ((speedAndSource >> 4) / 10),
            horizontalAccuracyMeters: accuracy.isFinite ? accuracy : null,
          ),
        );
      }
      offset += pointBytes;
    }
    if (route.isEmpty) return null;
    return XiaomiActivityWorkoutRecord(
      startedAt: route.first.timestamp,
      endedAt: route.last.timestamp,
      activityType: subtype,
      route: route,
    );
  }

  // Workout GPS v2 (Gadgetbridge layout): 1-byte header, then a stream of
  // 18-byte points read to EOF (no leading point count). Point layout:
  // time(u32) | longitude(f32) | latitude(f32) | horizontalAccuracy(f32) |
  // locationSpeedAndGpsSource(u16: high 12 bits = 0.1 m/s). No altitude field.
  XiaomiActivityWorkoutRecord? _parseWorkoutRouteV2(
    Uint8List data,
    int subtype,
  ) {
    const headerBytes = 1;
    const pointBytes = 18;
    final limit = data.length - 4;
    final bodyOffset = 8 + headerBytes;
    if (bodyOffset + pointBytes > limit) return null;
    final view = ByteData.sublistView(data);
    final route = <XiaomiWorkoutRoutePoint>[];
    var offset = bodyOffset;
    while (offset + pointBytes <= limit) {
      final seconds = view.getUint32(offset, Endian.little);
      final longitude = view.getFloat32(offset + 4, Endian.little);
      final latitude = view.getFloat32(offset + 8, Endian.little);
      final accuracy = view.getFloat32(offset + 12, Endian.little);
      final speedAndSource = view.getUint16(offset + 16, Endian.little);
      if (seconds != 0 &&
          latitude.isFinite &&
          longitude.isFinite &&
          latitude.abs() <= 90 &&
          longitude.abs() <= 180) {
        route.add(
          XiaomiWorkoutRoutePoint(
            timestamp: _activityTimestamp(seconds),
            latitude: latitude,
            longitude: longitude,
            speedMetersPerSecond: ((speedAndSource >> 4) / 10),
            horizontalAccuracyMeters: accuracy.isFinite ? accuracy : null,
          ),
        );
      }
      offset += pointBytes;
    }
    if (route.isEmpty) return null;
    return XiaomiActivityWorkoutRecord(
      startedAt: route.first.timestamp,
      endedAt: route.last.timestamp,
      activityType: subtype,
      route: route,
    );
  }

  XiaomiActivityWorkoutRecord? _parseWorkoutRecovery(
    Uint8List data,
    int fileTimestamp,
    int subtype,
    int version,
  ) {
    if (version != 1) return null;
    final limit = data.length - 4;
    if (limit < 16) return null;
    final view = ByteData.sublistView(data);
    final startSeconds = view.getUint32(8, Endian.little);
    final count = view.getUint16(14, Endian.little);
    if (16 + count > limit) return null;
    final recovery = XiaomiWorkoutHeartRateRecovery(
      startedAt: _activityTimestamp(
        startSeconds == 0 ? fileTimestamp : startSeconds,
      ),
      recoveredHeartRate: data[12] == 0 ? null : data[12],
      recoveryRate: data[13] == 0 ? null : data[13],
      heartRates: data
          .sublist(16, 16 + count)
          .where((value) => value >= 30 && value <= 240)
          .toList(growable: false),
    );
    return XiaomiActivityWorkoutRecord(
      startedAt: _activityTimestamp(fileTimestamp),
      endedAt: recovery.startedAt,
      activityType: subtype,
      recovery: recovery,
    );
  }

  List<XiaomiActivityAbnormalHealthRecord> _parseAbnormalHealth(
    Uint8List data,
    int version,
  ) {
    // Mi Fitness' native AbnormalRecordParser supports only v1/v2 here. The
    // parser's binary body follows the seven-byte FitnessDataId and the
    // reserved header byte. Older captures in the wild omitted that reserved
    // byte, so retain a guarded compatibility fallback for those snapshots.
    if (version != 1 && version != 2) return const [];
    final limit = data.length - 4;
    const officialHeaderSize = 8;
    if (limit < 7 + 13) return const [];

    final view = ByteData.sublistView(data);
    var offset = officialHeaderSize;
    if (!_looksLikeAbnormalSegment(view, data, offset, limit)) {
      offset = 7;
    }
    final records = <XiaomiActivityAbnormalHealthRecord>[];
    while (offset + 13 <= limit) {
      final startedSeconds = view.getUint32(offset, Endian.little);
      final endedSeconds = view.getUint32(offset + 4, Endian.little);
      final type = data[offset + 8];
      final threshold = view.getUint16(offset + 9, Endian.little);
      final count = view.getUint16(offset + 11, Endian.little);
      offset += 13;

      if (offset + count * 5 > limit) break;
      final kind = switch (type) {
        1 => XiaomiActivityAbnormalHealthKind.highHeartRate,
        2 => XiaomiActivityAbnormalHealthKind.lowHeartRate,
        3 => XiaomiActivityAbnormalHealthKind.lowBloodOxygen,
        4 => XiaomiActivityAbnormalHealthKind.highStress,
        5 => XiaomiActivityAbnormalHealthKind.irregularHeartbeat,
        _ => null,
      };
      final startedAt = startedSeconds == 0
          ? null
          : _activityTimestamp(startedSeconds);
      final endedAt = endedSeconds == 0
          ? null
          : _activityTimestamp(endedSeconds);
      if (count == 0) {
        if (kind == XiaomiActivityAbnormalHealthKind.irregularHeartbeat) {
          final eventStart = startedAt ?? endedAt;
          if (eventStart != null) {
            records.add(
              XiaomiActivityAbnormalHealthRecord(
                timestamp: eventStart,
                kind: XiaomiActivityAbnormalHealthKind.irregularHeartbeat,
                startedAt: eventStart,
                endedAt: endedAt ?? startedAt,
              ),
            );
          }
        }
        continue;
      }
      DateTime? firstSampleAt;
      DateTime? lastSampleAt;
      for (var index = 0; index < count; index++) {
        final timestampSeconds = view.getUint32(offset, Endian.little);
        final value = data[offset + 4];
        offset += 5;
        if (timestampSeconds == 0) continue;
        final sampleAt = _activityTimestamp(timestampSeconds);
        firstSampleAt ??= sampleAt;
        lastSampleAt = sampleAt;
        if (kind == null ||
            kind == XiaomiActivityAbnormalHealthKind.irregularHeartbeat) {
          continue;
        }
        records.add(
          XiaomiActivityAbnormalHealthRecord(
            timestamp: sampleAt,
            value: value,
            kind: kind,
            threshold: threshold,
            startedAt: startedAt,
            endedAt: endedAt,
          ),
        );
      }
      if (kind == XiaomiActivityAbnormalHealthKind.irregularHeartbeat) {
        final eventStart = startedAt ?? firstSampleAt ?? endedAt;
        final eventEnd = endedAt ?? lastSampleAt ?? startedAt;
        if (eventStart != null) {
          records.add(
            XiaomiActivityAbnormalHealthRecord(
              timestamp: eventStart,
              kind: XiaomiActivityAbnormalHealthKind.irregularHeartbeat,
              startedAt: eventStart,
              endedAt: eventEnd,
            ),
          );
        }
      }
    }
    return records;
  }

  bool _looksLikeAbnormalSegment(
    ByteData view,
    Uint8List data,
    int offset,
    int limit,
  ) {
    if (offset + 13 > limit) return false;
    final type = data[offset + 8];
    if (type < 1 || type > 5) return false;
    final count = view.getUint16(offset + 11, Endian.little);
    return offset + 13 + count * 5 <= limit;
  }

  XiaomiActivityDailyRecord? _parseDaily(
    Uint8List data,
    int timestamp,
    int version,
  ) {
    // Mi Fitness' dailyType=0/fileType=1 is DailyReportParser.  Its
    // one-dimensional validity bitmap has 35 fields and is followed by the
    // fields in the fixed order below.  This is deliberately separate from
    // the packed minute records handled by _parseDailyDetails.
    const fieldSizes = <int>[
      4,
      2,
      1,
      1,
      1,
      4,
      1,
      4,
      1,
      1,
      1,
      1,
      3,
      2,
      2,
      1,
      1,
      4,
      1,
      4,
      1,
      2,
      2,
      1,
      1,
      1,
      1,
      2,
      1,
      1,
      2,
      2,
      2,
      2,
      2,
    ];
    const fieldSupportVersions = <int>[
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      2,
      2,
      3,
      3,
      3,
      3,
      3,
      3,
      4,
      4,
      4,
      5,
      5,
      5,
      5,
      5,
      5,
      6,
      6,
      6,
      6,
      7,
    ];
    final headerSize = switch (version) {
      1 || 2 => 2,
      3 || 4 => 3,
      5 => 4,
      6 || 7 => 5,
      _ => 0,
    };
    final limit = data.length - 4;
    final payloadSize = fieldSizes
        .asMap()
        .entries
        // Some v7 devices omit the optional trailing floors field entirely
        // when its validity bit is clear. Keep the legacy minimum-size guard
        // for the stable report body and let read(34) validate the tail.
        .where((entry) => entry.key < 34)
        .where((entry) => fieldSupportVersions[entry.key] <= version)
        .fold(0, (sum, entry) => sum + entry.value);
    if (headerSize == 0 || limit < 8 + headerSize + payloadSize) {
      return null;
    }
    final view = ByteData.sublistView(data);
    var offset = 8 + headerSize;
    int? read(int field) {
      if (fieldSupportVersions[field] > version) return null;
      final size = fieldSizes[field];
      if (offset + size > limit) return null;
      final value = switch (size) {
        1 => view.getUint8(offset),
        2 when field == 30 => view.getInt16(offset, Endian.little),
        2 => view.getUint16(offset, Endian.little),
        3 =>
          view.getUint8(offset) |
              (view.getUint8(offset + 1) << 8) |
              (view.getUint8(offset + 2) << 16),
        4 => view.getUint32(offset, Endian.little),
        _ => throw StateError('Unsupported Xiaomi daily report field size'),
      };
      offset += size;
      return value;
    }

    final values = <int, int?>{};
    final validFields = <int, bool>{};
    var validityIndex = 0;
    for (var field = 0; field < fieldSizes.length; field++) {
      if (fieldSupportVersions[field] > version) continue;
      validFields[field] =
          (data[8 + validityIndex ~/ 8] & (1 << (7 - validityIndex % 8))) != 0;
      validityIndex++;
      values[field] = read(field);
    }
    bool valid(int field) => validFields[field] ?? false;
    int? value(int field) => valid(field) ? values[field] : null;
    return XiaomiActivityDailyRecord(
      date: _activityTimestamp(timestamp),
      steps: value(0),
      activeCalories: value(1),
      calories: value(13),
      // Slot 2 is reserved. Its byte is consumed above, but not exposed.
      restingHeartRate: value(3),
      maxHeartRate: value(4),
      maxHeartRateAt: _activityTime(value(5)),
      minHeartRate: value(6),
      minHeartRateAt: _activityTime(value(7)),
      averageHeartRate: value(8),
      averageStress: value(9),
      maxStress: value(10),
      minStress: value(11),
      standingBitmap: value(12),
      remainingRecoveryHours: value(14),
      currentBloodOxygen: value(15),
      maxBloodOxygen: value(16),
      maxBloodOxygenAt: _activityTime(value(17)),
      minBloodOxygen: value(18),
      minBloodOxygenAt: _activityTime(value(19)),
      averageBloodOxygen: value(20),
      floorsClimbed: value(34),
      trainingLoadToday: value(21),
      trainingLoadLast7Days: value(22),
      trainingLoadLevel: value(23),
      vitalityIncreaseLight: value(24),
      vitalityIncreaseModerate: value(25),
      vitalityIncreaseHigh: value(26),
      // Field 27 is the device's running 7-day total. It skips zero days on
      // some firmwares, so the per-day earned value is reconstructed from the
      // intensity buckets and the calendar-window total is summed by the UI.
      vitalityCurrent: _vitalityDayTotal(value(24), value(25), value(26)),
      vitalityLast7Days: value(27),
      vitalityNextTargetType: value(28),
      vitalityNextTargetMinutes: value(29),
      fitnessBalance: value(30),
      fitnessLevel: value(31),
      fatigueLevel: value(32),
      trainingStressScore: value(33),
    );
  }

  DateTime? _activityTime(int? seconds) =>
      seconds == null || seconds == 0 ? null : _activityTimestamp(seconds);

  /// Per-day earned vitality reconstructed from the intensity buckets.
  ///
  /// The daily report only carries a running 7-day total, not the day's own
  /// earned points. Summing the light/moderate/high buckets keeps zero days
  /// explicit so the 7-day window is a real calendar sum.
  int? _vitalityDayTotal(int? light, int? moderate, int? high) {
    if (light == null && moderate == null && high == null) return null;
    return (light ?? 0) + (moderate ?? 0) + (high ?? 0);
  }

  List<XiaomiActivitySampleRecord> _parseManualMeasures(
    Uint8List data,
    int timestamp,
    int version,
  ) {
    // FitnessDataHeader is: seven-byte FitnessDataId, one reserved byte and
    // (for v1 only) one validity byte. Mi Fitness' ManualMeasureParser then
    // reads a repeated timestamp/type/value stream.
    final valueOffset = version == 1 ? 9 : 8;
    final limit = data.length - 4;
    if ((version != 1 && version != 2 && version != 3) ||
        limit <= valueOffset) {
      return const [];
    }

    final view = ByteData.sublistView(data);
    var offset = valueOffset;
    final values = <int, _ManualMeasureValues>{};
    while (offset + 5 <= limit) {
      final sampleTimestamp = view.getUint32(offset, Endian.little);
      final encodedType = data[offset + 4];
      offset += 5;

      final type = version == 1 ? encodedType : encodedType & 0x0f;
      final valueLength = version == 1
          ? _manualValueLength(type)
          : encodedType >> 4;
      if (valueLength == null ||
          valueLength <= 0 ||
          offset + valueLength > limit) {
        _log.fine(
          'Xiaomi manual measure stream stopped at '
          'type=$type length=$valueLength',
        );
        break;
      }

      if (type == 1 || type == 2 || type == 3) {
        final value = switch (valueLength) {
          1 => data[offset],
          2 => view.getUint16(offset, Endian.little),
          _ => null,
        };
        if (value != null && sampleTimestamp > 0) {
          final record = values.putIfAbsent(
            sampleTimestamp,
            _ManualMeasureValues.new,
          );
          switch (type) {
            case 1:
              record.heartRate = value;
            case 2:
              record.bloodOxygen = value;
            case 3:
              record.stress = value;
          }
        }
      }
      // Types 4 and 5 are temperature and blood pressure. They are consumed
      // here exactly as Mi Fitness does, even though the current health model
      // has no cards for those measurements yet.
      offset += valueLength;
    }

    final result = values.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return result
        .map(
          (entry) => XiaomiActivitySampleRecord(
            timestamp: _activityTimestamp(entry.key),
            heartRate: entry.value.heartRate,
            bloodOxygen: entry.value.bloodOxygen,
            stress: entry.value.stress,
          ),
        )
        .toList(growable: false);
  }

  int? _manualValueLength(int type) => switch (type) {
    1 || 2 || 3 => 1,
    4 => 4,
    5 => 6,
    _ => null,
  };

  List<XiaomiActivitySampleRecord> _parseDailyDetails(
    Uint8List data,
    int timestamp,
    int version,
  ) {
    // This is the same four-dimensional record layout used by Mi Fitness'
    // DailyRecordParser.  Each validity nibble describes one packed group;
    // groups that are absent do not occupy bytes in the record.
    final groups = version == 1 ? _dailyRecordV1Groups : _dailyRecordV2Groups;
    final headerSize = switch (version) {
      1 || 2 => 4,
      3 => 5,
      4 || 5 => 6,
      _ => 0,
    };
    final limit = data.length - 4;
    if (headerSize == 0 || limit < 8 + headerSize) {
      return const [];
    }

    final validity = data.sublist(8, 8 + headerSize);
    final samples = <XiaomiActivitySampleRecord>[];
    var offset = 8 + headerSize;
    var sampleIndex = 0;
    while (offset < limit) {
      final values = <int, int>{};
      var validityIndex = 0;
      final dynamicAnchorType = switch (version) {
        1 => 13,
        2 => 11,
        _ => 15,
      };
      var dynamicConsumed = false;
      for (final group in groups) {
        if (group.minimumVersion > version) continue;
        final validityByte = validity[validityIndex ~/ 2];
        final shift = validityIndex.isEven ? 4 : 0;
        final flags = (validityByte >> shift) & 0x0f;
        validityIndex++;
        if ((flags & 8) == 0) continue;
        if (offset + group.byteSize > limit) return samples;

        // A few older Vela files use the high validity bit only and leave the
        // per-field bits in the reserved pattern used by the legacy parser.
        // Mi Fitness consumes the whole group in that case. Keep this narrow
        // compatibility path so those files do not lose steps and samples,
        // while using the official field bits whenever any are present.
        final hasOfficialField = group.fields.any(
          (field) => (flags & field.validityBit) != 0,
        );

        final raw = switch (group.byteSize) {
          1 => data[offset],
          2 => ByteData.sublistView(data).getUint16(offset, Endian.little),
          _ => throw StateError('Unsupported Xiaomi daily record group size'),
        };
        offset += group.byteSize;
        for (final field in group.fields) {
          if (!hasOfficialField && (flags & 8) == 0) continue;
          if (hasOfficialField && (flags & field.validityBit) == 0) continue;
          values[field.type] =
              (raw >> field.startBit) & ((1 << field.bitSize) - 1);
        }

        // The dynamic type-16 byte follows the last fixed data-info entry
        // supported by the version. Unsupported v2 entries for SpO2/stress
        // therefore do not move this boundary earlier than the official
        // parser does.
        if (!dynamicConsumed &&
            group.fields.any((field) => field.type == dynamicAnchorType) &&
            values[1] == 1) {
          if (offset >= limit) return samples;
          offset++;
          dynamicConsumed = true;
        }
      }

      // Mi Fitness consumes this dynamic byte when the daily record says an
      // abnormal-heart-rate value is present. It is not exposed as a minute
      // sample; the dedicated dailyType=9 file supplies the event details.
      if (!dynamicConsumed && values[1] == 1) {
        if (offset >= limit) return samples;
        offset++;
      }

      if (values.isEmpty) {
        if (offset <= 8 + headerSize) break;
        sampleIndex++;
        continue;
      }
      int? steps;
      int? activityType;
      int? activityStrength;
      int? sportType;
      int? activeCalories;
      int? distanceMeters;
      int? heartRate;
      int? energy;
      int? caloriesDelta;
      int? energyStatus;
      int? energyStatusValue;
      int? bloodOxygen;
      int? pressure;
      int? lightSensation;
      int? volumeMomentum;
      int? floors;
      int? stress;

      steps = values[2];
      activityType = values[3];
      activeCalories = values[4];
      activityStrength = values[5];
      sportType = values[6];
      distanceMeters = values[7];
      heartRate = values[8];
      energy = values[9];
      // `newCalories` is an increment for this minute. A total is only
      // available in the daily report (`totalCalories`), parsed separately.
      caloriesDelta = values[10] ?? values[11];
      energyStatus = values[12];
      energyStatusValue = values[13];
      bloodOxygen = values[14];
      // The VelaOS record field is named `curPressure`, but it is the
      // minute-level stress value shown by Mi Fitness. Expose it as both the
      // raw pressure field and the stress metric so the stress series is not
      // empty while the daily summary still has a value.
      pressure = values[15];
      stress = values[15];
      lightSensation = values[17];
      volumeMomentum = values[18];
      floors = values[19];
      samples.add(
        XiaomiActivitySampleRecord(
          timestamp: _activityTimestamp(timestamp + sampleIndex * 60),
          activityType: activityType,
          activityStrength: activityStrength,
          sportType: sportType,
          steps: steps,
          activeCalories: activeCalories,
          distanceMeters: distanceMeters,
          heartRate: heartRate,
          energy: energy,
          caloriesDelta: caloriesDelta,
          energyStatus: energyStatus,
          energyStatusValue: energyStatusValue,
          bloodOxygen: bloodOxygen,
          pressure: pressure,
          lightSensation: lightSensation,
          volumeMomentum: volumeMomentum,
          floors: floors,
          stress: stress,
        ),
      );
      sampleIndex++;
    }
    return samples;
  }

  XiaomiActivityWorkoutRecord? _parseWorkoutSummary(
    Uint8List data,
    int timestamp,
    int subtype,
    int version,
  ) {
    // Keep the compact report decoder used by HEAD as the compatibility
    // anchor. Some Vela/S5 firmwares advertise a newer schema version while
    // still emitting this older wire layout; rejecting that report makes the
    // whole workout history disappear even though the file transferred
    // successfully. When both decoders recognize a file, merge the richer
    // fields instead of choosing one representation.
    final legacy = _parseLegacyWorkoutSummary(
      data,
      timestamp,
      subtype,
      version,
    );
    final current = _parseWorkoutSummaryCurrent(
      data,
      timestamp,
      subtype,
      version,
    );
    if (legacy != null && current != null) {
      // Field-level conflicts must resolve in favor of the current-schema
      // decoder: `_mergeWorkoutRecord` keeps the left record's non-null
      // values when both sides carry summary fields. Legacy remains the
      // fallback for whole-file decode failures only.
      return _mergeWorkoutRecord(current, legacy);
    }
    return current ?? legacy;
  }

  XiaomiActivityWorkoutRecord? _parseWorkoutSummaryCurrent(
    Uint8List data,
    int timestamp,
    int subtype,
    int version,
  ) {
    final modern = _modernWorkoutReportFields(subtype, version);
    if (modern != null) {
      return _parseModernWorkoutSummary(data, subtype, version, modern);
    }
    final fields = _sportReportFields(subtype);
    final validityLength = _sportReportValidityLength(subtype, version);
    final limit = data.length - 4;
    if (fields == null ||
        validityLength == null ||
        limit < 8 + validityLength) {
      return null;
    }
    final view = ByteData.sublistView(data);
    final valid = data.sublist(8, 8 + validityLength);
    final values = <int, int>{};
    var offset = 8 + validityLength;
    var validIndex = 0;
    for (final field in fields) {
      final supported = field.minimumVersion <= version;
      final isValid =
          supported &&
          validIndex ~/ 8 < valid.length &&
          (valid[validIndex ~/ 8] & (1 << (7 - validIndex % 8))) != 0;
      if (supported) validIndex++;
      if (!supported) continue;
      if (offset + field.byteSize > limit) return null;
      final value = switch (field.byteSize) {
        1 => view.getUint8(offset),
        2 => view.getUint16(offset, Endian.little),
        4 => view.getUint32(offset, Endian.little),
        _ => throw StateError('Unsupported Xiaomi sport report field size'),
      };
      offset += field.byteSize;
      if (isValid) values[field.type] = value;
    }

    final started = values[1];
    final ended = values[2];
    if (started == null || ended == null || started == 0 || ended <= started) {
      return null;
    }
    return XiaomiActivityWorkoutRecord(
      startedAt: _activityTimestamp(started),
      endedAt: _activityTimestamp(ended),
      activityType: subtype,
      distanceMeters: values[5],
      calories: values[6],
      averageHeartRate: values[16],
      maximumHeartRate: values[17],
      minimumHeartRate: values[18],
    );
  }

  XiaomiActivityWorkoutRecord? _parseLegacyWorkoutSummary(
    Uint8List data,
    int timestamp,
    int subtype,
    int version,
  ) {
    final headerSize = _legacyWorkoutHeaderSize(subtype, version);
    final limit = data.length - 4;
    if (headerSize == 0 || limit < 8 + headerSize + 8) return null;
    final view = ByteData.sublistView(data);
    var offset = 8 + headerSize;
    if (subtype == 0x16 || subtype == 0x17) {
      if (offset + 2 > limit) return null;
      offset += 2;
    }
    if (offset + 8 > limit) return null;
    final started = view.getUint32(offset, Endian.little);
    final ended = view.getUint32(offset + 4, Endian.little);
    if (started == 0 || ended <= started) return null;

    int? distanceMeters;
    int? calories;
    final commonOffset = offset + 8;
    if (subtype == 0x16 || subtype == 0x17) {
      if (commonOffset + 14 <= limit) {
        distanceMeters = view.getUint32(commonOffset + 8, Endian.little);
        calories = view.getUint16(commonOffset + 12, Endian.little);
      }
    } else if (commonOffset + 6 <= limit) {
      if (subtype == 0x01 || subtype == 0x02) {
        if (commonOffset + 8 <= limit) {
          distanceMeters = view.getUint32(commonOffset + 4, Endian.little);
        }
        if (commonOffset + 10 <= limit) {
          calories = view.getUint16(commonOffset + 8, Endian.little);
        }
      } else {
        calories = view.getUint16(commonOffset + 4, Endian.little);
      }
    }
    return XiaomiActivityWorkoutRecord(
      startedAt: _activityTimestamp(started),
      endedAt: _activityTimestamp(ended),
      activityType: subtype,
      distanceMeters: distanceMeters,
      calories: calories,
    );
  }

  int _legacyWorkoutHeaderSize(int subtype, int version) => switch (subtype) {
    0x01 || 0x02 => version == 4 ? 4 : 0,
    0x03 => switch (version) {
      5 => 4,
      9 => 6,
      10 => 8,
      11 => 9,
      _ => 0,
    },
    0x06 || 0x07 => switch (version) {
      8 => 7,
      9 => 8,
      _ => 0,
    },
    0x08 => switch (version) {
      5 => 3,
      7 => 5,
      8 || 9 || 10 => 6,
      _ => 0,
    },
    0x09 => switch (version) {
      6 => 4,
      7 => 5,
      8 => 8,
      _ => 0,
    },
    0x0b => version >= 3 && version <= 6 ? 4 : 0,
    0x0d => switch (version) {
      4 => 4,
      6 || 7 => 5,
      _ => 0,
    },
    0x0e => version == 3 || version == 5 ? 5 : 0,
    0x10 => version == 5 ? 4 : 0,
    0x16 => switch (version) {
      1 => 5,
      4 => 7,
      5 || 6 => 9,
      9 => 13,
      _ => 0,
    },
    0x17 => version == 4 ? 5 : 0,
    _ => 0,
  };

  XiaomiActivityWorkoutRecord? _parseModernWorkoutSummary(
    Uint8List data,
    int subtype,
    int version,
    List<_ModernSportReportField> fields,
  ) {
    final validityLength = _sportReportValidityLength(subtype, version);
    final limit = data.length - 4;
    if (validityLength == null || limit < 8 + validityLength) return null;
    final validity = data.sublist(8, 8 + validityLength);
    final bodyOffset = 8 + validityLength;
    final view = ByteData.sublistView(data);
    final values = <_WorkoutReportValue, num>{};
    for (final field in fields) {
      final bitSet =
          field.validityIndex ~/ 8 < validity.length &&
          (validity[field.validityIndex ~/ 8] &
                  (1 << (7 - field.validityIndex % 8))) !=
              0;
      if (!bitSet && !field.always) {
        continue;
      }
      final offset = bodyOffset + field.offset;
      if (offset + field.byteSize > limit) return null;
      values[field.value] = switch (field.type) {
        _SportWireType.u8 => view.getUint8(offset),
        _SportWireType.u16 => view.getUint16(offset, Endian.little),
        _SportWireType.u32 => view.getUint32(offset, Endian.little),
        _SportWireType.f32 => view.getFloat32(offset, Endian.little),
      };
    }

    int? integer(_WorkoutReportValue value) => values[value]?.toInt();
    double? decimal(_WorkoutReportValue value) => values[value]?.toDouble();
    final started = integer(_WorkoutReportValue.startedAt);
    final ended = integer(_WorkoutReportValue.endedAt);
    if (started == null || ended == null || started == 0 || ended <= started) {
      return null;
    }
    final zones = <XiaomiWorkoutHeartRateZone>[];
    for (var zone = 1; zone <= 5; zone++) {
      final duration = integer(_heartRateZoneDurationValue(zone));
      if (duration == null) continue;
      zones.add(
        XiaomiWorkoutHeartRateZone(
          zone: zone,
          durationSeconds: duration,
          lowerLimit: integer(_heartRateZoneLowerValue(zone)),
        ),
      );
    }
    return XiaomiActivityWorkoutRecord(
      startedAt: _activityTimestamp(started),
      endedAt: _activityTimestamp(ended),
      activityType: subtype,
      subSportType: integer(_WorkoutReportValue.subSportType),
      totalDurationSeconds: integer(_WorkoutReportValue.totalDuration),
      effectiveDurationSeconds: integer(_WorkoutReportValue.effectiveDuration),
      distanceMeters: integer(_WorkoutReportValue.distance),
      calories:
          integer(_WorkoutReportValue.totalCalories) ??
          integer(_WorkoutReportValue.activeCalories),
      activeCalories: integer(_WorkoutReportValue.activeCalories),
      averagePaceSecondsPerKilometer: integer(_WorkoutReportValue.averagePace),
      bestPaceSecondsPerKilometer: integer(_WorkoutReportValue.bestPace),
      worstPaceSecondsPerKilometer: integer(_WorkoutReportValue.worstPace),
      averageSpeedKph: decimal(_WorkoutReportValue.averageSpeed),
      bestSpeedKph: decimal(_WorkoutReportValue.bestSpeed),
      totalSteps: integer(_WorkoutReportValue.totalSteps),
      averageStrideCentimeters: integer(_WorkoutReportValue.averageStride),
      averageCadence: integer(_WorkoutReportValue.averageCadence),
      maximumCadence: integer(_WorkoutReportValue.maximumCadence),
      averageHeartRate: integer(_WorkoutReportValue.averageHeartRate),
      maximumHeartRate: integer(_WorkoutReportValue.maximumHeartRate),
      minimumHeartRate: integer(_WorkoutReportValue.minimumHeartRate),
      averageBloodOxygen: integer(_WorkoutReportValue.averageBloodOxygen),
      maximumBloodOxygen: integer(_WorkoutReportValue.maximumBloodOxygen),
      minimumBloodOxygen: integer(_WorkoutReportValue.minimumBloodOxygen),
      averageStress: integer(_WorkoutReportValue.averageStress),
      maximumStress: integer(_WorkoutReportValue.maximumStress),
      minimumStress: integer(_WorkoutReportValue.minimumStress),
      totalAscentMeters: decimal(_WorkoutReportValue.totalAscent),
      totalDescentMeters: decimal(_WorkoutReportValue.totalDescent),
      averageAltitudeMeters: decimal(_WorkoutReportValue.averageAltitude),
      maximumAltitudeMeters: decimal(_WorkoutReportValue.maximumAltitude),
      minimumAltitudeMeters: decimal(_WorkoutReportValue.minimumAltitude),
      aerobicTrainingEffect: decimal(_WorkoutReportValue.aerobicEffect),
      anaerobicTrainingEffect: decimal(_WorkoutReportValue.anaerobicEffect),
      peakTrainingEffect: decimal(_WorkoutReportValue.peakEffect),
      vo2Max: integer(_WorkoutReportValue.vo2Max),
      bodyEnergyConsumption: integer(_WorkoutReportValue.bodyEnergy),
      expectedRecoveryHours: integer(_WorkoutReportValue.recoveryHours),
      trainingLoad: integer(_WorkoutReportValue.trainingLoad),
      earnedVitality: integer(_WorkoutReportValue.earnedVitality),
      heartRateZoneMethod: integer(_WorkoutReportValue.heartRateZoneMethod),
      heartRateZones: zones,
      averagePowerWatts: integer(_WorkoutReportValue.averagePower),
      maximumPowerWatts: integer(_WorkoutReportValue.maximumPower),
      totalArmPulls: integer(_WorkoutReportValue.totalArmPulls),
      mainSwimmingStroke: integer(_WorkoutReportValue.mainSwimmingStroke),
      averageStrokeFrequency: integer(_WorkoutReportValue.averageStrokeRate),
      maximumStrokeFrequency: integer(_WorkoutReportValue.maximumStrokeRate),
      turnCount: integer(_WorkoutReportValue.turnCount),
      averageSwolf: integer(_WorkoutReportValue.averageSwolf),
      bestSwolf: integer(_WorkoutReportValue.bestSwolf),
      poolWidthMeters: integer(_WorkoutReportValue.poolWidth),
      totalJumps: integer(_WorkoutReportValue.totalJumps),
      averageJumpFrequency: integer(_WorkoutReportValue.averageJumpRate),
      bestJumpFrequency: integer(_WorkoutReportValue.bestJumpRate),
      tripCount: integer(_WorkoutReportValue.tripCount),
      setCount: integer(_WorkoutReportValue.setCount),
      totalStrokes: integer(_WorkoutReportValue.totalStrokes),
      averageRowingFrequency: integer(_WorkoutReportValue.averageRowingRate),
      bestRowingFrequency: integer(_WorkoutReportValue.bestRowingRate),
    );
  }

  _WorkoutReportValue _heartRateZoneDurationValue(int zone) => switch (zone) {
    1 => _WorkoutReportValue.heartRateZone1Duration,
    2 => _WorkoutReportValue.heartRateZone2Duration,
    3 => _WorkoutReportValue.heartRateZone3Duration,
    4 => _WorkoutReportValue.heartRateZone4Duration,
    _ => _WorkoutReportValue.heartRateZone5Duration,
  };

  _WorkoutReportValue _heartRateZoneLowerValue(int zone) => switch (zone) {
    1 => _WorkoutReportValue.heartRateZone1Lower,
    2 => _WorkoutReportValue.heartRateZone2Lower,
    3 => _WorkoutReportValue.heartRateZone3Lower,
    4 => _WorkoutReportValue.heartRateZone4Lower,
    _ => _WorkoutReportValue.heartRateZone5Lower,
  };

  List<_ModernSportReportField>? _modernWorkoutReportFields(
    int subtype,
    int version,
  ) => switch ((subtype, version)) {
    (22, 8) || (22, 9) => _modernOutdoorFootReportFields,
    (22, 6) => _modernOutdoorFootV6ReportFields,
    (23, 8) => _modernOutdoorNonFootV8ReportFields,
    (23, 9) => _modernOutdoorNonFootV9ReportFields,
    (3, 13) => _modernIndoorRunV13ReportFields,
    (3, 14) => _modernIndoorRunV14ReportFields,
    (7, 10) => _modernIndoorCyclingV10ReportFields,
    (8, 11) || (8, 12) || (8, 13) || (8, 14) => _modernFreeTrainingReportFields,
    (9, 8) || (10, 8) => _modernSwimmingV8ReportFields,
    (11, 7) => _modernEllipticalV7ReportFields,
    (13, 8) => _modernRowingV8ReportFields,
    (14, 7) => _modernRopeSkippingV7ReportFields,
    _ => null,
  };

  List<_SportReportField>? _sportReportFields(int subtype) => switch (subtype) {
    // OutdoorSportReportParser and HikingReportParser share this prefix.
    1 || 2 || 4 || 5 || 15 => _sportOutdoorReportFields,
    3 => _sportIndoorRunReportFields,
    6 => _sportOutdoorBikingReportFields,
    7 => _sportIndoorBikingReportFields,
    8 || 12 || 14 || 16 || 18 || 19 => _sportSimpleReportFields,
    9 || 10 => _sportSwimmingReportFields,
    11 => _sportEllipticalReportFields,
    13 => _sportSimpleReportFields,
    21 => _sportSkiReportFields,
    _ => null,
  };

  int? _sportReportValidityLength(int subtype, int version) {
    if (version <= 0) return null;
    return switch (subtype) {
      1 || 2 || 4 || 5 =>
        version <= 3
            ? 4
            : version == 4
            ? 5
            : null,
      15 =>
        version <= 2
            ? 4
            : version == 3
            ? 5
            : null,
      3 => switch (version) {
        1 || 2 || 3 => 3,
        4 || 5 => 4,
        6 => 5,
        7 || 8 || 9 => 6,
        10 => 8,
        11 => 9,
        12 => 11,
        13 => 12,
        14 => 13,
        _ => null,
      },
      6 =>
        version <= 3
            ? 4
            : version == 4
            ? 5
            : null,
      7 =>
        version <= 2
            ? 2
            : version <= 4
            ? 3
            : version <= 6
            ? 5
            : version == 7
            ? 6
            : version == 8
            ? 7
            : version == 9
            ? 8
            : version == 10
            ? 9
            : null,
      8 =>
        version <= 2
            ? 2
            : version <= 5
            ? 3
            : version == 6
            ? 4
            : version == 7
            ? 5
            : version <= 10
            ? 6
            : version <= 12
            ? 7
            : version <= 14
            ? 8
            : null,
      9 || 10 =>
        version == 1
            ? 2
            : version <= 4
            ? 3
            : version <= 6
            ? 4
            : version == 7
            ? 5
            : version == 8
            ? 8
            : null,
      11 =>
        version <= 2
            ? 3
            : version <= 6
            ? 4
            : version == 7
            ? 6
            : null,
      12 =>
        version == 1
            ? 2
            : version <= 3
            ? 3
            : version <= 6
            ? 4
            : version == 7
            ? 5
            : null,
      13 =>
        version == 1
            ? 3
            : version <= 4
            ? 4
            : version <= 7
            ? 5
            : version == 8
            ? 6
            : null,
      14 =>
        version <= 2
            ? 4
            : version <= 6
            ? 5
            : version == 7
            ? 6
            : null,
      16 =>
        version <= 2
            ? 3
            : version <= 6
            ? 4
            : version == 7
            ? 5
            : null,
      18 =>
        version == 1
            ? 4
            : version <= 4
            ? 5
            : version == 5
            ? 6
            : null,
      19 =>
        version <= 4
            ? 4
            : version == 5
            ? 5
            : null,
      20 =>
        version == 1
            ? 2
            : version <= 4
            ? 3
            : null,
      21 =>
        version == 1
            ? 5
            : version <= 4
            ? 6
            : version <= 6
            ? 7
            : null,
      22 =>
        version == 1
            ? 5
            : version <= 3
            ? 6
            : version == 4
            ? 7
            : version <= 6
            ? 9
            : version <= 8
            ? 12
            : version == 9
            ? 13
            : null,
      23 =>
        version <= 2
            ? 5
            : version <= 5
            ? 6
            : version == 6
            ? 7
            : version <= 8
            ? 8
            : version == 9
            ? 9
            : null,
      24 => version <= 2 ? 7 : null,
      25 => version <= 2 ? 4 : null,
      _ => null,
    };
  }

  List<XiaomiActivitySleepRecord> _parseSleep(
    Uint8List data,
    int timestamp,
    int version,
    int subtype,
  ) {
    if (subtype == 3 && version == 2) {
      final record = _parseSleepStages(data);
      return record == null ? const [] : [record];
    }
    final limit = data.length - 4;
    if (subtype == 8) {
      return _parseSleepDetails(data, version, limit);
    }
    if (limit < 37) return const [];
    final view = ByteData.sublistView(data);
    final offset = 8 + 7;
    final durationMinutes = view.getUint16(offset, Endian.little);
    final started = view.getUint32(offset + 2, Endian.little);
    final ended = view.getUint32(offset + 6, Endian.little);
    if (started == 0 || ended == 0 || durationMinutes == 0) return const [];
    return [
      XiaomiActivitySleepRecord(
        startedAt: _activityTimestamp(started),
        endedAt: _activityTimestamp(ended),
        durationSeconds: durationMinutes * 60,
      ),
    ];
  }

  List<XiaomiActivitySleepRecord> _parseSleepDetails(
    Uint8List data,
    int version,
    int limit,
  ) {
    // Versions 1–4 use the older compact all-day-sleep layout.  The schema
    // files shipped by Mi Fitness define the report layout used by versions 5
    // and 6; do not apply that layout to the compact files.
    if (version < 5) {
      return _parseLegacySleepDetails(data, version, limit);
    }
    if (version > 6) return const [];
    final validityLength = _sleepValidityLength(version);
    // sleepFull(1) + start/end(8) + quality/efficiency(2) + four u32
    // duration/time fields(16). v6 appends eleven HRV summary fields:
    // six u16 values, one u32 timestamp, and four more u16 values.
    const fixedRecordLength = 27;
    const hrvSummaryLength = 24;
    final minimumRecordLength =
        fixedRecordLength + (version == 6 ? hrvSummaryLength : 0);
    if (validityLength == 0 ||
        limit < 8 + validityLength + minimumRecordLength) {
      return const [];
    }
    final view = ByteData.sublistView(data);
    final validity = data.sublist(8, 8 + validityLength);
    var offset = 8 + validityLength;

    // Mi Fitness's schema parser consumes the fixed record in this order. The
    // validity bits only mark a value as usable; they do not remove the value
    // from the body.
    int? readUint8() {
      if (offset + 1 > limit) return null;
      return data[offset++];
    }

    int? readUint32() {
      if (offset + 4 > limit) return null;
      final value = view.getUint32(offset, Endian.little);
      offset += 4;
      return value;
    }

    int? readUint16() {
      if (offset + 2 > limit) return null;
      final value = view.getUint16(offset, Endian.little);
      offset += 2;
      return value;
    }

    final sleepFullRaw = readUint8();
    final startedRaw = readUint32();
    final endedRaw = readUint32();
    final qualityRaw = readUint8();
    final efficiencyRaw = readUint8();
    final asleepDurationRaw = readUint32();
    final bedDurationRaw = readUint32();
    final goBedRaw = readUint32();
    final leaveBedRaw = readUint32();
    if ([
      sleepFullRaw,
      startedRaw,
      endedRaw,
      qualityRaw,
      efficiencyRaw,
      asleepDurationRaw,
      bedDurationRaw,
      goBedRaw,
      leaveBedRaw,
    ].any((value) => value == null)) {
      return const [];
    }

    int? hrvAverageRaw;
    int? hrvStandardDeviationRaw;
    int? hrvMedianRaw;
    int? hrvLowerQuantileRaw;
    int? hrvUpperQuantileRaw;
    int? hrvMiddleQuantileRaw;
    int? hrvTimestampRaw;
    int? hrvMaximumRaw;
    int? hrvMinimumRaw;
    int? hrvBaselineMaximumRaw;
    int? hrvBaselineMinimumRaw;
    if (version == 6) {
      hrvAverageRaw = readUint16();
      hrvStandardDeviationRaw = readUint16();
      hrvMedianRaw = readUint16();
      hrvLowerQuantileRaw = readUint16();
      hrvUpperQuantileRaw = readUint16();
      hrvMiddleQuantileRaw = readUint16();
      hrvTimestampRaw = readUint32();
      hrvMaximumRaw = readUint16();
      hrvMinimumRaw = readUint16();
      hrvBaselineMaximumRaw = readUint16();
      hrvBaselineMinimumRaw = readUint16();
      if ([
        hrvAverageRaw,
        hrvStandardDeviationRaw,
        hrvMedianRaw,
        hrvLowerQuantileRaw,
        hrvUpperQuantileRaw,
        hrvMiddleQuantileRaw,
        hrvTimestampRaw,
        hrvMaximumRaw,
        hrvMinimumRaw,
        hrvBaselineMaximumRaw,
        hrvBaselineMinimumRaw,
      ].any((value) => value == null)) {
        return const [];
      }
    }

    final heartRate = _readSleepRecordSeries(
      view: view,
      limit: limit,
      offset: offset,
      version: version,
      valid: _sleepValidity(validity, version, _SleepValidityField.heartRate),
    );
    offset = heartRate.offset;
    final bloodOxygen = _readSleepRecordSeries(
      view: view,
      limit: limit,
      offset: offset,
      version: version,
      valid: _sleepValidity(validity, version, _SleepValidityField.bloodOxygen),
    );
    offset = bloodOxygen.offset;

    final hrv = _readSleepRecordSeries(
      view: view,
      limit: limit,
      offset: offset,
      version: version,
      valid:
          version == 6 &&
          _sleepValidity(validity, version, _SleepValidityField.hrvSeries),
      sampleWidth: 2,
    );
    offset = hrv.offset;

    final snore = _readSleepRecordSeries(
      view: view,
      limit: limit,
      offset: offset,
      version: version,
      valid: _sleepValidity(validity, version, _SleepValidityField.snore),
      sampleWidth: 4,
    );
    offset = snore.offset;

    // Mi Fitness calls the remaining bytes featureData and passes them to its
    // native sleep algorithm. The known packet stream is decoded when
    // present; other feature-data records remain opaque.
    final stagePackets = _parseSleepStagePackets(data, offset, limit);
    final packetSummary = stagePackets.summary;
    final startedValue =
        _sleepValidity(validity, version, _SleepValidityField.start) &&
            startedRaw! > 0
        ? startedRaw
        : null;
    final endedValue =
        _sleepValidity(validity, version, _SleepValidityField.end) &&
            endedRaw! > 0
        ? endedRaw
        : null;
    final goBedValue =
        _sleepValidity(validity, version, _SleepValidityField.goBed) &&
            goBedRaw! > 0
        ? goBedRaw
        : null;
    final leaveBedValue =
        _sleepValidity(validity, version, _SleepValidityField.leaveBed) &&
            leaveBedRaw! > 0
        ? leaveBedRaw
        : null;

    var resolvedStarted = startedValue ?? goBedValue;
    var resolvedEnded = endedValue ?? leaveBedValue;
    final reportedDuration =
        _sleepValidity(validity, version, _SleepValidityField.asleepDuration) &&
            asleepDurationRaw! > 0
        ? asleepDurationRaw
        : null;
    if (resolvedStarted == null &&
        resolvedEnded != null &&
        reportedDuration != null) {
      resolvedStarted = resolvedEnded - reportedDuration;
    }
    if (resolvedEnded == null &&
        resolvedStarted != null &&
        reportedDuration != null) {
      resolvedEnded = resolvedStarted + reportedDuration;
    }
    // The device summary carries one entry per real sleep segment; a single
    // file may legitimately contain a main night plus a following segment.
    // Expand them below instead of collapsing to the file header. Progressive
    // snapshots of the same segment are reconciled by bedtime in HealthStore.
    if (packetSummary != null &&
        packetSummary.startedAtSeconds > 0 &&
        packetSummary.endedAtSeconds > packetSummary.startedAtSeconds) {
      resolvedStarted = packetSummary.startedAtSeconds;
      resolvedEnded = packetSummary.endedAtSeconds;
    }
    if (resolvedStarted == null || resolvedEnded == null) return const [];
    if (resolvedEnded <= resolvedStarted) return const [];
    final heartRateStats = heartRate.statsBetween(
      resolvedStarted,
      resolvedEnded,
    );
    final bloodOxygenStats = bloodOxygen.statsBetween(
      resolvedStarted,
      resolvedEnded,
    );
    final hrvPoints = hrv.firstRecordTimeSeconds <= 0
        ? const <XiaomiActivitySleepHrvPoint>[]
        : hrv.values
              .asMap()
              .entries
              .where((entry) => entry.value != null)
              .map(
                (entry) => XiaomiActivitySleepHrvPoint(
                  timestamp: _activityTimestamp(
                    hrv.firstRecordTimeSeconds +
                        entry.key * hrv.intervalSeconds,
                  ),
                  value: entry.value!,
                ),
              )
              .toList(growable: false);
    final heartRatePoints = _sleepVitalPoints(
      heartRate,
      startedAtSeconds: resolvedStarted,
      endedAtSeconds: resolvedEnded,
      useSleepStartWhenFirstTimeMissing: version < 2,
      includeOutsideSleepWindow: true,
    );
    final bloodOxygenPoints = _sleepVitalPoints(
      bloodOxygen,
      startedAtSeconds: resolvedStarted,
      endedAtSeconds: resolvedEnded,
      useSleepStartWhenFirstTimeMissing: version < 2,
      includeOutsideSleepWindow: true,
    );
    final packetDuration = packetSummary?.durationMinutes;
    final duration = packetDuration != null && packetDuration > 0
        ? packetDuration * 60
        : reportedDuration ?? resolvedEnded - resolvedStarted;
    final base = XiaomiActivitySleepRecord(
      startedAt: _activityTimestamp(resolvedStarted),
      endedAt: _activityTimestamp(resolvedEnded),
      durationSeconds: duration,
      averageHeartRate: heartRateStats?.average,
      averageBloodOxygen: bloodOxygenStats?.average,
      minimumHeartRate: heartRateStats?.minimum,
      maximumHeartRate: heartRateStats?.maximum,
      minimumBloodOxygen: bloodOxygenStats?.minimum,
      maximumBloodOxygen: bloodOxygenStats?.maximum,
      quality:
          _sleepValidity(validity, version, _SleepValidityField.quality) &&
              qualityRaw! >= 0
          ? qualityRaw
          : null,
      sleepEfficiency:
          _sleepValidity(validity, version, _SleepValidityField.efficiency) &&
              efficiencyRaw! >= 0
          ? efficiencyRaw
          : null,
      bedDurationSeconds:
          _sleepValidity(validity, version, _SleepValidityField.bedDuration) &&
              bedDurationRaw! > 0
          ? bedDurationRaw
          : null,
      goBedAt: goBedValue == null ? null : _activityTimestamp(goBedValue),
      leaveBedAt: leaveBedValue == null
          ? null
          : _activityTimestamp(leaveBedValue),
      awakeDurationSeconds: packetSummary == null
          ? null
          : packetSummary.awakeDurationMinutes * 60,
      lightSleepDurationSeconds: packetSummary == null
          ? null
          : packetSummary.lightDurationMinutes * 60,
      deepSleepDurationSeconds: packetSummary == null
          ? null
          : packetSummary.deepDurationMinutes * 60,
      remSleepDurationSeconds: packetSummary == null
          ? null
          : packetSummary.remDurationMinutes * 60,
      sleepIndex: packetSummary?.sleepIndex,
      wakeCount: packetSummary?.wakeCount,
      hasRem: packetSummary?.hasRem,
      hasStage:
          packetSummary?.hasStage ??
          (stagePackets.stages.isEmpty ? null : true),
      sleepScoreVersion: packetSummary?.sleepScoreVersion,
      averageHrv:
          version == 6 &&
              _sleepValidity(validity, version, _SleepValidityField.hrvAverage)
          ? hrvAverageRaw
          : null,
      hrvStandardDeviation:
          version == 6 &&
              _sleepValidity(
                validity,
                version,
                _SleepValidityField.hrvStandardDeviation,
              )
          ? hrvStandardDeviationRaw
          : null,
      hrvMedian:
          version == 6 &&
              _sleepValidity(validity, version, _SleepValidityField.hrvMedian)
          ? hrvMedianRaw
          : null,
      hrvLowerQuantile:
          version == 6 &&
              _sleepValidity(
                validity,
                version,
                _SleepValidityField.hrvLowerQuantile,
              )
          ? hrvLowerQuantileRaw
          : null,
      hrvUpperQuantile:
          version == 6 &&
              _sleepValidity(
                validity,
                version,
                _SleepValidityField.hrvUpperQuantile,
              )
          ? hrvUpperQuantileRaw
          : null,
      hrvMiddleQuantile:
          version == 6 &&
              _sleepValidity(
                validity,
                version,
                _SleepValidityField.hrvMiddleQuantile,
              )
          ? hrvMiddleQuantileRaw
          : null,
      hrvTimestamp:
          version == 6 &&
              _sleepValidity(
                validity,
                version,
                _SleepValidityField.hrvTimestamp,
              ) &&
              hrvTimestampRaw! > 0
          ? _activityTimestamp(hrvTimestampRaw)
          : null,
      hrvMax:
          version == 6 &&
              _sleepValidity(validity, version, _SleepValidityField.hrvMaximum)
          ? hrvMaximumRaw
          : null,
      hrvMin:
          version == 6 &&
              _sleepValidity(validity, version, _SleepValidityField.hrvMinimum)
          ? hrvMinimumRaw
          : null,
      hrvBaselineMax:
          version == 6 &&
              _sleepValidity(
                validity,
                version,
                _SleepValidityField.hrvBaselineMaximum,
              )
          ? hrvBaselineMaximumRaw
          : null,
      hrvBaselineMin:
          version == 6 &&
              _sleepValidity(
                validity,
                version,
                _SleepValidityField.hrvBaselineMinimum,
              )
          ? hrvBaselineMinimumRaw
          : null,
      hrvPoints: hrvPoints,
      heartRatePoints: heartRatePoints,
      bloodOxygenPoints: bloodOxygenPoints,
      stages: stagePackets.stages,
    );
    return _expandSleepPacketSummaries(
      base: base,
      packets: stagePackets,
      heartRate: heartRate,
      bloodOxygen: bloodOxygen,
    );
  }

  /// Expands the device summaries instead of collapsing the packet stream to
  /// the main night. Mi Fitness's native parser returns every
  /// [SleepStageSummary]; index 1 is only the preferred summary when a caller
  /// needs one representative night.
  List<XiaomiActivitySleepRecord> _expandSleepPacketSummaries({
    required XiaomiActivitySleepRecord base,
    required _SleepPacketParseResult packets,
    required _SleepByteSeries heartRate,
    required _SleepByteSeries bloodOxygen,
  }) {
    if (packets.summaries.isEmpty) {
      return [
        base.copyWith(
          heartRatePoints: _sleepVitalPointsInInterval(
            base.heartRatePoints,
            base.startedAt,
            base.endedAt,
          ),
          bloodOxygenPoints: _sleepVitalPointsInInterval(
            base.bloodOxygenPoints,
            base.startedAt,
            base.endedAt,
          ),
        ),
      ];
    }
    final segmentSummaries = packets.summaries
        .where(
          (summary) =>
              summary.startedAtSeconds > 0 &&
              summary.endedAtSeconds > summary.startedAtSeconds,
        )
        .toList(growable: false);
    // The nightly aggregates on `base` (quality, sleep efficiency, bed times
    // and the HRV summary) describe the main night only. Xiaomi numbers the
    // main segment with sleepIndex 1; when the firmware does not number
    // segments, the longest one is the main night. Copying these fields onto
    // every segment would make a nap inherit the night's score.
    var mainIndex = segmentSummaries.indexWhere(
      (summary) => summary.sleepIndex == 1,
    );
    if (mainIndex < 0) {
      mainIndex = 0;
      for (var index = 1; index < segmentSummaries.length; index++) {
        if (segmentSummaries[index].durationMinutes >
            segmentSummaries[mainIndex].durationMinutes) {
          mainIndex = index;
        }
      }
    }
    final records = segmentSummaries.indexed
        .map((entry) {
          final summary = entry.$2;
          final isMainSleep = entry.$1 == mainIndex;
          final startedAt = _activityTimestamp(summary.startedAtSeconds);
          final endedAt = _activityTimestamp(summary.endedAtSeconds);
          // Mi Fitness only attaches assist data to a segment for which the
          // device supplied stage data. Each statistic is recomputed inside
          // that segment's own interval; a segment with no matching samples
          // must not inherit the all-day/first-segment value.
          final heartRateStats = summary.hasStage
              ? heartRate.statsBetween(
                  summary.startedAtSeconds,
                  summary.endedAtSeconds,
                )
              : null;
          final bloodOxygenStats = summary.hasStage
              ? bloodOxygen.statsBetween(
                  summary.startedAtSeconds,
                  summary.endedAtSeconds,
                )
              : null;
          final hrvPoints = base.hrvPoints
              .where(
                (point) =>
                    !point.timestamp.isBefore(startedAt) &&
                    point.timestamp.isBefore(endedAt),
              )
              .toList(growable: false);
          final heartRatePoints = summary.hasStage
              ? _sleepVitalPointsInInterval(
                  base.heartRatePoints,
                  startedAt,
                  endedAt,
                )
              : const <XiaomiActivitySleepVitalPoint>[];
          final bloodOxygenPoints = summary.hasStage
              ? _sleepVitalPointsInInterval(
                  base.bloodOxygenPoints,
                  startedAt,
                  endedAt,
                )
              : const <XiaomiActivitySleepVitalPoint>[];
          final stages = summary.hasStage
              ? packets.stages
                    .where(
                      (stage) =>
                          !stage.timestamp.isBefore(startedAt) &&
                          stage.timestamp.isBefore(endedAt),
                    )
                    .toList(growable: false)
              : const <XiaomiActivitySleepStageRecord>[];
          return XiaomiActivitySleepRecord(
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: summary.durationMinutes * 60,
            averageHeartRate: heartRateStats?.average,
            minimumHeartRate: heartRateStats?.minimum,
            maximumHeartRate: heartRateStats?.maximum,
            averageBloodOxygen: bloodOxygenStats?.average,
            minimumBloodOxygen: bloodOxygenStats?.minimum,
            maximumBloodOxygen: bloodOxygenStats?.maximum,
            quality: isMainSleep ? base.quality : null,
            sleepEfficiency: isMainSleep ? base.sleepEfficiency : null,
            bedDurationSeconds: isMainSleep ? base.bedDurationSeconds : null,
            goBedAt: isMainSleep ? base.goBedAt : null,
            leaveBedAt: isMainSleep ? base.leaveBedAt : null,
            awakeDurationSeconds: summary.awakeDurationMinutes * 60,
            lightSleepDurationSeconds: summary.lightDurationMinutes * 60,
            deepSleepDurationSeconds: summary.deepDurationMinutes * 60,
            remSleepDurationSeconds: summary.remDurationMinutes * 60,
            averageHrv: isMainSleep ? base.averageHrv : null,
            hrvMin: isMainSleep ? base.hrvMin : null,
            hrvMax: isMainSleep ? base.hrvMax : null,
            hrvBaselineMin: isMainSleep ? base.hrvBaselineMin : null,
            hrvBaselineMax: isMainSleep ? base.hrvBaselineMax : null,
            hrvStandardDeviation: isMainSleep
                ? base.hrvStandardDeviation
                : null,
            hrvMedian: isMainSleep ? base.hrvMedian : null,
            hrvLowerQuantile: isMainSleep ? base.hrvLowerQuantile : null,
            hrvMiddleQuantile: isMainSleep ? base.hrvMiddleQuantile : null,
            hrvUpperQuantile: isMainSleep ? base.hrvUpperQuantile : null,
            hrvTimestamp: isMainSleep ? base.hrvTimestamp : null,
            sleepIndex: summary.sleepIndex,
            wakeCount: summary.wakeCount,
            hasRem: summary.hasRem,
            hasStage: summary.hasStage,
            sleepScoreVersion: summary.sleepScoreVersion,
            hrvPoints: hrvPoints,
            heartRatePoints: heartRatePoints,
            bloodOxygenPoints: bloodOxygenPoints,
            stages: stages,
          );
        })
        .toList(growable: false);
    return records.isEmpty ? [base] : records;
  }

  List<XiaomiActivitySleepRecord> _parseLegacySleepDetails(
    Uint8List data,
    int version,
    int limit,
  ) {
    final headerSize = version >= 5 ? 2 : 1;
    if (version < 1 || version > 4 || limit < 8 + headerSize + 9) {
      return const [];
    }
    final view = ByteData.sublistView(data);
    final header = data.sublist(8, 8 + headerSize);
    var offset = 8 + headerSize;
    if (offset >= limit) return const [];
    offset++; // compact sleep-finished/awake flag
    if (offset + 8 > limit) return const [];
    final started = view.getUint32(offset, Endian.little);
    final ended = view.getUint32(offset + 4, Endian.little);
    offset += 8;
    if (started == 0 || ended <= started) return const [];

    int? quality;
    var headerIndex = 3;
    if (version >= 4) {
      if (offset >= limit) return const [];
      if (_validHeaderBit(header, headerIndex)) {
        quality = view.getUint8(offset);
      }
      offset++;
      headerIndex++;
    }

    final heartRate = _readSleepByteSeries(
      view,
      data,
      limit,
      offset,
      version,
      _validHeaderBit(header, headerIndex),
    );
    offset = heartRate.offset;
    headerIndex++;
    final bloodOxygen = _readSleepByteSeries(
      view,
      data,
      limit,
      offset,
      version,
      _validHeaderBit(header, headerIndex),
    );
    offset = bloodOxygen.offset;
    headerIndex++;
    if (version >= 3) {
      final snore = _readSleepByteSeries(
        view,
        data,
        limit,
        offset,
        version,
        _validHeaderBit(header, headerIndex),
        sampleWidth: 4,
      );
      offset = snore.offset;
    }
    final stagePackets = _parseSleepStagePackets(data, offset, limit);
    final packetSummary = stagePackets.summary;
    var resolvedStarted = started;
    var resolvedEnded = ended;
    if (packetSummary != null &&
        packetSummary.startedAtSeconds > 0 &&
        packetSummary.endedAtSeconds > packetSummary.startedAtSeconds) {
      resolvedStarted = packetSummary.startedAtSeconds;
      resolvedEnded = packetSummary.endedAtSeconds;
    }
    final heartRateStats = heartRate.statsBetween(
      resolvedStarted,
      resolvedEnded,
    );
    final bloodOxygenStats = bloodOxygen.statsBetween(
      resolvedStarted,
      resolvedEnded,
    );
    final durationSeconds =
        packetSummary != null && packetSummary.durationMinutes > 0
        ? packetSummary.durationMinutes * 60
        : resolvedEnded - resolvedStarted;
    final heartRatePoints = _sleepVitalPoints(
      heartRate,
      startedAtSeconds: resolvedStarted,
      endedAtSeconds: resolvedEnded,
      useSleepStartWhenFirstTimeMissing: version < 2,
      includeOutsideSleepWindow: true,
    );
    final bloodOxygenPoints = _sleepVitalPoints(
      bloodOxygen,
      startedAtSeconds: resolvedStarted,
      endedAtSeconds: resolvedEnded,
      useSleepStartWhenFirstTimeMissing: version < 2,
      includeOutsideSleepWindow: true,
    );
    final base = XiaomiActivitySleepRecord(
      startedAt: _activityTimestamp(resolvedStarted),
      endedAt: _activityTimestamp(resolvedEnded),
      durationSeconds: durationSeconds,
      averageHeartRate: heartRateStats?.average,
      averageBloodOxygen: bloodOxygenStats?.average,
      minimumHeartRate: heartRateStats?.minimum,
      maximumHeartRate: heartRateStats?.maximum,
      minimumBloodOxygen: bloodOxygenStats?.minimum,
      maximumBloodOxygen: bloodOxygenStats?.maximum,
      quality: quality,
      awakeDurationSeconds: packetSummary == null
          ? null
          : packetSummary.awakeDurationMinutes * 60,
      lightSleepDurationSeconds: packetSummary == null
          ? null
          : packetSummary.lightDurationMinutes * 60,
      deepSleepDurationSeconds: packetSummary == null
          ? null
          : packetSummary.deepDurationMinutes * 60,
      remSleepDurationSeconds: packetSummary == null
          ? null
          : packetSummary.remDurationMinutes * 60,
      sleepIndex: packetSummary?.sleepIndex,
      wakeCount: packetSummary?.wakeCount,
      hasRem: packetSummary?.hasRem,
      hasStage:
          packetSummary?.hasStage ??
          (stagePackets.stages.isEmpty ? null : true),
      sleepScoreVersion: packetSummary?.sleepScoreVersion,
      heartRatePoints: heartRatePoints,
      bloodOxygenPoints: bloodOxygenPoints,
      stages: stagePackets.stages,
    );
    return _expandSleepPacketSummaries(
      base: base,
      packets: stagePackets,
      heartRate: heartRate,
      bloodOxygen: bloodOxygen,
    );
  }

  XiaomiActivitySleepRecord? _parseSleepStages(Uint8List data) {
    final limit = data.length - 4;
    if (limit < 37) return null;
    final view = ByteData.sublistView(data);
    var offset = 8 + 7;
    final durationMinutes = view.getUint16(offset, Endian.little);
    final started = view.getUint32(offset + 2, Endian.little);
    final ended = view.getUint32(offset + 6, Endian.little);
    offset += 10;
    if (started == 0 || ended <= started || durationMinutes == 0) return null;
    final totalsOffset = offset + 3;
    if (totalsOffset + 8 > limit) return null;
    final deepDurationMinutes = view.getUint16(totalsOffset, Endian.little);
    final lightDurationMinutes = view.getUint16(
      totalsOffset + 2,
      Endian.little,
    );
    final remDurationMinutes = view.getUint16(totalsOffset + 4, Endian.little);
    final awakeDurationMinutes = view.getUint16(
      totalsOffset + 6,
      Endian.little,
    );
    // Three reserved bytes, four stage totals, then one trailing reserved
    // byte precede the five-byte stage records.
    offset += 3 + 8 + 1;
    final stages = <XiaomiActivitySleepStageRecord>[];
    while (offset + 5 <= limit) {
      final timestamp = view.getUint32(offset, Endian.little);
      final stage = _sleepStageFileValue(data[offset + 4]);
      if (timestamp != 0 && stage >= 0) {
        stages.add(
          XiaomiActivitySleepStageRecord(
            timestamp: _activityTimestamp(timestamp),
            stage: stage,
          ),
        );
      }
      offset += 5;
    }
    return XiaomiActivitySleepRecord(
      startedAt: _activityTimestamp(started),
      endedAt: _activityTimestamp(ended),
      durationSeconds: durationMinutes * 60,
      awakeDurationSeconds: awakeDurationMinutes * 60,
      lightSleepDurationSeconds: lightDurationMinutes * 60,
      deepSleepDurationSeconds: deepDurationMinutes * 60,
      remSleepDurationSeconds: remDurationMinutes * 60,
      hasRem: remDurationMinutes > 0,
      hasStage: stages.isNotEmpty,
      stages: stages,
    );
  }

  _SleepPacketParseResult _parseSleepStagePackets(
    Uint8List data,
    int offset,
    int limit,
  ) {
    // The feature-data tail uses the packet stream consumed by Mi Fitness:
    // magic 0xfb 0xfa 0xfc 0xff, a five-byte header prefix, a little-endian
    // timestamp, parity, type, and a big-endian payload length. Type 16 is a
    // compact summary record; type 17 contains big-endian stage/duration
    // points. The device has already performed stage classification before
    // this stream is sent, so this parser only decodes the wire records.
    final view = ByteData.sublistView(data);
    final stages = <XiaomiActivitySleepStageRecord>[];
    final summaries = <_SleepPacketSummary>[];
    var sleepScoreVersion = 0;
    while (offset + 17 <= limit) {
      if (view.getUint32(offset, Endian.little) != 0xfffcfafb) {
        offset++;
        continue;
      }
      final type = data[offset + 14];
      final dataLength = (data[offset + 15] << 8) | data[offset + 16];
      final timestamp = view.getUint64(offset + 5, Endian.little);
      final payloadOffset = offset + 17;
      if (type == 2 ||
          type == 3 ||
          type == 9 ||
          type == 12 ||
          type == 13 ||
          type == 14 ||
          type == 15) {
        // These packet types carry flags in the two bytes that otherwise look
        // like a length. They have no payload in the sleep stream.
        offset = payloadOffset;
        continue;
      }
      if (payloadOffset + dataLength > limit) break;
      offset = payloadOffset;
      if (type == 19) {
        // Mi Fitness's native parser marks device-provided summaries as
        // score-version 1 when this marker is present.
        sleepScoreVersion = 1;
      } else if (type == 16 && dataLength >= 13) {
        // Native Mi Fitness accepts N consecutive 13-byte summaries in one
        // type-16 payload. The first starts at the packet timestamp; each
        // following summary starts after the previous interval plus its
        // trailing one-byte gap.
        var currentTimestamp = timestamp;
        final payloadEnd = offset + dataLength;
        for (
          var recordOffset = offset;
          recordOffset + 13 <= payloadEnd;
          recordOffset += 13
        ) {
          final sleepIndexAndWakeCount = data[recordOffset];
          final sleepIndex = sleepIndexAndWakeCount >> 4;
          final wakeCount = sleepIndexAndWakeCount & 0x0f;
          final durationMinutes = view.getUint16(recordOffset + 1, Endian.big);
          final awakeDurationMinutes = view.getUint16(
            recordOffset + 3,
            Endian.big,
          );
          final lightDurationMinutes = view.getUint16(
            recordOffset + 5,
            Endian.big,
          );
          final remDurationMinutes = view.getUint16(
            recordOffset + 7,
            Endian.big,
          );
          final deepDurationMinutes = view.getUint16(
            recordOffset + 9,
            Endian.big,
          );
          final flags = data[recordOffset + 11];
          final remState = (flags >> 4) & 0x03;
          final stageState = (flags >> 2) & 0x03;
          final unknownDurationMinutes = data[recordOffset + 12];
          final endedTimestamp =
              currentTimestamp + (durationMinutes + awakeDurationMinutes) * 60;
          summaries.add(
            _SleepPacketSummary(
              startedAtSeconds: currentTimestamp,
              endedAtSeconds: endedTimestamp,
              durationMinutes: durationMinutes,
              awakeDurationMinutes: awakeDurationMinutes,
              lightDurationMinutes: lightDurationMinutes,
              remDurationMinutes: remDurationMinutes,
              deepDurationMinutes: deepDurationMinutes,
              sleepIndex: sleepIndex,
              wakeCount: wakeCount,
              hasRem: remState == 1,
              hasStage: stageState == 1,
              unknownDurationMinutes: unknownDurationMinutes,
              sleepScoreVersion: sleepScoreVersion == 0
                  ? null
                  : sleepScoreVersion,
            ),
          );
          currentTimestamp = endedTimestamp + unknownDurationMinutes * 60;
        }
      } else if (type == 17) {
        var current = timestamp * 1000;
        for (var index = 0; index + 1 < dataLength; index += 2) {
          final value = view.getUint16(offset + index, Endian.big);
          final durationMinutes = value & 0xfff;
          final stage = _sleepStageDetailValue(value >> 12);
          if (stage >= 0) {
            stages.add(
              XiaomiActivitySleepStageRecord(
                timestamp: _activityTimestamp(current ~/ 1000),
                stage: stage,
                endedAt: durationMinutes == 0
                    ? null
                    : _activityTimestamp(
                        current ~/ 1000 + durationMinutes * 60,
                      ),
              ),
            );
          }
          current += durationMinutes * 60 * 1000;
        }
      }
      offset += dataLength;
    }
    final finalSummaries = sleepScoreVersion == 0
        ? summaries
        : summaries
              .map(
                (summary) =>
                    summary.copyWith(sleepScoreVersion: sleepScoreVersion),
              )
              .toList(growable: false);
    return _SleepPacketParseResult(stages: stages, summaries: finalSummaries);
  }

  int _sleepValidityLength(int version) => switch (version) {
    5 => 2,
    6 => 3,
    _ => 0,
  };

  bool _sleepValidity(
    Uint8List validity,
    int version,
    _SleepValidityField field,
  ) {
    final index = switch (version) {
      5 => switch (field) {
        _SleepValidityField.start => 0,
        _SleepValidityField.end => 1,
        _SleepValidityField.quality => 2,
        _SleepValidityField.efficiency => 3,
        _SleepValidityField.asleepDuration => 4,
        _SleepValidityField.bedDuration => 5,
        _SleepValidityField.goBed => 6,
        _SleepValidityField.leaveBed => 7,
        _SleepValidityField.heartRate => 8,
        _SleepValidityField.bloodOxygen => 9,
        _SleepValidityField.snore => 10,
        _ => -1,
      },
      6 => switch (field) {
        _SleepValidityField.start => 0,
        _SleepValidityField.end => 1,
        _SleepValidityField.quality => 2,
        _SleepValidityField.efficiency => 3,
        _SleepValidityField.asleepDuration => 4,
        _SleepValidityField.bedDuration => 5,
        _SleepValidityField.goBed => 6,
        _SleepValidityField.leaveBed => 7,
        _SleepValidityField.hrvAverage => 8,
        _SleepValidityField.hrvStandardDeviation => 9,
        _SleepValidityField.hrvMedian => 10,
        _SleepValidityField.hrvLowerQuantile => 11,
        _SleepValidityField.hrvUpperQuantile => 12,
        _SleepValidityField.hrvMiddleQuantile => 13,
        _SleepValidityField.hrvTimestamp => 14,
        _SleepValidityField.hrvMaximum => 15,
        _SleepValidityField.hrvMinimum => 16,
        _SleepValidityField.hrvBaselineMaximum => 17,
        _SleepValidityField.hrvBaselineMinimum => 18,
        _SleepValidityField.heartRate => 19,
        _SleepValidityField.bloodOxygen => 20,
        _SleepValidityField.hrvSeries => 21,
        _SleepValidityField.snore => 22,
      },
      _ => -1,
    };
    return _validHeaderBit(validity, index);
  }

  _SleepByteSeries _readSleepRecordSeries({
    required ByteData view,
    required int limit,
    required int offset,
    required int version,
    required bool valid,
    int sampleWidth = 1,
    int validMinimum = 1,
    int validMaximum = 254,
  }) {
    // The record block is conditional on its validity bit in the official
    // v5/v6 schema.  Do not consume bytes for an absent block.
    if (!valid) return _SleepByteSeries(offset: offset);
    if (offset + 4 > limit) return _SleepByteSeries(offset: limit);
    final interval = view.getUint16(offset, Endian.little);
    final count = view.getUint16(offset + 2, Endian.little);
    offset += 4;
    if (count == 0) return _SleepByteSeries(offset: offset);
    var firstRecordTime = 0;
    if (version >= 2) {
      if (offset + 4 > limit) return _SleepByteSeries(offset: limit);
      firstRecordTime = view.getUint32(offset, Endian.little);
      offset += 4;
    }
    final remaining = limit - offset;
    if (sampleWidth <= 0 || count > remaining ~/ sampleWidth) {
      return _SleepByteSeries(offset: limit);
    }
    final end = offset + count * sampleWidth;
    final values = <int?>[];
    for (var index = 0; index < count; index++) {
      final value = switch (sampleWidth) {
        1 => view.getUint8(offset + index),
        2 => view.getUint16(offset + index * 2, Endian.little),
        4 => view.getUint32(offset + index * 4, Endian.little),
        _ => null,
      };
      if (value == null) {
        values.add(null);
      } else if (sampleWidth == 1 &&
          (value < validMinimum || value > validMaximum)) {
        values.add(null);
      } else {
        values.add(value);
      }
    }
    // Keep the read of interval and firstRecordTime explicit: both are part
    // of the wire format even though the summary model only needs averages.
    if (interval < 0 || firstRecordTime < 0) {
      return _SleepByteSeries(offset: end);
    }
    return _SleepByteSeries(
      offset: end,
      average: _SleepByteSeries._stats(values)?.average,
      minimum: _SleepByteSeries._stats(values)?.minimum,
      maximum: _SleepByteSeries._stats(values)?.maximum,
      intervalSeconds: interval,
      firstRecordTimeSeconds: firstRecordTime,
      values: values,
    );
  }

  List<XiaomiActivitySleepVitalPoint> _sleepVitalPoints(
    _SleepByteSeries series, {
    required int startedAtSeconds,
    required int endedAtSeconds,
    required bool useSleepStartWhenFirstTimeMissing,
    bool includeOutsideSleepWindow = false,
  }) {
    if (series.values.isEmpty || series.intervalSeconds <= 0) {
      return const [];
    }
    final firstRecordTime = series.firstRecordTimeSeconds > 0
        ? series.firstRecordTimeSeconds
        : useSleepStartWhenFirstTimeMissing
        ? startedAtSeconds
        : 0;
    if (firstRecordTime <= 0) return const [];
    final points = <XiaomiActivitySleepVitalPoint>[];
    for (var index = 0; index < series.values.length; index++) {
      final value = series.values[index];
      if (value == null) continue;
      final timestamp = firstRecordTime + index * series.intervalSeconds;
      if (!includeOutsideSleepWindow &&
          (timestamp < startedAtSeconds || timestamp >= endedAtSeconds)) {
        continue;
      }
      points.add(
        XiaomiActivitySleepVitalPoint(
          timestamp: _activityTimestamp(timestamp),
          value: value,
        ),
      );
    }
    return List.unmodifiable(points);
  }

  List<XiaomiActivitySleepVitalPoint> _sleepVitalPointsInInterval(
    List<XiaomiActivitySleepVitalPoint> points,
    DateTime startedAt,
    DateTime endedAt,
  ) => List.unmodifiable(
    points.where(
      (point) =>
          !point.timestamp.isBefore(startedAt) &&
          point.timestamp.isBefore(endedAt),
    ),
  );

  int _sleepStageFileValue(int raw) => switch (raw) {
    2 || 3 || 4 || 5 => raw,
    _ => -1,
  };

  int _sleepStageDetailValue(int raw) => switch (raw) {
    0 => 5,
    1 => 3,
    2 => 2,
    3 => 4,
    4 => 0,
    _ => 1,
  };

  _SleepByteSeries _readSleepByteSeries(
    ByteData view,
    Uint8List data,
    int limit,
    int offset,
    int version,
    bool valid, {
    int sampleWidth = 1,
  }) {
    if (!valid) return _SleepByteSeries(offset: offset);
    if (offset + 4 > limit) return _SleepByteSeries(offset: limit);
    final interval = view.getUint16(offset, Endian.little);
    offset += 2;
    final count = view.getUint16(offset, Endian.little);
    offset += 2;
    var firstRecordTime = 0;
    if (version >= 2) {
      if (offset + 4 > limit) return _SleepByteSeries(offset: limit);
      firstRecordTime = view.getUint32(offset, Endian.little);
      offset += 4;
    }
    final available = (limit - offset) ~/ sampleWidth;
    final samplesToRead = available.clamp(0, count);
    if (samplesToRead == 0) {
      return _SleepByteSeries(offset: offset + available * sampleWidth);
    }
    final values = <int?>[];
    for (var index = 0; index < samplesToRead; index++) {
      if (sampleWidth == 1) {
        final value = data[offset + index];
        values.add(value == 0 || value == 255 ? null : value);
      }
    }
    final end = offset + samplesToRead * sampleWidth;
    final stats = _SleepByteSeries._stats(values);
    return _SleepByteSeries(
      offset: end,
      average: stats?.average,
      minimum: stats?.minimum,
      maximum: stats?.maximum,
      intervalSeconds: interval,
      firstRecordTimeSeconds: firstRecordTime,
      values: values,
    );
  }

  bool _validHeaderBit(Uint8List header, int index) =>
      index >= 0 && index < header.length * 8
      ? (header[index ~/ 8] & (1 << (7 - index % 8))) != 0
      : false;

  int _crc32(Uint8List data) {
    var crc = 0xffffffff;
    for (final byte in data) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  Future<pb_fitness.RemainingSportData_List> fetchRemainingSportData() =>
      _requestFitness(
        id: pb_fitness.Fitness_FitnessID.GET_REMAINING_SPORT_DATA,
        payload: pb_fitness.Fitness(),
        hasResponse: (fitness) => fitness.hasRemainingSportDataList(),
        response: (fitness) => fitness.remainingSportDataList,
      );

  Future<void> registerBasicDataReports() =>
      _sendFitness(pb_fitness.Fitness_FitnessID.REGISTER_BASIC_DATA_REPORT);

  Future<void> unregisterBasicDataReports() =>
      _sendFitness(pb_fitness.Fitness_FitnessID.UNREGISTER_BASIC_DATA_REPORT);

  Future<pb_fitness.UserProfile> fetchUserProfile() => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.REQUEST_USER_PROFILE,
    payload: pb_fitness.Fitness(),
    hasResponse: (fitness) => fitness.hasUserProfile(),
    response: (fitness) => fitness.userProfile,
  );

  Future<void> setUserProfile(pb_fitness.UserProfile profile) => _sendFitness(
    pb_fitness.Fitness_FitnessID.SET_USER_PROFILE,
    payload: pb_fitness.Fitness(userProfile: profile),
  );

  Future<pb_fitness.SedentaryReminder> fetchSedentaryReminder() =>
      _requestFitness(
        id: pb_fitness.Fitness_FitnessID.GET_SEDENTARY_REMINDER,
        payload: pb_fitness.Fitness(),
        hasResponse: (fitness) => fitness.hasSedentaryReminder(),
        response: (fitness) => fitness.sedentaryReminder,
      );

  Future<void> setSedentaryReminder(pb_fitness.SedentaryReminder reminder) =>
      _sendFitness(
        pb_fitness.Fitness_FitnessID.SET_SEDENTARY_REMINDER,
        payload: pb_fitness.Fitness(sedentaryReminder: reminder),
      );

  Future<pb_fitness.PressureMonitor> fetchPressureMonitor() => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.GET_PRESSURE_MONITOR,
    payload: pb_fitness.Fitness(),
    hasResponse: (fitness) => fitness.hasPressureMonitor(),
    response: (fitness) => fitness.pressureMonitor,
  );

  Future<void> setPressureMonitor(pb_fitness.PressureMonitor monitor) =>
      _sendFitness(
        pb_fitness.Fitness_FitnessID.SET_PRESSURE_MONITOR,
        payload: pb_fitness.Fitness(pressureMonitor: monitor),
      );

  Future<pb_fitness.MeasureReminder> fetchBloodPressureReminder() =>
      _requestMeasureReminder(
        pb_fitness.Fitness_FitnessID.GET_BLOOD_PRESSURE_REMINDER,
      );

  Future<void> setBloodPressureReminder(pb_fitness.MeasureReminder reminder) =>
      _sendMeasureReminder(
        pb_fitness.Fitness_FitnessID.SET_BLOOD_PRESSURE_REMINDER,
        reminder,
      );

  Future<pb_fitness.MeasureReminder> fetchEcgReminder() =>
      _requestMeasureReminder(pb_fitness.Fitness_FitnessID.GET_ECG_REMINDER);

  Future<void> setEcgReminder(pb_fitness.MeasureReminder reminder) =>
      _sendMeasureReminder(
        pb_fitness.Fitness_FitnessID.SET_ECG_REMINDER,
        reminder,
      );

  Future<pb_fitness.VitalityReminder> fetchVitalityReminder() =>
      _requestFitness(
        id: pb_fitness.Fitness_FitnessID.GET_VITALITY_REMINDER,
        payload: pb_fitness.Fitness(),
        hasResponse: (fitness) => fitness.hasVitalityReminder(),
        response: (fitness) => fitness.vitalityReminder,
      );

  Future<void> setVitalityReminder(pb_fitness.VitalityReminder reminder) =>
      _sendFitness(
        pb_fitness.Fitness_FitnessID.SET_VITALITY_REMINDER,
        payload: pb_fitness.Fitness(vitalityReminder: reminder),
      );

  Future<pb_fitness.ActivityReminder> fetchActivityReminder() =>
      _requestFitness(
        id: pb_fitness.Fitness_FitnessID.GET_ACTIVITY_REMINDER,
        payload: pb_fitness.Fitness(),
        hasResponse: (fitness) => fitness.hasActivityReminder(),
        response: (fitness) => fitness.activityReminder,
      );

  Future<void> setActivityReminder(pb_fitness.ActivityReminder reminder) =>
      _sendFitness(
        pb_fitness.Fitness_FitnessID.SET_ACTIVITY_REMINDER,
        payload: pb_fitness.Fitness(activityReminder: reminder),
      );

  /// Returns the latest sleep summary, including sleep sections and averages.
  Future<pb_fitness.SleepResult> fetchSleepResult({Duration? timeout}) =>
      _requestFitness(
        id: pb_fitness.Fitness_FitnessID.SYNC_SLEEP_RESULT,
        payload: pb_fitness.Fitness(),
        timeout: timeout,
        hasResponse: (fitness) => fitness.hasSleepResult(),
        response: (fitness) => fitness.sleepResult,
      );

  Future<pb_fitness.HeartRateMonitor> fetchHeartRateMonitor() =>
      _requestFitness(
        id: pb_fitness.Fitness_FitnessID.GET_HEART_RATE_MONITOR,
        payload: pb_fitness.Fitness(),
        hasResponse: (fitness) => fitness.hasHeartRateMonitor(),
        response: (fitness) => fitness.heartRateMonitor,
      );

  Future<void> setHeartRateMonitor(pb_fitness.HeartRateMonitor monitor) =>
      _sendFitness(
        pb_fitness.Fitness_FitnessID.SET_HEART_RATE_MONITOR,
        payload: pb_fitness.Fitness(heartRateMonitor: monitor),
      );

  Future<pb_fitness.BloodOxygenMonitor> fetchBloodOxygenMonitor() =>
      _requestFitness(
        id: pb_fitness.Fitness_FitnessID.GET_BLOOD_OXYGEN_MONITOR,
        payload: pb_fitness.Fitness(),
        hasResponse: (fitness) => fitness.hasBloodOxygenMonitor(),
        response: (fitness) => fitness.bloodOxygenMonitor,
      );

  Future<void> setBloodOxygenMonitor(pb_fitness.BloodOxygenMonitor monitor) =>
      _sendFitness(
        pb_fitness.Fitness_FitnessID.SET_BLOOD_OXYGEN_MONITOR,
        payload: pb_fitness.Fitness(bloodOxygenMonitor: monitor),
      );

  Future<pb_fitness.ECGResponse> requestEcg(pb_fitness.ECGRequest request) =>
      _requestFitness(
        id: pb_fitness.Fitness_FitnessID.ECG_REQUEST,
        payload: pb_fitness.Fitness(ecgRequest: request),
        hasResponse: (fitness) => fitness.hasEcgResponse(),
        response: (fitness) => fitness.ecgResponse,
      );

  Future<pb_fitness.ECGActivation> fetchEcgActivation() => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.CHECK_ECG_ACTIVATION,
    payload: pb_fitness.Fitness(),
    hasResponse: (fitness) => fitness.hasEcgActivation(),
    response: (fitness) => fitness.ecgActivation,
  );

  Future<void> setEcgActivation(bool enabled) => _sendFitness(
    enabled
        ? pb_fitness.Fitness_FitnessID.ACTIVATE_ECG
        : pb_fitness.Fitness_FitnessID.DEACTIVATE_ECG,
    payload: pb_fitness.Fitness(
      ecgActivation: pb_fitness.ECGActivation(status: enabled),
    ),
  );

  Future<void> setWomenHealthReminder(
    pb_fitness.WomenHealth_Reminder_List reminders,
  ) => _sendFitness(
    pb_fitness.Fitness_FitnessID.SET_WOMEN_HEALTH_REMINDER,
    payload: pb_fitness.Fitness(reminderList: reminders),
  );

  Future<pb_fitness.Goal_Status> fetchGoalStatus() => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.GET_GOAL_STATUS,
    payload: pb_fitness.Fitness(),
    hasResponse: (fitness) => fitness.hasGoalStatus(),
    response: (fitness) => fitness.goalStatus,
  );

  Future<void> setGoalStatus(pb_fitness.Goal_Status status) => _sendFitness(
    pb_fitness.Fitness_FitnessID.SET_GOAL_STATUS,
    payload: pb_fitness.Fitness(goalStatus: status),
  );

  Future<pb_fitness.VitalityData_List> fetchVitalityData() => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.SYNC_VITALITY_DATA,
    payload: pb_fitness.Fitness(),
    hasResponse: (fitness) => fitness.hasVitalityDataList(),
    response: (fitness) => fitness.vitalityDataList,
  );

  Future<void> syncVitalityData(pb_fitness.VitalityData_List data) =>
      _sendFitness(
        pb_fitness.Fitness_FitnessID.SYNC_VITALITY_DATA,
        payload: pb_fitness.Fitness(vitalityDataList: data),
      );

  Future<pb_fitness.BestSportData_List> fetchBestSportData() => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.SYNC_BEST_SPORT_DATA,
    payload: pb_fitness.Fitness(),
    hasResponse: (fitness) => fitness.hasSportDataList(),
    response: (fitness) => fitness.sportDataList,
  );

  Future<void> syncBestSportData(pb_fitness.BestSportData_List data) =>
      _sendFitness(
        pb_fitness.Fitness_FitnessID.SYNC_BEST_SPORT_DATA,
        payload: pb_fitness.Fitness(sportDataList: data),
      );

  Future<pb_fitness.SportStatus> fetchSportStatus() => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.GET_SPORT_STATUS,
    payload: pb_fitness.Fitness(),
    hasResponse: (fitness) => fitness.hasSportStatus(),
    response: (fitness) => fitness.sportStatus,
  );

  Future<pb_fitness.SportPreResponse> prepareSport(
    pb_fitness.SportPreRequest request,
  ) => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.SPORT_PRE_REQUEST,
    payload: pb_fitness.Fitness(sportPreRequest: request),
    hasResponse: (fitness) => fitness.hasSportPreResponse(),
    response: (fitness) => fitness.sportPreResponse,
  );

  Future<pb_fitness.SportResponse> requestSport(
    pb_fitness.SportRequest request,
  ) => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.SPORT_REQUEST,
    payload: pb_fitness.Fitness(sportRequest: request),
    hasResponse: (fitness) => fitness.hasSportResponse(),
    response: (fitness) => fitness.sportResponse,
  );

  Future<pb_fitness.SleepRegularity> fetchSleepRegularity() => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.GET_SLEEP_REGULARITY,
    payload: pb_fitness.Fitness(),
    hasResponse: (fitness) => fitness.hasSleepRegularity(),
    response: (fitness) => fitness.sleepRegularity,
  );

  Future<void> setSleepRegularity(pb_fitness.SleepRegularity setting) =>
      _sendFitness(
        pb_fitness.Fitness_FitnessID.SET_SLEEP_REGULARITY,
        payload: pb_fitness.Fitness(sleepRegularity: setting),
      );

  Future<pb_fitness.SleepDisorder> fetchSleepDisorder() => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.GET_SLEEP_DISORDER,
    payload: pb_fitness.Fitness(),
    hasResponse: (fitness) => fitness.hasSleepDisorder(),
    response: (fitness) => fitness.sleepDisorder,
  );

  Future<void> setSleepDisorder(pb_fitness.SleepDisorder setting) =>
      _sendFitness(
        pb_fitness.Fitness_FitnessID.SET_SLEEP_DISORDER,
        payload: pb_fitness.Fitness(sleepDisorder: setting),
      );

  Future<pb_fitness.WomenHealth> fetchWomenHealth() => _requestFitness(
    id: pb_fitness.Fitness_FitnessID.GET_WOMEN_HEALTH,
    payload: pb_fitness.Fitness(),
    hasResponse: (fitness) => fitness.hasWomenHealth(),
    response: (fitness) => fitness.womenHealth,
  );

  Future<pb_fitness.WomenHealth_Section_List> fetchWomenHealthSections() =>
      _requestFitness(
        id: pb_fitness.Fitness_FitnessID.REQUEST_WOMEN_HEALTH,
        payload: pb_fitness.Fitness(),
        hasResponse: (fitness) => fitness.hasSectionList(),
        response: (fitness) => fitness.sectionList,
      );

  Future<void> syncWomenHealth(pb_fitness.WomenHealth health) => _sendFitness(
    pb_fitness.Fitness_FitnessID.SYNC_WOMEN_HEALTH,
    payload: pb_fitness.Fitness(womenHealth: health),
  );

  Future<void> setWomenHealthForecast(bool enabled) => _sendFitness(
    pb_fitness.Fitness_FitnessID.SET_WOMEN_HEALTH_FORCAST,
    payload: pb_fitness.Fitness(forcastOn: enabled),
  );

  /// Sends a raw FITNESS command for protocol capabilities not yet wrapped by
  /// a convenience method. The packet remains observable through
  /// [fitnessPackets] when the device reports a result.
  Future<void> sendFitnessCommand(
    pb_fitness.Fitness_FitnessID id, {
    pb_fitness.Fitness? payload,
  }) => _sendFitness(id, payload: payload);

  /// Requests a raw FITNESS response matched by packet id.
  Future<pb_fitness.Fitness> requestFitnessCommand(
    pb_fitness.Fitness_FitnessID id, {
    pb_fitness.Fitness? payload,
    Set<int>? responseIds,
    Duration? timeout,
  }) {
    final acceptedIds = responseIds ?? {id.value};
    _log.fine(
      '[${entity.id}] requesting Xiaomi FITNESS id=${id.value}, '
      'responses=${acceptedIds.join(',')}',
    );
    return component.requestPool.request<pb_fitness.Fitness>(
      packet: _fitnessPacket(id, payload ?? pb_fitness.Fitness()),
      timeout: timeout,
      typeMatcher: (packet) =>
          packet.whichPayload() == pb.WearPacket_Payload.fitness &&
          acceptedIds.contains(packet.id),
      responseMapper: (packet) => packet.fitness,
    );
  }

  Future<T> _requestFitness<T>({
    required pb_fitness.Fitness_FitnessID id,
    required pb_fitness.Fitness payload,
    required bool Function(pb_fitness.Fitness fitness) hasResponse,
    required T Function(pb_fitness.Fitness fitness) response,
    Set<int>? responseIds,
    Duration? timeout,
  }) {
    final acceptedIds = responseIds ?? {id.value};
    _log.fine(
      '[${entity.id}] requesting Xiaomi FITNESS id=${id.value}, '
      'responses=${acceptedIds.join(',')}',
    );
    return component.requestPool.request<T>(
      packet: _fitnessPacket(id, payload),
      timeout: timeout,
      typeMatcher: (packet) =>
          packet.whichPayload() == pb.WearPacket_Payload.fitness &&
          acceptedIds.contains(packet.id) &&
          hasResponse(packet.fitness),
      responseMapper: (packet) => response(packet.fitness),
    );
  }

  Future<Uint8List> _requestBytes({
    required pb_fitness.Fitness_FitnessID id,
    pb_fitness.Fitness? payload,
    Set<int>? responseIds,
    Duration? timeout,
    bool Function(pb_fitness.Fitness fitness)? hasResponse,
  }) => _requestFitness<Uint8List>(
    id: id,
    payload: payload ?? pb_fitness.Fitness(),
    responseIds: responseIds,
    hasResponse: hasResponse ?? (fitness) => fitness.hasIds(),
    response: (fitness) => Uint8List.fromList(fitness.ids),
    timeout: timeout,
  );

  Future<pb_fitness.MeasureReminder> _requestMeasureReminder(
    pb_fitness.Fitness_FitnessID id,
  ) => _requestFitness(
    id: id,
    payload: pb_fitness.Fitness(),
    hasResponse: (fitness) => fitness.hasMeasureReminder(),
    response: (fitness) => fitness.measureReminder,
  );

  Future<void> _sendMeasureReminder(
    pb_fitness.Fitness_FitnessID id,
    pb_fitness.MeasureReminder reminder,
  ) => _sendFitness(id, payload: pb_fitness.Fitness(measureReminder: reminder));

  Future<void> _sendFitness(
    pb_fitness.Fitness_FitnessID id, {
    pb_fitness.Fitness? payload,
  }) {
    _log.fine('[${entity.id}] sending Xiaomi FITNESS id=${id.value}');
    return component.sendPbPacket(
      _fitnessPacket(id, payload ?? pb_fitness.Fitness()),
    );
  }

  @override
  void onLayer2Packet(L2Channel channel, L2OpCode opcode, Uint8List payload) {
    if (channel == L2Channel.fileFitness) {
      onActivityPayload(payload);
      return;
    }
    super.onLayer2Packet(channel, opcode, payload);
  }

  @override
  void onWearPacket(pb.WearPacket packet) {
    if (packet.whichPayload() == pb.WearPacket_Payload.system) {
      final system = packet.system;
      if (system.hasPresentBasicStatus()) {
        _applyPresentStatus(system.presentBasicStatus);
      }
      if (system.hasReportBasicStatus()) {
        _applyReportStatus(system.reportBasicStatus);
      }
      if (system.hasWearStatus()) {
        _applyWearingStatus(system.wearStatus.value);
      }
      return;
    }

    if (packet.whichPayload() != pb.WearPacket_Payload.fitness) return;
    final knownId = pb_fitness.Fitness_FitnessID.values.any(
      (value) => value.value == packet.id,
    );
    if (!knownId) {
      _log.warning(
        '[${entity.id}] unsupported Xiaomi FITNESS packet id=${packet.id} '
        'payload=${packet.fitness.whichPayload()}',
      );
    } else {
      _log.fine(
        '[${entity.id}] received Xiaomi FITNESS packet id=${packet.id} '
        'payload=${packet.fitness.whichPayload()}',
      );
    }
    _fitnessPackets.add(packet.fitness);
  }

  void _applyPresentStatus(pb_system.BasicStatus_Present present) {
    final next = XiaomiHealthState(
      isCharging: present.isCharging,
      isWearing: present.isWearing,
      isSleeping: present.isSleeping,
      battery: present.hasBattery() ? present.battery : null,
      chargingStatus: present.isCharging ? 1 : 2,
      wearingStatus: present.isWearing ? 1 : 2,
      sleepingStatus: present.isSleeping ? 1 : 2,
      sportType: present.hasSport() ? present.sport.sportType.value : null,
      sportState: present.hasSport() && present.sport.hasSportState()
          ? present.sport.sportState.value
          : null,
    );
    _commitState(next, battery: present.hasBattery() ? present.battery : null);
  }

  void _applyReportStatus(pb_system.BasicStatus_Report report) {
    var next = _state;
    if (report.hasCharging()) {
      final value = report.charging.value;
      final charging = switch (value) {
        1 => true,
        2 || 3 => false,
        _ => null,
      };
      if (charging == null) {
        _log.warning('[${entity.id}] unknown charging status $value');
      } else {
        next = next.copyWith(isCharging: charging, chargingStatus: value);
      }
    }
    if (report.hasWearing()) {
      final value = report.wearing.value;
      if (value == 1 || value == 2) {
        next = next.copyWith(isWearing: value == 1, wearingStatus: value);
      } else {
        _log.warning('[${entity.id}] unknown wearing status $value');
      }
    }
    if (report.hasSleeping()) {
      final value = report.sleeping.value;
      if (value == 1 || value == 2) {
        next = next.copyWith(isSleeping: value == 1, sleepingStatus: value);
      } else {
        _log.warning('[${entity.id}] unknown sleeping status $value');
      }
    }
    if (report.hasWaring()) {
      next = next.copyWith(warningStatus: report.waring.value);
    }
    if (report.hasSport()) {
      next = next.copyWith(
        sportType: report.sport.sportType.value,
        sportState: report.sport.hasSportState()
            ? report.sport.sportState.value
            : null,
      );
    }
    _commitState(next);
  }

  void _applyWearingStatus(int value) {
    if (value != 1 && value != 2) {
      _log.warning('[${entity.id}] unknown wearing status $value');
      return;
    }
    _commitState(_state.copyWith(isWearing: value == 1, wearingStatus: value));
  }

  void _commitState(XiaomiHealthState next, {int? battery}) {
    if (_sameState(_state, next) && battery == null) return;
    _state = next;
    entity.emit(XiaomiHealthStateUpdated(deviceId: entity.id, health: next));
    if (battery != null) {
      entity.emit(
        BatteryUpdated(
          deviceId: entity.id,
          battery: models.BatteryStatus(
            capacity: battery,
            chargeStatus: next.isCharging == true
                ? models.ChargeStatus.charging
                : models.ChargeStatus.notCharging,
          ),
        ),
      );
    }
  }

  bool _sameState(XiaomiHealthState left, XiaomiHealthState right) =>
      left.isCharging == right.isCharging &&
      left.isWearing == right.isWearing &&
      left.isSleeping == right.isSleeping &&
      left.battery == right.battery &&
      left.chargingStatus == right.chargingStatus &&
      left.wearingStatus == right.wearingStatus &&
      left.sleepingStatus == right.sleepingStatus &&
      left.warningStatus == right.warningStatus &&
      left.sportType == right.sportType &&
      left.sportState == right.sportState;
}

/// Converts a timestamp from Xiaomi's activity-file protocol.
///
/// Activity-file timestamps are local wall-clock values represented as an
/// epoch-shaped integer. The file ID carries the device timezone in signed
/// 15-minute units. When that value is available, add it to the wire instant
/// and expose the resulting device-local wall-clock fields. Calls without the
/// file timezone retain the historical wall-clock behavior for
/// compatibility with stored/replayed data.
DateTime xiaomiActivityTimestamp(int seconds, {int? timezoneOffset15Min}) {
  final encoded = DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  );
  // The device writes the record timestamp in UTC. The matching timezone field
  // is the offset in 15-minute blocks, so the device's local wall-clock value
  // is `encoded + offset` (Mi Fitness `FitnessDateUtils.changeTo0TimeIn0TzOneDay`
  // and Gadgetbridge both treat the raw seconds as an instant, not as a
  // pre-localized wall clock). Building the result from the shifted UTC fields
  // yields a local DateTime that already carries the device wall clock, so a
  // phone in the same timezone as the device shows exactly what the watch does.
  final shifted = timezoneOffset15Min == null
      ? encoded
      : encoded.add(Duration(minutes: timezoneOffset15Min * 15));
  return DateTime(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
    shifted.millisecond,
    shifted.microsecond,
  );
}

class _ParsedActivityFile {
  const _ParsedActivityFile({
    this.daily,
    this.samples = const [],
    this.sleep = const [],
    this.workouts = const [],
    this.abnormalHealthRecords = const [],
  });

  final XiaomiActivityDailyRecord? daily;
  final List<XiaomiActivitySampleRecord> samples;
  final List<XiaomiActivitySleepRecord> sleep;
  final List<XiaomiActivityWorkoutRecord> workouts;
  final List<XiaomiActivityAbnormalHealthRecord> abnormalHealthRecords;
}

class _ManualMeasureValues {
  int? heartRate;
  int? bloodOxygen;
  int? stress;
}

enum _WorkoutPointKind {
  caloriesAndSteps,
  calories,
  heartRate,
  bloodOxygen,
  stress,
  altitudeInt10,
  altitudeFloat,
  altitudeDeltaTenths,
  distance8,
  distance8Tenths,
  distance15,
  stride,
  cadence,
  pace,
  speed,
  power,
  jumpFrequency,
  jumpHeight,
  strokeFrequency,
  skip,
}

class _WorkoutPointField {
  const _WorkoutPointField(
    this.kind,
    this.existsBit,
    this.validBit,
    this.byteSize,
  );

  final _WorkoutPointKind kind;
  final int existsBit;
  final int validBit;
  final int byteSize;
}

class _WorkoutRecordLayout {
  const _WorkoutRecordLayout({
    required this.validityBytes,
    required this.segmentHeaderBytes,
    required this.recordCountOffset,
    required this.resumeTimestampOffset,
    required this.pointFields,
    this.initialAltitudeOffset,
  });

  final int validityBytes;
  final int segmentHeaderBytes;
  final int recordCountOffset;
  final int resumeTimestampOffset;
  final List<_WorkoutPointField> pointFields;
  final int? initialAltitudeOffset;
}

const _outdoorFootRecordV8 = _WorkoutRecordLayout(
  validityBytes: 7,
  segmentHeaderBytes: 27,
  recordCountOffset: 4,
  resumeTimestampOffset: 8,
  initialAltitudeOffset: 0,
  pointFields: [
    _WorkoutPointField(_WorkoutPointKind.caloriesAndSteps, 0, 1, 1),
    _WorkoutPointField(_WorkoutPointKind.heartRate, 4, 5, 1),
    _WorkoutPointField(_WorkoutPointKind.altitudeDeltaTenths, 8, 11, 1),
    _WorkoutPointField(_WorkoutPointKind.distance8Tenths, 12, 13, 1),
    _WorkoutPointField(_WorkoutPointKind.stride, 16, 17, 1),
    _WorkoutPointField(_WorkoutPointKind.skip, 20, 21, 4),
    _WorkoutPointField(_WorkoutPointKind.skip, 24, 25, 1),
    _WorkoutPointField(_WorkoutPointKind.cadence, 28, 29, 1),
    _WorkoutPointField(_WorkoutPointKind.pace, 32, 33, 2),
    _WorkoutPointField(_WorkoutPointKind.skip, 36, 37, 2),
    _WorkoutPointField(_WorkoutPointKind.power, 40, 41, 2),
    _WorkoutPointField(_WorkoutPointKind.skip, 44, 45, 2),
    _WorkoutPointField(_WorkoutPointKind.skip, 48, 49, 2),
  ],
);

const _outdoorFootRecordV9 = _WorkoutRecordLayout(
  validityBytes: 7,
  segmentHeaderBytes: 27,
  recordCountOffset: 4,
  resumeTimestampOffset: 8,
  pointFields: [
    _WorkoutPointField(_WorkoutPointKind.caloriesAndSteps, 0, 1, 1),
    _WorkoutPointField(_WorkoutPointKind.heartRate, 4, 5, 1),
    _WorkoutPointField(_WorkoutPointKind.altitudeInt10, 8, 9, 4),
    _WorkoutPointField(_WorkoutPointKind.distance15, 12, 14, 2),
    _WorkoutPointField(_WorkoutPointKind.stride, 16, 17, 1),
    _WorkoutPointField(_WorkoutPointKind.skip, 20, 21, 4),
    _WorkoutPointField(_WorkoutPointKind.skip, 24, 25, 1),
    _WorkoutPointField(_WorkoutPointKind.cadence, 28, 29, 1),
    _WorkoutPointField(_WorkoutPointKind.pace, 32, 33, 2),
    _WorkoutPointField(_WorkoutPointKind.skip, 36, 37, 2),
    _WorkoutPointField(_WorkoutPointKind.power, 40, 41, 2),
    _WorkoutPointField(_WorkoutPointKind.skip, 44, 45, 2),
    _WorkoutPointField(_WorkoutPointKind.skip, 48, 49, 2),
  ],
);

// SPORTS_OUTDOOR_WALKING_V2 v5 (Gadgetbridge layout). The five signature bytes
// `FF CF F8 BF FF` double as the record-field bitmap: byte 0 is all ones, so the
// eight point fields below are always active. Segment header: 4 pad | int32
// recordCount | int32 startTimestamp | byte phase | int32 totalDistance.
const _outdoorFootRecordV5 = _WorkoutRecordLayout(
  validityBytes: 5,
  segmentHeaderBytes: 17,
  recordCountOffset: 4,
  resumeTimestampOffset: 8,
  pointFields: [
    _WorkoutPointField(_WorkoutPointKind.caloriesAndSteps, 0, 0, 1),
    _WorkoutPointField(_WorkoutPointKind.heartRate, 1, 1, 1),
    _WorkoutPointField(_WorkoutPointKind.altitudeDeltaTenths, 2, 2, 1),
    _WorkoutPointField(_WorkoutPointKind.distance8Tenths, 3, 3, 1),
    _WorkoutPointField(_WorkoutPointKind.stride, 4, 4, 1),
    _WorkoutPointField(_WorkoutPointKind.skip, 5, 5, 5),
    _WorkoutPointField(_WorkoutPointKind.cadence, 6, 6, 1),
    _WorkoutPointField(_WorkoutPointKind.pace, 7, 7, 2),
  ],
);

const _outdoorNonFootRecordV7 = _WorkoutRecordLayout(
  validityBytes: 4,
  segmentHeaderBytes: 23,
  recordCountOffset: 4,
  resumeTimestampOffset: 8,
  pointFields: [
    _WorkoutPointField(_WorkoutPointKind.caloriesAndSteps, 0, 1, 1),
    _WorkoutPointField(_WorkoutPointKind.heartRate, 4, 5, 1),
    _WorkoutPointField(_WorkoutPointKind.altitudeInt10, 8, 9, 4),
    _WorkoutPointField(_WorkoutPointKind.distance15, 12, 14, 2),
    _WorkoutPointField(_WorkoutPointKind.speed, 16, 17, 2),
    _WorkoutPointField(_WorkoutPointKind.cadence, 20, 21, 1),
    _WorkoutPointField(_WorkoutPointKind.power, 24, 25, 2),
  ],
);

const _outdoorNonFootRecordV5 = _WorkoutRecordLayout(
  validityBytes: 3,
  segmentHeaderBytes: 23,
  recordCountOffset: 4,
  resumeTimestampOffset: 8,
  initialAltitudeOffset: 0,
  pointFields: [
    _WorkoutPointField(_WorkoutPointKind.caloriesAndSteps, 0, 1, 1),
    _WorkoutPointField(_WorkoutPointKind.heartRate, 4, 5, 1),
    _WorkoutPointField(_WorkoutPointKind.altitudeDeltaTenths, 8, 11, 1),
    _WorkoutPointField(_WorkoutPointKind.distance8Tenths, 12, 13, 1),
    _WorkoutPointField(_WorkoutPointKind.speed, 16, 17, 2),
    _WorkoutPointField(_WorkoutPointKind.cadence, 20, 21, 1),
  ],
);

const _outdoorNonFootRecordV6 = _WorkoutRecordLayout(
  validityBytes: 3,
  segmentHeaderBytes: 23,
  recordCountOffset: 4,
  resumeTimestampOffset: 8,
  initialAltitudeOffset: 0,
  pointFields: [
    _WorkoutPointField(_WorkoutPointKind.caloriesAndSteps, 0, 1, 1),
    _WorkoutPointField(_WorkoutPointKind.heartRate, 4, 5, 1),
    _WorkoutPointField(_WorkoutPointKind.altitudeInt10, 8, 9, 4),
    _WorkoutPointField(_WorkoutPointKind.distance15, 12, 14, 2),
    _WorkoutPointField(_WorkoutPointKind.speed, 16, 17, 2),
    _WorkoutPointField(_WorkoutPointKind.cadence, 20, 21, 1),
  ],
);

const _indoorRunRecordFields = <_WorkoutPointField>[
  _WorkoutPointField(_WorkoutPointKind.caloriesAndSteps, 0, 1, 1),
  _WorkoutPointField(_WorkoutPointKind.heartRate, 4, 5, 1),
  _WorkoutPointField(_WorkoutPointKind.distance8, 8, 9, 1),
  _WorkoutPointField(_WorkoutPointKind.stride, 12, 13, 1),
  _WorkoutPointField(_WorkoutPointKind.skip, 16, 17, 4),
  _WorkoutPointField(_WorkoutPointKind.skip, 20, 21, 1),
  _WorkoutPointField(_WorkoutPointKind.cadence, 24, 25, 1),
  _WorkoutPointField(_WorkoutPointKind.pace, 28, 29, 2),
  _WorkoutPointField(_WorkoutPointKind.power, 32, 33, 2),
  _WorkoutPointField(_WorkoutPointKind.skip, 36, 37, 2),
  _WorkoutPointField(_WorkoutPointKind.skip, 40, 41, 2),
];

const _indoorRunRecordV9 = _WorkoutRecordLayout(
  validityBytes: 6,
  segmentHeaderBytes: 19,
  recordCountOffset: 0,
  resumeTimestampOffset: 4,
  pointFields: _indoorRunRecordFields,
);

const _indoorRunRecordV10 = _WorkoutRecordLayout(
  validityBytes: 6,
  segmentHeaderBytes: 25,
  recordCountOffset: 0,
  resumeTimestampOffset: 4,
  pointFields: [
    ..._indoorRunRecordFields,
    _WorkoutPointField(_WorkoutPointKind.altitudeInt10, 44, 45, 4),
  ],
);

const _indoorCyclingRecordV6 = _WorkoutRecordLayout(
  validityBytes: 4,
  segmentHeaderBytes: 13,
  recordCountOffset: 0,
  resumeTimestampOffset: 4,
  pointFields: [
    _WorkoutPointField(_WorkoutPointKind.caloriesAndSteps, 0, 1, 1),
    _WorkoutPointField(_WorkoutPointKind.heartRate, 4, 5, 1),
    _WorkoutPointField(_WorkoutPointKind.distance8Tenths, 8, 9, 1),
    _WorkoutPointField(_WorkoutPointKind.skip, 12, 13, 1),
    _WorkoutPointField(_WorkoutPointKind.power, 16, 17, 2),
    _WorkoutPointField(_WorkoutPointKind.speed, 20, 21, 2),
    _WorkoutPointField(_WorkoutPointKind.cadence, 24, 25, 1),
  ],
);

const _freeTrainingRecordV6 = _WorkoutRecordLayout(
  validityBytes: 2,
  segmentHeaderBytes: 26,
  recordCountOffset: 0,
  resumeTimestampOffset: 4,
  pointFields: [
    _WorkoutPointField(_WorkoutPointKind.heartRate, 0, 1, 1),
    _WorkoutPointField(_WorkoutPointKind.calories, 4, 5, 1),
    _WorkoutPointField(_WorkoutPointKind.bloodOxygen, 8, 9, 1),
    _WorkoutPointField(_WorkoutPointKind.stress, 12, 13, 1),
  ],
);

const _freeTrainingPointFields = <_WorkoutPointField>[
  _WorkoutPointField(_WorkoutPointKind.heartRate, 0, 1, 1),
  _WorkoutPointField(_WorkoutPointKind.calories, 4, 5, 1),
  _WorkoutPointField(_WorkoutPointKind.bloodOxygen, 8, 9, 1),
  _WorkoutPointField(_WorkoutPointKind.stress, 12, 13, 1),
];

const _freeTrainingRecordV4 = _WorkoutRecordLayout(
  validityBytes: 2,
  segmentHeaderBytes: 13,
  recordCountOffset: 0,
  resumeTimestampOffset: 4,
  pointFields: _freeTrainingPointFields,
);

const _freeTrainingRecordV5 = _WorkoutRecordLayout(
  validityBytes: 2,
  segmentHeaderBytes: 19,
  recordCountOffset: 0,
  resumeTimestampOffset: 4,
  pointFields: _freeTrainingPointFields,
);

const _ropeSkippingRecordV6 = _WorkoutRecordLayout(
  validityBytes: 3,
  segmentHeaderBytes: 13,
  recordCountOffset: 0,
  resumeTimestampOffset: 4,
  pointFields: [
    _WorkoutPointField(_WorkoutPointKind.heartRate, 0, 1, 1),
    _WorkoutPointField(_WorkoutPointKind.calories, 4, 5, 1),
    _WorkoutPointField(_WorkoutPointKind.jumpFrequency, 8, 9, 2),
    _WorkoutPointField(_WorkoutPointKind.jumpHeight, 12, 13, 1),
    _WorkoutPointField(_WorkoutPointKind.skip, 16, 17, 1),
  ],
);

const _ellipticalRecordV3 = _WorkoutRecordLayout(
  validityBytes: 2,
  segmentHeaderBytes: 9,
  recordCountOffset: 0,
  resumeTimestampOffset: 4,
  pointFields: [
    _WorkoutPointField(_WorkoutPointKind.caloriesAndSteps, 0, 1, 1),
    _WorkoutPointField(_WorkoutPointKind.heartRate, 4, 5, 1),
    _WorkoutPointField(_WorkoutPointKind.cadence, 8, 9, 1),
  ],
);

const _rowingRecordV4 = _WorkoutRecordLayout(
  validityBytes: 2,
  segmentHeaderBytes: 13,
  recordCountOffset: 0,
  resumeTimestampOffset: 4,
  pointFields: [
    _WorkoutPointField(_WorkoutPointKind.heartRate, 0, 1, 1),
    _WorkoutPointField(_WorkoutPointKind.calories, 4, 5, 1),
    _WorkoutPointField(_WorkoutPointKind.strokeFrequency, 8, 9, 1),
  ],
);

/// The one-dimensional sport-report fields used by Mi Fitness' native
/// report parsers. A field remains in the body when its validity bit is
/// clear; the bit only says whether the decoded value can be used.
class _SportReportField {
  const _SportReportField(this.type, this.byteSize, {this.minimumVersion = 1});

  final int type;
  final int byteSize;
  final int minimumVersion;
}

enum _SportWireType { u8, u16, u32, f32 }

enum _WorkoutReportValue {
  subSportType,
  startedAt,
  endedAt,
  totalDuration,
  effectiveDuration,
  distance,
  totalCalories,
  activeCalories,
  averagePace,
  bestPace,
  worstPace,
  averageSpeed,
  bestSpeed,
  totalSteps,
  averageStride,
  averageCadence,
  maximumCadence,
  averageHeartRate,
  maximumHeartRate,
  minimumHeartRate,
  averageBloodOxygen,
  maximumBloodOxygen,
  minimumBloodOxygen,
  averageStress,
  maximumStress,
  minimumStress,
  totalAscent,
  totalDescent,
  averageAltitude,
  maximumAltitude,
  minimumAltitude,
  aerobicEffect,
  anaerobicEffect,
  peakEffect,
  vo2Max,
  bodyEnergy,
  recoveryHours,
  heartRateZoneMethod,
  heartRateZone5Duration,
  heartRateZone4Duration,
  heartRateZone3Duration,
  heartRateZone2Duration,
  heartRateZone1Duration,
  heartRateZone5Lower,
  heartRateZone4Lower,
  heartRateZone3Lower,
  heartRateZone2Lower,
  heartRateZone1Lower,
  trainingLoad,
  earnedVitality,
  averagePower,
  maximumPower,
  totalArmPulls,
  mainSwimmingStroke,
  averageStrokeRate,
  maximumStrokeRate,
  turnCount,
  averageSwolf,
  bestSwolf,
  poolWidth,
  totalJumps,
  averageJumpRate,
  bestJumpRate,
  tripCount,
  setCount,
  totalStrokes,
  averageRowingRate,
  bestRowingRate,
}

class _ModernSportReportField {
  const _ModernSportReportField.u8(
    this.value,
    this.validityIndex,
    this.offset, {
    this.always = false,
  }) : type = _SportWireType.u8,
       byteSize = 1;
  const _ModernSportReportField.u16(
    this.value,
    this.validityIndex,
    this.offset, {
    this.always = false,
  }) : type = _SportWireType.u16,
       byteSize = 2;
  const _ModernSportReportField.u32(
    this.value,
    this.validityIndex,
    this.offset, {
    this.always = false,
  }) : type = _SportWireType.u32,
       byteSize = 4;
  const _ModernSportReportField.f32(
    this.value,
    this.validityIndex,
    this.offset, {
    this.always = false,
  }) : type = _SportWireType.f32,
       byteSize = 4;

  final _WorkoutReportValue value;
  final int validityIndex;
  final int offset;
  final _SportWireType type;
  final int byteSize;

  /// When true the field is read from the fixed body offset even if the
  /// validity bit is clear. The walking-v2 v6 report's 9-byte validity header
  /// uses a different bit order than the v8/v9 schema, so honoring those bits
  /// would drop fields that are actually present; read fixed offsets instead.
  final bool always;
}

const _modernOutdoorFootReportFields = <_ModernSportReportField>[
  _ModernSportReportField.u16(_WorkoutReportValue.subSportType, 0, 0),
  _ModernSportReportField.u32(_WorkoutReportValue.startedAt, 1, 2),
  _ModernSportReportField.u32(_WorkoutReportValue.endedAt, 2, 6),
  _ModernSportReportField.u32(_WorkoutReportValue.totalDuration, 3, 10),
  _ModernSportReportField.u32(_WorkoutReportValue.effectiveDuration, 4, 14),
  _ModernSportReportField.u32(_WorkoutReportValue.distance, 5, 18),
  _ModernSportReportField.u16(_WorkoutReportValue.totalCalories, 6, 22),
  _ModernSportReportField.u16(_WorkoutReportValue.activeCalories, 7, 24),
  _ModernSportReportField.u32(_WorkoutReportValue.averagePace, 8, 26),
  _ModernSportReportField.u32(_WorkoutReportValue.bestPace, 9, 30),
  _ModernSportReportField.u32(_WorkoutReportValue.worstPace, 10, 34),
  _ModernSportReportField.f32(_WorkoutReportValue.averageSpeed, 11, 38),
  _ModernSportReportField.f32(_WorkoutReportValue.bestSpeed, 12, 42),
  _ModernSportReportField.u32(_WorkoutReportValue.totalSteps, 13, 46),
  _ModernSportReportField.u16(_WorkoutReportValue.averageStride, 14, 50),
  _ModernSportReportField.u16(_WorkoutReportValue.averageCadence, 15, 52),
  _ModernSportReportField.u16(_WorkoutReportValue.maximumCadence, 16, 54),
  _ModernSportReportField.u8(_WorkoutReportValue.averageHeartRate, 17, 56),
  _ModernSportReportField.u8(_WorkoutReportValue.maximumHeartRate, 18, 57),
  _ModernSportReportField.u8(_WorkoutReportValue.minimumHeartRate, 19, 58),
  _ModernSportReportField.f32(_WorkoutReportValue.totalAscent, 20, 59),
  _ModernSportReportField.f32(_WorkoutReportValue.totalDescent, 21, 63),
  _ModernSportReportField.f32(_WorkoutReportValue.averageAltitude, 22, 67),
  _ModernSportReportField.f32(_WorkoutReportValue.maximumAltitude, 23, 71),
  _ModernSportReportField.f32(_WorkoutReportValue.minimumAltitude, 24, 75),
  _ModernSportReportField.f32(_WorkoutReportValue.aerobicEffect, 25, 79),
  _ModernSportReportField.f32(_WorkoutReportValue.anaerobicEffect, 27, 84),
  _ModernSportReportField.f32(_WorkoutReportValue.peakEffect, 29, 89),
  _ModernSportReportField.u8(_WorkoutReportValue.vo2Max, 31, 94),
  _ModernSportReportField.u8(_WorkoutReportValue.bodyEnergy, 33, 96),
  _ModernSportReportField.u16(_WorkoutReportValue.recoveryHours, 34, 97),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZoneMethod, 35, 99),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone5Duration,
    36,
    100,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone4Duration,
    37,
    104,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone3Duration,
    38,
    108,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone2Duration,
    39,
    112,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone1Duration,
    40,
    116,
  ),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone5Lower, 41, 120),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone4Lower, 42, 121),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone3Lower, 43, 122),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone2Lower, 44, 123),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone1Lower, 45, 124),
  _ModernSportReportField.u16(_WorkoutReportValue.trainingLoad, 61, 179),
  _ModernSportReportField.u8(_WorkoutReportValue.earnedVitality, 70, 196),
];

// SPORTS_OUTDOOR_WALKING_V2 v6 report. Unlike the record layout (v5 = the v8
// schema truncated to 13 bytes), the v6 report body does NOT match the v8/v9
// schema: the captured body is 183 bytes (v8 needs 241) and its HR-zone block
// sits at offset 95, not the schema's 100. The server no longer hosts this
// older generation, so the offsets below follow the only calibrated authority
// (Gadgetbridge getOutdoorWalkingV2Parser, headerSize 9). The captured file
// ships a 9-byte validity header whose bit order differs from v8/v9, so every
// field is read from its fixed offset (`always: true`) as GB does.
const _modernOutdoorFootV6ReportFields = <_ModernSportReportField>[
  _ModernSportReportField.u16(
    _WorkoutReportValue.subSportType,
    0,
    0,
    always: true,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.startedAt,
    1,
    2,
    always: true,
  ),
  _ModernSportReportField.u32(_WorkoutReportValue.endedAt, 2, 6, always: true),
  _ModernSportReportField.u32(
    _WorkoutReportValue.effectiveDuration,
    3,
    10,
    always: true,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.distance,
    5,
    18,
    always: true,
  ),
  _ModernSportReportField.u16(
    _WorkoutReportValue.totalCalories,
    6,
    22,
    always: true,
  ),
  _ModernSportReportField.u16(
    _WorkoutReportValue.activeCalories,
    7,
    24,
    always: true,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.averagePace,
    8,
    26,
    always: true,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.bestPace,
    9,
    30,
    always: true,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.worstPace,
    10,
    34,
    always: true,
  ),
  _ModernSportReportField.f32(
    _WorkoutReportValue.averageSpeed,
    11,
    38,
    always: true,
  ),
  _ModernSportReportField.f32(
    _WorkoutReportValue.bestSpeed,
    12,
    42,
    always: true,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.totalSteps,
    13,
    46,
    always: true,
  ),
  _ModernSportReportField.u16(
    _WorkoutReportValue.averageStride,
    14,
    50,
    always: true,
  ),
  _ModernSportReportField.u16(
    _WorkoutReportValue.averageCadence,
    15,
    52,
    always: true,
  ),
  _ModernSportReportField.u16(
    _WorkoutReportValue.maximumCadence,
    16,
    54,
    always: true,
  ),
  _ModernSportReportField.u8(
    _WorkoutReportValue.averageHeartRate,
    17,
    56,
    always: true,
  ),
  _ModernSportReportField.u8(
    _WorkoutReportValue.maximumHeartRate,
    18,
    57,
    always: true,
  ),
  _ModernSportReportField.u8(
    _WorkoutReportValue.minimumHeartRate,
    19,
    58,
    always: true,
  ),
  _ModernSportReportField.f32(
    _WorkoutReportValue.aerobicEffect,
    25,
    79,
    always: true,
  ),
  _ModernSportReportField.f32(
    _WorkoutReportValue.anaerobicEffect,
    27,
    84,
    always: true,
  ),
  _ModernSportReportField.u16(
    _WorkoutReportValue.recoveryHours,
    34,
    92,
    always: true,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone5Duration,
    36,
    95,
    always: true,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone4Duration,
    37,
    99,
    always: true,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone3Duration,
    38,
    103,
    always: true,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone2Duration,
    39,
    107,
    always: true,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone1Duration,
    40,
    111,
    always: true,
  ),
  _ModernSportReportField.u16(
    _WorkoutReportValue.trainingLoad,
    61,
    136,
    always: true,
  ),
  _ModernSportReportField.u8(
    _WorkoutReportValue.earnedVitality,
    70,
    153,
    always: true,
  ),
];

const _modernOutdoorNonFootBaseReportFields = <_ModernSportReportField>[
  _ModernSportReportField.u16(_WorkoutReportValue.subSportType, 0, 0),
  _ModernSportReportField.u32(_WorkoutReportValue.startedAt, 1, 2),
  _ModernSportReportField.u32(_WorkoutReportValue.endedAt, 2, 6),
  _ModernSportReportField.u32(_WorkoutReportValue.totalDuration, 3, 10),
  _ModernSportReportField.u32(_WorkoutReportValue.effectiveDuration, 4, 14),
  _ModernSportReportField.u32(_WorkoutReportValue.distance, 5, 18),
  _ModernSportReportField.u16(_WorkoutReportValue.totalCalories, 6, 22),
  _ModernSportReportField.u16(_WorkoutReportValue.activeCalories, 7, 24),
  _ModernSportReportField.u32(_WorkoutReportValue.bestPace, 8, 26),
  _ModernSportReportField.u32(_WorkoutReportValue.worstPace, 9, 30),
  _ModernSportReportField.f32(_WorkoutReportValue.averageSpeed, 10, 34),
  _ModernSportReportField.f32(_WorkoutReportValue.bestSpeed, 11, 38),
  _ModernSportReportField.u8(_WorkoutReportValue.averageHeartRate, 12, 42),
  _ModernSportReportField.u8(_WorkoutReportValue.maximumHeartRate, 13, 43),
  _ModernSportReportField.u8(_WorkoutReportValue.minimumHeartRate, 14, 44),
  _ModernSportReportField.f32(_WorkoutReportValue.totalAscent, 15, 45),
  _ModernSportReportField.f32(_WorkoutReportValue.totalDescent, 16, 49),
  _ModernSportReportField.f32(_WorkoutReportValue.averageAltitude, 17, 53),
  _ModernSportReportField.f32(_WorkoutReportValue.maximumAltitude, 18, 57),
  _ModernSportReportField.f32(_WorkoutReportValue.minimumAltitude, 19, 61),
  _ModernSportReportField.f32(_WorkoutReportValue.aerobicEffect, 20, 65),
  _ModernSportReportField.f32(_WorkoutReportValue.anaerobicEffect, 22, 70),
  _ModernSportReportField.f32(_WorkoutReportValue.peakEffect, 24, 75),
  _ModernSportReportField.u8(_WorkoutReportValue.vo2Max, 26, 80),
  _ModernSportReportField.u8(_WorkoutReportValue.bodyEnergy, 28, 82),
  _ModernSportReportField.u16(_WorkoutReportValue.recoveryHours, 29, 83),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZoneMethod, 30, 85),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone5Duration,
    31,
    86,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone4Duration,
    32,
    90,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone3Duration,
    33,
    94,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone2Duration,
    34,
    98,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone1Duration,
    35,
    102,
  ),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone5Lower, 36, 106),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone4Lower, 37, 107),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone3Lower, 38, 108),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone2Lower, 39, 109),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone1Lower, 40, 110),
  _ModernSportReportField.u16(_WorkoutReportValue.trainingLoad, 47, 134),
];

const _modernOutdoorNonFootV8ReportFields = <_ModernSportReportField>[
  ..._modernOutdoorNonFootBaseReportFields,
  _ModernSportReportField.u8(_WorkoutReportValue.earnedVitality, 56, 151),
  _ModernSportReportField.u16(_WorkoutReportValue.averageCadence, 57, 152),
  _ModernSportReportField.u16(_WorkoutReportValue.maximumCadence, 58, 154),
];

const _modernOutdoorNonFootV9ReportFields = <_ModernSportReportField>[
  ..._modernOutdoorNonFootBaseReportFields,
  _ModernSportReportField.u8(_WorkoutReportValue.earnedVitality, 50, 138),
  _ModernSportReportField.u16(_WorkoutReportValue.averageCadence, 51, 139),
  _ModernSportReportField.u16(_WorkoutReportValue.maximumCadence, 52, 141),
  _ModernSportReportField.u16(_WorkoutReportValue.averagePower, 60, 154),
  _ModernSportReportField.u16(_WorkoutReportValue.maximumPower, 61, 156),
];

const _modernIndoorRunBaseReportFields = <_ModernSportReportField>[
  _ModernSportReportField.u32(_WorkoutReportValue.startedAt, 0, 0),
  _ModernSportReportField.u32(_WorkoutReportValue.endedAt, 1, 4),
  _ModernSportReportField.u32(_WorkoutReportValue.totalDuration, 2, 8),
  _ModernSportReportField.u32(_WorkoutReportValue.distance, 3, 12),
  _ModernSportReportField.u16(_WorkoutReportValue.activeCalories, 4, 16),
  _ModernSportReportField.u32(_WorkoutReportValue.averagePace, 5, 18),
  _ModernSportReportField.u32(_WorkoutReportValue.bestPace, 6, 22),
  _ModernSportReportField.u32(_WorkoutReportValue.worstPace, 7, 26),
  _ModernSportReportField.u32(_WorkoutReportValue.totalSteps, 8, 30),
  _ModernSportReportField.u16(_WorkoutReportValue.averageStride, 9, 34),
  _ModernSportReportField.u16(_WorkoutReportValue.averageCadence, 10, 36),
  _ModernSportReportField.u16(_WorkoutReportValue.maximumCadence, 11, 38),
  _ModernSportReportField.u8(_WorkoutReportValue.averageHeartRate, 12, 40),
  _ModernSportReportField.u8(_WorkoutReportValue.maximumHeartRate, 13, 41),
  _ModernSportReportField.u8(_WorkoutReportValue.minimumHeartRate, 14, 42),
  _ModernSportReportField.f32(_WorkoutReportValue.aerobicEffect, 15, 43),
  _ModernSportReportField.u8(_WorkoutReportValue.vo2Max, 17, 48),
  _ModernSportReportField.u8(_WorkoutReportValue.bodyEnergy, 19, 50),
  _ModernSportReportField.u16(_WorkoutReportValue.recoveryHours, 20, 51),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone5Duration,
    21,
    53,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone4Duration,
    22,
    57,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone3Duration,
    23,
    61,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone2Duration,
    24,
    65,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone1Duration,
    25,
    69,
  ),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone5Lower, 26, 73),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone4Lower, 27, 74),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone3Lower, 28, 75),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone2Lower, 29, 76),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone1Lower, 30, 77),
  _ModernSportReportField.u16(_WorkoutReportValue.totalCalories, 36, 98),
  _ModernSportReportField.u32(_WorkoutReportValue.effectiveDuration, 37, 100),
  _ModernSportReportField.f32(_WorkoutReportValue.anaerobicEffect, 38, 104),
  _ModernSportReportField.f32(_WorkoutReportValue.peakEffect, 40, 109),
  _ModernSportReportField.u16(_WorkoutReportValue.subSportType, 42, 114),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZoneMethod, 45, 125),
];

const _modernIndoorRunV13ReportFields = <_ModernSportReportField>[
  ..._modernIndoorRunBaseReportFields,
  _ModernSportReportField.u16(_WorkoutReportValue.trainingLoad, 53, 150),
  _ModernSportReportField.u8(_WorkoutReportValue.earnedVitality, 62, 167),
];

const _modernIndoorRunV14ReportFields = <_ModernSportReportField>[
  ..._modernIndoorRunBaseReportFields,
  _ModernSportReportField.u16(_WorkoutReportValue.trainingLoad, 54, 152),
  _ModernSportReportField.u8(_WorkoutReportValue.earnedVitality, 63, 169),
];

const _modernFreeTrainingReportFields = <_ModernSportReportField>[
  _ModernSportReportField.u32(_WorkoutReportValue.startedAt, 0, 0),
  _ModernSportReportField.u32(_WorkoutReportValue.endedAt, 1, 4),
  _ModernSportReportField.u32(_WorkoutReportValue.totalDuration, 2, 8),
  _ModernSportReportField.u16(_WorkoutReportValue.activeCalories, 3, 12),
  _ModernSportReportField.u8(_WorkoutReportValue.averageHeartRate, 4, 14),
  _ModernSportReportField.u8(_WorkoutReportValue.maximumHeartRate, 5, 15),
  _ModernSportReportField.u8(_WorkoutReportValue.minimumHeartRate, 6, 16),
  _ModernSportReportField.u8(_WorkoutReportValue.averageBloodOxygen, 7, 17),
  _ModernSportReportField.u8(_WorkoutReportValue.maximumBloodOxygen, 8, 18),
  _ModernSportReportField.u8(_WorkoutReportValue.minimumBloodOxygen, 9, 19),
  _ModernSportReportField.u8(_WorkoutReportValue.averageStress, 10, 20),
  _ModernSportReportField.u8(_WorkoutReportValue.maximumStress, 11, 21),
  _ModernSportReportField.u8(_WorkoutReportValue.minimumStress, 12, 22),
  _ModernSportReportField.f32(_WorkoutReportValue.aerobicEffect, 13, 23),
  _ModernSportReportField.u8(_WorkoutReportValue.bodyEnergy, 15, 28),
  _ModernSportReportField.u16(_WorkoutReportValue.recoveryHours, 16, 29),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone5Duration,
    17,
    31,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone4Duration,
    18,
    35,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone3Duration,
    19,
    39,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone2Duration,
    20,
    43,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone1Duration,
    21,
    47,
  ),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone5Lower, 22, 51),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone4Lower, 23, 52),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone3Lower, 24, 53),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone2Lower, 25, 54),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone1Lower, 26, 55),
  _ModernSportReportField.u16(_WorkoutReportValue.totalCalories, 27, 56),
  _ModernSportReportField.u32(_WorkoutReportValue.effectiveDuration, 28, 58),
  _ModernSportReportField.f32(_WorkoutReportValue.anaerobicEffect, 29, 62),
  _ModernSportReportField.f32(_WorkoutReportValue.peakEffect, 31, 67),
  _ModernSportReportField.u16(_WorkoutReportValue.subSportType, 33, 72),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZoneMethod, 36, 83),
  _ModernSportReportField.u16(_WorkoutReportValue.trainingLoad, 39, 90),
  _ModernSportReportField.u8(_WorkoutReportValue.earnedVitality, 41, 93),
];

const _modernIndoorCyclingV10ReportFields = <_ModernSportReportField>[
  _ModernSportReportField.u32(_WorkoutReportValue.startedAt, 0, 0),
  _ModernSportReportField.u32(_WorkoutReportValue.endedAt, 1, 4),
  _ModernSportReportField.u32(_WorkoutReportValue.totalDuration, 2, 8),
  _ModernSportReportField.u32(_WorkoutReportValue.distance, 3, 12),
  _ModernSportReportField.u16(_WorkoutReportValue.activeCalories, 4, 16),
  _ModernSportReportField.f32(_WorkoutReportValue.bestSpeed, 5, 18),
  _ModernSportReportField.u8(_WorkoutReportValue.averageHeartRate, 6, 22),
  _ModernSportReportField.u8(_WorkoutReportValue.maximumHeartRate, 7, 23),
  _ModernSportReportField.u8(_WorkoutReportValue.minimumHeartRate, 8, 24),
  _ModernSportReportField.f32(_WorkoutReportValue.aerobicEffect, 9, 25),
  _ModernSportReportField.u8(_WorkoutReportValue.bodyEnergy, 11, 30),
  _ModernSportReportField.u16(_WorkoutReportValue.recoveryHours, 12, 31),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone5Duration,
    13,
    33,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone4Duration,
    14,
    37,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone3Duration,
    15,
    41,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone2Duration,
    16,
    45,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone1Duration,
    17,
    49,
  ),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone5Lower, 18, 53),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone4Lower, 19, 54),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone3Lower, 20, 55),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone2Lower, 21, 56),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone1Lower, 22, 57),
  _ModernSportReportField.u16(_WorkoutReportValue.totalCalories, 23, 58),
  _ModernSportReportField.u32(_WorkoutReportValue.effectiveDuration, 24, 60),
  _ModernSportReportField.f32(_WorkoutReportValue.anaerobicEffect, 25, 64),
  _ModernSportReportField.f32(_WorkoutReportValue.peakEffect, 27, 69),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZoneMethod, 31, 83),
  _ModernSportReportField.u16(_WorkoutReportValue.averageCadence, 35, 94),
  _ModernSportReportField.u16(_WorkoutReportValue.maximumCadence, 36, 96),
  _ModernSportReportField.u16(_WorkoutReportValue.averagePower, 37, 98),
  _ModernSportReportField.u16(_WorkoutReportValue.maximumPower, 38, 100),
  _ModernSportReportField.u16(_WorkoutReportValue.trainingLoad, 45, 120),
  _ModernSportReportField.u8(_WorkoutReportValue.vo2Max, 54, 137),
  _ModernSportReportField.u8(_WorkoutReportValue.earnedVitality, 56, 139),
];

const _modernSwimmingV8ReportFields = <_ModernSportReportField>[
  _ModernSportReportField.u32(_WorkoutReportValue.startedAt, 0, 0),
  _ModernSportReportField.u32(_WorkoutReportValue.endedAt, 1, 4),
  _ModernSportReportField.u32(_WorkoutReportValue.totalDuration, 2, 8),
  _ModernSportReportField.u32(_WorkoutReportValue.distance, 3, 12),
  _ModernSportReportField.u16(_WorkoutReportValue.activeCalories, 4, 16),
  _ModernSportReportField.u32(_WorkoutReportValue.averagePace, 5, 18),
  _ModernSportReportField.u32(_WorkoutReportValue.bestPace, 6, 22),
  _ModernSportReportField.u32(_WorkoutReportValue.worstPace, 7, 26),
  _ModernSportReportField.u8(_WorkoutReportValue.bodyEnergy, 8, 30),
  _ModernSportReportField.u16(_WorkoutReportValue.recoveryHours, 9, 31),
  _ModernSportReportField.u16(_WorkoutReportValue.totalArmPulls, 10, 33),
  _ModernSportReportField.u8(_WorkoutReportValue.mainSwimmingStroke, 11, 35),
  _ModernSportReportField.u8(_WorkoutReportValue.averageStrokeRate, 12, 36),
  _ModernSportReportField.u8(_WorkoutReportValue.maximumStrokeRate, 13, 37),
  _ModernSportReportField.u16(_WorkoutReportValue.turnCount, 14, 38),
  _ModernSportReportField.u16(_WorkoutReportValue.averageSwolf, 15, 40),
  _ModernSportReportField.u16(_WorkoutReportValue.bestSwolf, 16, 42),
  _ModernSportReportField.u8(_WorkoutReportValue.poolWidth, 17, 44),
  _ModernSportReportField.u16(_WorkoutReportValue.totalCalories, 18, 45),
  _ModernSportReportField.u32(_WorkoutReportValue.effectiveDuration, 19, 47),
  _ModernSportReportField.f32(_WorkoutReportValue.aerobicEffect, 25, 67),
  _ModernSportReportField.f32(_WorkoutReportValue.anaerobicEffect, 27, 72),
  _ModernSportReportField.u16(_WorkoutReportValue.trainingLoad, 29, 77),
  _ModernSportReportField.u8(_WorkoutReportValue.earnedVitality, 31, 80),
  _ModernSportReportField.u8(_WorkoutReportValue.averageHeartRate, 46, 100),
  _ModernSportReportField.u8(_WorkoutReportValue.maximumHeartRate, 47, 101),
  _ModernSportReportField.u8(_WorkoutReportValue.minimumHeartRate, 48, 102),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZoneMethod, 49, 103),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone5Duration,
    50,
    104,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone4Duration,
    51,
    108,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone3Duration,
    52,
    112,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone2Duration,
    53,
    116,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone1Duration,
    54,
    120,
  ),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone5Lower, 55, 124),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone4Lower, 56, 125),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone3Lower, 57, 126),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone2Lower, 58, 127),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone1Lower, 59, 128),
];

const _modernRopeSkippingV7ReportFields = <_ModernSportReportField>[
  ..._modernSimpleTrainingCoreReportFields,
  _ModernSportReportField.u32(_WorkoutReportValue.totalJumps, 22, 52),
  _ModernSportReportField.u32(_WorkoutReportValue.averageJumpRate, 23, 56),
  _ModernSportReportField.u32(_WorkoutReportValue.bestJumpRate, 24, 60),
  _ModernSportReportField.u8(_WorkoutReportValue.setCount, 31, 88),
  _ModernSportReportField.u32(_WorkoutReportValue.effectiveDuration, 32, 89),
  _ModernSportReportField.f32(_WorkoutReportValue.anaerobicEffect, 33, 93),
  _ModernSportReportField.f32(_WorkoutReportValue.peakEffect, 35, 98),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZoneMethod, 39, 112),
  _ModernSportReportField.u16(_WorkoutReportValue.tripCount, 43, 121),
  _ModernSportReportField.u16(_WorkoutReportValue.trainingLoad, 44, 123),
  _ModernSportReportField.u8(_WorkoutReportValue.earnedVitality, 46, 126),
];

const _modernRowingV8ReportFields = <_ModernSportReportField>[
  ..._modernSimpleTrainingCoreReportFields,
  _ModernSportReportField.u32(_WorkoutReportValue.totalStrokes, 22, 52),
  _ModernSportReportField.u32(_WorkoutReportValue.averageRowingRate, 23, 56),
  _ModernSportReportField.u32(_WorkoutReportValue.bestRowingRate, 24, 60),
  _ModernSportReportField.u8(_WorkoutReportValue.setCount, 28, 76),
  _ModernSportReportField.u32(_WorkoutReportValue.effectiveDuration, 29, 77),
  _ModernSportReportField.f32(_WorkoutReportValue.anaerobicEffect, 30, 81),
  _ModernSportReportField.f32(_WorkoutReportValue.peakEffect, 32, 86),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZoneMethod, 36, 100),
  _ModernSportReportField.u16(_WorkoutReportValue.trainingLoad, 40, 109),
  _ModernSportReportField.u8(_WorkoutReportValue.earnedVitality, 42, 112),
];

const _modernEllipticalV7ReportFields = <_ModernSportReportField>[
  _ModernSportReportField.u32(_WorkoutReportValue.startedAt, 0, 0),
  _ModernSportReportField.u32(_WorkoutReportValue.endedAt, 1, 4),
  _ModernSportReportField.u32(_WorkoutReportValue.totalDuration, 2, 8),
  _ModernSportReportField.u16(_WorkoutReportValue.activeCalories, 3, 12),
  _ModernSportReportField.u32(_WorkoutReportValue.totalSteps, 4, 14),
  _ModernSportReportField.u16(_WorkoutReportValue.averageCadence, 5, 18),
  _ModernSportReportField.u16(_WorkoutReportValue.maximumCadence, 6, 20),
  _ModernSportReportField.u8(_WorkoutReportValue.averageHeartRate, 7, 22),
  _ModernSportReportField.u8(_WorkoutReportValue.maximumHeartRate, 8, 23),
  _ModernSportReportField.u8(_WorkoutReportValue.minimumHeartRate, 9, 24),
  _ModernSportReportField.f32(_WorkoutReportValue.aerobicEffect, 10, 25),
  _ModernSportReportField.u8(_WorkoutReportValue.bodyEnergy, 12, 30),
  _ModernSportReportField.u16(_WorkoutReportValue.recoveryHours, 13, 31),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone5Duration,
    14,
    33,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone4Duration,
    15,
    37,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone3Duration,
    16,
    41,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone2Duration,
    17,
    45,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone1Duration,
    18,
    49,
  ),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone5Lower, 19, 53),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone4Lower, 20, 54),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone3Lower, 21, 55),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone2Lower, 22, 56),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone1Lower, 23, 57),
  _ModernSportReportField.u16(_WorkoutReportValue.totalCalories, 24, 58),
  _ModernSportReportField.u8(_WorkoutReportValue.setCount, 26, 64),
  _ModernSportReportField.u32(_WorkoutReportValue.effectiveDuration, 27, 65),
  _ModernSportReportField.f32(_WorkoutReportValue.anaerobicEffect, 28, 69),
  _ModernSportReportField.f32(_WorkoutReportValue.peakEffect, 30, 74),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZoneMethod, 34, 88),
  _ModernSportReportField.u16(_WorkoutReportValue.trainingLoad, 38, 97),
  _ModernSportReportField.u8(_WorkoutReportValue.earnedVitality, 40, 100),
];

const _modernSimpleTrainingCoreReportFields = <_ModernSportReportField>[
  _ModernSportReportField.u32(_WorkoutReportValue.startedAt, 0, 0),
  _ModernSportReportField.u32(_WorkoutReportValue.endedAt, 1, 4),
  _ModernSportReportField.u32(_WorkoutReportValue.totalDuration, 2, 8),
  _ModernSportReportField.u16(_WorkoutReportValue.activeCalories, 3, 12),
  _ModernSportReportField.u8(_WorkoutReportValue.averageHeartRate, 4, 14),
  _ModernSportReportField.u8(_WorkoutReportValue.maximumHeartRate, 5, 15),
  _ModernSportReportField.u8(_WorkoutReportValue.minimumHeartRate, 6, 16),
  _ModernSportReportField.f32(_WorkoutReportValue.aerobicEffect, 7, 17),
  _ModernSportReportField.u8(_WorkoutReportValue.bodyEnergy, 9, 22),
  _ModernSportReportField.u16(_WorkoutReportValue.recoveryHours, 10, 23),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone5Duration,
    11,
    25,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone4Duration,
    12,
    29,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone3Duration,
    13,
    33,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone2Duration,
    14,
    37,
  ),
  _ModernSportReportField.u32(
    _WorkoutReportValue.heartRateZone1Duration,
    15,
    41,
  ),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone5Lower, 16, 45),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone4Lower, 17, 46),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone3Lower, 18, 47),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone2Lower, 19, 48),
  _ModernSportReportField.u8(_WorkoutReportValue.heartRateZone1Lower, 20, 49),
  _ModernSportReportField.u16(_WorkoutReportValue.totalCalories, 21, 50),
];

const _sportOutdoorReportFields = <_SportReportField>[
  _SportReportField(1, 4),
  _SportReportField(2, 4),
  _SportReportField(3, 4),
  _SportReportField(5, 4),
  _SportReportField(6, 2),
  _SportReportField(8, 4),
  _SportReportField(9, 4),
  _SportReportField(12, 4),
  _SportReportField(13, 4),
  _SportReportField(14, 2),
  _SportReportField(16, 1),
  _SportReportField(17, 1),
  _SportReportField(18, 1),
];

const _sportOutdoorBikingReportFields = <_SportReportField>[
  _SportReportField(1, 4),
  _SportReportField(2, 4),
  _SportReportField(3, 4),
  _SportReportField(5, 4),
  _SportReportField(6, 2),
  _SportReportField(8, 4),
  _SportReportField(9, 4),
  _SportReportField(12, 4),
  _SportReportField(16, 1),
  _SportReportField(17, 1),
  _SportReportField(18, 1),
];

const _sportIndoorBikingReportFields = <_SportReportField>[
  _SportReportField(1, 4),
  _SportReportField(2, 4),
  _SportReportField(3, 4),
  _SportReportField(5, 4, minimumVersion: 5),
  _SportReportField(6, 2),
  _SportReportField(12, 4, minimumVersion: 5),
  _SportReportField(16, 1),
  _SportReportField(17, 1),
  _SportReportField(18, 1),
];

const _sportIndoorRunReportFields = <_SportReportField>[
  _SportReportField(1, 4),
  _SportReportField(2, 4),
  _SportReportField(3, 4),
  _SportReportField(5, 4),
  _SportReportField(6, 2),
  _SportReportField(10, 4, minimumVersion: 10),
  _SportReportField(8, 4),
  _SportReportField(9, 4),
  _SportReportField(13, 4),
  _SportReportField(148, 2, minimumVersion: 10),
  _SportReportField(15, 2, minimumVersion: 10),
  _SportReportField(14, 2),
  _SportReportField(16, 1),
  _SportReportField(17, 1),
  _SportReportField(18, 1),
];

const _sportSimpleReportFields = <_SportReportField>[
  _SportReportField(1, 4),
  _SportReportField(2, 4),
  _SportReportField(3, 4),
  _SportReportField(6, 2),
  _SportReportField(16, 1),
  _SportReportField(17, 1),
  _SportReportField(18, 1),
];

const _sportSwimmingReportFields = <_SportReportField>[
  _SportReportField(1, 4),
  _SportReportField(2, 4),
  _SportReportField(3, 4),
  _SportReportField(5, 4),
  _SportReportField(6, 2),
  _SportReportField(10, 4, minimumVersion: 7),
  _SportReportField(8, 4),
  _SportReportField(9, 4),
];

const _sportEllipticalReportFields = <_SportReportField>[
  _SportReportField(1, 4),
  _SportReportField(2, 4),
  _SportReportField(3, 4),
  _SportReportField(6, 2),
  _SportReportField(13, 4),
  _SportReportField(15, 2, minimumVersion: 6),
  _SportReportField(14, 2),
  _SportReportField(16, 1),
  _SportReportField(17, 1),
  _SportReportField(18, 1),
];

const _sportSkiReportFields = <_SportReportField>[
  _SportReportField(1, 4),
  _SportReportField(2, 4),
  _SportReportField(3, 4),
  _SportReportField(5, 4),
  _SportReportField(6, 2),
  _SportReportField(11, 4),
  _SportReportField(12, 4),
  _SportReportField(74, 1),
  _SportReportField(16, 1),
  _SportReportField(17, 1),
  _SportReportField(18, 1),
];

const _dailyRecordV1Groups = <_DailyRecordGroup>[
  _DailyRecordGroup(2, <_DailyRecordField>[
    _DailyRecordField(type: 1, startBit: 14, bitSize: 1, validityBit: 4),
    _DailyRecordField(type: 2, startBit: 0, bitSize: 14, validityBit: 2),
  ]),
  _DailyRecordGroup(1, <_DailyRecordField>[
    _DailyRecordField(type: 3, startBit: 4, bitSize: 4, validityBit: 4),
    _DailyRecordField(type: 4, startBit: 0, bitSize: 4, validityBit: 1),
  ]),
  _DailyRecordGroup(1, <_DailyRecordField>[
    _DailyRecordField(type: 5, startBit: 5, bitSize: 3, validityBit: 4),
    _DailyRecordField(type: 6, startBit: 0, bitSize: 5, validityBit: 1),
  ]),
  _DailyRecordGroup(2, <_DailyRecordField>[
    _DailyRecordField(type: 7, startBit: 0, bitSize: 16, validityBit: 4),
  ]),
  _DailyRecordGroup(1, <_DailyRecordField>[
    _DailyRecordField(type: 8, startBit: 0, bitSize: 8, validityBit: 4),
  ]),
  _DailyRecordGroup(1, <_DailyRecordField>[
    _DailyRecordField(type: 9, startBit: 0, bitSize: 8, validityBit: 4),
  ]),
  _DailyRecordGroup(2, <_DailyRecordField>[
    _DailyRecordField(type: 10, startBit: 13, bitSize: 3, validityBit: 4),
    _DailyRecordField(type: 12, startBit: 11, bitSize: 2, validityBit: 2),
    _DailyRecordField(type: 13, startBit: 0, bitSize: 11, validityBit: 1),
  ]),
];

const _dailyRecordV2Groups = <_DailyRecordGroup>[
  _DailyRecordGroup(2, <_DailyRecordField>[
    _DailyRecordField(type: 1, startBit: 14, bitSize: 1, validityBit: 4),
    _DailyRecordField(type: 2, startBit: 0, bitSize: 14, validityBit: 2),
  ]),
  _DailyRecordGroup(1, <_DailyRecordField>[
    _DailyRecordField(type: 3, startBit: 6, bitSize: 2, validityBit: 4),
    _DailyRecordField(type: 4, startBit: 0, bitSize: 6, validityBit: 1),
  ]),
  _DailyRecordGroup(1, <_DailyRecordField>[
    _DailyRecordField(type: 5, startBit: 5, bitSize: 3, validityBit: 4),
    _DailyRecordField(type: 6, startBit: 0, bitSize: 5, validityBit: 1),
  ]),
  _DailyRecordGroup(2, <_DailyRecordField>[
    _DailyRecordField(type: 7, startBit: 0, bitSize: 16, validityBit: 4),
  ]),
  _DailyRecordGroup(1, <_DailyRecordField>[
    _DailyRecordField(type: 8, startBit: 0, bitSize: 8, validityBit: 4),
  ]),
  _DailyRecordGroup(1, <_DailyRecordField>[
    _DailyRecordField(type: 9, startBit: 0, bitSize: 8, validityBit: 4),
  ]),
  _DailyRecordGroup(2, <_DailyRecordField>[
    _DailyRecordField(type: 11, startBit: 10, bitSize: 6, validityBit: 4),
    _DailyRecordField(type: 12, startBit: 8, bitSize: 2, validityBit: 2),
    _DailyRecordField(type: 13, startBit: 0, bitSize: 8, validityBit: 1),
  ]),
  _DailyRecordGroup(1, <_DailyRecordField>[
    _DailyRecordField(type: 14, startBit: 0, bitSize: 8, validityBit: 4),
  ], minimumVersion: 3),
  _DailyRecordGroup(1, <_DailyRecordField>[
    _DailyRecordField(type: 15, startBit: 0, bitSize: 8, validityBit: 4),
  ], minimumVersion: 3),
  // lightSensation is a full uint16 (bits 15-0), not a single byte. Treating it
  // as 1 byte desynchronizes every following record by one byte, which showed
  // up as nonsense heart rates (32 / 156 / 224 bpm) in the UI.
  _DailyRecordGroup(2, <_DailyRecordField>[
    _DailyRecordField(type: 17, startBit: 0, bitSize: 16, validityBit: 4),
  ], minimumVersion: 4),
  // bodyMomentum is likewise a full uint16.
  _DailyRecordGroup(2, <_DailyRecordField>[
    _DailyRecordField(type: 18, startBit: 0, bitSize: 16, validityBit: 4),
  ], minimumVersion: 4),
  _DailyRecordGroup(1, <_DailyRecordField>[
    _DailyRecordField(type: 19, startBit: 0, bitSize: 8, validityBit: 4),
  ], minimumVersion: 5),
];

class _DailyRecordGroup {
  const _DailyRecordGroup(
    this.byteSize,
    this.fields, {
    this.minimumVersion = 1,
  });

  final int byteSize;
  final List<_DailyRecordField> fields;
  final int minimumVersion;
}

class _DailyRecordField {
  const _DailyRecordField({
    required this.type,
    required this.startBit,
    required this.bitSize,
    required this.validityBit,
  });

  final int type;
  final int startBit;
  final int bitSize;
  final int validityBit;
}

class _SleepByteSeries {
  const _SleepByteSeries({
    required this.offset,
    this.average,
    this.minimum,
    this.maximum,
    this.intervalSeconds = 0,
    this.firstRecordTimeSeconds = 0,
    this.values = const [],
  });

  final int offset;
  final int? average;
  final int? minimum;
  final int? maximum;
  final int intervalSeconds;
  final int firstRecordTimeSeconds;
  final List<int?> values;

  _SleepSeriesStats? statsBetween(int startedAt, int endedAt) {
    if (values.isEmpty) {
      if (average == null || minimum == null || maximum == null) return null;
      return _SleepSeriesStats(
        average: average!,
        minimum: minimum!,
        maximum: maximum!,
      );
    }
    if (intervalSeconds <= 0 || firstRecordTimeSeconds <= 0) {
      return _stats(values);
    }
    final selected = <int?>[];
    for (var index = 0; index < values.length; index++) {
      final timestamp = firstRecordTimeSeconds + index * intervalSeconds;
      if (timestamp >= startedAt && timestamp <= endedAt) {
        selected.add(values[index]);
      }
    }
    // A timestamped series with no samples inside this segment must stay
    // empty. Falling back to the whole file leaks another sleep segment's
    // vitals into this one's summary.
    return _stats(selected);
  }

  static _SleepSeriesStats? _stats(Iterable<int?> input) {
    var count = 0;
    var total = 0;
    int? minimum;
    int? maximum;
    for (final value in input) {
      if (value == null) continue;
      count++;
      total += value;
      minimum = minimum == null || value < minimum ? value : minimum;
      maximum = maximum == null || value > maximum ? value : maximum;
    }
    if (count == 0 || minimum == null || maximum == null) return null;
    return _SleepSeriesStats(
      average: (total / count).round(),
      minimum: minimum,
      maximum: maximum,
    );
  }
}

class _SleepSeriesStats {
  const _SleepSeriesStats({
    required this.average,
    required this.minimum,
    required this.maximum,
  });

  final int average;
  final int minimum;
  final int maximum;
}

enum _SleepValidityField {
  start,
  end,
  quality,
  efficiency,
  asleepDuration,
  bedDuration,
  goBed,
  leaveBed,
  hrvAverage,
  hrvStandardDeviation,
  hrvMedian,
  hrvLowerQuantile,
  hrvUpperQuantile,
  hrvMiddleQuantile,
  hrvTimestamp,
  hrvMaximum,
  hrvMinimum,
  hrvBaselineMaximum,
  hrvBaselineMinimum,
  heartRate,
  bloodOxygen,
  hrvSeries,
  snore,
}

class _SleepPacketParseResult {
  const _SleepPacketParseResult({
    required this.stages,
    this.summaries = const [],
  });

  final List<XiaomiActivitySleepStageRecord> stages;
  final List<_SleepPacketSummary> summaries;

  /// Mi Fitness keeps the night with sleepIndex 1 when several summaries are
  /// present. If no indexed night exists, use the longest device summary.
  _SleepPacketSummary? get summary {
    if (summaries.isEmpty) return null;
    final indexed = summaries.where((value) => value.sleepIndex == 1);
    final candidates = indexed.isEmpty ? summaries : indexed;
    return candidates.reduce(
      (left, right) =>
          left.durationMinutes >= right.durationMinutes ? left : right,
    );
  }
}

class _SleepPacketSummary {
  const _SleepPacketSummary({
    required this.startedAtSeconds,
    required this.endedAtSeconds,
    required this.durationMinutes,
    required this.awakeDurationMinutes,
    required this.lightDurationMinutes,
    required this.remDurationMinutes,
    required this.deepDurationMinutes,
    required this.sleepIndex,
    required this.wakeCount,
    required this.hasRem,
    required this.hasStage,
    required this.unknownDurationMinutes,
    required this.sleepScoreVersion,
  });

  final int startedAtSeconds;
  final int endedAtSeconds;
  final int durationMinutes;
  final int awakeDurationMinutes;
  final int lightDurationMinutes;
  final int remDurationMinutes;
  final int deepDurationMinutes;
  final int sleepIndex;
  final int wakeCount;
  final bool hasRem;
  final bool hasStage;
  final int unknownDurationMinutes;
  final int? sleepScoreVersion;

  _SleepPacketSummary copyWith({int? sleepScoreVersion}) => _SleepPacketSummary(
    startedAtSeconds: startedAtSeconds,
    endedAtSeconds: endedAtSeconds,
    durationMinutes: durationMinutes,
    awakeDurationMinutes: awakeDurationMinutes,
    lightDurationMinutes: lightDurationMinutes,
    remDurationMinutes: remDurationMinutes,
    deepDurationMinutes: deepDurationMinutes,
    sleepIndex: sleepIndex,
    wakeCount: wakeCount,
    hasRem: hasRem,
    hasStage: hasStage,
    unknownDurationMinutes: unknownDurationMinutes,
    sleepScoreVersion: sleepScoreVersion ?? this.sleepScoreVersion,
  );
}

pb.WearPacket _fitnessPacket(
  pb_fitness.Fitness_FitnessID id,
  pb_fitness.Fitness payload,
) {
  return pb.WearPacket(
    type: pb.WearPacket_Type.FITNESS,
    id: id.value,
    fitness: payload,
  );
}
