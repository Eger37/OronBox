import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:segmented_list/segmented_list.dart';
import 'package:oronbox/src/app/generated/app_localizations.dart';
import 'package:oronbox/src/app/widgets/sys_app_bar.dart';
import 'package:oronbox/src/core/constants/style_constants.dart';
import 'package:oronbox/src/features/devices/controllers/device_manager.dart';
import 'package:oronbox/src/features/devices/health/health_cards.dart';
import 'package:oronbox/src/features/devices/health/health_models.dart';

class XiaomiHealthDetailArgs {
  const XiaomiHealthDetailArgs({required this.metric, required this.data});

  final XiaomiHealthMetric metric;
  final XiaomiHealthData data;
}

/// The in-memory preview passed while opening a workout from the current
/// health snapshot. The route still carries [workoutId], so a deep link or a
/// restored route can reload the record from the local health store.
class XiaomiHealthWorkoutRouteArgs {
  const XiaomiHealthWorkoutRouteArgs({
    required this.health,
    required this.workout,
  });

  final XiaomiHealthDetailArgs health;
  final HealthWorkoutSummary workout;
}

String xiaomiHealthWorkoutRouteId(HealthWorkoutSummary workout) =>
    '${workout.startedAt.toUtc().millisecondsSinceEpoch}-${workout.activityType}';

class XiaomiHealthDetailPage extends StatefulWidget {
  const XiaomiHealthDetailPage({super.key, required this.args});

  final XiaomiHealthDetailArgs args;

  @override
  State<XiaomiHealthDetailPage> createState() => _XiaomiHealthDetailPageState();
}

class _XiaomiHealthDetailPageState extends State<XiaomiHealthDetailPage> {
  late HealthChartPeriod _period;
  late DateTime _anchorDate;

  XiaomiHealthDetailArgs get args => widget.args;

