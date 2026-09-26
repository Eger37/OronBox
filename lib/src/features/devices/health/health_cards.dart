import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oronbox/src/app/generated/app_localizations.dart';
import 'package:oronbox/src/features/devices/health/health_models.dart';

class AdaptiveHealthCardWrap extends StatelessWidget {
  const AdaptiveHealthCardWrap({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        const minCardWidth = 260.0;
        final width = constraints.maxWidth;
        final columnCount = ((width + gap) / (minCardWidth + gap))
            .floor()
            .clamp(1, 4);
        final cardWidth = (width - (columnCount - 1) * gap) / columnCount;
        final fullWidthActivity = width < 600 && columnCount > 1;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (index, child) in children.indexed)
              SizedBox(
                width: index == 0 && fullWidthActivity ? width : cardWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class ActivityOverviewCard extends StatelessWidget {
  const ActivityOverviewCard({
    required this.summary,
    required this.onPressed,
    super.key,
  });

  final HealthDailySummary? summary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final colors = theme.colorScheme;
    final value = summary;
    final steps = value?.steps;
    // `totalCalories` is basal + active energy. It must not be presented as
    // the activity-calorie ring when the report omits active calories.
    final calories = value?.activeCalories;
    final standing = value?.standingHours;
    return _HealthCard(
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.deviceHealthActivityOverview,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: CustomPaint(
              painter: _ActivityRingsPainter(
                trackColor: colors.outlineVariant,
                colors: [colors.primary, colors.tertiary, colors.secondary],
                progress: [
                  _progress(calories, 500),
                  _progress(steps, 10000),
                  _progress(standing, 12),
                ],
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ActivityValue(
                label: l10n.deviceHealthActiveCalories,
                value: calories == null ? '—' : '$calories kcal',
                color: colors.primary,
              ),
              _ActivityValue(
                label: l10n.deviceHealthSteps,
                value: steps == null ? '—' : '$steps',
                color: colors.tertiary,
              ),
              _ActivityValue(
                label: l10n.deviceHealthStanding,
                value: standing == null ? '—' : '$standing h',
                color: colors.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _progress(int? value, int target) =>
      value == null ? 0 : (value / target).clamp(0.0, 1.0);
}

/// A single-metric activity timeline. Xiaomi activity records are increments,
/// so the day view groups them into the same 24 hourly columns as the home
/// activity card instead of connecting sparse records into a false trace.
class ActivityTimelineChart extends StatelessWidget {
  const ActivityTimelineChart({
    required this.samples,
    required this.start,
    required this.end,
    required this.useCalories,
    this.height = 220,
    super.key,
  });

  final List<HealthActivitySample> samples;
  final DateTime start;
  final DateTime end;
  final bool useCalories;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ActivityHourlyChart(
      values: _activityHourlyValues(
        samples,
        start: start,
        end: end,
        useCalories: useCalories,
      ),
      start: start,
      end: end,
      color: useCalories ? colors.primary : colors.tertiary,
      gridColor: colors.outlineVariant,
      height: height,
    );
  }
}

/// Renders one full-day activity series as twenty-four hourly columns
/// together with the same four time anchors used by the health cards.
class ActivityHourlyChart extends StatelessWidget {
  const ActivityHourlyChart({
    required this.values,
    required this.start,
    required this.end,
    required this.color,
    required this.gridColor,
    this.showYAxis = true,
    this.height = 188,
    super.key,
  });

  final List<double> values;
  final DateTime start;
  final DateTime end;
  final Color color;
  final Color gridColor;
  final bool showYAxis;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maximum = _evenAxisMaximum(
                  values.fold<double>(0, math.max) * 1.15,
                );
                final slotWidth = constraints.maxWidth / values.length;
                final barWidth = (slotWidth * .58).clamp(4.0, 14.0).toDouble();
                return BarChart(
                  _activityHourlyChartData(
                    hourly: values,
                    maximum: maximum,
                    barWidth: barWidth,
                    color: color,
                    gridColor: gridColor,
                    labelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    showYAxis: showYAxis,
                  ),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.linear,
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          _ActivityHourlyXAxis(
            start: start,
            end: end,
            leadingWidth: showYAxis ? _healthCompactYAxisWidth : 0,
          ),
        ],
      ),
    );
  }
}

BarChartData _activityHourlyChartData({
  required List<double> hourly,
  required double maximum,
  required double barWidth,
  required Color color,
  required Color gridColor,
  required Color labelColor,
  required bool showYAxis,
}) {
  final track = gridColor.withValues(alpha: .18);
  return BarChartData(
    barGroups: [
      for (final (index, value) in hourly.indexed)
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: value,
              fromY: 0,
              width: barWidth,
              color: value > 0 ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(barWidth / 2),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                fromY: 0,
                toY: maximum,
                color: track,
              ),
            ),
          ],
        ),
    ],
    alignment: BarChartAlignment.spaceEvenly,
    minY: 0,
    maxY: maximum,
    gridData: FlGridData(
      show: showYAxis,
      drawVerticalLine: false,
      horizontalInterval: maximum / 2,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: gridColor.withValues(alpha: .35), strokeWidth: 1),
    ),
    titlesData: FlTitlesData(
      show: true,
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: showYAxis,
          reservedSize: showYAxis ? _healthCompactYAxisWidth : 0,
          interval: maximum / 2,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            space: _healthYAxisGap,
            child: Text(
              value.round().toString(),
              maxLines: 1,
              style: TextStyle(color: labelColor, fontSize: 9),
            ),
          ),
        ),
      ),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    ),
    borderData: FlBorderData(show: false),
    barTouchData: const BarTouchData(enabled: false),
  );
}

List<double> _activityHourlyValues(
  List<HealthActivitySample> samples, {
  required DateTime start,
  required DateTime end,
  required bool useCalories,
}) {
  const slots = 24;
  final values = List<double>.filled(slots, 0);
  final span = end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
  if (span <= 0) return values;
  for (final sample in samples) {
    final timestamp = sample.timestamp.millisecondsSinceEpoch;
    if (timestamp < start.millisecondsSinceEpoch ||
        timestamp >= end.millisecondsSinceEpoch) {
      continue;
    }
    final value = useCalories ? sample.activeCalories : sample.steps;
    if (value == null || value < 0) continue;
    final slot = ((timestamp - start.millisecondsSinceEpoch) * slots ~/ span)
        .clamp(0, slots - 1);
    values[slot] += value;
  }
  return values;
}

double _evenAxisMaximum(double value) {
  var maximum = math.max(1, value).ceilToDouble();
  if (maximum.round().isOdd) maximum += 1;
  return maximum;
}

class _ActivityHourlyXAxis extends StatelessWidget {
  const _ActivityHourlyXAxis({
    required this.start,
    required this.end,
    this.leadingWidth = 0,
  });

  final DateTime start;
  final DateTime end;
  final double leadingWidth;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final labels = [
      _activityAxisTime(start, 0, end),
      _activityAxisTime(start, 6, end),
      _activityAxisTime(start, 12, end),
      _activityAxisTime(start, 18, end),
      _activityAxisTime(start, 24, end),
    ];
    return Row(
      children: [
        SizedBox(width: leadingWidth),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final label in labels) Text(label, style: style)],
          ),
        ),
      ],
    );
  }
}

String _activityAxisTime(DateTime start, int hours, DateTime end) {
  final value = start.add(Duration(hours: hours));
  if (value == end && hours == 24) return '24:00';
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:00';
}

class HealthMetricCard extends StatelessWidget {
  const HealthMetricCard({
    required this.metric,
    required this.title,
    required this.icon,
    required this.color,
    required this.value,
    required this.detail,
    required this.samples,
    required this.onPressed,
    this.chartStart,
    this.chartEnd,
    super.key,
  });

