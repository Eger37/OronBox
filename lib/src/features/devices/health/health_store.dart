import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:oronbox/src/core/services/shared_prefs_service.dart';
import 'package:oronbox/src/features/devices/health/health_models.dart';

/// Local store for the rewritten Xiaomi health data model.
///
/// This intentionally uses a new key namespace. The previous health model is
/// not migrated: its entry is removed when this store is first opened for a
/// device.
class HealthStore {
  // v2 and v3 were written with activity timestamps shifted by the host
  // timezone. v4 stored the device's running 7-day total in the per-day
  // vitality field, and v5 may contain records written before Xiaomi raw
  // timestamps were corrected to device-local time. Drop older versions so a
  // corrected sync cannot be mixed with records carrying the old clock.
  static const _keyPrefix = 'health_data_v6_';
  static const _legacyKeyPrefixes = [
    'health_data_v1_',
    'health_data_v2_',
    'health_data_v3_',
    'health_data_v4_',
    'health_data_v5_',
  ];
  static const _maxDailyRecords = 90;
  static const _maxActivitySampleRecords = 30 * 24 * 60;
  static const _maxSleepRecords = 90;
  static const _maxWorkoutRecords = 90;
  static const _maxAbnormalHealthRecords = 90;

  final _prefs = SharedPrefsService.instance;

  Future<XiaomiHealthData> read(String deviceId) async {
    for (final prefix in _legacyKeyPrefixes) {
      final legacyKey = _keyFor(prefix, deviceId);
      if (_prefs.getString(legacyKey) != null) {
        await _prefs.remove(legacyKey);
      }
    }
    final value = _prefs.getString(_key(deviceId));
    if (value == null || value.isEmpty) return const XiaomiHealthData();
    try {
      return await compute(_decodeHealthData, value);
    } catch (_) {
      return const XiaomiHealthData();
    }
  }