  @override
  void initState() {
    super.initState();
    _period = HealthChartPeriod.day;
    _anchorDate = _initialAnchorDate(args.data, args.metric);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SysAppBar(
        secondary: true,
        title: Text(_title(l10n, args.metric)),
      ),
      body: SegmentedList(
        maxWidth: StyleConstants.pageMaxWidth,
        contentPadding: const EdgeInsets.only(top: 8, bottom: 24),
        sections: _sections(context),
      ),
    );
  }

  List<AbstractSegmentedSection> _sections(BuildContext context) {
    if (args.metric == XiaomiHealthMetric.workout) {
      return [
        CustomSegmentedSection(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                _HealthPeriodHeader(
                  period: _period,
                  anchorDate: _anchorDate,
                  canGoForward: _canGoForward,
                  onPeriodChanged: (period) => setState(() => _period = period),
                  onPrevious: () => _shiftPeriod(-1),
                  onNext: _canGoForward ? () => _shiftPeriod(1) : null,
                ),
                const SizedBox(height: 20),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  reverseDuration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(.035, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey<Object>(
                      '${args.metric.name}:${_period.name}:'
                      '${_currentRange.start.millisecondsSinceEpoch}',
                    ),
                    child: _workouts(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    final content = switch (args.metric) {
      XiaomiHealthMetric.activity => _activity(context),
      XiaomiHealthMetric.activeCalories => _activity(context),
      XiaomiHealthMetric.heartRate => _heartRate(context),
      XiaomiHealthMetric.restingHeartRate => _restingHeartRate(context),
      XiaomiHealthMetric.bloodOxygen => _seriesWithAbnormal(
        context,
        HealthAbnormalHealthKind.lowBloodOxygen,
      ),
      XiaomiHealthMetric.stress => _seriesWithAbnormal(
        context,
        HealthAbnormalHealthKind.highStress,
      ),
      XiaomiHealthMetric.vitality => _vitality(context),
      XiaomiHealthMetric.sleep => _sleep(context),
      XiaomiHealthMetric.workout => throw StateError('Handled above'),
    };
    return [
      CustomSegmentedSection(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              _HealthPeriodHeader(
                period: _period,
                anchorDate: _anchorDate,
                canGoForward: _canGoForward,
                onPeriodChanged: (period) => setState(() => _period = period),
                onPrevious: () => _shiftPeriod(-1),
                onNext: _canGoForward ? () => _shiftPeriod(1) : null,
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                reverseDuration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final offset = Tween<Offset>(
                    begin: const Offset(.035, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: offset, child: child),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<Object>(
                    '${args.metric.name}:${_period.name}:'
                    '${_currentRange.start.millisecondsSinceEpoch}',
                  ),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  _HealthDateRange get _currentRange =>
      _healthPeriodRange(_period, _anchorDate);

  bool get _canGoForward {
    final current = _healthPeriodRange(
      _period,
      _dateOnly(DateTime.now()),
    ).start;
    return _currentRange.start.isBefore(current);
  }

  void _shiftPeriod(int amount) {
    final next = switch (_period) {
      HealthChartPeriod.day => healthAddCalendarDays(_anchorDate, amount),
      HealthChartPeriod.week => healthAddCalendarDays(_anchorDate, amount * 7),
      HealthChartPeriod.month => DateTime(
        _anchorDate.year,
        _anchorDate.month + amount,
        1,
      ),
    };
    final normalized = _dateOnly(next);
    if (amount > 0 &&
        _healthPeriodRange(_period, normalized).start.isAfter(
          _healthPeriodRange(_period, _dateOnly(DateTime.now())).start,
        )) {
      return;
    }
    setState(() => _anchorDate = normalized);
  }

  Widget _heartRate(BuildContext context) {
    final content = <Widget>[_series(context)];
    final summary = _periodVitalsCard(context, XiaomiHealthMetric.heartRate);
    if (summary != null) {
      content
        ..add(const SizedBox(height: 16))
        ..add(summary);
    }
    const kinds = [
      HealthAbnormalHealthKind.highHeartRate,
      HealthAbnormalHealthKind.lowHeartRate,
      HealthAbnormalHealthKind.irregularHeartbeat,
    ];
    final availableKinds = kinds
        .where((kind) => _abnormalRecords({kind}).isNotEmpty)
        .toList();
    if (availableKinds.isNotEmpty) {
      content
        ..add(const SizedBox(height: 16))
        ..add(_heartHealthMonitoring(context, availableKinds));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: content,
    );
  }

  Widget _heartHealthMonitoring(
    BuildContext context,
    List<HealthAbnormalHealthKind> kinds,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        for (final (index, kind) in kinds.indexed) ...[
          if (index > 0) const SizedBox(height: 12),
          _abnormalEventSection(
            context,
            _abnormalRecords({kind}),
            _abnormalLabelForKind(l10n, kind),
            kind,
          ),
        ],
      ],
    );
  }

  Widget _seriesWithAbnormal(
    BuildContext context,
    HealthAbnormalHealthKind kind,
  ) {
    final records = _abnormalRecords({kind});
    final content = <Widget>[_series(context)];
    final summary = _periodVitalsCard(context, args.metric);
    if (summary != null) {
      content
        ..add(const SizedBox(height: 16))
        ..add(summary);
    }
    if (records.isNotEmpty) {
      content
        ..add(const SizedBox(height: 16))
        ..add(
          _abnormalEventSection(
            context,
            records,
            _abnormalLabelForKind(AppLocalizations.of(context)!, kind),
            kind,
          ),
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: content,
    );
  }

  Widget? _periodVitalsCard(BuildContext context, XiaomiHealthMetric metric) {
    final range = _currentRange;
    final days = _dailyDaysInRange(range)
        .where((day) => _hasDailyVitals(day, metric))
        .toList(growable: false);
    final samples =
        args.data
            .samplesFor(metric)
            .where((sample) {
              final timestamp = sample.timestamp.toLocal();
              return sample.isUsable &&
                  !timestamp.isBefore(range.start) &&
                  timestamp.isBefore(range.end);
            })
            .toList(growable: false)
          // The store keeps samples newest-first. The "latest" summary values below
          // must read the newest sample, so restore chronological order to match
          // the trend chart instead of reporting the oldest point.
          ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    if (days.isEmpty && samples.isEmpty) return null;

    final isDay = _period == HealthChartPeriod.day;
    final values = switch (metric) {
      XiaomiHealthMetric.heartRate => _heartRateOverviewValues(
        context,
        days,
        samples,
        isDay,
      ),
      XiaomiHealthMetric.stress => _stressOverviewValues(
        context,
        days,
        samples,
        isDay,
      ),
      _ => _bloodOxygenOverviewValues(context, days, samples, isDay),
    };
    if (values.isEmpty) return null;
    return _DetailCard(
      child: _HealthSummaryStats(entries: values, columns: values.length),
    );
  }

  bool _hasDailyVitals(HealthDailySummary day, XiaomiHealthMetric metric) =>
      switch (metric) {
        XiaomiHealthMetric.heartRate =>
          day.restingHeartRate != null ||
              day.minHeartRate != null ||
              day.maxHeartRate != null ||
              day.averageHeartRate != null,
        XiaomiHealthMetric.bloodOxygen =>
          day.currentBloodOxygen != null ||
              day.averageBloodOxygen != null ||
              day.minBloodOxygen != null ||
              day.maxBloodOxygen != null,
        XiaomiHealthMetric.stress =>
          day.averageStress != null ||
              day.minStress != null ||
              day.maxStress != null,
        _ => false,
      };

  List<(String, String)> _heartRateOverviewValues(
    BuildContext context,
    List<HealthDailySummary> days,
    List<HealthSample> samples,
    bool isDay,
  ) {
    if (isDay) {
      final day = days.lastOrNull;
      final minimum = day?.minHeartRate ?? _minimumSampleValue(samples);
      final maximum = day?.maxHeartRate ?? _maximumSampleValue(samples);
      return [
        (
          AppLocalizations.of(context)!.deviceHealthAverage,
          _withUnit(
            day?.averageHeartRate ?? _averageSampleValue(samples),
            'bpm',
          ),
        ),
        (
          AppLocalizations.of(context)!.deviceHealthResting,
          _withUnit(day?.restingHeartRate, 'bpm'),
        ),
        (
          AppLocalizations.of(context)!.deviceHealthMinimum,
          _withUnit(minimum, 'bpm'),
        ),
        (
          AppLocalizations.of(context)!.deviceHealthMaximum,
          _withUnit(maximum, 'bpm'),
        ),
      ];
    }
    final dailyAverages = days.map((day) => day.averageHeartRate);
    final average = _averageInt(dailyAverages) ?? _averageSampleValue(samples);
    final resting = _averageInt(days.map((day) => day.restingHeartRate));
    return [
      (
        AppLocalizations.of(context)!.deviceHealthAverage,
        _withUnit(average, 'bpm'),
      ),
      (
        AppLocalizations.of(context)!.deviceHealthResting,
        _withUnit(resting, 'bpm'),
      ),
      (
        AppLocalizations.of(context)!.deviceHealthMinimum,
        _withUnit(
          _minimumInt(days.map((day) => day.minHeartRate)) ??
              _minimumSampleValue(samples),
          'bpm',
        ),
      ),
      (
        AppLocalizations.of(context)!.deviceHealthMaximum,
        _withUnit(
          _maximumInt(days.map((day) => day.maxHeartRate)) ??
              _maximumSampleValue(samples),
          'bpm',
        ),
      ),
    ];
  }

  List<(String, String)> _bloodOxygenOverviewValues(
    BuildContext context,
    List<HealthDailySummary> days,
    List<HealthSample> samples,
    bool isDay,
  ) {
    if (isDay) {
      final day = days.lastOrNull;
      return [
        (
          AppLocalizations.of(context)!.deviceHealthAverage,
          _withUnit(
            day?.averageBloodOxygen ?? _averageSampleValue(samples),
            '%',
          ),
        ),
        (
          AppLocalizations.of(context)!.deviceHealthMinimum,
          _withUnit(day?.minBloodOxygen ?? _minimumSampleValue(samples), '%'),
        ),
        (
          AppLocalizations.of(context)!.deviceHealthMaximum,
          _withUnit(day?.maxBloodOxygen ?? _maximumSampleValue(samples), '%'),
        ),
      ];
    }
    return [
      (
        AppLocalizations.of(context)!.deviceHealthAverage,
        _withUnit(
          _averageInt(days.map((day) => day.averageBloodOxygen)) ??
              _averageSampleValue(samples),
          '%',
        ),
      ),
      (
        AppLocalizations.of(context)!.deviceHealthMinimum,
        _withUnit(
          _minimumInt(days.map((day) => day.minBloodOxygen)) ??
              _minimumSampleValue(samples),
          '%',
        ),
      ),
      (
        AppLocalizations.of(context)!.deviceHealthMaximum,
        _withUnit(
          _maximumInt(days.map((day) => day.maxBloodOxygen)) ??
              _maximumSampleValue(samples),
          '%',
        ),
      ),
    ];
  }

  List<(String, String)> _stressOverviewValues(
    BuildContext context,
    List<HealthDailySummary> days,
    List<HealthSample> samples,
    bool isDay,
  ) {
    if (isDay) {
      final day = days.lastOrNull;
      return [
        (
          AppLocalizations.of(context)!.deviceHealthAverage,
          _withUnit(day?.averageStress ?? _averageSampleValue(samples), ''),
        ),
        (
          AppLocalizations.of(context)!.deviceHealthMinimum,
          _withUnit(day?.minStress ?? _minimumSampleValue(samples), ''),
        ),
        (
          AppLocalizations.of(context)!.deviceHealthMaximum,
          _withUnit(day?.maxStress ?? _maximumSampleValue(samples), ''),
        ),
      ];
    }
    return [
      (
        AppLocalizations.of(context)!.deviceHealthAverage,
        _withUnit(
          _averageInt(days.map((day) => day.averageStress)) ??
              _averageSampleValue(samples),
          '',
        ),
      ),
      (
        AppLocalizations.of(context)!.deviceHealthMinimum,
        _withUnit(
          _minimumInt(days.map((day) => day.minStress)) ??
              _minimumSampleValue(samples),
          '',
        ),
      ),
      (
        AppLocalizations.of(context)!.deviceHealthMaximum,
        _withUnit(
          _maximumInt(days.map((day) => day.maxStress)) ??
              _maximumSampleValue(samples),
          '',
        ),
      ),
    ];
  }

  int? _averageInt(Iterable<int?> values) {
    final present = values.whereType<int>().toList(growable: false);
    if (present.isEmpty) return null;
    return (present.reduce((left, right) => left + right) / present.length)
        .round();
  }

  int? _minimumInt(Iterable<int?> values) {
    final present = values.whereType<int>();
    return present.isEmpty ? null : present.reduce(math.min);
  }

  int? _maximumInt(Iterable<int?> values) {
    final present = values.whereType<int>();
    return present.isEmpty ? null : present.reduce(math.max);
  }

  int? _averageSampleValue(List<HealthSample> samples) {
    if (samples.isEmpty) return null;
    return (samples.map((sample) => sample.value).reduce((a, b) => a + b) /
            samples.length)
        .round();
  }

  int? _minimumSampleValue(List<HealthSample> samples) => samples.isEmpty
      ? null
      : samples.map((sample) => sample.value.round()).reduce(math.min);

  int? _maximumSampleValue(List<HealthSample> samples) => samples.isEmpty
      ? null
      : samples.map((sample) => sample.value.round()).reduce(math.max);

  Widget _restingHeartRate(BuildContext context) {
    return _HealthTrendSection(
      data: args.data,
      metric: XiaomiHealthMetric.restingHeartRate,
      color: _color(XiaomiHealthMetric.restingHeartRate),
      period: _period,
      anchorDate: _anchorDate,
    );
  }

  Widget _abnormalEventSection(
    BuildContext context,
    List<HealthAbnormalHealthRecord> records,
    String title,
    HealthAbnormalHealthKind kind,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final sorted = [...records]
      ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_abnormalIcon(kind), color: _abnormalColor(kind)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text('${sorted.length} ${l10n.deviceHealthRecordCount}'),
            ],
          ),
          const SizedBox(height: 12),
          for (final (index, record) in sorted.indexed) ...[
            if (index > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _abnormalValue(record, l10n),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _abnormalDetails(record),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<HealthAbnormalHealthRecord> _abnormalRecords(
    Set<HealthAbnormalHealthKind> kinds,
  ) => args.data.abnormalHealthRecords
      .where((record) => kinds.contains(record.kind))
      .where((record) {
        final start = record.startedAt ?? record.timestamp;
        final end = record.endedAt ?? start;
        return _overlaps(_currentRange, start, end);
      })
      .toList(growable: false);

  String _abnormalLabelForKind(
    AppLocalizations l10n,
    HealthAbnormalHealthKind kind,
  ) => switch (kind) {
    HealthAbnormalHealthKind.highHeartRate => l10n.deviceHealthHeartRateHigh,
    HealthAbnormalHealthKind.lowHeartRate => l10n.deviceHealthHeartRateLow,
    HealthAbnormalHealthKind.lowBloodOxygen => l10n.deviceHealthLowBloodOxygen,
    HealthAbnormalHealthKind.highStress => l10n.deviceHealthHighStress,
    HealthAbnormalHealthKind.irregularHeartbeat =>
      l10n.deviceHealthIrregularHeartbeat,
  };

  IconData _abnormalIcon(HealthAbnormalHealthKind kind) => switch (kind) {
    HealthAbnormalHealthKind.highHeartRate ||
    HealthAbnormalHealthKind.highStress => Icons.trending_up,
    HealthAbnormalHealthKind.lowHeartRate ||
    HealthAbnormalHealthKind.lowBloodOxygen => Icons.trending_down,
    HealthAbnormalHealthKind.irregularHeartbeat => Icons.favorite_outline,
  };

  Color _abnormalColor(HealthAbnormalHealthKind kind) => switch (kind) {
    HealthAbnormalHealthKind.highHeartRate ||
    HealthAbnormalHealthKind.lowHeartRate ||
    HealthAbnormalHealthKind.irregularHeartbeat => Colors.redAccent,
    HealthAbnormalHealthKind.lowBloodOxygen => Colors.indigo,
    HealthAbnormalHealthKind.highStress => Colors.orange,
  };

  String _abnormalValue(
    HealthAbnormalHealthRecord record,
    AppLocalizations l10n,
  ) {
    final value = record.value;
    if (record.kind == HealthAbnormalHealthKind.irregularHeartbeat) {
      final start = record.startedAt ?? record.timestamp;
      final end = record.endedAt;
      return end == null
          ? l10n.deviceHealthDetected
          : _durationBetween(start, end);
    }
    if (value == null) return '—';
    return switch (record.kind) {
      HealthAbnormalHealthKind.highHeartRate ||
      HealthAbnormalHealthKind.lowHeartRate => '$value bpm',
      HealthAbnormalHealthKind.lowBloodOxygen => '$value%',
      HealthAbnormalHealthKind.highStress => '$value',
      HealthAbnormalHealthKind.irregularHeartbeat => l10n.deviceHealthDetected,
    };
  }

  String _abnormalDetails(HealthAbnormalHealthRecord record) {
    final start = record.startedAt ?? record.timestamp;
    final end = record.endedAt;
    final time = end == null
        ? _sleepDateTime(start)
        : '${_sleepDateTime(start)} – ${_sleepDateTime(end)}';
    if (record.kind == HealthAbnormalHealthKind.irregularHeartbeat) {
      return end == null ? time : '$time · ${_durationBetween(start, end)}';
    }
    final threshold = record.threshold;
    if (threshold == null) return time;
    final unit = switch (record.kind) {
      HealthAbnormalHealthKind.highHeartRate ||
      HealthAbnormalHealthKind.lowHeartRate => 'bpm',
      HealthAbnormalHealthKind.lowBloodOxygen => '%',
      HealthAbnormalHealthKind.highStress => '',
      HealthAbnormalHealthKind.irregularHeartbeat => '',
    };
    final operator = switch (record.kind) {
      HealthAbnormalHealthKind.highHeartRate ||
      HealthAbnormalHealthKind.highStress => '≥',
      HealthAbnormalHealthKind.lowHeartRate ||
      HealthAbnormalHealthKind.lowBloodOxygen => '≤',
      HealthAbnormalHealthKind.irregularHeartbeat => '',
    };
    return '$time · $operator $threshold$unit';
  }

  Widget _activity(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final range = _currentRange;
    final values = _activityValues(range);
    if (_period == HealthChartPeriod.day) {
      final samples = _activitySamplesForDay(range.start);
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActivityMetricCard(
            title: l10n.deviceHealthActiveCalories,
            value: _withUnit(values.activeCalories, 'kcal'),
            chart: ActivityHourlyChart(
              values: _activityHourlySeries(
                samples,
                (sample) => sample.activeCalories,
                XiaomiHealthMetric.activeCalories,
              ),
              start: range.start,
              end: range.end,
              color: colors.primary,
              gridColor: colors.outlineVariant,
            ),
          ),
          const SizedBox(height: 12),
          _ActivityMetricCard(
            title: l10n.deviceHealthSteps,
            value: _number(values.steps),
            chart: ActivityHourlyChart(
              values: _activityHourlySeries(
                samples,
                (sample) => sample.steps,
                XiaomiHealthMetric.activity,
              ),
              start: range.start,
              end: range.end,
              color: colors.tertiary,
              gridColor: colors.outlineVariant,
            ),
          ),
          const SizedBox(height: 12),
          _ActivityMetricCard(
            title: l10n.deviceHealthStanding,
            value: _withUnit(values.standingHours, 'h'),
            chart: ActivityHourlyChart(
              values: _standingHourlySeries(range.start, samples),
              start: range.start,
              end: range.end,
              color: colors.secondary,
              gridColor: colors.outlineVariant,
              showYAxis: false,
            ),
          ),
        ],
      );
    }
    final chartDays = _activityChartDaysInRange(range);
    final activitySamples = args.data.activitySamples
        .where(
          (sample) =>
              !sample.timestamp.isBefore(range.start) &&
              sample.timestamp.isBefore(range.end),
        )
        .toList();
    final chartMetric = args.metric == XiaomiHealthMetric.activeCalories
        ? XiaomiHealthMetric.activeCalories
        : XiaomiHealthMetric.activity;
    final activityColors = Theme.of(context).colorScheme;
    final chartColor = chartMetric == XiaomiHealthMetric.activeCalories
        ? activityColors.primary
        : activityColors.tertiary;
    final hasTrend = _period == HealthChartPeriod.day
        ? activitySamples.isNotEmpty
        : chartDays.any(
            (day) =>
                (chartMetric == XiaomiHealthMetric.activity
                    ? day.steps
                    : day.activeCalories) !=
                null,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveHealthCardWrap(
          children: [
            _ActivityMetricCard(
              title: l10n.deviceHealthActiveCalories,
              value: _withUnit(values.activeCalories, 'kcal'),
            ),
            _ActivityMetricCard(
              title: l10n.deviceHealthSteps,
              value: _number(values.steps),
            ),
            _ActivityMetricCard(
              title: l10n.deviceHealthStanding,
              value: _withUnit(values.standingHours, 'h'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chartMetric == XiaomiHealthMetric.activity
                    ? l10n.deviceHealthSteps
                    : l10n.deviceHealthActiveCalories,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (!hasTrend)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: Text(l10n.deviceHealthNoSamples)),
                )
              else if (_period == HealthChartPeriod.day)
                ActivityTimelineChart(
                  samples: activitySamples,
                  start: range.start,
                  end: range.end,
                  useCalories: chartMetric == XiaomiHealthMetric.activeCalories,
                  height: 188,
                )
              else
                HealthOfficialRangeChart(
                  metric: chartMetric,
                  period: _period,
                  samples: const [],
                  days: chartDays,
                  color: chartColor,
                  start: range.start,
                  end: range.end,
                  height: 188,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _series(BuildContext context) {
    return _HealthTrendSection(
      data: args.data,
      metric: args.metric,
      color: _color(args.metric),
      period: _period,
      anchorDate: _anchorDate,
    );
  }

  Widget _vitality(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final days = _dailyDaysInRange(_currentRange)
        .where(
          (day) =>
              day.vitalityCurrent != null ||
              day.vitalityIncreaseLight != null ||
              day.vitalityIncreaseModerate != null ||
              day.vitalityIncreaseHigh != null ||
              day.vitalityLast7Days != null ||
              day.trainingLoadToday != null ||
              day.trainingLoadLast7Days != null,
        )
        .toList(growable: false);
    final day = days.isEmpty ? null : days.last;
    final light = _sum(days.map((value) => value.vitalityIncreaseLight));
    final moderate = _sum(days.map((value) => value.vitalityIncreaseModerate));
    final high = _sum(days.map((value) => value.vitalityIncreaseHigh));
    if (day == null) {
      return _DetailCard(child: Text(l10n.deviceHealthNoData));
    }
    // The device's embedded 7-day field is not reliable when a day is zero
    // (it is sometimes calculated over the last seven non-zero days). Build
    // the calendar-window total locally and retain explicit zeroes.
    final vitalityScore = _vitalitySevenDayTotal(day);
    final trainingValues = <(String, String)>[
      if (day.remainingRecoveryHours != null)
        (
          AppLocalizations.of(context)!.deviceHealthRecoveryTime,
          '${day.remainingRecoveryHours} h',
        ),
      if (day.trainingLoadToday != null)
        (
          AppLocalizations.of(context)!.deviceHealthTodayLoad,
          '${day.trainingLoadToday}',
        ),
      if (day.trainingLoadLast7Days != null)
        (
          AppLocalizations.of(context)!.deviceHealthSevenDayLoad,
          '${day.trainingLoadLast7Days}',
        ),
      if (day.trainingLoadLevel != null)
        (
          AppLocalizations.of(context)!.deviceHealthLoadLevel,
          '${day.trainingLoadLevel}',
        ),
      if (day.fitnessBalance != null)
        (
          AppLocalizations.of(context)!.deviceHealthFitnessBalance,
          '${day.fitnessBalance}',
        ),
      if (day.fitnessLevel != null)
        (
          AppLocalizations.of(context)!.deviceHealthFitnessLevel,
          '${day.fitnessLevel}',
        ),
      if (day.fatigueLevel != null)
        (
          AppLocalizations.of(context)!.deviceHealthFatigueLevel,
          '${day.fatigueLevel}',
        ),
      if (day.trainingStressScore != null)
        (
          AppLocalizations.of(context)!.deviceHealthTrainingStress,
          '${day.trainingStressScore}',
        ),
    ];
    final theme = Theme.of(context);
    final vitalityColor = _color(XiaomiHealthMetric.vitality);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_fire_department_outlined,
                    color: vitalityColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.deviceHealthVitality,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.deviceHealthCurrentVitality,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _number(day.vitalityCurrent ?? vitalityScore),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        l10n.deviceHealthSevenDayVitality,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _number(vitalityScore),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: vitalityScore == null
                      ? 0
                      : (vitalityScore / 100).clamp(0.0, 1.0),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: vitalityColor,
                ),
              ),
              if (day.vitalityNextTargetMinutes != null) ...[
                const SizedBox(height: 6),
                Text(
                  day.vitalityNextTargetType == 1
                      ? l10n.deviceHealthVitalityRunSuggestion(
                          day.vitalityNextTargetMinutes!,
                        )
                      : l10n.deviceHealthVitalityActiveMinutes(
                          day.vitalityNextTargetMinutes!,
                        ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                _period == HealthChartPeriod.day
                    ? l10n.deviceHealthEarnedToday
                    : l10n.deviceHealthEarnedInPeriod,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _HealthSummaryStats(
                columns: 3,
                entries: [
                  (l10n.deviceHealthLightIntensity, _number(light)),
                  (l10n.deviceHealthModerateIntensity, _number(moderate)),
                  (l10n.deviceHealthHighIntensity, _number(high)),
                ],
              ),
            ],
          ),
        ),
        if (trainingValues.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DetailCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.deviceHealthTrainingStatus,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _MetricGrid(values: trainingValues),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _sleep(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sleeps = args.data.sleep
        // Mi Fitness assigns a sleep segment to the day on which it ends.
        // Using interval overlap duplicates an overnight sleep on two days.
        .where((sleep) {
          final endedAt = sleep.endedAt.toLocal();
          return !endedAt.isBefore(_currentRange.start) &&
              endedAt.isBefore(_currentRange.end);
        })
        .toList(growable: false);
    if (sleeps.isEmpty) {
      return _DetailCard(child: Text(l10n.deviceHealthNoSleep));
    }
    final sortedSleeps = [...sleeps]
      ..sort((left, right) {
        final leftIsLong = left.isLongSleep;
        final rightIsLong = right.isLongSleep;
        if (leftIsLong != rightIsLong) return leftIsLong ? -1 : 1;
        return right.startedAt.compareTo(left.startedAt);
      });
    final stageLabels = <HealthSleepStageKind, String>{
      HealthSleepStageKind.awake: l10n.deviceHealthSleepAwake,
      HealthSleepStageKind.rem: l10n.deviceHealthSleepRem,
      HealthSleepStageKind.light: l10n.deviceHealthSleepLight,
      HealthSleepStageKind.deep: l10n.deviceHealthSleepDeep,
    };
    final detailedSleeps = sortedSleeps
        .where(
          (sleep) =>
              sleep.isLongSleep ||
              sleep.stages.isNotEmpty ||
              sleep.averageHrv != null ||
              sleep.hrvPoints.isNotEmpty ||
              sleep.averageHeartRate != null ||
              sleep.averageBloodOxygen != null ||
              sleep.heartRatePoints.isNotEmpty ||
              sleep.bloodOxygenPoints.isNotEmpty,
        )
        .toList();
    final naps =
        sortedSleeps.where((sleep) => !detailedSleeps.contains(sleep)).toList()
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, sleep) in detailedSleeps.indexed) ...[
          _sleepLongCard(
            context,
            sleep,
            title: _sleepSegmentTitle(context, sleep),
            stageLabels: stageLabels,
          ),
          if (_sleepStructureValues(sleep, stageLabels).isNotEmpty) ...[
            const SizedBox(height: 8),
            _sleepStructureCard(context, sleep, stageLabels),
          ],
          if (sleep.averageHeartRate != null ||
              sleep.averageBloodOxygen != null ||
              sleep.heartRatePoints.isNotEmpty ||
              sleep.bloodOxygenPoints.isNotEmpty) ...[
            const SizedBox(height: 8),
            _sleepVitalsCard(context, sleep),
          ],
          if (sleep.averageHrv != null || sleep.hrvPoints.isNotEmpty) ...[
            const SizedBox(height: 8),
            _sleepHrvCard(context, sleep),
          ],
          if (index < detailedSleeps.length - 1) const SizedBox(height: 12),
        ],
        if (naps.isNotEmpty) ...[
          if (detailedSleeps.isNotEmpty) const SizedBox(height: 12),
          _DetailCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppLocalizations.of(context)!.deviceHealthNap,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final (index, nap) in naps.indexed) ...[
                  if (index > 0) const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_period == HealthChartPeriod.day ? '' : '${_date(nap.endedAt)} · '}'
                          '${_sleepClock(nap.startedAt)} – ${_sleepClock(nap.endedAt)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Text(
                        _sleepDuration(context, nap.durationSeconds),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _sleepSegmentTitle(BuildContext context, HealthSleepSummary sleep) {
    final l10n = AppLocalizations.of(context)!;
    final kind = sleep.isLongSleep
        ? l10n.deviceHealthLongSleep
        : AppLocalizations.of(context)!.deviceHealthNapSingular;
    return _period == HealthChartPeriod.day
        ? kind
        : '${_date(sleep.endedAt)} · $kind';
  }

  Widget _sleepLongCard(
    BuildContext context,
    HealthSleepSummary sleep, {
    required String title,
    required Map<HealthSleepStageKind, String> stageLabels,
  }) {
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                _sleepDuration(context, sleep.durationSeconds),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_sleepClock(sleep.startedAt)} – ${_sleepClock(sleep.endedAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (sleep.stages.isNotEmpty) ...[
            const SizedBox(height: 16),
            HealthSleepTimeline(summary: sleep, stageLabels: stageLabels),
          ],
        ],
      ),
    );
  }

  Widget _sleepStructureCard(
    BuildContext context,
    HealthSleepSummary sleep,
    Map<HealthSleepStageKind, String> stageLabels,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final values = _sleepStructureValues(sleep, stageLabels);
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.deviceHealthSleepStructure,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          if (values.isEmpty)
            Text(l10n.deviceHealthSleepNoStages)
          else
            for (final (index, value) in values.indexed) ...[
              if (index > 0) const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: value.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(value.label)),
                  Text('${value.percent}%'),
                  const SizedBox(width: 24),
                  Text(
                    _sleepDuration(context, value.seconds),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  Widget _sleepHrvCard(BuildContext context, HealthSleepSummary sleep) {
    final l10n = AppLocalizations.of(context)!;
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.deviceHealthSleepHrv,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          HealthSleepHrvChart(summary: sleep),
        ],
      ),
    );
  }

  Widget _sleepVitalsCard(BuildContext context, HealthSleepSummary sleep) {
    final l10n = AppLocalizations.of(context)!;
    final heartRatePoints = [...sleep.heartRatePoints]
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final bloodOxygenPoints = [...sleep.bloodOxygenPoints]
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final hasHeartRate = heartRatePoints.isNotEmpty;
    final series = <_WorkoutChartSeries>[];
    if (hasHeartRate) {
      series.add(
        _WorkoutChartSeries(
          label: l10n.deviceHealthChartHeartRate,
          unit: 'bpm',
          color: Theme.of(context).colorScheme.error,
          axis: _WorkoutChartAxis.left,
          points: heartRatePoints
              .map((point) => (point.timestamp, point.value.toDouble()))
              .toList(growable: false),
        ),
      );
    }
    if (bloodOxygenPoints.isNotEmpty) {
      series.add(
        _WorkoutChartSeries(
          label: l10n.deviceHealthChartBloodOxygen,
          unit: '%',
          color: Theme.of(context).colorScheme.primary,
          axis: hasHeartRate ? _WorkoutChartAxis.right : _WorkoutChartAxis.left,
          points: bloodOxygenPoints
              .map((point) => (point.timestamp, point.value.toDouble()))
              .toList(growable: false),
        ),
      );
    }
    final points = series.expand((value) => value.points).toList()
      ..sort((left, right) => left.$1.compareTo(right.$1));
    final entries = <(String, String)>[];
    final averageHeartRate =
        sleep.averageHeartRate ?? _averageSleepVital(heartRatePoints);
    final averageBloodOxygen =
        sleep.averageBloodOxygen ?? _averageSleepVital(bloodOxygenPoints);
    if (averageHeartRate != null) {
      entries.add((
        l10n.deviceHealthSleepAverageHeartRate,
        '$averageHeartRate bpm',
      ));
    }
    if (averageBloodOxygen != null) {
      entries.add((
        l10n.deviceHealthSleepAverageBloodOxygen,
        '$averageBloodOxygen%',
      ));
    }
    final scheme = Theme.of(context).colorScheme;
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.deviceHealthSleepDetails,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (series.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final value in series)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: value.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${value.label} · ${value.unit}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 206,
              child: _WorkoutFlChart(
                series: series,
                gridColor: scheme.outlineVariant,
                surfaceColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _clock(points.first.$1),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  _clock(points.last.$1),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
          if (entries.isNotEmpty) ...[
            SizedBox(height: series.isEmpty ? 12 : 14),
            _HealthSummaryStats(columns: 2, entries: entries),
          ],
        ],
      ),
    );
  }

  int? _averageSleepVital(List<HealthSleepVitalPoint> points) {
    if (points.isEmpty) return null;
    final sum = points.fold<int>(0, (total, point) => total + point.value);
    return (sum / points.length).round();
  }

  List<_SleepStructureValue> _sleepStructureValues(
    HealthSleepSummary sleep,
    Map<HealthSleepStageKind, String> labels,
  ) {
    const orderedKinds = [
      HealthSleepStageKind.deep,
      HealthSleepStageKind.light,
      HealthSleepStageKind.rem,
    ];
    const colors = <HealthSleepStageKind, Color>{
      HealthSleepStageKind.deep: Color(0xFF2231B6),
      HealthSleepStageKind.light: Color(0xFF3986F6),
      HealthSleepStageKind.rem: Color(0xFF47BEFF),
    };
    final reportedSeconds = <HealthSleepStageKind, int?>{
      HealthSleepStageKind.deep: sleep.deepSleepDurationSeconds,
      HealthSleepStageKind.light: sleep.lightSleepDurationSeconds,
      HealthSleepStageKind.rem: sleep.remSleepDurationSeconds,
    };
    final kinds = orderedKinds
        .where((kind) {
          final reported = reportedSeconds[kind];
          return (reported != null && reported > 0) ||
              sleep.stages.any((stage) => stage.kind == kind);
        })
        .toList(growable: false);
    final seconds = kinds
        .map((kind) {
          final reported = reportedSeconds[kind];
          return reported != null && reported > 0
              ? reported
              : _stageSeconds(sleep, kind);
        })
        .map((value) => value < 0 ? 0 : value)
        .toList(growable: false);
    final total = seconds.fold<int>(0, (sum, value) => sum + value);
    if (total <= 0) return const [];
    final percentages = _sleepPercentages(seconds, total);
    return [
      for (var index = 0; index < kinds.length; index++)
        _SleepStructureValue(
          label: labels[kinds[index]] ?? kinds[index].name,
          seconds: seconds[index],
          percent: percentages[index],
          color: colors[kinds[index]]!,
        ),
    ];
  }

  int _stageSeconds(HealthSleepSummary sleep, HealthSleepStageKind kind) =>
      sleep.stages
          .where((stage) => stage.kind == kind)
          .fold(
            0,
            (sum, stage) =>
                sum + (stage.durationSeconds < 0 ? 0 : stage.durationSeconds),
          );

  Widget _workouts(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final range = _currentRange;
    final workouts = args.data.workouts
        .where(
          (workout) =>
              workout.startedAt.toLocal().isBefore(range.end) &&
              !workout.endedAt.toLocal().isBefore(range.start),
        )
        .toList();
    if (workouts.isEmpty) {
      return _DetailCard(child: Text(l10n.deviceHealthNoWorkouts));
    }
    workouts.sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _workoutPeriodSummary(context, workouts),
        const SizedBox(height: 12),
        for (final workout in workouts) ...[
          _DetailCard(
            onTap: () => _openWorkout(context, workout),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(_workoutIcon(workout), color: _workoutColor(workout)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _workoutName(context, workout),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${_date(workout.startedAt)} · '
                            '${_clock(workout.startedAt)}–${_clock(workout.endedAt)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _duration(
                        workout.totalDurationSeconds ??
                            workout.endedAt
                                .difference(workout.startedAt)
                                .inSeconds,
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).hintColor,
                    ),
                  ],
                ),
                if (workout.distanceMeters != null ||
                    workout.calories != null ||
                    workout.effectiveAverageHeartRate != null ||
                    healthWorkoutSupportsPace(workout)) ...[
                  const SizedBox(height: 12),
                  _HealthSummaryStats(
                    columns: healthWorkoutSupportsPace(workout) ? 4 : 3,
                    entries: [
                      (
                        l10n.deviceHealthDistance,
                        workout.distanceMeters == null
                            ? '—'
                            : _workoutDistance(workout.distanceMeters!),
                      ),
                      (
                        l10n.deviceHealthCalories,
                        workout.calories == null
                            ? '—'
                            : '${workout.calories} kcal',
                      ),
                      (
                        l10n.deviceHealthAverageHeartRateLabel,
                        workout.effectiveAverageHeartRate == null
                            ? '—'
                            : '${workout.effectiveAverageHeartRate} bpm',
                      ),
                      if (healthWorkoutSupportsPace(workout))
                        (
                          l10n.deviceHealthAveragePace,
                          _pace(workout.averagePaceSecondsPerKilometer!),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  void _openWorkout(BuildContext context, HealthWorkoutSummary workout) {
    final routeId = Uri.encodeComponent(xiaomiHealthWorkoutRouteId(workout));
    final extra = XiaomiHealthWorkoutRouteArgs(health: args, workout: workout);
    if (GoRouter.maybeOf(context) != null) {
      context.push(
        '/devices/velaos-health/detail/workout/$routeId',
        extra: extra,
      );
      return;
    }
    // Keep this widget usable in isolated previews/tests that intentionally
    // do not install the application's GoRouter above the page.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _WorkoutDetailPage(workout: workout),
      ),
    );
  }

  Widget _workoutPeriodSummary(
    BuildContext context,
    List<HealthWorkoutSummary> workouts,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final duration = workouts.fold<int>(
      0,
      (total, workout) =>
          total +
          (workout.totalDurationSeconds ??
              workout.endedAt.difference(workout.startedAt).inSeconds),
    );
    final distanceValues = workouts
        .map((workout) => workout.distanceMeters)
        .whereType<int>()
        .toList(growable: false);
    final distance = distanceValues.fold<int>(
      0,
      (total, value) => total + value,
    );
    final calorieValues = workouts
        .map((workout) => workout.calories)
        .whereType<int>()
        .toList(growable: false);
    final calories = calorieValues.fold<int>(
      0,
      (total, value) => total + value,
    );
    final heartRates = workouts
        .map((workout) => workout.effectiveAverageHeartRate)
        .whereType<int>()
        .toList(growable: false);
    final averageHeartRate = heartRates.isEmpty
        ? null
        : (heartRates.reduce((left, right) => left + right) / heartRates.length)
              .round();
    return _DetailCard(
      child: _HealthSummaryStats(
        columns: 4,
        entries: [
          (l10n.deviceHealthWorkoutDuration, _duration(duration)),
          (
            l10n.deviceHealthDistance,
            distanceValues.isEmpty ? '—' : _workoutDistance(distance),
          ),
          (
            l10n.deviceHealthCalories,
            calorieValues.isEmpty ? '—' : '$calories kcal',
          ),
          (
            l10n.deviceHealthAverageHeartRateLabel,
            averageHeartRate == null ? '—' : '$averageHeartRate bpm',
          ),
        ],
      ),
    );
  }

  List<_ActivityDayValues> _activityDaysInRange(_HealthDateRange range) => [
    for (
      var offset = 0;
      offset < healthCalendarDaysBetween(range.start, range.end);
      offset++
    )
      _activityDayValues(healthAddCalendarDays(range.start, offset)),
  ].where((day) => day.hasValue).toList(growable: false);

  List<HealthDailySummary> _activityChartDaysInRange(_HealthDateRange range) =>
      [
        for (
          var offset = 0;
          offset < healthCalendarDaysBetween(range.start, range.end);
          offset++
        )
          _activityDaySummary(healthAddCalendarDays(range.start, offset)),
      ];

  HealthDailySummary _activityDaySummary(DateTime date) {
    final values = _activityDayValues(date);
    return HealthDailySummary(
      date: values.date,
      steps: values.steps,
      activeCalories: values.activeCalories,
    );
  }

  List<HealthDailySummary> _dailyDaysInRange(_HealthDateRange range) =>
      args.data.daily.where((day) {
        final date = _dateOnly(day.date);
        return !date.isBefore(range.start) && date.isBefore(range.end);
      }).toList()..sort((left, right) => left.date.compareTo(right.date));

  int? _vitalitySevenDayTotal(HealthDailySummary anchor) =>
      args.data.vitalitySevenDayTotal(anchor);

  List<HealthActivitySample> _activitySamplesForDay(DateTime date) => args
      .data
      .activitySamples
      .where((sample) => _sameDate(sample.timestamp, date))
      .toList(growable: false);

  List<double> _activityHourlySeries(
    List<HealthActivitySample> samples,
    int? Function(HealthActivitySample sample) valueFor,
    XiaomiHealthMetric metric,
  ) {
    const slots = 24;
    final values = List<double>.filled(slots, 0);
    final start = _currentRange.start;
    for (final sample in samples) {
      final value = valueFor(sample);
      if (value == null || value < 0) continue;
      final hour = sample.timestamp.toLocal().difference(start).inHours;
      if (hour >= 0 && hour < slots) values[hour] += value;
    }
    if (values.any((value) => value > 0)) return values;
    for (final sample in args.data.samples) {
      if (sample.metric != metric || !sample.isUsable) continue;
      final hour = sample.timestamp.toLocal().difference(start).inHours;
      if (hour >= 0 && hour < slots) values[hour] += sample.value;
    }
    return values;
  }

  List<double> _standingHourlySeries(
    DateTime date,
    List<HealthActivitySample> samples,
  ) {
    final day = _dailyDaysInRange(
      _HealthDateRange(start: date, end: healthAddCalendarDays(date, 1)),
    ).firstOrNull;
    final bitmap = day?.standingBitmap;
    if (bitmap != null) {
      return [
        for (var hour = 0; hour < 24; hour++) ((bitmap >> hour) & 1).toDouble(),
      ];
    }
    final values = List<double>.filled(24, 0);
    for (final sample in samples) {
      if ((sample.steps ?? 0) <= 0) continue;
      final hour = sample.timestamp.toLocal().difference(date).inHours;
      if (hour >= 0 && hour < values.length) values[hour] = 1;
    }
    return values;
  }

  _ActivityPeriodValues _activityValues(_HealthDateRange range) {
    final days = _activityDaysInRange(range);
    return _ActivityPeriodValues(
      steps: _sum(days.map((day) => day.steps)),
      activeCalories: _sum(days.map((day) => day.activeCalories)),
      standingHours: _sum(days.map((day) => day.standingHours)),
    );
  }

  _ActivityDayValues _activityDayValues(DateTime date) {
    final normalized = _dateOnly(date);
    HealthDailySummary? summary;
    for (final day in args.data.daily) {
      if (_sameDate(day.date, normalized)) summary = day;
    }
    final activitySummary = args.data.activitySummary;
    if (activitySummary != null &&
        _sameDate(activitySummary.date, normalized)) {
      summary ??= activitySummary;
    }
    final activitySamples = args.data.samples.where(
      (sample) =>
          (sample.metric == XiaomiHealthMetric.activity ||
              sample.metric == XiaomiHealthMetric.activeCalories) &&
          sample.isUsable &&
          _sameDate(sample.timestamp, normalized),
    );
    final rawActivitySamples = args.data.activitySamples.where(
      (sample) => _sameDate(sample.timestamp, normalized),
    );
    int? sum(XiaomiHealthMetric metric) {
      final values = activitySamples
          .where((sample) => sample.metric == metric)
          .map((sample) => sample.value)
          .toList(growable: false);
      if (values.isNotEmpty) {
        return values.fold<double>(0, (total, value) => total + value).round();
      }
      final rawValues = rawActivitySamples
          .map(
            (sample) => switch (metric) {
              XiaomiHealthMetric.activity => sample.steps,
              XiaomiHealthMetric.activeCalories => sample.activeCalories,
              _ => null,
            },
          )
          .whereType<int>();
      final raw = rawValues.toList(growable: false);
      if (raw.isEmpty) return null;
      return raw.reduce((left, right) => left + right);
    }

    final standingHours =
        summary?.standingHours ??
        (() {
          final hours = activitySamples
              .where((sample) => sample.metric == XiaomiHealthMetric.activity)
              .map((sample) => sample.timestamp.toLocal().hour)
              .toSet();
          if (hours.isEmpty) {
            hours.addAll(
              rawActivitySamples
                  .where((sample) => (sample.steps ?? 0) > 0)
                  .map((sample) => sample.timestamp.toLocal().hour),
            );
          }
          return hours.length;
        })();
    final result = _ActivityDayValues(
      date: normalized,
      steps: summary?.steps ?? sum(XiaomiHealthMetric.activity),
      activeCalories:
          summary?.activeCalories ?? sum(XiaomiHealthMetric.activeCalories),
      standingHours: summary == null && activitySamples.isEmpty
          ? null
          : standingHours,
    );
    return result;
  }

  int? _sum(Iterable<int?> values) {
    final present = values.whereType<int>().toList(growable: false);
    if (present.isEmpty) return null;
    return present.reduce((left, right) => left + right);
  }

  String _withUnit(int? value, String unit) =>
      value == null ? '—' : '$value $unit'.trim();

  bool _overlaps(_HealthDateRange range, DateTime start, DateTime end) {
    final localStart = start.toLocal();
    final localEnd = end.toLocal();
    return localStart.isBefore(range.end) && !localEnd.isBefore(range.start);
  }
}

class _HealthTrendSection extends StatelessWidget {
  const _HealthTrendSection({
    required this.data,
    required this.metric,
    required this.color,
    required this.period,
    required this.anchorDate,
  });

  final XiaomiHealthData data;
  final XiaomiHealthMetric metric;
  final Color color;
  final HealthChartPeriod period;
  final DateTime anchorDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final range = _range;
    final days = _daysInRange(range);
    final samples = _samplesInRange(range);
    final stats = _stats(days, samples);
    final unit = _metricUnit(metric);
    final hasData = stats.average != null || stats.latest != null;
    final headline = samples.isNotEmpty ? stats.latest : stats.average;
    final headlineLabel = samples.isNotEmpty
        ? switch (metric) {
            XiaomiHealthMetric.heartRate => l10n.deviceHealthLatestHeartRate,
            XiaomiHealthMetric.bloodOxygen =>
              l10n.deviceHealthLatestBloodOxygen,
            XiaomiHealthMetric.stress => l10n.deviceHealthLatestStress,
            _ => '${l10n.deviceHealthLatest} · ${_title(l10n, metric)}',
          }
        : '${l10n.deviceHealthAverage} · ${_title(l10n, metric)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasData) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headlineLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatMetric(headline, unit),
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasData)
                HealthOfficialRangeChart(
                  metric: metric,
                  period: period,
                  samples: samples,
                  days: days,
                  color: color,
                  start: range.start,
                  end: range.end,
                  height: 196,
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: Text(l10n.deviceHealthNoSamples)),
                ),
            ],
          ),
        ),
        // Heart rate, SpO2 and stress render a dedicated 平均/最低/最高 vitals
        // card from the detail page instead of this latest/average/range block,
        // so keep a single consistent summary per metric.
        if (metric != XiaomiHealthMetric.heartRate &&
            metric != XiaomiHealthMetric.bloodOxygen &&
            metric != XiaomiHealthMetric.stress) ...[
          const SizedBox(height: 12),
          _DetailCard(
            child: _HealthSummaryStats(
              columns: 3,
              entries: [
                (l10n.deviceHealthLatest, _formatMetric(stats.latest, '')),
                (l10n.deviceHealthAverage, _formatMetric(stats.average, '')),
                (
                  l10n.deviceHealthRange,
                  stats.minimum == null || stats.maximum == null
                      ? '—'
                      : '${_formatMetric(stats.minimum, '')}–'
                            '${_formatMetric(stats.maximum, '')}',
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  _HealthDateRange get _range {
    return _healthPeriodRange(period, anchorDate);
  }

  List<HealthDailySummary> _daysInRange(_HealthDateRange range) {
    final existing = <String, HealthDailySummary>{};
    for (final day in data.daily) {
      final date = _dateOnly(day.date);
      if (date.isBefore(range.start) || !date.isBefore(range.end)) {
        continue;
      }
      if (healthMetricDailyValues(day, metric).hasValue) {
        existing[_dateKey(date)] = day;
      }
    }
    return [
      for (
        var offset = 0;
        offset < healthCalendarDaysBetween(range.start, range.end);
        offset++
      )
        existing[_dateKey(healthAddCalendarDays(range.start, offset))] ??
            HealthDailySummary(
              date: healthAddCalendarDays(range.start, offset),
            ),
    ];
  }

  List<HealthSample> _samplesInRange(_HealthDateRange range) =>
      data.samplesFor(metric).where((sample) {
          final timestamp = sample.timestamp.toLocal();
          return sample.isUsable &&
              !timestamp.isBefore(range.start) &&
              timestamp.isBefore(range.end);
        }).toList()
        ..sort((left, right) => left.timestamp.compareTo(right.timestamp));

  _HealthMetricStats _stats(
    List<HealthDailySummary> days,
    List<HealthSample> samples,
  ) {
    final values = <double>[];
    final minimums = <double>[];
    final maximums = <double>[];
    for (final day in days) {
      final daily = healthMetricDailyValues(day, metric);
      if (daily.average != null) {
        values.add(daily.average!);
      } else if (daily.minimum != null && daily.maximum != null) {
        values.add((daily.minimum! + daily.maximum!) / 2);
      }
      if (daily.minimum != null) minimums.add(daily.minimum!);
      if (daily.maximum != null) maximums.add(daily.maximum!);
    }
    if (period == HealthChartPeriod.day && samples.isNotEmpty) {
      values
        ..clear()
        ..addAll(samples.map((sample) => sample.value));
      minimums
        ..clear()
        ..add(values.reduce((left, right) => left < right ? left : right));
      maximums
        ..clear()
        ..add(values.reduce((left, right) => left > right ? left : right));
    }
    HealthDailySummary? latestDay;
    for (final day in days.reversed) {
      if (healthMetricDailyValues(day, metric).hasValue) {
        latestDay = day;
        break;
      }
    }
    final latestDaily = latestDay == null
        ? null
        : healthMetricDailyValues(latestDay, metric);
    final latest = samples.isNotEmpty
        ? samples.last.value
        : latestDaily?.average ?? latestDaily?.minimum ?? latestDaily?.maximum;
    final average = values.isEmpty
        ? null
        : values.reduce((left, right) => left + right) / values.length;
    return _HealthMetricStats(
      latest: latest,
      average: average,
      minimum: minimums.isEmpty
          ? null
          : minimums.reduce((left, right) => left < right ? left : right),
      maximum: maximums.isEmpty
          ? null
          : maximums.reduce((left, right) => left > right ? left : right),
    );
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _HealthDateRange {
  const _HealthDateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

class _HealthPeriodHeader extends StatelessWidget {
  const _HealthPeriodHeader({
    required this.period,
    required this.anchorDate,
    required this.canGoForward,
    required this.onPeriodChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final HealthChartPeriod period;
  final DateTime anchorDate;
  final bool canGoForward;
  final ValueChanged<HealthChartPeriod> onPeriodChanged;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<HealthChartPeriod>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: HealthChartPeriod.day,
              label: Text(l10n.deviceHealthDayView),
            ),
            ButtonSegment(
              value: HealthChartPeriod.week,
              label: Text(l10n.deviceHealthWeekView),
            ),
            ButtonSegment(
              value: HealthChartPeriod.month,
              label: Text(l10n.deviceHealthMonthView),
            ),
          ],
          selected: {period},
          onSelectionChanged: (values) {
            if (values.isNotEmpty) onPeriodChanged(values.first);
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).previousPageTooltip,
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                _healthPeriodLabel(context, period, anchorDate),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).nextPageTooltip,
              onPressed: canGoForward ? onNext : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

_HealthDateRange _healthPeriodRange(HealthChartPeriod period, DateTime anchor) {
  final date = _dateOnly(anchor);
  return switch (period) {
    HealthChartPeriod.day => _HealthDateRange(
      start: date,
      end: healthAddCalendarDays(date, 1),
    ),
    HealthChartPeriod.week => _HealthDateRange(
      start: _weekStart(date),
      end: healthAddCalendarDays(_weekStart(date), 7),
    ),
    HealthChartPeriod.month => _HealthDateRange(
      start: DateTime(date.year, date.month),
      end: DateTime(date.year, date.month + 1),
    ),
  };
}

DateTime _weekStart(DateTime date) =>
    healthAddCalendarDays(date, 1 - date.weekday);

DateTime _initialAnchorDate(XiaomiHealthData data, XiaomiHealthMetric metric) {
  final candidates = <DateTime?>[
    data.latestSample(metric)?.timestamp,
    switch (metric) {
      XiaomiHealthMetric.sleep => data.latestSleep?.endedAt,
      XiaomiHealthMetric.workout =>
        data.workouts.isEmpty
            ? null
            : data.workouts
                  .reduce(
                    (left, right) =>
                        left.startedAt.isAfter(right.startedAt) ? left : right,
                  )
                  .startedAt,
      _ => data.latestDay?.date,
    },
    if (metric == XiaomiHealthMetric.activity ||
        metric == XiaomiHealthMetric.activeCalories)
      data.activitySummary?.date,
  ];
  DateTime? latest;
  for (final candidate in candidates) {
    if (candidate == null || (latest != null && !candidate.isAfter(latest))) {
      continue;
    }
    latest = candidate;
  }
  return _dateOnly(latest ?? DateTime.now());
}

String _healthPeriodLabel(
  BuildContext context,
  HealthChartPeriod period,
  DateTime anchor,
) {
  final range = _healthPeriodRange(period, anchor);
  final locale = Localizations.localeOf(context).languageCode;
  if (locale == 'zh') {
    return switch (period) {
      HealthChartPeriod.day =>
        '${range.start.year}年${range.start.month}月${range.start.day}日',
      HealthChartPeriod.week =>
        '${_isoWeekYear(range.start)}年${_isoWeekNumber(range.start)}周',
      HealthChartPeriod.month => '${range.start.year}年${range.start.month}月',
    };
  }
  return switch (period) {
    HealthChartPeriod.day =>
      '${range.start.year}/${range.start.month}/${range.start.day}',
    HealthChartPeriod.week =>
      'W${_isoWeekNumber(range.start)}, ${_isoWeekYear(range.start)}',
    HealthChartPeriod.month => '${range.start.year}/${range.start.month}',
  };
}

int _isoWeekYear(DateTime date) =>
    healthAddCalendarDays(date, 4 - date.weekday).year;

int _isoWeekNumber(DateTime date) {
  final thursday = healthAddCalendarDays(date, 4 - date.weekday);
  final firstThursday = DateTime(thursday.year, 1, 4);
  final firstMonday = healthAddCalendarDays(
    firstThursday,
    1 - firstThursday.weekday,
  );
  return (healthCalendarDaysBetween(firstMonday, thursday) ~/ 7) + 1;
}

bool _sameDate(DateTime left, DateTime right) {
  final a = left.toLocal();
  final b = right.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _ActivityDayValues {
  const _ActivityDayValues({
    required this.date,
    this.steps,
    this.activeCalories,
    this.standingHours,
  });

  final DateTime date;
  final int? steps;
  final int? activeCalories;
  final int? standingHours;

  bool get hasValue =>
      steps != null || activeCalories != null || standingHours != null;
}

class _ActivityPeriodValues {
  const _ActivityPeriodValues({
    this.steps,
    this.activeCalories,
    this.standingHours,
  });

  final int? steps;
  final int? activeCalories;
  final int? standingHours;
}

class _HealthMetricStats {
  const _HealthMetricStats({
    this.latest,
    this.average,
    this.minimum,
    this.maximum,
  });

  final double? latest;
  final double? average;
  final double? minimum;
  final double? maximum;
}

String _metricUnit(XiaomiHealthMetric metric) => switch (metric) {
  XiaomiHealthMetric.heartRate || XiaomiHealthMetric.restingHeartRate => 'bpm',
  XiaomiHealthMetric.bloodOxygen => '%',
  _ => '',
};

String _formatMetric(double? value, String unit) {
  if (value == null) return '—';
  final number = value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$number $unit'.trim();
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Route entry for a workout detail. A list tap supplies [preview] so the
/// page renders immediately; a direct/restored route reloads the same record
/// from the active device's local health store using [workoutId].
class XiaomiHealthWorkoutPage extends ConsumerStatefulWidget {
  const XiaomiHealthWorkoutPage({
    super.key,
    required this.workoutId,
    this.preview,
  });

  final String workoutId;
  final HealthWorkoutSummary? preview;

  @override
  ConsumerState<XiaomiHealthWorkoutPage> createState() =>
      _XiaomiHealthWorkoutPageState();
}

class _XiaomiHealthWorkoutPageState
    extends ConsumerState<XiaomiHealthWorkoutPage> {
  HealthWorkoutSummary? _workout;
  Object? _error;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _workout = widget.preview;
    if (_workout == null) unawaited(_loadWorkout());
  }

  Future<void> _loadWorkout() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await ref
          .read(deviceManagerProvider.notifier)
          .loadXiaomiHealthData();
      final workout = data.workouts
          .where(
            (value) => xiaomiHealthWorkoutRouteId(value) == widget.workoutId,
          )
          .firstOrNull;
      if (workout == null) throw StateError('Workout record not found');
      if (mounted) setState(() => _workout = workout);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workout = _workout;
    if (workout != null) return _WorkoutDetailPage(workout: workout);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SysAppBar(secondary: true, title: Text(l10n.deviceHealthWorkout)),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Text(
                _error == null
                    ? l10n.deviceHealthNoWorkouts
                    : l10n.deviceHealthLoadFailed,
              ),
      ),
    );
  }
}

class _WorkoutDetailPage extends StatelessWidget {
  const _WorkoutDetailPage({required this.workout});

  final HealthWorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = _workoutColor(workout);
    final details = _workoutDetails(context, workout);
    return Scaffold(
      appBar: SysAppBar(
        secondary: true,
        title: Text(_workoutName(context, workout)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: StyleConstants.pageMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.deviceHealthWorkoutDuration,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _duration(
                          workout.totalDurationSeconds ??
                              workout.endedAt
                                  .difference(workout.startedAt)
                                  .inSeconds,
                        ),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_date(workout.startedAt)} · '
                        '${_clock(workout.startedAt)}–${_clock(workout.endedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _DetailCard(
                  child: _HealthSummaryStats(
                    columns: healthWorkoutSupportsPace(workout) ? 4 : 3,
                    entries: [
                      (
                        l10n.deviceHealthDistance,
                        workout.distanceMeters == null
                            ? '—'
                            : _workoutDistance(workout.distanceMeters!),
                      ),
                      (
                        l10n.deviceHealthCalories,
                        workout.calories == null
                            ? '—'
                            : '${workout.calories} kcal',
                      ),
                      (
                        l10n.deviceHealthAverageHeartRateLabel,
                        workout.effectiveAverageHeartRate == null
                            ? '—'
                            : '${workout.effectiveAverageHeartRate} bpm',
                      ),
                      if (healthWorkoutSupportsPace(workout))
                        (
                          l10n.deviceHealthAveragePace,
                          _pace(workout.averagePaceSecondsPerKilometer!),
                        ),
                    ],
                  ),
                ),
                if (workout.route.length >= 2) ...[
                  const SizedBox(height: 12),
                  _DetailCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!
                              .deviceHealthWorkoutRoute,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 210,
                          child: CustomPaint(
                            painter: _WorkoutRoutePainter(
                              points: workout.route,
                              color: color,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_hasWorkoutChartSeries(workout)) ...[
                  const SizedBox(height: 12),
                  _WorkoutRecordSeriesCard(workout: workout),
                ],
                if (workout.heartRateZones.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _WorkoutHeartRateZonesCard(workout: workout),
                ],
                if (workout.samples.any(
                  (sample) =>
                      sample.swolf != null ||
                      sample.swimmingPaceSecondsPer100Meters != null,
                )) ...[
                  const SizedBox(height: 12),
                  _WorkoutSwimmingSectionsCard(workout: workout),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _DetailCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)!
                              .deviceHealthWorkoutDetails,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 640 ? 3 : 2;
                            return _HealthSummaryStats(
                              entries: details,
                              columns: columns,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
                if (workout.recovery != null) ...[
                  const SizedBox(height: 12),
                  _WorkoutRecoveryCard(recovery: workout.recovery!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkoutSwimmingSectionsCard extends StatelessWidget {
  const _WorkoutSwimmingSectionsCard({required this.workout});

  final HealthWorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    final sections = workout.samples
        .where(
          (sample) =>
              sample.swolf != null ||
              sample.swimmingPaceSecondsPer100Meters != null,
        )
        .toList(growable: false);
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.deviceHealthSwimmingSections,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final (index, section) in sections.indexed) ...[
            if (index > 0) const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 38,
                  child: Text(
                    '${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Expanded(
                  child: Text(
                    _swimmingStrokeName(context, section.swimmingStroke),
                  ),
                ),
                if (section.swimmingPaceSecondsPer100Meters != null)
                  Text(
                    '${_shortDuration(section.swimmingPaceSecondsPer100Meters!)} /100m',
                  ),
                const SizedBox(width: 14),
                Text('SWOLF ${section.swolf ?? '—'}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkoutRecordSeriesCard extends StatelessWidget {
  const _WorkoutRecordSeriesCard({required this.workout});

  final HealthWorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    final series = _workoutChartSeries(context, workout);
    if (series.isEmpty) return const SizedBox.shrink();
    final points = series.expand((value) => value.points).toList()
      ..sort((left, right) => left.$1.compareTo(right.$1));
    if (points.isEmpty) return const SizedBox.shrink();
    final start = points.first.$1;
    final end = points.last.$1;
    final hasLeftAxis = series.any(
      (value) => value.axis == _WorkoutChartAxis.left,
    );
    final hasRightAxis = series.any(
      (value) => value.axis == _WorkoutChartAxis.right,
    );
    final scheme = Theme.of(context).colorScheme;
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.deviceHealthWorkoutCharts,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final value in series)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: value.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${value.label}${value.unit.isEmpty ? '' : ' · ${value.unit}'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 206,
            child: _WorkoutFlChart(
              series: series,
              gridColor: scheme.outlineVariant,
              surfaceColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(width: hasLeftAxis ? _workoutYAxisReservedSize : 0),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _clock(start),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      _clock(end),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(width: hasRightAxis ? _workoutYAxisReservedSize : 0),
            ],
          ),
        ],
      ),
    );
  }
}

enum _WorkoutChartAxis { left, right }

const _workoutYAxisReservedSize = 28.0;
const _workoutYAxisTitleGap = 4.0;

class _WorkoutChartSeries {
  const _WorkoutChartSeries({
    required this.label,
    required this.unit,
    required this.color,
    required this.axis,
    required this.points,
  });

  final String label;
  final String unit;
  final Color color;
  final _WorkoutChartAxis axis;
  final List<(DateTime, double)> points;
}

class _WorkoutFlChart extends StatelessWidget {
  const _WorkoutFlChart({
    required this.series,
    required this.gridColor,
    required this.surfaceColor,
  });

  final List<_WorkoutChartSeries> series;
  final Color gridColor;
  final Color surfaceColor;

  @override
  Widget build(BuildContext context) {
    final points = series.expand((value) => value.points).toList();
    final first = points
        .map((value) => value.$1.millisecondsSinceEpoch)
        .reduce(math.min);
    final last = points
        .map((value) => value.$1.millisecondsSinceEpoch)
        .reduce(math.max);
    final span = math.max(1, last - first).toDouble();
    final bounds = <_WorkoutChartAxis, (double, double)>{};
    for (final axis in _WorkoutChartAxis.values) {
      final values = series
          .where((value) => value.axis == axis)
          .expand((value) => value.points.map((point) => point.$2))
          .where((value) => value.isFinite)
          .toList(growable: false);
      if (values.isEmpty) continue;
      final minimum = values.reduce(math.min);
      final maximum = values.reduce(math.max);
      final spread = math.max(1.0, maximum - minimum);
      final floor = minimum - spread * .08;
      var lower = (minimum >= 0 ? math.max(0.0, floor) : floor).floorToDouble();
      var upper = (maximum + spread * .08).ceilToDouble();
      if ((upper - lower).round().isOdd) upper += 1;
      if (lower >= upper) upper = lower + 2;
      bounds[axis] = (lower, upper);
    }
    final chartPoints = [
      for (final value in series)
        _workoutChartPoints(value, first, span, bounds),
    ];
    final bars = [
      for (final (index, value) in series.indexed)
        LineChartBarData(
          spots: chartPoints[index].spots,
          color: value.color,
          barWidth: 2,
          isCurved: false,
          isStrokeCapRound: true,
          isStrokeJoinRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                value.color.withValues(alpha: .28),
                value.color.withValues(alpha: .025),
              ],
            ),
          ),
        ),
    ];
    final axisLabelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 10,
    );
    AxisTitles axisTitles(_WorkoutChartAxis axis) {
      final range = bounds[axis];
      if (range == null) {
        return const AxisTitles(sideTitles: SideTitles(showTitles: false));
      }
      return AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: _workoutYAxisReservedSize,
          interval: .5,
          getTitlesWidget: (value, meta) {
            final actual = range.$1 + (range.$2 - range.$1) * value;
            return SideTitleWidget(
              meta: meta,
              space: _workoutYAxisTitleGap,
              child: Text(
                _workoutAxisLabel(actual),
                style: axisLabelStyle,
                textAlign: axis == _WorkoutChartAxis.left
                    ? TextAlign.right
                    : TextAlign.left,
              ),
            );
          },
        ),
      );
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 1,
        minY: 0,
        maxY: 1,
        lineBarsData: bars,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: .5,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: gridColor.withValues(alpha: .35), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: axisTitles(_WorkoutChartAxis.left),
          rightTitles: axisTitles(_WorkoutChartAxis.right),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineTouchData: LineTouchData(
          enabled: true,
          getTouchedSpotIndicator: (_, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                FlLine(color: gridColor.withValues(alpha: .48), strokeWidth: 1),
                const FlDotData(show: false),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => surfaceColor,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                _workoutTooltipItem(
                  spot,
                  series: series,
                  chartPoints: chartPoints,
                ),
            ],
          ),
        ),
      ),
      duration: const Duration(milliseconds: 180),
      curve: Curves.linear,
    );
  }
}

LineTooltipItem? _workoutTooltipItem(
  LineBarSpot spot, {
  required List<_WorkoutChartSeries> series,
  required List<_WorkoutChartPoints> chartPoints,
}) {
  if (spot.barIndex < 0 || spot.barIndex >= series.length) return null;
  final points = chartPoints[spot.barIndex].sourceIndexes;
  if (spot.spotIndex < 0 || spot.spotIndex >= points.length) return null;
  final sourceIndex = points[spot.spotIndex];
  if (sourceIndex == null ||
      sourceIndex >= series[spot.barIndex].points.length) {
    return null;
  }
  final sourcePoint = series[spot.barIndex].points[sourceIndex];
  return LineTooltipItem(
    '${_clock(sourcePoint.$1)} · ${_axisNumber(sourcePoint.$2)} '
    '${series[spot.barIndex].unit}',
    TextStyle(color: spot.bar.color, fontWeight: FontWeight.w600),
  );
}

_WorkoutChartPoints _workoutChartPoints(
  _WorkoutChartSeries series,
  int first,
  double span,
  Map<_WorkoutChartAxis, (double, double)> bounds,
) {
  final spots = <FlSpot>[];
  final sourceIndexes = <int?>[];
  DateTime? previous;
  for (final (index, point) in series.points.indexed) {
    if (previous != null &&
        point.$1.difference(previous).inMinutes > 15 &&
        spots.isNotEmpty &&
        spots.last != FlSpot.nullSpot) {
      spots.add(FlSpot.nullSpot);
      sourceIndexes.add(null);
    }
    spots.add(
      FlSpot(
        (point.$1.millisecondsSinceEpoch - first) / span,
        _normalizeWorkoutValue(point.$2, bounds[series.axis]),
      ),
    );
    sourceIndexes.add(index);
    previous = point.$1;
  }
  return _WorkoutChartPoints(spots: spots, sourceIndexes: sourceIndexes);
}

class _WorkoutChartPoints {
  const _WorkoutChartPoints({required this.spots, required this.sourceIndexes});

  final List<FlSpot> spots;
  final List<int?> sourceIndexes;
}

double _normalizeWorkoutValue(double value, (double, double)? bounds) {
  if (bounds == null) return 0;
  final span = math.max(bounds.$2 - bounds.$1, 1e-9);
  return ((value - bounds.$1) / span).clamp(0.0, 1.0).toDouble();
}

String _axisNumber(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(1);

String _workoutAxisLabel(double value) => value.round().toString();

bool _hasWorkoutChartSeries(HealthWorkoutSummary workout) =>
    workout.samples.any(
      (sample) =>
          sample.heartRate != null ||
          sample.cadence != null ||
          sample.paceSecondsPerKilometer != null ||
          sample.speedKph != null ||
          sample.powerWatts != null ||
          sample.strokeFrequency != null ||
          sample.jumpFrequency != null ||
          sample.bloodOxygen != null ||
          sample.stress != null,
    );

List<_WorkoutChartSeries> _workoutChartSeries(
  BuildContext context,
  HealthWorkoutSummary workout,
) {
  final scheme = Theme.of(context).colorScheme;
  List<(DateTime, double)> points(double? Function(HealthWorkoutSample) read) {
    final result =
        workout.samples
            .map((sample) {
              final value = read(sample);
              // A non-finite value would poison the painter's bounds and can
              // produce NaN canvas coordinates, which hangs rasterization.
              if (value == null || !value.isFinite) return null;
              return (sample.timestamp, value);
            })
            .whereType<(DateTime, double)>()
            .toList()
          ..sort((left, right) => left.$1.compareTo(right.$1));
    return result;
  }

  _WorkoutChartSeries? make({
    required String label,
    required String unit,
    required Color color,
    required _WorkoutChartAxis axis,
    required double? Function(HealthWorkoutSample) read,
  }) {
    final values = points(read);
    return values.isEmpty
        ? null
        : _WorkoutChartSeries(
            label: label,
            unit: unit,
            color: color,
            axis: axis,
            points: values,
          );
  }

  final result = <_WorkoutChartSeries>[];
  final heartRate = make(
    label: AppLocalizations.of(context)!.deviceHealthChartHeartRate,
    unit: 'bpm',
    color: scheme.error,
    axis: _WorkoutChartAxis.left,
    read: (sample) => sample.heartRate?.toDouble(),
  );
  if (heartRate != null) result.add(heartRate);

  final secondary = [
    make(
      label: AppLocalizations.of(context)!.deviceHealthChartCadence,
      unit: '/min',
      color: scheme.tertiary,
      axis: _WorkoutChartAxis.right,
      read: (sample) => sample.cadence?.toDouble(),
    ),
    make(
      label: AppLocalizations.of(context)!.deviceHealthChartPace,
      unit: '',
      color: scheme.primary,
      axis: _WorkoutChartAxis.right,
      read: (sample) => sample.paceSecondsPerKilometer?.toDouble(),
    ),
    make(
      label: AppLocalizations.of(context)!.deviceHealthChartSpeed,
      unit: 'km/h',
      color: scheme.secondary,
      axis: _WorkoutChartAxis.right,
      read: (sample) => sample.speedKph,
    ),
    make(
      label: AppLocalizations.of(context)!.deviceHealthChartPower,
      unit: 'W',
      color: scheme.tertiary,
      axis: _WorkoutChartAxis.right,
      read: (sample) => sample.powerWatts?.toDouble(),
    ),
    make(
      label: AppLocalizations.of(context)!.deviceHealthChartStrokeRate,
      unit: '/min',
      color: scheme.primary,
      axis: _WorkoutChartAxis.right,
      read: (sample) => sample.strokeFrequency?.toDouble(),
    ),
    make(
      label: AppLocalizations.of(context)!.deviceHealthChartJumpRate,
      unit: '/min',
      color: scheme.secondary,
      axis: _WorkoutChartAxis.right,
      read: (sample) => sample.jumpFrequency?.toDouble(),
    ),
    make(
      label: AppLocalizations.of(context)!.deviceHealthChartBloodOxygen,
      unit: '%',
      color: scheme.primary,
      axis: _WorkoutChartAxis.right,
      read: (sample) => sample.bloodOxygen?.toDouble(),
    ),
    make(
      label: AppLocalizations.of(context)!.deviceHealthChartStress,
      unit: '',
      color: scheme.secondary,
      axis: _WorkoutChartAxis.right,
      read: (sample) => sample.stress?.toDouble(),
    ),
  ];
  final selectedSecondary = secondary
      .whereType<_WorkoutChartSeries>()
      .firstOrNull;
  if (selectedSecondary != null) result.add(selectedSecondary);
  if (result.isEmpty) {
    final fallback = secondary.whereType<_WorkoutChartSeries>().firstOrNull;
    if (fallback != null) {
      result.add(
        _WorkoutChartSeries(
          label: fallback.label,
          unit: fallback.unit,
          color: fallback.color,
          axis: _WorkoutChartAxis.left,
          points: fallback.points,
        ),
      );
    }
  }
  return result;
}

class _WorkoutHeartRateZonesCard extends StatelessWidget {
  const _WorkoutHeartRateZonesCard({required this.workout});

  final HealthWorkoutSummary workout;

  @override
  Widget build(BuildContext context) {
    final zones = [...workout.heartRateZones]
      ..sort((left, right) => left.zone.compareTo(right.zone));
    final maximum = zones.fold<int>(
      1,
      (value, zone) =>
          zone.durationSeconds > value ? zone.durationSeconds : value,
    );
    const colors = [
      Colors.blueGrey,
      Colors.lightBlue,
      Colors.green,
      Colors.orange,
      Colors.redAccent,
    ];
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.deviceHealthHeartRateZones,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          for (final zone in zones) ...[
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    _heartRateZoneLabel(
                      AppLocalizations.of(context)!,
                      zone.zone,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: zone.durationSeconds / maximum,
                      color: colors[(zone.zone - 1).clamp(0, 4)],
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 58,
                  child: Text(
                    _shortDuration(zone.durationSeconds),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            if (zone != zones.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _WorkoutRecoveryCard extends StatelessWidget {
  const _WorkoutRecoveryCard({required this.recovery});

  final HealthWorkoutHeartRateRecovery recovery;

  @override
  Widget build(BuildContext context) {
    final values = recovery.heartRates;
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context)!.deviceHealthRecoveryAfterWorkout,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          _HealthSummaryStats(
            columns: 3,
            entries: [
              (
                AppLocalizations.of(context)!.deviceHealthRecoveredHeartRate,
                recovery.recoveredHeartRate == null
                    ? '—'
                    : '${recovery.recoveredHeartRate} bpm',
              ),
              (
                AppLocalizations.of(context)!.deviceHealthRecoveryRate,
                recovery.recoveryRate == null
                    ? '—'
                    : '${recovery.recoveryRate}%',
              ),
              (
                AppLocalizations.of(context)!.deviceHealthSamples,
                '${values.length}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkoutRoutePainter extends CustomPainter {
  const _WorkoutRoutePainter({required this.points, required this.color});

  final List<HealthWorkoutRoutePoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final valid = points
        .where((point) => point.latitude.isFinite && point.longitude.isFinite)
        .toList(growable: false);
    if (valid.length < 2 || size.isEmpty) return;
    final minLat = valid.map((point) => point.latitude).reduce(math.min);
    final maxLat = valid.map((point) => point.latitude).reduce(math.max);
    final minLon = valid.map((point) => point.longitude).reduce(math.min);
    final maxLon = valid.map((point) => point.longitude).reduce(math.max);
    final latSpan = math.max(maxLat - minLat, .000001);
    // A longitude degree is shorter at higher latitudes. Use local planar
    // distances and one scale for both axes so the route keeps its shape.
    final longitudeScale = math
        .cos((minLat + maxLat) / 2 * math.pi / 180)
        .abs();
    final lonSpan = math.max((maxLon - minLon) * longitudeScale, .000001);
    const inset = 18.0;
    final usableWidth = math.max(1.0, size.width - inset * 2);
    final usableHeight = math.max(1.0, size.height - inset * 2);
    final scale = math.min(usableWidth / lonSpan, usableHeight / latSpan);
    final mapWidth = lonSpan * scale;
    final mapHeight = latSpan * scale;
    final left = (size.width - mapWidth) / 2;
    final top = (size.height - mapHeight) / 2;
    final path = Path();
    for (final (index, point) in valid.indexed) {
      final x = left + (point.longitude - minLon) * longitudeScale * scale;
      final y = top + mapHeight - (point.latitude - minLat) * scale;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _WorkoutRoutePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: const EdgeInsets.all(18), child: child),
        ),
      ),
    );
  }
}

class _ActivityMetricCard extends StatelessWidget {
  const _ActivityMetricCard({
    required this.title,
    required this.value,
    this.chart,
  });

  final String title;
  final String value;
  final Widget? chart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Text(value, style: theme.textTheme.titleMedium),
            ],
          ),
          if (chart != null) ...[const SizedBox(height: 8), chart!],
        ],
      ),
    );
  }
}

/// Flat label/value facts used for secondary health information. Keeping this
/// in the same visual grammar as the homepage sleep card avoids turning every
/// metric into another nested tile.
class _HealthSummaryStats extends StatelessWidget {
  const _HealthSummaryStats({required this.entries, this.columns});

  final List<(String, String)> entries;
  final int? columns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (columns ?? entries.length).clamp(1, entries.length);
        final gap = 16.0;
        final width = (constraints.maxWidth - (count - 1) * gap) / count;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            for (final entry in entries)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      entry.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: valueStyle,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.values});

  final List<(String, String)> values;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = values.length <= 3
            ? values.length
            : constraints.maxWidth >= 640
            ? 3
            : 2;
        return _HealthSummaryStats(entries: values, columns: columns);
      },
    );
  }
}