  final XiaomiHealthMetric metric;
  final String title;
  final IconData icon;
  final Color color;
  final String value;
  final String detail;
  final List<HealthSample> samples;
  final VoidCallback onPressed;
  final DateTime? chartStart;
  final DateTime? chartEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _HealthCard(
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Icon(Icons.chevron_right, color: theme.hintColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(detail, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _HealthHomeTimelineChart(
                          metric: metric,
                          samples: samples,
                          color: color,
                          gridColor: theme.colorScheme.outlineVariant,
                          start: chartStart,
                          end: chartEnd,
                          showGrid: false,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                _HealthXAxis(
                  start: chartStart,
                  end: chartEnd,
                  compact: true,
                  leadingWidth: _healthCompactYAxisWidth,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HealthDailyMetricCard extends StatelessWidget {
  const HealthDailyMetricCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.value,
    required this.detail,
    required this.days,
    required this.valueFor,
    required this.onPressed,
    super.key,
  });

  final String title;
  final IconData icon;
  final Color color;
  final String value;
  final String detail;
  final List<HealthDailySummary> days;
  final int? Function(HealthDailySummary day) valueFor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _HealthCard(
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Icon(Icons.chevron_right, color: theme.hintColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(detail, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Expanded(
            child: HealthDailyLineChart(
              days: days,
              valueFor: valueFor,
              color: color,
              height: 72,
              showXAxis: false,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }
}

class HealthAbnormalHeartRateCard extends StatelessWidget {
  const HealthAbnormalHeartRateCard({
    required this.title,
    required this.records,
    required this.highLabel,
    required this.lowLabel,
    required this.recordLabel,
    required this.onPressed,
    super.key,
  });

  final String title;
  final List<HealthAbnormalHeartRateRecord> records;
  final String highLabel;
  final String lowLabel;
  final String recordLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...records]
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final latest = sorted.isEmpty ? null : sorted.last;
    final kind = latest == null
        ? ''
        : switch (latest.kind) {
            HealthAbnormalHeartRateKind.high => highLabel,
            HealthAbnormalHeartRateKind.low => lowLabel,
            HealthAbnormalHeartRateKind.unknown => '',
          };
    return _HealthCard(
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_outlined, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Icon(Icons.chevron_right, color: theme.hintColor),
            ],
          ),
          const Spacer(),
          Text(
            latest == null ? '—' : '${latest.value} bpm',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            latest == null
                ? recordLabel
                : '$kind · ${records.length} $recordLabel',
            style: theme.textTheme.bodyMedium,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class HealthAbnormalHealthCard extends StatelessWidget {
  const HealthAbnormalHealthCard({
    required this.title,
    required this.records,
    required this.labelFor,
    required this.valueFor,
    required this.recordLabel,
    required this.onPressed,
    this.icon = Icons.warning_amber_outlined,
    this.color = Colors.red,
    super.key,
  });

  final String title;
  final List<HealthAbnormalHealthRecord> records;
  final String Function(HealthAbnormalHealthRecord record) labelFor;
  final String Function(HealthAbnormalHealthRecord record) valueFor;
  final String recordLabel;
  final VoidCallback onPressed;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...records]
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final latest = sorted.isEmpty ? null : sorted.last;
    return _HealthCard(
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Icon(Icons.chevron_right, color: theme.hintColor),
            ],
          ),
          const Spacer(),
          Text(
            latest == null ? '—' : valueFor(latest),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            latest == null
                ? recordLabel
                : '${labelFor(latest)} · ${records.length} $recordLabel',
            style: theme.textTheme.bodyMedium,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class HealthDailyLineChart extends StatelessWidget {
  const HealthDailyLineChart({
    required this.days,
    required this.valueFor,
    required this.color,
    this.height = 220,
    this.showXAxis = true,
    this.compact = false,
    super.key,
  });

  final List<HealthDailySummary> days;
  final int? Function(HealthDailySummary day) valueFor;
  final Color color;
  final double height;
  final bool showXAxis;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...days]
      ..sort((left, right) => left.date.compareTo(right.date));
    final visible = sorted.length > 30
        ? sorted.sublist(sorted.length - 30)
        : sorted;
    return Column(
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _HealthDailyLinePainter(
              days: visible,
              valueFor: valueFor,
              color: color,
              gridColor: theme.colorScheme.outlineVariant,
              labelColor:
                  theme.textTheme.bodySmall?.color ??
                  theme.colorScheme.onSurfaceVariant,
              compact: compact,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        if (showXAxis && visible.isNotEmpty) ...[
          const SizedBox(height: 6),
          _HealthDailyXAxis(
            days: visible,
            compact: compact,
            leadingWidth: compact
                ? _healthCompactYAxisWidth
                : _healthYAxisWidth,
          ),
        ],
      ],
    );
  }
}

class HealthSleepCard extends StatelessWidget {
  const HealthSleepCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.summary,
    this.totalDurationSeconds,
    required this.noDataLabel,
    required this.onPressed,
    super.key,
  });

  final String title;
  final IconData icon;
  final Color color;
  final HealthSleepSummary? summary;
  final int? totalDurationSeconds;
  final String noDataLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final sleep = summary;
    final stageStats = <(String, String)>[];
    final vitalStats = <(String, String)>[];
    if (sleep != null) {
      final deep = _sleepStageDuration(
        sleep,
        HealthSleepStageKind.deep,
        sleep.deepSleepDurationSeconds,
      );
      final light = _sleepStageDuration(
        sleep,
        HealthSleepStageKind.light,
        sleep.lightSleepDurationSeconds,
      );
      final rem = _sleepStageDuration(
        sleep,
        HealthSleepStageKind.rem,
        sleep.remSleepDurationSeconds,
      );
      if (deep != null) {
        stageStats.add((
          l10n.deviceHealthSleepDeep,
          _formatSleepSegmentDuration(deep),
        ));
      }
      if (light != null) {
        stageStats.add((
          l10n.deviceHealthSleepLight,
          _formatSleepSegmentDuration(light),
        ));
      }
      if (rem != null) {
        stageStats.add((
          l10n.deviceHealthSleepRem,
          _formatSleepSegmentDuration(rem),
        ));
      }
      final hrv = _averageSleepHrv(sleep);
      if (hrv != null) {
        vitalStats.add((l10n.deviceHealthSleepHrv, '$hrv ms'));
      }
      if (sleep.averageHeartRate != null) {
        vitalStats.add((
          l10n.deviceHealthSleepAverageHeartRate,
          '${sleep.averageHeartRate} bpm',
        ));
      }
      if (sleep.averageBloodOxygen != null) {
        vitalStats.add((
          l10n.deviceHealthSleepAverageBloodOxygen,
          '${sleep.averageBloodOxygen}%',
        ));
      }
    }
    return _HealthCard(
      height: null,
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Icon(Icons.chevron_right, color: theme.hintColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            sleep == null
                ? '—'
                : _formatSleepDuration(
                    totalDurationSeconds ?? sleep.durationSeconds,
                  ),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 2),
          Text(
            sleep == null
                ? noDataLabel
                : '${_formatSleepTime(sleep.startedAt)} – '
                      '${_formatSleepTime(sleep.endedAt)}',
            style: theme.textTheme.bodySmall,
          ),
          if (stageStats.isNotEmpty || vitalStats.isNotEmpty) ...[
            const SizedBox(height: 6),
            if (stageStats.isNotEmpty) _SleepCardStatsRow(entries: stageStats),
            if (vitalStats.isNotEmpty) ...[
              const SizedBox(height: 4),
              _SleepCardStatsRow(entries: vitalStats),
            ],
          ],
        ],
      ),
    );
  }
}

/// Compact vitality summary that follows the same hierarchy as the sleep
/// card: one prominent value followed by flat supporting facts. Vitality is a
/// daily score, not a 24-hour sampled signal, so a sparkline would imply a
/// precision the device does not provide.
class HealthVitalityCard extends StatelessWidget {
  const HealthVitalityCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.summary,
    required this.noDataLabel,
    required this.onPressed,
    this.sevenDayTotal,
    super.key,
  });

  final String title;
  final IconData icon;
  final Color color;
  final HealthDailySummary? summary;
  final String noDataLabel;
  final VoidCallback onPressed;

  /// Local calendar-window total that keeps zero days explicit. Prefer it over
  /// the device's embedded 7-day field, which can skip zero days.
  final int? sevenDayTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final day = summary;
    final score =
        sevenDayTotal ?? day?.vitalityLast7Days ?? day?.vitalityCurrent;
    final entries = <(String, String)>[
      if (day?.vitalityIncreaseLight != null)
        (l10n.deviceHealthLightIntensity, '+${day!.vitalityIncreaseLight}'),
      if (day?.vitalityIncreaseModerate != null ||
          day?.vitalityIncreaseHigh != null)
        (
          l10n.deviceHealthModerateHighIntensity,
          '+${(day!.vitalityIncreaseModerate ?? 0) + (day.vitalityIncreaseHigh ?? 0)}',
        ),
      if (day?.vitalityNextTargetMinutes != null)
        (
          _localizedVitality(context, '下一目标', 'Next target'),
          _localizedVitality(
            context,
            '${day!.vitalityNextTargetMinutes} 分钟',
            '${day.vitalityNextTargetMinutes} min',
          ),
        ),
    ];
    return _HealthCard(
      height: null,
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Icon(Icons.chevron_right, color: theme.hintColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            score == null ? '—' : '$score',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 2),
          Text(
            day == null
                ? noDataLabel
                : _localizedVitality(context, '近 7 日累计', '7-day total'),
            style: theme.textTheme.bodySmall,
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SleepCardStatsRow(entries: entries.take(3).toList()),
          ],
        ],
      ),
    );
  }
}

String _localizedVitality(BuildContext context, String zh, String fallback) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : fallback;

class HealthWorkoutCard extends StatelessWidget {
  const HealthWorkoutCard({
    required this.workouts,
    required this.onPressed,
    super.key,
  });