  Future<void> write(String deviceId, XiaomiHealthData data) async {
    // De-duplicate before sorting so the caller's merge order is preserved
    // for equal keys. XiaomiHealthSyncService puts freshly received records
    // before the cached records, which lets a repeated sync replace stale
    // daily/sample values for the same date or timestamp.
    final daily = [..._deduplicateDaily(data.daily)]
      ..sort((a, b) => b.date.compareTo(a.date));
    final samples = [..._deduplicateSamples(data.samples)]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final activitySamples = [
      ..._deduplicateActivitySamples(data.activitySamples),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final sleep = [..._deduplicateSleep(data.sleep)]
      ..sort((a, b) {
        final endComparison = b.endedAt.compareTo(a.endedAt);
        if (endComparison != 0) return endComparison;
        return b.startedAt.compareTo(a.startedAt);
      });
    final workouts = [..._deduplicateWorkouts(data.workouts)]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final abnormalHealthRecords = [
      ..._deduplicateAbnormalHealthRecords(data.abnormalHealthRecords),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final normalized = XiaomiHealthData(
      daily: daily.take(_maxDailyRecords).toList(),
      samples: _capSamplesPerMetric(samples),
      activitySamples: activitySamples.take(_maxActivitySampleRecords).toList(),
      sleep: sleep.take(_maxSleepRecords).toList(),
      workouts: [
        for (final workout in workouts.take(_maxWorkoutRecords))
          _capWorkoutPoints(workout),
      ],
      abnormalHealthRecords: abnormalHealthRecords
          .take(_maxAbnormalHealthRecords)
          .toList(),
      capabilities: data.capabilities,
      lastSyncedAt: data.lastSyncedAt,
    );
    final ok = await _prefs.setString(_key(deviceId), normalized.encode());
    if (!ok) throw StateError('Unable to persist health data');
    healthDataRevision.value++;
  }

  String _key(String deviceId) =>
      '$_keyPrefix${sha1.convert(utf8.encode(deviceId)).toString()}';

  String _keyFor(String prefix, String deviceId) =>
      '$prefix${sha1.convert(utf8.encode(deviceId)).toString()}';

  List<HealthDailySummary> _deduplicateDaily(List<HealthDailySummary> values) {
    final result = <String, HealthDailySummary>{};
    for (final value in values) {
      result[_dateKey(value.date)] ??= value;
    }
    return result.values.toList(growable: false);
  }

  List<HealthSample> _deduplicateSamples(List<HealthSample> values) {
    final result = <String, HealthSample>{};
    for (final value in values) {
      result['${value.metric.name}|${value.timestamp.toIso8601String()}'] ??=
          value;
    }
    return result.values.toList(growable: false);
  }

  /// Activity records are composite minute samples. A repeated sync may
  /// contain the same timestamp from a daily-detail file and a later parser
  /// replay may fill in fields that were absent in the first pass. Merge the
  /// newest record field-by-field instead of dropping the richer record or
  /// summing a cumulative value twice.
  List<HealthActivitySample> _deduplicateActivitySamples(
    List<HealthActivitySample> values,
  ) {
    final result = <String, HealthActivitySample>{};
    for (final value in values) {
      final key = value.timestamp.toIso8601String();
      final existing = result[key];
      result[key] = existing == null
          ? value
          : HealthActivitySample(
              timestamp: value.timestamp,
              activityType: value.activityType ?? existing.activityType,
              activityStrength:
                  value.activityStrength ?? existing.activityStrength,
              sportType: value.sportType ?? existing.sportType,
              steps: value.steps ?? existing.steps,
              activeCalories: value.activeCalories ?? existing.activeCalories,
              distanceMeters: value.distanceMeters ?? existing.distanceMeters,
              heartRate: value.heartRate ?? existing.heartRate,
              energy: value.energy ?? existing.energy,
              caloriesDelta: value.caloriesDelta ?? existing.caloriesDelta,
              energyStatus: value.energyStatus ?? existing.energyStatus,
              energyStatusValue:
                  value.energyStatusValue ?? existing.energyStatusValue,
              bloodOxygen: value.bloodOxygen ?? existing.bloodOxygen,
              pressure: value.pressure ?? existing.pressure,
              lightSensation: value.lightSensation ?? existing.lightSensation,
              volumeMomentum: value.volumeMomentum ?? existing.volumeMomentum,
              floors: value.floors ?? existing.floors,
              stress: value.stress ?? existing.stress,
            );
    }
    return result.values.toList(growable: false);
  }

  List<HealthSleepSummary> _deduplicateSleep(List<HealthSleepSummary> values) {
    final result = <String, HealthSleepSummary>{};
    for (final value in values) {
      // Gadgetbridge keys Xiaomi sleep summaries by the exact bedtime. During
      // a night the watch may send that same bedtime repeatedly with
      // progressively later wake times; the later record replaces the
      // earlier one. Do not merge nearby bedtimes or contained intervals:
      // those can be legitimate separate sleep segments.
      final key = value.startedAt.toIso8601String();
      final existing = result[key];
      if (existing == null ||
          value.endedAt.isAfter(existing.endedAt) ||
          (value.endedAt == existing.endedAt &&
              value.stages.length > existing.stages.length)) {
        result[key] = value;
      }
    }
    return result.values.toList(growable: false);
  }

  List<HealthWorkoutSummary> _deduplicateWorkouts(
    List<HealthWorkoutSummary> values,
  ) {
    final result = <String, HealthWorkoutSummary>{};
    for (final value in values) {
      final key = '${value.startedAt.toIso8601String()}|${value.activityType}';
      final existing = result[key];
      if (existing == null ||
          _workoutRichness(value) > _workoutRichness(existing)) {
        result[key] = value;
      }
    }
    return result.values.toList(growable: false);
  }

  int _workoutRichness(HealthWorkoutSummary value) {
    final summaries = <Object?>[
      value.distanceMeters,
      value.calories,
      value.averageHeartRate,
      value.totalDurationSeconds,
      value.averagePaceSecondsPerKilometer,
      value.averageSpeedKph,
      value.averageCadence,
      value.aerobicTrainingEffect,
      value.trainingLoad,
      value.averageSwolf,
      value.totalJumps,
      value.totalStrokes,
    ].whereType<Object>().length;
    return summaries * 2 +
        value.samples.length +
        value.route.length +
        value.heartRateZones.length +
        (value.recovery == null ? 0 : 4);
  }

  List<HealthAbnormalHealthRecord> _deduplicateAbnormalHealthRecords(
    List<HealthAbnormalHealthRecord> values,
  ) {
    final result = <String, HealthAbnormalHealthRecord>{};
    for (final value in values) {
      final key = [
        value.kind.name,
        value.timestamp.toIso8601String(),
        value.startedAt?.toIso8601String() ?? '',
        value.endedAt?.toIso8601String() ?? '',
      ].join('|');
      result[key] ??= value;
    }
    return result.values.toList(growable: false);
  }

  String _dateKey(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

XiaomiHealthData _decodeHealthData(String value) =>
    XiaomiHealthData.decode(value);

// Retention budget per metric, not per row: each minute-level activity
// record fans out into up to five derived HealthSample rows (heart rate,
// blood oxygen, stress, steps, active calories), so a single global row
// cap would silently truncate the 30-day window to under a week.
const _healthSampleRecordsPerMetric = 30 * 24 * 60;
// Per-point lists inside a workout (1 Hz samples and GPS route) can reach
// tens of thousands of entries; keep them bounded so the single encoded
// blob stays a size SharedPreferences can write without jank.
const _healthWorkoutPointRecords = 2000;

/// Bumped after every successful [HealthStore.write] so open health pages
/// can refresh when a sync (manual, scheduled, or command-bus driven)
/// persists new data while they are mounted.
final healthDataRevision = ValueNotifier<int>(0);

/// Keeps the newest [_healthSampleRecordsPerMetric] rows for every metric
/// independently. [sortedDesc] must be newest-first, per-metric truncation
/// then always drops the oldest rows.
List<HealthSample> _capSamplesPerMetric(List<HealthSample> sortedDesc) {
  final remaining = <XiaomiHealthMetric, int>{};
  final result = <HealthSample>[];
  for (final sample in sortedDesc) {
    final budget = remaining.update(
      sample.metric,
      (value) => value - 1,
      ifAbsent: () => _healthSampleRecordsPerMetric,
    );
    if (budget <= 0) continue;
    result.add(sample);
  }
  return result;
}

/// Bounds the per-second sample/route lists of one workout with stride
/// downsampling that always preserves the first and last point. Rebuilds
/// through the JSON round-trip so the constructor list does not need a
/// 70-parameter copyWith.
HealthWorkoutSummary _capWorkoutPoints(HealthWorkoutSummary workout) {
  if (workout.samples.length <= _healthWorkoutPointRecords &&
      workout.route.length <= _healthWorkoutPointRecords) {
    return workout;
  }
  final json = workout.toJson();
  json['samples'] = _downsamplePoints(workout.samples)
      .map((HealthWorkoutSample value) => value.toJson())
      .toList();
  json['route'] = _downsamplePoints(workout.route)
      .map((HealthWorkoutRoutePoint value) => value.toJson())
      .toList();
  return HealthWorkoutSummary.fromJson(json);
}

List<T> _downsamplePoints<T>(List<T> points) {
  if (points.length <= _healthWorkoutPointRecords) return points;
  final step = points.length / _healthWorkoutPointRecords;
  final result = <T>[];
  for (var position = 0.0; position < points.length - 1; position += step) {
    result.add(points[position.floor()]);
  }
  result.add(points.last);
  return result;
}