String _title(AppLocalizations l10n, XiaomiHealthMetric metric) =>
    switch (metric) {
      XiaomiHealthMetric.activity => l10n.deviceHealthActivityOverview,
      XiaomiHealthMetric.activeCalories => l10n.deviceHealthActivityOverview,
      XiaomiHealthMetric.heartRate => l10n.deviceHealthHeartRate,
      XiaomiHealthMetric.restingHeartRate => l10n.deviceHealthRestingHeartRate,
      XiaomiHealthMetric.bloodOxygen => l10n.deviceHealthBloodOxygen,
      XiaomiHealthMetric.stress => l10n.deviceHealthStress,
      XiaomiHealthMetric.vitality => l10n.deviceHealthVitality,
      XiaomiHealthMetric.sleep => l10n.deviceHealthSleep,
      XiaomiHealthMetric.workout => l10n.deviceHealthWorkout,
    };

Color _color(XiaomiHealthMetric metric) => switch (metric) {
  XiaomiHealthMetric.heartRate => Colors.redAccent,
  XiaomiHealthMetric.restingHeartRate => Colors.pinkAccent,
  XiaomiHealthMetric.bloodOxygen => Colors.indigo,
  XiaomiHealthMetric.stress => Colors.orange,
  XiaomiHealthMetric.vitality => Colors.amber,
  _ => Colors.teal,
};