  final List<HealthWorkoutSummary> workouts;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final workout = workouts.isEmpty
        ? null
        : workouts.reduce(
            (latest, candidate) =>
                candidate.endedAt.isAfter(latest.endedAt) ? candidate : latest,
          );
    final accent = workout == null ? Colors.teal : _workoutAccent(workout);
    final stats = <(String, String)>[];
    if (workout?.distanceMeters != null) {
      stats.add((
        l10n.deviceHealthDistance,
        _formatWorkoutDistance(workout!.distanceMeters!),
      ));
    }
    if (workout?.calories != null) {
      stats.add((l10n.deviceHealthCalories, '${workout!.calories} kcal'));
    }
    if (workout?.effectiveAverageHeartRate != null) {
      stats.add((
        l10n.deviceHealthHeartRate,
        '${workout!.effectiveAverageHeartRate} bpm',
      ));
    }
    if (workout != null && healthWorkoutSupportsPace(workout)) {
      stats.add((
        l10n.deviceHealthAveragePace,
        _formatWorkoutPace(workout.averagePaceSecondsPerKilometer!),
      ));
    }
    return _HealthCard(
      height: null,
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_run_outlined, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.deviceHealthWorkoutGeneric,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Icon(Icons.chevron_right, color: theme.hintColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            workout == null ? '—' : _workoutCardName(context, workout),
            style: theme.textTheme.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            workout == null
                ? l10n.deviceHealthNoData
                : '${_formatHealthDate(workout.startedAt)} '
                      '${_formatHealthTime(workout.startedAt)} · '
                      '${_formatWorkoutDuration(workout.endedAt.difference(workout.startedAt))}',
            style: theme.textTheme.bodySmall,
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SleepCardStatsRow(entries: stats.take(4).toList()),
          ],
        ],
      ),
    );
  }
}

class _SleepCardStatsRow extends StatelessWidget {
  const _SleepCardStatsRow({required this.entries});

  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, entry) in entries.indexed)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == entries.length - 1 ? 0 : 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.$1,
                    style: labelStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    entry.$2,
                    style: valueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class HealthSleepTimeline extends StatelessWidget {
  const HealthSleepTimeline({
    required this.summary,
    required this.stageLabels,
    super.key,
  });

  final HealthSleepSummary summary;
  final Map<HealthSleepStageKind, String> stageLabels;

  @override
  Widget build(BuildContext context) {
    final colors = <HealthSleepStageKind, Color>{
      // Mi Fitness SleepStageStyle's default palette.
      HealthSleepStageKind.awake: const Color(0xFFB8C1D5),
      HealthSleepStageKind.rem: const Color(0xFF47BEFF),
      HealthSleepStageKind.light: const Color(0xFF3986F6),
      HealthSleepStageKind.deep: const Color(0xFF2231B6),
    };
    final visibleKinds = summary.stages
        .map((stage) => stage.kind)
        .where((kind) => kind != HealthSleepStageKind.unknown)
        .toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SleepStageLegend(
          stageLabels: stageLabels,
          colors: colors,
          visibleKinds: visibleKinds,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: CustomPaint(
            painter: _SleepTimelinePainter(
              start: summary.startedAt,
              end: summary.endedAt,
              stages: summary.stages,
              colors: colors,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 6),
        _HealthXAxis(start: summary.startedAt, end: summary.endedAt),
      ],
    );
  }
}

class HealthSleepHrvChart extends StatelessWidget {
  const HealthSleepHrvChart({required this.summary, super.key});

  final HealthSleepSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final points = [...summary.hrvPoints]
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final pointValues = points.map((point) => point.value).toList();
    final average = summary.averageHrv ?? _average(pointValues);
    final minimum = summary.hrvMin ?? _minimum(pointValues);
    final maximum = summary.hrvMax ?? _maximum(pointValues);
    final bounds = _sleepHrvBounds(
      minimum: minimum,
      maximum: maximum,
      values: pointValues,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SleepHrvStat(
                label: l10n.deviceHealthAverage,
                value: _formatHrv(average),
              ),
            ),
            Expanded(
              child: _SleepHrvStat(
                label: l10n.deviceHealthRange,
                value: minimum == null || maximum == null
                    ? '—'
                    : '${_formatHrvNumber(minimum)}–'
                          '${_formatHrvNumber(maximum)}',
              ),
            ),
          ],
        ),
        if (points.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _SleepHrvPainter(
                start: summary.startedAt,
                end: summary.endedAt,
                points: points,
                bounds: bounds,
                color: theme.colorScheme.tertiary,
                gridColor: theme.colorScheme.outlineVariant,
                labelStyle: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 6),
          _HealthXAxis(
            start: summary.startedAt,
            end: summary.endedAt,
            leadingWidth: _sleepHrvYAxisWidth,
          ),
        ],
      ],
    );
  }

  int? _average(List<int> values) {
    if (values.isEmpty) return null;
    return (values.reduce((left, right) => left + right) / values.length)
        .round();
  }

  int? _minimum(List<int> values) =>
      values.isEmpty ? null : values.reduce(math.min);

  int? _maximum(List<int> values) =>
      values.isEmpty ? null : values.reduce(math.max);

  String _formatHrv(int? value) =>
      value == null ? '—' : '${_formatHrvNumber(value)} ms';

  String _formatHrvNumber(int value) => value.toString();
}

class _SleepStageLegend extends StatelessWidget {
  const _SleepStageLegend({
    required this.stageLabels,
    required this.colors,
    required this.visibleKinds,
  });

  final Map<HealthSleepStageKind, String> stageLabels;
  final Map<HealthSleepStageKind, Color> colors;
  final Set<HealthSleepStageKind> visibleKinds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kinds = <HealthSleepStageKind>[
      HealthSleepStageKind.deep,
      HealthSleepStageKind.light,
      HealthSleepStageKind.rem,
      HealthSleepStageKind.awake,
    ].where(visibleKinds.contains);
    return Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        for (final kind in kinds)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: colors[kind],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                stageLabels[kind] ?? kind.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class HealthLineChart extends StatelessWidget {
  const HealthLineChart({
    required this.metric,
    required this.samples,
    required this.color,
    this.height = 220,
    this.start,
    this.end,
    super.key,
  });

  final List<HealthSample> samples;
  final XiaomiHealthMetric metric;
  final Color color;
  final double height;
  final DateTime? start;
  final DateTime? end;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        SizedBox(
          height: height,
          child: _HealthExactLineChart(
            metric: metric,
            samples: samples,
            color: color,
            gridColor: theme.colorScheme.outlineVariant,
            start: start,
            end: end,
          ),
        ),
        const SizedBox(height: 6),
        _HealthXAxis(start: start, end: end, leadingWidth: _healthYAxisWidth),
      ],
    );
  }
}

/// The same three time scales used by Mi Fitness' day/week/month health
/// pages. Detail charts keep the source points and render them through the
/// shared fl_chart line/area component; missing intervals remain gaps.
enum HealthChartPeriod { day, week, month }

class HealthOfficialRangeChart extends StatelessWidget {
  const HealthOfficialRangeChart({
    required this.metric,
    required this.period,
    required this.samples,
    required this.days,
    required this.color,
    this.start,
    this.end,
    this.height = 196,
    super.key,
  });

  final XiaomiHealthMetric metric;
  final HealthChartPeriod period;
  final List<HealthSample> samples;
  final List<HealthDailySummary> days;
  final Color color;
  final DateTime? start;
  final DateTime? end;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedStart = _resolvedStart();
    final resolvedEnd = _resolvedEnd(resolvedStart);
    final bars = _bars(resolvedStart, resolvedEnd);
    final axis = _adaptiveHealthAxis(
      metric,
      bars.whereType<_HealthRangeBar>().map((bar) => bar.average),
    );
    return Column(
      children: [
        SizedBox(
          height: height,
          child: _HealthRangeLineChart(
            metric: metric,
            period: period,
            bars: bars,
            color: color,
            gridColor: theme.colorScheme.outlineVariant,
            start: resolvedStart,
            end: resolvedEnd,
            axis: axis,
          ),
        ),
        const SizedBox(height: 6),
        _HealthOfficialXAxis(
          period: period,
          start: resolvedStart,
          end: resolvedEnd,
          days: days,
          leadingWidth: _healthYAxisWidth,
        ),
      ],
    );
  }

  DateTime _resolvedStart() {
    if (start != null) return start!;
    final latest = samples.isEmpty
        ? null
        : samples.reduce(
            (left, right) =>
                left.timestamp.isAfter(right.timestamp) ? left : right,
          );
    final anchor =
        latest?.timestamp ??
        (days.isEmpty ? null : days.last.date) ??
        DateTime.now();
    final local = anchor.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  DateTime _resolvedEnd(DateTime resolvedStart) {
    if (end != null) return end!;
    return switch (period) {
      HealthChartPeriod.day => healthAddCalendarDays(resolvedStart, 1),
      HealthChartPeriod.week => healthAddCalendarDays(resolvedStart, 7),
      HealthChartPeriod.month => healthAddCalendarDays(resolvedStart, 31),
    };
  }

  List<_HealthRangeBar?> _bars(DateTime resolvedStart, DateTime resolvedEnd) {
    if (period == HealthChartPeriod.day) {
      final daySamples = [...samples]
        ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
      if (daySamples.isNotEmpty) {
        // Keep the source cadence. A sample at 08:03 must remain at 08:03;
        // placing it into one of 24/48 artificial slots loses the detail that
        // the official daily page exposes through its point-bars.
        return daySamples
            .map(
              (sample) => _HealthRangeBar(
                label: sample.timestamp,
                minimum: sample.value,
                maximum: sample.value,
                average: sample.value,
              ),
            )
            .toList(growable: false);
      }
      // The summary only carries min/max for the whole day with no timestamp,
      // so there is no honest x position to draw it at. Returning no bar keeps
      // the chart from inventing a point at noon; the 平均/最低/最高 summary
      // below the chart already communicates these values.
      return const <_HealthRangeBar?>[];
    }

    final sampleValuesByDay = <String, List<double>>{};
    for (final sample in samples) {
      final local = sample.timestamp.toLocal();
      final key = '${local.year}-${local.month}-${local.day}';
      sampleValuesByDay.putIfAbsent(key, () => <double>[]).add(sample.value);
    }
    return days
        .map((day) {
          final summary = healthMetricDailyValues(day, metric);
          final local = day.date.toLocal();
          final sampleValues =
              sampleValuesByDay['${local.year}-${local.month}-${local.day}'] ??
              const <double>[];
          final average = summary.average ?? _averageDouble(sampleValues);
          final minimum = summary.minimum ?? _minimumDouble(sampleValues);
          final maximum = summary.maximum ?? _maximumDouble(sampleValues);
          if (minimum == null && maximum == null && average == null) {
            return null;
          }
          // A day can legitimately carry only one edge (for example a single
          // minimum without an average), so every fallback chain must tolerate
          // the other two being null independently.
          final fallback = average ?? minimum ?? maximum!;
          return _HealthRangeBar(
            label: day.date,
            minimum: minimum ?? fallback,
            maximum: maximum ?? fallback,
            average:
                average ?? ((minimum ?? fallback) + (maximum ?? fallback)) / 2,
          );
        })
        .toList(growable: false);
  }
}

/// The compact home chart keeps the HEAD visual grammar: forty-eight rounded
/// half-hour slots, with each measured slot rendered as a coloured range.
/// This is deliberately a slot/range chart rather than a line chart: the
/// homepage communicates coverage and value spread at a glance, while the
/// detail page owns the precise time-series view.
class _HealthHomeTimelineChart extends StatelessWidget {
  const _HealthHomeTimelineChart({
    required this.metric,
    required this.samples,
    required this.color,
    required this.gridColor,
    required this.showGrid,
    this.start,
    this.end,
  });

  final XiaomiHealthMetric metric;
  final List<HealthSample> samples;
  final Color color;
  final Color gridColor;
  final bool showGrid;
  final DateTime? start;
  final DateTime? end;

  @override
  Widget build(BuildContext context) {
    final chartStart = start ?? healthDayStart(DateTime.now());
    final chartEnd = end ?? healthAddCalendarDays(chartStart, 1);
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => BarChart(
        _healthHomeBarChartData(
          metric: metric,
          samples: samples,
          start: chartStart,
          end: chartEnd,
          color: color,
          gridColor: gridColor,
          showGrid: showGrid,
          chartWidth: constraints.maxWidth,
          labelColor: theme.colorScheme.onSurfaceVariant,
        ),
        duration: const Duration(milliseconds: 180),
        curve: Curves.linear,
      ),
    );
  }
}

BarChartData _healthHomeBarChartData({
  required XiaomiHealthMetric metric,
  required List<HealthSample> samples,
  required DateTime start,
  required DateTime end,
  required Color color,
  required Color gridColor,
  required bool showGrid,
  required double chartWidth,
  required Color labelColor,
}) {
  final axis = _healthAxis(metric);
  const slots = 48;
  final ranges = aggregateHealthRanges(
    samples,
    start: start,
    end: end,
    slots: slots,
  );
  final axisSpan = axis.maximum - axis.minimum;
  final slotWidth = chartWidth.isFinite ? chartWidth / slots : 6.0;
  final trackWidth = (slotWidth * .64)
      .clamp(2.0, showGrid ? 10.0 : 7.0)
      .toDouble();
  final minimumRange = axisSpan * (showGrid ? .045 : .04);
  final trackColor = gridColor.withValues(alpha: showGrid ? .30 : .18);
  final groups = <BarChartGroupData>[];
  for (var index = 0; index < slots; index++) {
    final range = ranges[index];
    final backDraw = BackgroundBarChartRodData(
      show: true,
      fromY: axis.minimum,
      toY: axis.maximum,
      color: trackColor,
    );
    if (range == null) {
      groups.add(
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: axis.minimum,
              fromY: axis.minimum,
              width: trackWidth,
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(trackWidth / 2),
              backDrawRodData: backDraw,
            ),
          ],
        ),
      );
      continue;
    }

    var minimum = range.minimum.clamp(axis.minimum, axis.maximum).toDouble();
    var maximum = range.maximum.clamp(axis.minimum, axis.maximum).toDouble();
    if (maximum - minimum < minimumRange) {
      // Keep a measured high value at its actual height. Centering a narrow
      // range and then filling the minimum visual height after clamping used
      // to move readings such as 218 bpm all the way to the 220 bpm ceiling.
      if (axis.maximum - maximum < minimumRange) {
        minimum = math.max(axis.minimum, maximum - minimumRange);
      } else {
        maximum = math.min(axis.maximum, minimum + minimumRange);
      }
    }
    groups.add(
      BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            fromY: minimum,
            toY: maximum,
            width: trackWidth,
            color: color,
            borderRadius: BorderRadius.circular(trackWidth / 2),
            backDrawRodData: backDraw,
          ),
        ],
      ),
    );
  }

  return BarChartData(
    barGroups: groups,
    alignment: BarChartAlignment.spaceEvenly,
    minY: axis.minimum,
    maxY: axis.maximum,
    baselineY: axis.minimum,
    gridData: FlGridData(
      show: showGrid,
      drawVerticalLine: false,
      horizontalInterval: axisSpan / 2,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: gridColor.withValues(alpha: .35), strokeWidth: 1),
    ),
    titlesData: FlTitlesData(
      show: true,
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: _healthCompactYAxisWidth,
          interval: axisSpan / 2,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            space: _healthYAxisGap,
            child: Text(
              axis.format(value, includeUnit: false),
              maxLines: 1,
              style: TextStyle(color: labelColor, fontSize: 9),
            ),
          ),
        ),
      ),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    ),
    borderData: FlBorderData(show: false),
    barTouchData: const BarTouchData(enabled: false),
  );
}

class _HealthExactLineChart extends StatelessWidget {
  const _HealthExactLineChart({
    required this.metric,
    required this.samples,
    required this.color,
    required this.gridColor,
    required this.start,
    required this.end,
  });

  final XiaomiHealthMetric metric;
  final List<HealthSample> samples;
  final Color color;
  final Color gridColor;
  final DateTime? start;
  final DateTime? end;

  @override
  Widget build(BuildContext context) {
    final resolvedStart = start ?? healthDayStart(DateTime.now());
    final resolvedEnd = end ?? healthAddCalendarDays(resolvedStart, 1);
    final bars = [...samples]
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    return LineChart(
      _healthRangeChartData(
        metric: metric,
        period: HealthChartPeriod.day,
        bars: [
          for (final sample in bars)
            _HealthRangeBar(
              label: sample.timestamp,
              minimum: sample.value,
              maximum: sample.value,
              average: sample.value,
            ),
        ],
        color: color,
        gridColor: gridColor,
        start: resolvedStart,
        end: resolvedEnd,
        axis: _adaptiveHealthAxis(metric, bars.map((sample) => sample.value)),
        context: context,
      ),
      duration: const Duration(milliseconds: 180),
      curve: Curves.linear,
    );
  }
}

class _HealthRangeLineChart extends StatelessWidget {
  const _HealthRangeLineChart({
    required this.metric,
    required this.period,
    required this.bars,
    required this.color,
    required this.gridColor,
    required this.start,
    required this.end,
    required this.axis,
  });

  final XiaomiHealthMetric metric;
  final HealthChartPeriod period;
  final List<_HealthRangeBar?> bars;
  final Color color;
  final Color gridColor;
  final DateTime start;
  final DateTime end;
  final _HealthAxis axis;

  @override
  Widget build(BuildContext context) => LineChart(
    _healthRangeChartData(
      metric: metric,
      period: period,
      bars: bars,
      color: color,
      gridColor: gridColor,
      start: start,
      end: end,
      axis: axis,
      context: context,
    ),
    duration: const Duration(milliseconds: 180),
    curve: Curves.linear,
  );
}