String _number(num? value) => value == null ? '—' : value.round().toString();
String _date(DateTime value) {
  final local = value.toLocal();
  return '${local.year}/${local.month}/${local.day}';
}

String _clock(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _workoutDistance(int meters) =>
    meters >= 1000 ? '${(meters / 1000).toStringAsFixed(2)} km' : '$meters m';

String _workoutName(BuildContext context, HealthWorkoutSummary workout) {
  final type = workout.activityType;
  final subType = workout.subSportType;
  if (type == 22) {
    return switch (subType) {
      2 ||
      207 => AppLocalizations.of(context)!.deviceHealthWorkoutOutdoorWalking,
      4 => AppLocalizations.of(context)!.deviceHealthWorkoutMountaineering,
      5 => AppLocalizations.of(context)!.deviceHealthWorkoutTrailRunning,
      15 => AppLocalizations.of(context)!.deviceHealthWorkoutHiking,
      _ => AppLocalizations.of(context)!.deviceHealthWorkoutOutdoorRunning,
    };
  }
  if (type == 23) {
    return AppLocalizations.of(context)!.deviceHealthWorkoutOutdoorCycling;
  }
  return switch (type) {
    1 => AppLocalizations.of(context)!.deviceHealthWorkoutOutdoorRunning,
    2 => AppLocalizations.of(context)!.deviceHealthWorkoutOutdoorWalking,
    3 => AppLocalizations.of(context)!.deviceHealthWorkoutIndoorRunning,
    4 => AppLocalizations.of(context)!.deviceHealthWorkoutMountaineering,
    5 => AppLocalizations.of(context)!.deviceHealthWorkoutTrailRunning,
    6 => AppLocalizations.of(context)!.deviceHealthWorkoutOutdoorCycling,
    7 => AppLocalizations.of(context)!.deviceHealthWorkoutIndoorCycling,
    8 => AppLocalizations.of(context)!.deviceHealthWorkoutFreeTraining,
    9 || 10 => AppLocalizations.of(context)!.deviceHealthWorkoutSwimming,
    11 => AppLocalizations.of(context)!.deviceHealthWorkoutElliptical,
    13 => AppLocalizations.of(context)!.deviceHealthWorkoutRowing,
    14 => AppLocalizations.of(context)!.deviceHealthWorkoutJumpRope,
    15 => AppLocalizations.of(context)!.deviceHealthWorkoutHiking,
    _ => AppLocalizations.of(context)!.deviceHealthWorkoutGeneric,
  };
}

IconData _workoutIcon(HealthWorkoutSummary workout) =>
    switch (workout.activityType) {
      2 || 4 || 5 || 15 => Icons.hiking_outlined,
      6 || 7 || 23 => Icons.directions_bike_outlined,
      8 => Icons.fitness_center_outlined,
      9 || 10 => Icons.pool_outlined,
      11 => Icons.motion_photos_on_outlined,
      13 => Icons.rowing_outlined,
      14 => Icons.sports_gymnastics_outlined,
      _ => Icons.directions_run_outlined,
    };

Color _workoutColor(HealthWorkoutSummary workout) =>
    switch (workout.activityType) {
      6 || 7 || 23 => Colors.blue,
      9 || 10 => Colors.cyan,
      11 => Colors.deepPurple,
      13 => Colors.indigo,
      14 => Colors.orange,
      8 => Colors.pinkAccent,
      _ => Colors.teal,
    };

String _heartRateZoneLabel(AppLocalizations l10n, int zone) => switch (zone) {
  1 => l10n.deviceHealthZoneWarmup,
  2 => l10n.deviceHealthZoneFatBurning,
  3 => l10n.deviceHealthZoneAerobic,
  4 => l10n.deviceHealthZoneAnaerobic,
  5 => l10n.deviceHealthZoneExtreme,
  _ => l10n.deviceHealthZoneLabel(zone),
};

List<(String, String)> _workoutDetails(
  BuildContext context,
  HealthWorkoutSummary workout,
) {
  final l10n = AppLocalizations.of(context)!;
  final values = <(String, String)>[];
  void add(String label, Object? value, String unit) {
    if (value == null) return;
    final formatted = value is double
        ? value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)
        : value.toString();
    values.add((label, '$formatted$unit'));
  }

  if (workout.effectiveDurationSeconds != null) {
    values.add((
      AppLocalizations.of(context)!.deviceHealthActiveDuration,
      _duration(workout.effectiveDurationSeconds!),
    ));
  }
  if (workout.averagePaceSecondsPerKilometer != null) {
    values.add((
      AppLocalizations.of(context)!.deviceHealthAveragePace,
      _pace(workout.averagePaceSecondsPerKilometer!),
    ));
  }
  if (workout.bestPaceSecondsPerKilometer != null) {
    values.add((
      AppLocalizations.of(context)!.deviceHealthBestPace,
      _pace(workout.bestPaceSecondsPerKilometer!),
    ));
  }
  add(l10n.deviceHealthAverageSpeed, workout.averageSpeedKph, ' km/h');
  add(l10n.deviceHealthTopSpeed, workout.bestSpeedKph, ' km/h');
  add(l10n.deviceHealthSteps, workout.totalSteps, '');
  add(l10n.deviceHealthAverageStride, workout.averageStrideCentimeters, ' cm');
  add(l10n.deviceHealthAverageCadence, workout.averageCadence, '/min');
  add(l10n.deviceHealthMaximumCadence, workout.maximumCadence, '/min');
  if (workout.effectiveMinimumHeartRate != null ||
      workout.effectiveMaximumHeartRate != null) {
    values.add((
      AppLocalizations.of(context)!.deviceHealthHeartRateRange,
      '${workout.effectiveMinimumHeartRate ?? '—'}–'
          '${workout.effectiveMaximumHeartRate ?? '—'} bpm',
    ));
  }
  if (workout.minimumBloodOxygen != null ||
      workout.maximumBloodOxygen != null) {
    values.add((
      AppLocalizations.of(context)!.deviceHealthBloodOxygenRange,
      '${workout.minimumBloodOxygen ?? '—'}–${workout.maximumBloodOxygen ?? '—'}%',
    ));
  }
  add(
    l10n.deviceHealthAverageBloodOxygenDetail,
    workout.averageBloodOxygen,
    '%',
  );
  add(l10n.deviceHealthAverage, workout.averageStress, '');
  add(l10n.deviceHealthTotalAscent, workout.totalAscentMeters, ' m');
  add(l10n.deviceHealthTotalDescent, workout.totalDescentMeters, ' m');
  add(l10n.deviceHealthAverageAltitude, workout.averageAltitudeMeters, ' m');
  add(l10n.deviceHealthAerobicEffect, workout.aerobicTrainingEffect, '');
  add(l10n.deviceHealthAnaerobicEffect, workout.anaerobicTrainingEffect, '');
  add(l10n.deviceHealthPeakEffect, workout.peakTrainingEffect, '');
  add(l10n.deviceHealthVo2Max, workout.vo2Max, ' ml/kg/min');
  add(l10n.deviceHealthBodyEnergyUsed, workout.bodyEnergyConsumption, '');
  add(l10n.deviceHealthExpectedRecovery, workout.expectedRecoveryHours, ' h');
  add(l10n.deviceHealthTrainingLoad, workout.trainingLoad, '');
  add(l10n.deviceHealthVitalityEarned, workout.earnedVitality, '');
  add(l10n.deviceHealthAveragePower, workout.averagePowerWatts, ' W');
  add(l10n.deviceHealthMaximumPower, workout.maximumPowerWatts, ' W');
  add(l10n.deviceHealthArmPulls, workout.totalArmPulls, '');
  if (workout.mainSwimmingStroke != null) {
    values.add((
      AppLocalizations.of(context)!.deviceHealthMainStroke,
      _swimmingStrokeName(context, workout.mainSwimmingStroke),
    ));
  }
  add(
    l10n.deviceHealthAverageStrokeRate,
    workout.averageStrokeFrequency,
    '/min',
  );
  add(
    l10n.deviceHealthMaximumStrokeRate,
    workout.maximumStrokeFrequency,
    '/min',
  );
  add(l10n.deviceHealthTurns, workout.turnCount, '');
  add(l10n.deviceHealthAverageSwolf, workout.averageSwolf, '');
  add(l10n.deviceHealthBestSwolf, workout.bestSwolf, '');
  add(l10n.deviceHealthPoolLength, workout.poolWidthMeters, ' m');
  add(l10n.deviceHealthJumps, workout.totalJumps, '');
  add(l10n.deviceHealthAverageJumpRate, workout.averageJumpFrequency, '/min');
  add(l10n.deviceHealthBestJumpRate, workout.bestJumpFrequency, '/min');
  add(l10n.deviceHealthTrips, workout.tripCount, '');
  add(l10n.deviceHealthSets, workout.setCount, '');
  add(l10n.deviceHealthTotalStrokes, workout.totalStrokes, '');
  add(
    l10n.deviceHealthAverageRowingRate,
    workout.averageRowingFrequency,
    '/min',
  );
  add(l10n.deviceHealthBestRowingRate, workout.bestRowingFrequency, '/min');
  return values;
}