LineChartData _healthRangeChartData({
  required XiaomiHealthMetric metric,
  required HealthChartPeriod period,
  required List<_HealthRangeBar?> bars,
  required Color color,
  required Color gridColor,
  required DateTime start,
  required DateTime end,
  required _HealthAxis axis,
  required BuildContext context,
}) {
  final daySpan = math.max(1, end.difference(start).inMilliseconds).toDouble();
  final spots = <FlSpot>[];
  final sourceBySpot = <_HealthRangeBar?>[];
  DateTime? previous;
  for (var index = 0; index < bars.length; index++) {
    final bar = bars[index];
    if (bar == null) {
      if (spots.isNotEmpty && spots.last != FlSpot.nullSpot) {
        spots.add(FlSpot.nullSpot);
        sourceBySpot.add(null);
      }
      previous = null;
      continue;
    }
    if (period == HealthChartPeriod.day &&
        previous != null &&
        bar.label.difference(previous).inMinutes > 15) {
      spots.add(FlSpot.nullSpot);
      sourceBySpot.add(null);
    }
    final x = period == HealthChartPeriod.day
        ? bar.label.difference(start).inMilliseconds /
              Duration.millisecondsPerHour
        : index + .5;
    spots.add(FlSpot(x, bar.average.clamp(axis.minimum, axis.maximum)));
    sourceBySpot.add(bar);
    previous = bar.label;
  }
  while (spots.isNotEmpty && spots.last == FlSpot.nullSpot) {
    spots.removeLast();
    sourceBySpot.removeLast();
  }
  final maxX = period == HealthChartPeriod.day
      ? daySpan / Duration.millisecondsPerHour
      : math.max(1, bars.length).toDouble();
  final line = LineChartBarData(
    spots: spots,
    color: color,
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
        colors: [color.withValues(alpha: .28), color.withValues(alpha: .025)],
      ),
    ),
  );
  final axisInterval = (axis.maximum - axis.minimum) / 2;
  final axisLabelStyle = Theme.of(context).textTheme.labelSmall
      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
  return LineChartData(
    minX: 0,
    maxX: maxX,
    minY: axis.minimum,
    maxY: axis.maximum,
    baselineY: axis.minimum,
    lineBarsData: spots.isEmpty ? const [] : [line],
    gridData: FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: axisInterval,
      getDrawingHorizontalLine: (_) =>
          FlLine(color: gridColor.withValues(alpha: .35), strokeWidth: 1),
    ),
    titlesData: FlTitlesData(
      show: true,
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: _healthYAxisWidth,
          interval: axisInterval,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            space: _healthYAxisGap,
            child: Text(
              axis.format(value, includeUnit: false),
              maxLines: 1,
              style: axisLabelStyle,
            ),
          ),
        ),
      ),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    ),
    borderData: FlBorderData(show: false),
    lineTouchData: LineTouchData(
      enabled: spots.isNotEmpty,
      getTouchedSpotIndicator: (_, indexes) => [
        for (final _ in indexes)
          TouchedSpotIndicatorData(
            FlLine(color: color.withValues(alpha: .48), strokeWidth: 1),
            const FlDotData(show: false),
          ),
      ],
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) =>
            Theme.of(context).colorScheme.surfaceContainerHighest,
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        getTooltipItems: (touchedSpots) => [
          for (final touched in touchedSpots)
            if (touched.spotIndex >= 0 &&
                touched.spotIndex < sourceBySpot.length &&
                sourceBySpot[touched.spotIndex] != null)
              LineTooltipItem(
                _healthChartTooltipLabel(
                  sourceBySpot[touched.spotIndex]!,
                  metric,
                  period,
                  axis,
                ),
                TextStyle(color: color, fontWeight: FontWeight.w600),
              )
            else
              null,
        ],
      ),
    ),
  );
}

String _healthChartTooltipLabel(
  _HealthRangeBar bar,
  XiaomiHealthMetric metric,
  HealthChartPeriod period,
  _HealthAxis axis,
) {
  final label = period == HealthChartPeriod.day
      ? _formatHealthTime(bar.label)
      : _formatHealthDate(bar.label);
  return '$label · ${axis.format(bar.average)}';
}

class _HealthRangeBar {
  const _HealthRangeBar({
    required this.label,
    required this.minimum,
    required this.maximum,
    required this.average,
  });

  final DateTime label;
  final double minimum;
  final double maximum;
  final double average;
}

class HealthMetricDailyValues {
  const HealthMetricDailyValues({this.average, this.minimum, this.maximum});

  final double? average;
  final double? minimum;
  final double? maximum;

  bool get hasValue => average != null || minimum != null || maximum != null;
}

HealthMetricDailyValues healthMetricDailyValues(
  HealthDailySummary day,
  XiaomiHealthMetric metric,
) => switch (metric) {
  XiaomiHealthMetric.heartRate => HealthMetricDailyValues(
    average: day.averageHeartRate?.toDouble(),
    minimum: day.minHeartRate?.toDouble(),
    maximum: day.maxHeartRate?.toDouble(),
  ),
  XiaomiHealthMetric.restingHeartRate => HealthMetricDailyValues(
    average: day.restingHeartRate?.toDouble(),
    minimum: day.restingHeartRate?.toDouble(),
    maximum: day.restingHeartRate?.toDouble(),
  ),
  XiaomiHealthMetric.bloodOxygen => HealthMetricDailyValues(
    average: day.averageBloodOxygen?.toDouble(),
    minimum: day.minBloodOxygen?.toDouble(),
    maximum: day.maxBloodOxygen?.toDouble(),
  ),
  XiaomiHealthMetric.stress => HealthMetricDailyValues(
    average: day.averageStress?.toDouble(),
    minimum: day.minStress?.toDouble(),
    maximum: day.maxStress?.toDouble(),
  ),
  XiaomiHealthMetric.vitality => HealthMetricDailyValues(
    average: (day.vitalityLast7Days ?? day.vitalityCurrent)?.toDouble(),
    minimum: (day.vitalityLast7Days ?? day.vitalityCurrent)?.toDouble(),
    maximum: (day.vitalityLast7Days ?? day.vitalityCurrent)?.toDouble(),
  ),
  XiaomiHealthMetric.activity => HealthMetricDailyValues(
    average: day.steps?.toDouble(),
    minimum: day.steps?.toDouble(),
    maximum: day.steps?.toDouble(),
  ),
  XiaomiHealthMetric.activeCalories => HealthMetricDailyValues(
    average: day.activeCalories?.toDouble(),
    minimum: day.activeCalories?.toDouble(),
    maximum: day.activeCalories?.toDouble(),
  ),
  XiaomiHealthMetric.sleep ||
  XiaomiHealthMetric.workout => const HealthMetricDailyValues(),
};

/// Calendar-day addition on wall-clock fields. [DateTime.add] with a fixed
/// 24-hour [Duration] shifts the result by an hour when the interval crosses
/// a daylight-saving boundary, which silently moves weekly/monthly windows.
DateTime healthAddCalendarDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// Whole calendar days between two dates, independent of host timezone
/// offset changes (see [healthAddCalendarDays]).
int healthCalendarDaysBetween(DateTime start, DateTime end) => DateTime.utc(
  end.year,
  end.month,
  end.day,
).difference(DateTime.utc(start.year, start.month, start.day)).inDays;

double? _averageDouble(List<double> values) {
  if (values.isEmpty) return null;
  return values.reduce((left, right) => left + right) / values.length;
}

double? _minimumDouble(List<double> values) =>
    values.isEmpty ? null : values.reduce(math.min);

double? _maximumDouble(List<double> values) =>
    values.isEmpty ? null : values.reduce(math.max);

class _HealthOfficialXAxis extends StatelessWidget {
  const _HealthOfficialXAxis({
    required this.period,
    required this.start,
    required this.end,
    required this.days,
    this.leadingWidth = 0,
  });

  final HealthChartPeriod period;
  final DateTime start;
  final DateTime end;
  final List<HealthDailySummary> days;
  final double leadingWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final labels = switch (period) {
      HealthChartPeriod.day => [
        _formatChartTime(start),
        _formatChartTime(start.add(const Duration(hours: 6))),
        _formatChartTime(start.add(const Duration(hours: 12))),
        _formatChartTime(start.add(const Duration(hours: 18))),
        _formatChartEndTime(start, end),
      ],
      HealthChartPeriod.week || HealthChartPeriod.month => _periodDateLabels(),
    };
    return Row(
      children: [
        SizedBox(width: leadingWidth),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (final label in labels) Text(label, style: style)],
          ),
        ),
      ],
    );
  }

  List<String> _periodDateLabels() {
    if (days.isEmpty) {
      return [_formatHealthDate(start), _formatHealthDate(end)];
    }
    final indices = period == HealthChartPeriod.week
        ? [0, days.length ~/ 2, days.length - 1]
        : [0, days.length ~/ 3, (days.length * 2) ~/ 3, days.length - 1];
    final result = <String>[];
    for (final index in indices) {
      if (index < 0 || index >= days.length) continue;
      final label = _formatHealthDate(days[index].date);
      if (!result.contains(label)) result.add(label);
    }
    return result;
  }
}

class _HealthXAxis extends StatelessWidget {
  const _HealthXAxis({
    required this.start,
    required this.end,
    this.compact = false,
    this.leadingWidth = 0,
  });

  final DateTime? start;
  final DateTime? end;
  final bool compact;
  final double leadingWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedStart = start ?? healthDayStart(DateTime.now());
    final resolvedEnd = end ?? healthAddCalendarDays(resolvedStart, 1);
    final middle = resolvedStart.add(
      Duration(
        milliseconds:
            (resolvedEnd.millisecondsSinceEpoch -
                resolvedStart.millisecondsSinceEpoch) ~/
            2,
      ),
    );
    final style =
        (compact ? theme.textTheme.labelSmall : theme.textTheme.bodySmall)
            ?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: compact ? 9 : null,
            );
    return Row(
      children: [
        SizedBox(width: leadingWidth),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatChartTime(resolvedStart), style: style),
              Text(_formatChartTime(middle), style: style),
              Text(
                _formatChartEndTime(resolvedStart, resolvedEnd),
                style: style,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HealthDailyXAxis extends StatelessWidget {
  const _HealthDailyXAxis({
    required this.days,
    required this.compact,
    this.leadingWidth = 0,
  });

  final List<HealthDailySummary> days;
  final bool compact;
  final double leadingWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        (compact ? theme.textTheme.labelSmall : theme.textTheme.bodySmall)
            ?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: compact ? 9 : null,
            );
    return Row(
      children: [
        SizedBox(width: leadingWidth),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatHealthDate(days.first.date), style: style),
              if (days.length > 1)
                Text(
                  _formatHealthDate(days[days.length ~/ 2].date),
                  style: style,
                ),
              Text(_formatHealthDate(days.last.date), style: style),
            ],
          ),
        ),
      ],
    );
  }
}

class _HealthAxis {
  const _HealthAxis({
    required this.minimum,
    required this.maximum,
    this.unit = '',
  });

  final double minimum;
  final double maximum;
  final String unit;

  double get middle => (minimum + maximum) / 2;

  String format(double value, {bool includeUnit = true}) {
    final number = value.round().toString();
    return !includeUnit || unit.isEmpty ? number : '$number $unit';
  }
}

// Keep the axis column narrow enough that the plot owns most of the card. The
// gap is independent from the column width so labels do not touch the plot
// when the column is tightened.
const _healthYAxisWidth = 32.0;
const _healthCompactYAxisWidth = 26.0;
const _healthYAxisGap = 4.0;
const _sleepHrvYAxisWidth = 30.0;

class _HealthDailyLinePainter extends CustomPainter {
  _HealthDailyLinePainter({
    required this.days,
    required this.valueFor,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.compact,
  });

  final List<HealthDailySummary> days;
  final int? Function(HealthDailySummary day) valueFor;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final points = days
        .map((day) => (day: day, value: valueFor(day)))
        .where((point) => point.value != null)
        .toList(growable: false);
    if (points.isEmpty) return;

    final values = points.map((point) => point.value!).toList();
    final dataMinimum = values.reduce(math.min);
    final dataMaximum = values.reduce(math.max);
    final spread = dataMaximum - dataMinimum;
    final padding = math.max(1.0, spread * .15);
    final lower = dataMinimum - padding;
    final upper = dataMaximum + padding;
    final first = points.first.day.date;
    final last = points.last.day.date;
    final span = last.millisecondsSinceEpoch - first.millisecondsSinceEpoch;
    final plotLeft = compact ? _healthCompactYAxisWidth : _healthYAxisWidth;
    final axisLabelWidth = plotLeft - _healthYAxisGap;
    final plotTop = compact ? 2.0 : 6.0;
    final plotBottom = compact ? 2.0 : 6.0;
    final plotWidth = math.max(1.0, size.width - plotLeft);
    final plotHeight = math.max(1.0, size.height - plotTop - plotBottom);
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: compact ? .22 : .32)
      ..strokeWidth = 1;
    final textStyle = TextStyle(color: labelColor, fontSize: compact ? 9 : 10);

    for (var index = 0; index <= 2; index++) {
      final fraction = index / 2;
      final y = plotTop + plotHeight * fraction;
      canvas.drawLine(Offset(plotLeft, y), Offset(size.width, y), gridPaint);
      final value = upper - (upper - lower) * fraction;
      final painter = TextPainter(
        text: TextSpan(text: value.round().toString(), style: textStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
      )..layout(maxWidth: axisLabelWidth);
      painter.paint(
        canvas,
        Offset(
          plotLeft - _healthYAxisGap - painter.width,
          y - painter.height / 2,
        ),
      );
    }

    double x(DateTime date) {
      if (span <= 0) return plotLeft + plotWidth / 2;
      final elapsed =
          date.millisecondsSinceEpoch - first.millisecondsSinceEpoch;
      return plotLeft + plotWidth * (elapsed / span).clamp(0.0, 1.0);
    }

    double y(int value) {
      final normalized = ((value - lower) / (upper - lower)).clamp(0.0, 1.0);
      return plotTop + plotHeight * (1 - normalized);
    }

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 2 : 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final position = Offset(x(point.day.date), y(point.value!));
      final gap = index == 0
          ? Duration.zero
          : point.day.date.difference(points[index - 1].day.date);
      if (index == 0 || gap > const Duration(days: 2)) {
        path.moveTo(position.dx, position.dy);
      } else {
        path.lineTo(position.dx, position.dy);
      }
    }
    canvas.drawPath(path, linePaint);

    final pointPaint = Paint()..color = color;
    final radius = compact ? 2.4 : 3.2;
    for (final point in points) {
      canvas.drawCircle(
        Offset(x(point.day.date), y(point.value!)),
        radius,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HealthDailyLinePainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.valueFor != valueFor ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelColor != labelColor ||
      oldDelegate.compact != compact;
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.child,
    required this.onPressed,
    this.height = 214,
  });

  final Widget child;
  final VoidCallback onPressed;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: height,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.all(constraints.maxWidth < 190 ? 12 : 18),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityValue extends StatelessWidget {
  const _ActivityValue({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(label, style: textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: textTheme.labelLarge),
      ],
    );
  }
}

class _ActivityRingsPainter extends CustomPainter {
  _ActivityRingsPainter({
    required this.trackColor,
    required this.colors,
    required this.progress,
  });

  final Color trackColor;
  final List<Color> colors;
  final List<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width * .42, (size.height - 8) * .80);
    final center = Offset(size.width / 2, size.height - 8);
    for (var index = 0; index < 3; index++) {
      final currentRadius = math.max(1.0, radius - index * 14.0);
      final track = Paint()
        ..color = trackColor.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 9;
      final value = Paint()
        ..color = colors[index]
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 9;
      final rect = Rect.fromCircle(center: center, radius: currentRadius);
      canvas.drawArc(rect, math.pi, math.pi, false, track);
      canvas.drawArc(rect, math.pi, math.pi * progress[index], false, value);
    }
  }

  @override
  bool shouldRepaint(covariant _ActivityRingsPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.colors != colors ||
      oldDelegate.trackColor != trackColor;
}

class _SleepTimelinePainter extends CustomPainter {
  _SleepTimelinePainter({
    required this.start,
    required this.end,
    required this.stages,
    required this.colors,
  });

  final DateTime start;
  final DateTime end;
  final List<HealthSleepStageSegment> stages;
  final Map<HealthSleepStageKind, Color> colors;