String _pace(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return "$minutes'$remainder\"";
}

String _shortDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return minutes == 0 ? '${remainder}s' : '${minutes}m ${remainder}s';
}

String _swimmingStrokeName(BuildContext context, int? stroke) =>
    switch (stroke) {
      0 => AppLocalizations.of(context)!.deviceHealthStrokeMedley,
      1 => AppLocalizations.of(context)!.deviceHealthStrokeBreaststroke,
      2 => AppLocalizations.of(context)!.deviceHealthStrokeFreestyle,
      3 => AppLocalizations.of(context)!.deviceHealthStrokeBackstroke,
      4 => AppLocalizations.of(context)!.deviceHealthStrokeButterfly,
      _ => AppLocalizations.of(context)!.deviceHealthSectionLabel,
    };

String _sleepDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_date(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _duration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

String _durationBetween(DateTime start, DateTime end) {
  final seconds = end.difference(start).inSeconds;
  return _duration(seconds < 0 ? 0 : seconds);
}

String _sleepClock(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _sleepDuration(BuildContext context, int seconds) {
  final safeSeconds = seconds < 0 ? 0 : seconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  if (Localizations.localeOf(context).languageCode == 'zh') {
    if (hours == 0) return '$minutes分';
    if (minutes == 0) return '$hours小时';
    return '$hours小时$minutes分';
  }
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

class _SleepStructureValue {
  const _SleepStructureValue({
    required this.label,
    required this.seconds,
    required this.percent,
    required this.color,
  });

  final String label;
  final int seconds;
  final int percent;
  final Color color;
}

List<int> _sleepPercentages(List<int> values, int total) {
  if (total <= 0) return List<int>.filled(values.length, 0);
  final exact = values.map((value) => value * 100 / total).toList();
  final result = exact.map((value) => value.floor()).toList();
  final remaining = 100 - result.fold<int>(0, (sum, value) => sum + value);
  final indices = [for (var index = 0; index < values.length; index++) index]
    ..sort(
      (left, right) =>
          (exact[right] - result[right]).compareTo(exact[left] - result[left]),
    );
  for (var index = 0; index < remaining && indices.isNotEmpty; index++) {
    result[indices[index % indices.length]]++;
  }
  return result;
}