  static const _kinds = [
    HealthSleepStageKind.awake,
    HealthSleepStageKind.rem,
    HealthSleepStageKind.light,
    HealthSleepStageKind.deep,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const plotTop = 12.0;
    const plotBottom = 12.0;
    final plotWidth = math.max(1.0, size.width);
    final plotHeight = math.max(1.0, size.height - plotTop - plotBottom);
    final segments = _normalizedSleepStages(
      start: start,
      end: end,
      stages: stages,
    );
    final visibleKinds = _kinds
        .where((kind) => segments.any((stage) => stage.kind == kind))
        .toList(growable: false);
    if (visibleKinds.isEmpty) return;

    // Mi Fitness lays out entries next to each other using their real
    // durations.  Keep that same rule here instead of quantizing the report
    // into slots.  A sleep report can contain tiny gaps between packets; those
    // gaps are not rendered as white holes in the official chart, so the
    // visual widths are normalized from the stage durations and fill the plot.
    final laneHeight = plotHeight / visibleKinds.length;
    final stageThickness = math.min(34.0, math.max(24.0, laneHeight * .66));
    final cornerRadius = math.min(8.0, stageThickness / 2);
    final joinWidth = math.min(10.0, math.max(5.0, plotWidth * .012));

    double yFor(HealthSleepStageKind kind) {
      final index = visibleKinds.indexOf(kind);
      return plotTop + laneHeight * (index + .5);
    }

    final durations = segments
        .map(
          (stage) => math.max(
            1.0,
            stage.endedAt.difference(stage.startedAt).inMilliseconds.toDouble(),
          ),
        )
        .toList(growable: false);
    final totalDuration = durations.fold<double>(
      0,
      (total, duration) => total + duration,
    );
    if (totalDuration <= 0) return;

    final bands =
        <({HealthSleepStageSegment stage, double left, double right})>[];
    var elapsed = 0.0;
    for (var index = 0; index < segments.length; index++) {
      final left = plotWidth * elapsed / totalDuration;
      elapsed += durations[index];
      final right = index == segments.length - 1
          ? plotWidth
          : math.max(left + 1.0, plotWidth * elapsed / totalDuration);
      bands.add((stage: segments[index], left: left, right: right));
    }

    final bandPaint = Paint()..isAntiAlias = true;
    for (var index = 0; index < bands.length; index++) {
      final band = bands[index];
      final color = colors[band.stage.kind];
      if (color == null) continue;
      final centerY = yFor(band.stage.kind);
      final rect = Rect.fromLTRB(
        band.left,
        centerY - stageThickness / 2,
        band.right,
        centerY + stageThickness / 2,
      );
      bandPaint.color = color;
      canvas.drawPath(
        _sleepBandPath(
          rect,
          radius: cornerRadius,
          roundLeft: index == 0,
          roundRight: index == bands.length - 1,
        ),
        bandPaint,
      );
    }

    // The official renderer closes each stage with a shared transition path.
    // Draw that path over the flat-ended bands so the chart is one continuous
    // staircase ribbon: no rounded inner caps and no white gaps. The narrow
    // orthogonal transition is also where Mi Fitness blends the stage colors.
    for (var index = 1; index < bands.length; index++) {
      final previous = bands[index - 1];
      final current = bands[index];
      if (previous.stage.kind == current.stage.kind) continue;
      final previousColor = colors[previous.stage.kind];
      final currentColor = colors[current.stage.kind];
      if (previousColor == null || currentColor == null) continue;
      final previousY = yFor(previous.stage.kind);
      final currentY = yFor(current.stage.kind);
      final transitionPath = _sleepTransitionPath(
        x: current.left,
        fromY: previousY,
        toY: currentY,
        halfHeight: stageThickness / 2,
        width: joinWidth,
      );
      final top = math.min(previousY, currentY) - stageThickness / 2;
      final bottom = math.max(previousY, currentY) + stageThickness / 2;
      final topColor = previousY <= currentY ? previousColor : currentColor;
      final bottomColor = previousY <= currentY ? currentColor : previousColor;
      final transitionPaint = Paint()
        ..isAntiAlias = true
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ).createShader(Rect.fromLTRB(0, top, 1, bottom));
      canvas.drawPath(transitionPath, transitionPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SleepTimelinePainter oldDelegate) =>
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.stages != stages ||
      oldDelegate.colors != colors;
}

Path _sleepBandPath(
  Rect rect, {
  required double radius,
  required bool roundLeft,
  required bool roundRight,
}) {
  final corner = math.min(radius, math.min(rect.width, rect.height) / 2);
  final path = Path();
  path.moveTo(rect.left + (roundLeft ? corner : 0), rect.top);
  path.lineTo(rect.right - (roundRight ? corner : 0), rect.top);
  if (roundRight) {
    path.quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + corner);
  }
  path.lineTo(rect.right, rect.bottom - (roundRight ? corner : 0));
  if (roundRight) {
    path.quadraticBezierTo(
      rect.right,
      rect.bottom,
      rect.right - corner,
      rect.bottom,
    );
  }
  path.lineTo(rect.left + (roundLeft ? corner : 0), rect.bottom);
  if (roundLeft) {
    path.quadraticBezierTo(
      rect.left,
      rect.bottom,
      rect.left,
      rect.bottom - corner,
    );
  }
  path.lineTo(rect.left, rect.top + (roundLeft ? corner : 0));
  if (roundLeft) {
    path.quadraticBezierTo(rect.left, rect.top, rect.left + corner, rect.top);
  }
  path.close();
  return path;
}

Path _sleepTransitionPath({
  required double x,
  required double fromY,
  required double toY,
  required double halfHeight,
  required double width,
}) {
  final rect = Rect.fromLTRB(
    x - width / 2,
    math.min(fromY, toY) - halfHeight,
    x + width / 2,
    math.max(fromY, toY) + halfHeight,
  );
  return Path()..addRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(math.min(3.0, width / 2))),
  );
}

List<HealthSleepStageSegment> _normalizedSleepStages({
  required DateTime start,
  required DateTime end,
  required Iterable<HealthSleepStageSegment> stages,
}) {
  final sorted = [...stages]
    ..sort((left, right) => left.startedAt.compareTo(right.startedAt));
  final normalized = <HealthSleepStageSegment>[];
  for (final stage in sorted) {
    if (stage.kind == HealthSleepStageKind.unknown) continue;
    final clippedStart = stage.startedAt.isBefore(start)
        ? start
        : stage.startedAt;
    final clippedEnd = stage.endedAt.isAfter(end) ? end : stage.endedAt;
    if (!clippedEnd.isAfter(clippedStart)) continue;
    final clipped = HealthSleepStageSegment(
      startedAt: clippedStart,
      endedAt: clippedEnd,
      kind: stage.kind,
    );
    if (normalized.isNotEmpty &&
        normalized.last.kind == clipped.kind &&
        clipped.startedAt.difference(normalized.last.endedAt).inMilliseconds <=
            1000) {
      final previous = normalized.last;
      normalized[normalized.length - 1] = HealthSleepStageSegment(
        startedAt: previous.startedAt,
        endedAt: clipped.endedAt.isAfter(previous.endedAt)
            ? clipped.endedAt
            : previous.endedAt,
        kind: previous.kind,
      );
    } else {
      normalized.add(clipped);
    }
  }
  return normalized;
}

class _SleepHrvStat extends StatelessWidget {
  const _SleepHrvStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _SleepHrvPainter extends CustomPainter {
  _SleepHrvPainter({
    required this.start,
    required this.end,
    required this.points,
    required this.bounds,
    required this.color,
    required this.gridColor,
    required this.labelStyle,
  });

  final DateTime start;
  final DateTime end;
  final List<HealthSleepHrvPoint> points;
  final ({double lower, double upper}) bounds;
  final Color color;
  final Color gridColor;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final plottedPoints = _downsampleSleepHrvPoints(points);
    if (plottedPoints.isEmpty) return;
    final span = end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
    if (span <= 0) return;

    const plotTop = 6.0;
    const plotBottom = 6.0;
    final plotLeft = _sleepHrvYAxisWidth;
    final plotWidth = math.max(1.0, size.width - plotLeft);
    final plotHeight = math.max(1.0, size.height - plotTop - plotBottom);
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: .3)
      ..strokeWidth = 1;
    for (var index = 0; index <= 2; index++) {
      final fraction = index / 2;
      final y = plotTop + plotHeight * fraction;
      canvas.drawLine(Offset(plotLeft, y), Offset(size.width, y), gridPaint);
      final value = bounds.upper - (bounds.upper - bounds.lower) * fraction;
      final label = TextPainter(
        text: TextSpan(text: value.round().toString(), style: labelStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
      )..layout(maxWidth: plotLeft - _healthYAxisGap);
      label.paint(
        canvas,
        Offset(plotLeft - _healthYAxisGap - label.width, y - label.height / 2),
      );
    }

    double x(DateTime timestamp) {
      final elapsed =
          timestamp.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
      return plotLeft + plotWidth * (elapsed / span).clamp(0.0, 1.0);
    }

    double y(int value) {
      final normalized =
          ((value - bounds.lower) / (bounds.upper - bounds.lower)).clamp(
            0.0,
            1.0,
          );
      return plotTop + plotHeight * (1 - normalized);
    }

    final path = Path();
    for (var index = 0; index < plottedPoints.length; index++) {
      final point = plottedPoints[index];
      final position = Offset(x(point.timestamp), y(point.value));
      final gap = index == 0
          ? Duration.zero
          : point.timestamp.difference(plottedPoints[index - 1].timestamp);
      if (index == 0 || gap > const Duration(hours: 2)) {
        path.moveTo(position.dx, position.dy);
      } else {
        path.lineTo(position.dx, position.dy);
      }
    }
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);
    final pointPaint = Paint()..color = color;
    for (final point in plottedPoints) {
      canvas.drawCircle(
        Offset(x(point.timestamp), y(point.value)),
        2.5,
        pointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SleepHrvPainter oldDelegate) =>
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.points != points ||
      oldDelegate.bounds != bounds ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelStyle != labelStyle;
}

({double lower, double upper}) _sleepHrvBounds({
  required int? minimum,
  required int? maximum,
  required Iterable<int> values,
}) {
  final valueList = values.toList(growable: false);
  final fallbackMinimum = valueList.isEmpty
      ? (maximum ?? 0)
      : valueList.reduce(_minInt);
  final fallbackMaximum = valueList.isEmpty
      ? (minimum ?? 0)
      : valueList.reduce(_maxInt);
  var lower = (minimum ?? fallbackMinimum).toDouble();
  var upper = (maximum ?? fallbackMaximum).toDouble();
  if (upper <= lower) {
    lower -= 1;
    upper += 1;
  }
  lower = lower.floorToDouble();
  upper = upper.ceilToDouble();
  if ((upper - lower).round().isOdd) upper += 1;
  return (lower: lower, upper: upper);
}

List<HealthSleepHrvPoint> _downsampleSleepHrvPoints(
  Iterable<HealthSleepHrvPoint> input,
) {
  final sorted = [...input]
    ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
  if (sorted.length <= 1) return sorted;

  const bucket = Duration(minutes: 10);
  final result = <HealthSleepHrvPoint>[sorted.first];
  var lastSelected = sorted.first.timestamp;
  for (final point in sorted.skip(1)) {
    if (point.timestamp.difference(lastSelected) >= bucket) {
      result.add(point);
      lastSelected = point.timestamp;
    }
  }

  final minimum = sorted.reduce(
    (left, right) => left.value <= right.value ? left : right,
  );
  final maximum = sorted.reduce(
    (left, right) => left.value >= right.value ? left : right,
  );
  for (final extreme in [minimum, maximum]) {
    if (!result.any((point) => point.timestamp == extreme.timestamp)) {
      result.add(extreme);
    }
  }
  result.sort((left, right) => left.timestamp.compareTo(right.timestamp));
  return result;
}

int _minInt(int left, int right) => left < right ? left : right;

int _maxInt(int left, int right) => left > right ? left : right;

class HealthRangeBucket {
  const HealthRangeBucket({required this.minimum, required this.maximum});

  final double minimum;
  final double maximum;
}

/// Divides a time interval into [slots] equal buckets and returns each
/// bucket's measured minimum and maximum.
List<HealthRangeBucket?> aggregateHealthRanges(
  Iterable<HealthSample> samples, {
  required DateTime start,
  required DateTime end,
  required int slots,
}) {
  if (slots <= 0) return const <HealthRangeBucket?>[];
  final buckets = List<List<double>>.generate(slots, (_) => <double>[]);
  final span = end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
  if (span <= 0) return List<HealthRangeBucket?>.filled(slots, null);
  for (final sample in samples) {
    if (!sample.isUsable ||
        sample.timestamp.isBefore(start) ||
        !sample.timestamp.isBefore(end)) {
      continue;
    }
    final elapsed =
        sample.timestamp.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
    final index = (elapsed * slots ~/ span).clamp(0, slots - 1);
    buckets[index].add(sample.value);
  }
  return buckets
      .map((values) {
        if (values.isEmpty) return null;
        return HealthRangeBucket(
          minimum: values.reduce(math.min),
          maximum: values.reduce(math.max),
        );
      })
      .toList(growable: false);
}

_HealthAxis _healthAxis(XiaomiHealthMetric metric) => switch (metric) {
  XiaomiHealthMetric.heartRate || XiaomiHealthMetric.restingHeartRate =>
    const _HealthAxis(minimum: 30, maximum: 220, unit: 'bpm'),
  XiaomiHealthMetric.bloodOxygen => const _HealthAxis(
    minimum: 50,
    maximum: 100,
    unit: '%',
  ),
  XiaomiHealthMetric.stress => const _HealthAxis(minimum: 0, maximum: 100),
  XiaomiHealthMetric.vitality => const _HealthAxis(minimum: 0, maximum: 100),
  XiaomiHealthMetric.activity => const _HealthAxis(
    minimum: 0,
    maximum: 1000,
    unit: 'steps',
  ),
  XiaomiHealthMetric.activeCalories => const _HealthAxis(
    minimum: 0,
    maximum: 100,
    unit: 'kcal',
  ),
  XiaomiHealthMetric.sleep ||
  XiaomiHealthMetric.workout => const _HealthAxis(minimum: 0, maximum: 100),
};

/// Tightens the metric's natural axis to the visible data so a day with a
/// single 91 bpm reading no longer stretches from 30 to 220 with an empty
/// chart. Bounds are snapped to readable steps and kept inside the metric's
/// physical limits.
_HealthAxis _adaptiveHealthAxis(
  XiaomiHealthMetric metric,
  Iterable<double> values,
) {
  final base = _healthAxis(metric);
  final present = values
      .where((value) => value.isFinite)
      .toList(growable: false);
  if (present.isEmpty) return base;
  final dataMinimum = present.reduce(math.min);
  final dataMaximum = present.reduce(math.max);
  final span = dataMaximum - dataMinimum;

  final (double floor, double ceiling, double step) = switch (metric) {
    XiaomiHealthMetric.heartRate ||
    XiaomiHealthMetric.restingHeartRate => (30.0, 220.0, 10.0),
    XiaomiHealthMetric.bloodOxygen => (50.0, 100.0, 5.0),
    XiaomiHealthMetric.stress => (0.0, 100.0, 10.0),
    XiaomiHealthMetric.vitality => (0.0, 100.0, 10.0),
    XiaomiHealthMetric.activity => (0.0, double.infinity, 500.0),
    XiaomiHealthMetric.activeCalories => (0.0, double.infinity, 50.0),
    _ => (base.minimum, base.maximum, 0.0),
  };

  // A metric with no natural step (sleep/workout) keeps its base bounds.
  if (step <= 0) return base;

  var lower = dataMinimum;
  var upper = dataMaximum;
  // Give at least one readable step of headroom so a single value sits in the
  // middle rather than hugging an edge.
  final padding = math.max(step, span * .12);
  lower -= padding;
  upper += padding;
  lower = (lower / step).floorToDouble() * step;
  upper = (upper / step).ceilToDouble() * step;
  if (upper - lower < step * 2) {
    final middle = (lower + upper) / 2;
    lower = middle - step;
    upper = middle + step;
  }
  lower = lower.clamp(floor, ceiling);
  upper = upper.clamp(floor, ceiling);
  if (upper - lower < step) {
    if (lower <= floor) {
      upper = math.min(ceiling, floor + step);
    } else {
      lower = math.max(floor, upper - step);
    }
  }
  if (lower >= upper) return base;
  return _HealthAxis(minimum: lower, maximum: upper, unit: base.unit);
}

DateTime healthDayStart(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String _formatSleepTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _formatChartTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _formatChartEndTime(DateTime start, DateTime end) {
  final localStart = start.toLocal();
  final localEnd = end.toLocal();
  if (localStart.hour == 0 &&
      localStart.minute == 0 &&
      localEnd.hour == 0 &&
      localEnd.minute == 0 &&
      localEnd.difference(localStart).inDays == 1) {
    return '24:00';
  }
  return _formatChartTime(end);
}

String _formatHealthDate(DateTime value) {
  final local = value.toLocal();
  return '${local.month}/${local.day}';
}

String _formatHealthTime(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _workoutCardName(BuildContext context, HealthWorkoutSummary workout) {
  final zh = Localizations.localeOf(context).languageCode == 'zh';
  String name(String chinese, String fallback) => zh ? chinese : fallback;
  if (workout.activityType == 22) {
    return switch (workout.subSportType) {
      2 || 207 => name('户外健走', 'Outdoor walking'),
      4 => name('登山', 'Mountaineering'),
      5 => name('越野跑', 'Trail running'),
      15 => name('徒步', 'Hiking'),
      _ => name('户外跑步', 'Outdoor running'),
    };
  }
  return switch (workout.activityType) {
    1 => name('户外跑步', 'Outdoor running'),
    2 => name('户外健走', 'Outdoor walking'),
    3 => name('室内跑步', 'Indoor running'),
    4 => name('登山', 'Mountaineering'),
    5 => name('越野跑', 'Trail running'),
    6 || 23 => name('户外骑行', 'Outdoor cycling'),
    7 => name('室内骑行', 'Indoor cycling'),
    8 => name('自由训练', 'Free training'),
    9 || 10 => name('游泳', 'Swimming'),
    11 => name('椭圆机', 'Elliptical'),
    13 => name('划船机', 'Rowing'),
    14 => name('跳绳', 'Jump rope'),
    15 => name('徒步', 'Hiking'),
    _ => name('运动', 'Workout'),
  };
}

Color _workoutAccent(HealthWorkoutSummary workout) =>
    switch (workout.activityType) {
      6 || 7 || 23 => Colors.blue,
      9 || 10 => Colors.cyan,
      11 => Colors.deepPurple,
      13 => Colors.indigo,
      14 => Colors.orange,
      8 => Colors.pinkAccent,
      _ => Colors.teal,
    };

String _formatSleepDuration(int seconds) =>
    '${seconds ~/ 3600}h ${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}m';

String _formatSleepSegmentDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

String _formatWorkoutDuration(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 24 * 60 * 60);
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours == 0) return '${minutes}m';
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

String _formatWorkoutDistance(int meters) =>
    meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '$meters m';

String _formatWorkoutPace(int seconds) {
  final minutes = seconds ~/ 60;
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return "$minutes'$remainder\"";
}

int? _sleepStageDuration(
  HealthSleepSummary summary,
  HealthSleepStageKind kind,
  int? reportedSeconds,
) {
  if (reportedSeconds != null && reportedSeconds > 0) {
    return reportedSeconds;
  }
  final seconds = summary.stages
      .where((stage) => stage.kind == kind)
      .fold<int>(0, (total, stage) => total + stage.durationSeconds);
  return seconds > 0 ? seconds : null;
}

int? _averageSleepHrv(HealthSleepSummary summary) {
  final average = summary.averageHrv;
  if (average != null) return average;
  final values = summary.hrvPoints.map((point) => point.value).toList();
  if (values.isEmpty) return null;
  return (values.reduce((left, right) => left + right) / values.length).round();
}
