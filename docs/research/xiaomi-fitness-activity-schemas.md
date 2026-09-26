# Xiaomi Fitness activity schema architecture

Date: 2026-09-06

> Implementation note: the historical gap analysis below describes the parser
> baseline at the start of this work. The daily totals/deltas section and the
> current implementation section reflect the present worktree. The report is
> not a promise that every official schema is supported.

## Scope and sources

This report compares the local primary artifacts for Xiaomi Fitness 9.23.35 and
9.24.367 with OronBox's current activity-file parser. It does not use web
sources. The APK assets are:

- `/Users/orpudding/Documents/MiFitness/小米运动健康_9.23.35_jadx/resources/assets/schemas.zip`
- `/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/resources/assets/schemas.zip`

Archive-member references below use paths inside those ZIP files.

## Executive picture

The wearable sends one activity file with a seven-byte `FitnessDataId`, a
reserved byte, a schema-defined body, and a trailing CRC. `FitnessDataId`
contains the timestamp, schema version, data category, activity subtype, and
file kind. Xiaomi Fitness uses those values as a three-part route:

```text
FitnessDataId
  -> category/activity type + file kind + v{version}
  -> index.json schema path
  -> BinarySchemaDecoder
  -> typed parse result (daily/report/record/GPS/HR recovery)
  -> storage.json business storage route
  -> database/repositories
  -> summary cards, charts, sport list and sport detail UI
```

OronBox correctly implements the transport envelope, CRC validation, and a
useful subset of health parsing. It does not implement the official generic
schema engine or its storage router. The current worktree keeps the selected
common sport report/record/GPS/heart-rate-recovery paths as typed Dart models;
unsupported schema routes remain explicit instead of being silently treated as
generic numeric samples.

## What is in `schemas.zip`

Both archives contain four kinds of content:

1. `.version`, package metadata.
2. `index.json`, the route from header semantics to a schema member.
3. `storage.json`, the route from decoded data to application storage keys.
4. JSON binary schemas grouped as `<activity>/<file-kind>/<name>_vN.json`.

In 9.24, `index.json::$types` maps raw category `0` to `health` and `1` to
`sport`. Health subtype examples are daily activity `0`, manual measurement
`6`, all-day sleep `8`, abnormal `9`, weight/body composition `10`, ECG `11`,
temperature `12`, and OSA `13`. Sport subtypes include indoor running `3`,
free training `8`, swimming `9/10`, outdoor foot `22`, outdoor non-foot `23`,
climbing `24`, diving `25`, and esports `26`. File kinds are health
`0=record, 1=report`; sport adds `2=gps, 3=hrr`. Source: 9.24 archive member
`index.json`, `$types`.

The concrete schema files describe more than fixed integers. The official
`BinarySchemaDecoder` supports structures, references, arrays, end-of-file
arrays, validity conditions, bit fields, dependent values, and GPS-specific
handling. Its state and entry points are visible in
`/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/sources/com/xiaomi/fit/fitness/parser/schema/BinarySchemaDecoder.java:48`.

## How Xiaomi Fitness loads and selects a schema

### Asset and downloaded-schema precedence

The default combined provider first asks the downloaded file cache and then
falls back to the APK asset. See
`/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/sources/com/xiaomi/fit/fitness/parser/schema/CombinedSchemaProvider.java:20`.

The more explicit control path selects extracted/downloaded schemas when the
schema MD5 changed, unless the developer setting forces local assets. Otherwise
it reads the bundled ZIP. See `ParserWayControl.java:27-42` and `:51-71` in the
same `parser/schema` directory.

Asset loading scans `schemas.zip` for an exact member path. The path is resolved
from the cached `index.json`, then that JSON member is read as text. See
`/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/sources/com/xiaomi/fit/fitness/parser/schema/utils/SchemaAssetsUtils.java:32-50` and `:98-121`.

For downloaded schemas, Xiaomi extracts the ZIP into a `schemas` directory,
guards against ZIP path traversal, and reads members from disk. See
`/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/sources/com/xiaomi/fit/fitness/parser/schema/utils/SchemaFilesUtilsKt.java:34-105` and `:107-130`.

`SchemaIndexCache` lazily reads both `index.json` and `storage.json` from either
the asset ZIP or the extracted files. Downloaded caches are invalidated by the
schema MD5. See
`/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/sources/com/xiaomi/fit/fitness/parser/schema/utils/SchemaIndexCache.java:69-100`.

### Exact route key

The legacy/fallback route is `(activityType, fileType, "v" + version)`.
`getSchemaInfo()` maps sport and health subtype numbers to semantic directory
names and maps file type `0/1/2/3` to `record/report/gps/hrr`. See
`/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/sources/com/xiaomi/fit/fitness/parser/schema/utils/SchemaFilesUtilsKt.java:133-235`.

The newer route first asks `SchemaIndex.getPathByDataId()`, which uses the
`$types` maps, and falls back to the hard-coded route above. See
`/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/sources/com/xiaomi/fit/fitness/parser/schema/utils/SchemaCacheManagerKt.java:31-41`.

This means version is not a loose compatibility hint. It selects an exact
schema. If `daily_activity/report/v7` is present but only v6 is implemented,
the two formats must not be assumed identical.

## Parse categories and domain results

`FitnessDataParser` first selects health or sport from `dataType`.

For health, it selects dedicated parsers for daily record/report, daytime and
night sleep, user profile, manual measurement, all-day sleep, abnormal events,
weight/body composition, ECG, and temperature. See
`/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/sources/com/xiaomi/fit/fitness/parser/FitnessDataParser.java:95-132`.

For sport, file kind selects four independent products:

- `record`: time-series and sport-specific detail.
- `report`: the workout summary and aggregate metrics.
- `gps`: route/location data.
- `hrr`: recovery-heart-rate data.

See `FitnessDataParser.java:146-160`. Known sport subtypes get a specialized
record/report parser; unknown types fall back to generic schema-based parsers.
See `FitnessDataParser.java:163-214` and `:217-269`.

Schema decoding is not the final domain mapping. Daily parsers use
`storage.json` field mappings. The routing code maps header category/activity
and file kind, then can select conditional rules from decoded values. Sport
report routing additionally uses `subSportType`. See
`/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/sources/com/xiaomi/fit/fitness/parser/schema/utils/SchemaCacheManagerKt.java:64-85` and `:88-140`.

The 9.24 `storage.json` shows concrete examples:

- daily report `totalFloorsClimbed` -> `daily_activity_report`;
- daily record `floors` -> `daily_activity_record`;
- manual measurement with `measurementType.type == 6` -> `ultravioletIndex`.

Source: 9.24 archive member `storage.json`, `daily_activity` and
`manual_measurement`.

The typed parser result then exposes objects such as `SportBasicReport`, sport
record maps, GPS records, and recovery-rate data to repository/database APIs.
The official sport detail view model retrieves report, record, GPS, and
recovery data separately before it assembles the detail screen; see
`/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/sources/com/xiaomi/fitness/detail/viewmodel/SportRecordDetailViewModel.java` (metadata names
`getSportData`, `getSportRecordData`, `getGPSAndRecordData`, and
`requestRecoverRateData`). This explains the official UI split: report supplies
the headline summary, while record/GPS/HRR supply charts, route, laps/segments,
heart-rate zones, pace/cadence series, and recovery detail.

## Daily totals versus minute-level deltas

The daily activity protocol deliberately has two layers. They must not be
merged by field name:

| File | Schema field | Meaning | OronBox model |
| --- | --- | --- | --- |
| `daily_activity/report` | `totalSteps` | Device total for the day | `HealthDailySummary.steps` |
| `daily_activity/report` | `totalactiveCalories` | Device active-calorie total for the day | `HealthDailySummary.activeCalories` |
| `daily_activity/report` | `totalCalories` | Device total energy for the day, including basal energy | `HealthDailySummary.calories` |
| `daily_activity/record` | `newSteps` | Increment for one minute record | `HealthActivitySample.steps` |
| `daily_activity/record` | `activityCalories` | Increment for one minute record | `HealthActivitySample.activeCalories` |
| `daily_activity/record` | `newCalories` | Increment of total energy for one minute | `HealthActivitySample.caloriesDelta` |

The report total is authoritative when it is present. When a report is absent
or a field is invalid, the adapter sums the matching record deltas for the
selected date. It never uses `totalCalories` as `activeCalories`, and it never
sums a report total with its record deltas. Repeated snapshots are de-duplicated
by record timestamp before storage, so replaying the same file cannot double
the total. The raw activity record also keeps pressure, light sensation,
volume momentum, and floors as separate fields; pressure is not stress.

## Archive comparison: 9.23.35 -> 9.24.367

9.23 has 71 members and 87 indexed schema-version routes. 9.24 has 78 members
and 94 indexed routes. Of the common files, 24 are byte-identical and 42 schema
or metadata files changed.

New members in 9.24:

- `ball_games/gps/ball_games_gps_v1.json`
- `ball_games/record/ball_games_record_v2.json`
- `ball_games/report/ball_games_report_v6.json`
- `daily_activity/record/daily_activity_record_v5.json`
- `daily_activity/report/daily_activity_report_v7.json`
- `ecg/report/ecg_report_v1.json`
- `ecg/report/ecg_report_v2.json`
- `free_training/record/free_training_record_v6.json`
- `indoor_running/record/indoor_running_record_v10.json`
- `indoor_running/report/indoor_running_report_v14.json`
- `manual_measurement/record/manual_measurement_record_v3.json`

Removed physical members in 9.24:

- `daily_activity/record/daily_activity_record_v3.json`
- `full_day_sleep/record/full_day_sleep_record_v5.json`
- `full_day_sleep/record/full_day_sleep_record_v6.json`
- `recover_hr/recovery_hr_report_v1.json`

The all-day-sleep deletion is a routing correction rather than loss of support:
9.24 `index.json` routes all-day-sleep record v5/v6 to the corresponding report
schemas. The `recovery_hr` top-level index entry disappears, while normal sport
activities still route `hrr/v1` to `hrr/hrr_v1.json`.

Important new protocol coverage in 9.24 is therefore daily record v5, daily
report v7, manual measurement v3, indoor running record v10/report v14, free
training record v6, ball-game record v2/report v6/GPS v1, and ECG schemas. The
change to `storage.json` also makes floors and UV index first-class stored data.

## OronBox's current implementation

OronBox validates the CRC, retains the seven-byte ID, and parses the device file
directly. See
`/Users/orpudding/Documents/GitHub/OronBox/lib/src/device/xiaomi/components/health_system.dart:1085-1103`.

It manually decodes header bits into `type`, `subtype`, and `detail`, then uses a
fixed conditional dispatch. Current accepted products are:

- daily report: health subtype 0, detail/report 1;
- daily minute record: health subtype 0, detail/record 0;
- manual measurement: health subtype 6;
- sleep: health subtype 3 or 8;
- abnormal events: health subtype 9;
- sport report: any supported sport subtype with detail/report 1.

Everything else returns an empty parsed file. See
`/Users/orpudding/Documents/GitHub/OronBox/lib/src/device/xiaomi/components/health_system.dart:1219-1266`.

The sync layer maps those intermediate records into `HealthDailySummary`, flat
`HealthSample` points for chart compatibility, composite
`HealthActivitySample` records for lossless activity detail,
`HealthSleepSummary`, `HealthWorkoutSummary`, and
`HealthAbnormalHealthRecord`, merges them with prior local data, and writes
`HealthStore`. See
`/Users/orpudding/Documents/GitHub/OronBox/lib/src/features/devices/health/xiaomi_health_sync_service.dart:176-247` and the domain types at
`/Users/orpudding/Documents/GitHub/OronBox/lib/src/features/devices/health/health_models.dart:3-13`, `:56-104`, `:260-335`, and `:474`.

## Historical coverage gaps at the start of this work

### 1. Entire official categories are unparsed

OronBox has no activity-file parse branch for health subtype 2 daytime sleep,
10 weight/body composition, 11 ECG, 12 temperature, or 13 OSA. It also has no
user-profile path (official native subtype 5). Some of these lack corresponding
OronBox domain models and UI.

Manual measurement consumes temperature and blood-pressure bytes but discards
them because its sample model only has heart rate, blood oxygen, and stress.
See `health_system.dart:1593-1596`. It also does not implement the new 9.24 UV
index storage route.

### 2. Daily v5/v7 drift

OronBox's daily record parser accepts versions 1-5 and preserves the common
v5 minute fields in a composite `XiaomiActivitySampleRecord`. Its daily report
parser accepts v1-v7 and maps the common totals, heart-rate, blood-oxygen,
vitality/training fields, and v7 total floors climbed. See
`health_system.dart:2195-2608`.

The parser is still intentionally not a generic schema engine. Fields such as
UV, temperature, blood pressure, ECG, and body composition remain outside the
current product scope and are not silently flattened into activity data.

### 3. Sport record is entirely missing

OronBox only enters sport parsing when `detail == 1`, which is report. It ignores
all `record` files. Consequently, it cannot produce the time-series used for
pace, speed, cadence, heart rate, altitude, rowing/stroke/skip data, swimming
lengths, group/lap detail, or type-specific mechanics. This is the main reason
an official-like sport detail UI cannot yet be functionally complete.

### 4. GPS is entirely missing

Sport file type 2 never reaches an OronBox branch. This excludes outdoor route
points and GPS-derived detail for outdoor foot/non-foot, climbing, skiing,
swimming, and the new 9.24 ball-game GPS schema. A map or route replay cannot be
built faithfully from the current domain model.

### 5. Heart-rate recovery is entirely missing

Sport file type 3 is ignored. The official app has a dedicated
`RecoverRateRecordParser` (`FitnessDataParser.java:157-160`) and retrieves the
result separately for sport detail. OronBox therefore lacks post-exercise
recovery-heart-rate presentation.

### 6. Sport report is heavily projected

OronBox does recognize many report versions, including indoor run v14 and
free-training v14, using hand-maintained validity lengths. See
`health_system.dart:1811-1987`. But it saves only start/end, activity type,
distance, calories, and average/minimum/maximum heart rate
(`health_system.dart:1780-1794`).

The official `SportBasicReport` mapping contains a much broader vocabulary:
duration/valid duration, pace and speed, steps and cadence, elevation, training
effect, VO2 max, recovery time, heart-rate-zone durations, swimming/rowing/
skipping metrics, power, training load, running dynamics, diving metrics,
sport-specific ball/golf values, goals, and more. The field list is visible in
`/Users/orpudding/Documents/MiFitness/小米运动健康_9.24.367_jadx/sources/com/xiaomi/fit/fitness/parser/sport/base/SportReportBaseParser.java` (nested `ReportType` metadata), while report construction occurs at `:295-306` and
returns a `sportReport` at `:1035-1045`.

### 7. No schema/store indirection

OronBox has no runtime equivalent of `index.json`, generic
`BinarySchemaDecoder`, or `storage.json`. Every new version requires Dart code
changes, and unsupported files are silently represented as an empty parse
result. The snapshot system preserves raw bytes, which reduces reverse-
engineering cost, but replay still uses the same hard-coded parser
(`health_system.dart:1154-1204`).

## Recommended architecture direction

Treat the official archive as upstream protocol evidence, not as a repository
artifact or runtime dependency. Do not commit `schemas.zip`, copy its members,
or reproduce the complete official schema engine. Most routes are not required
by OronBox. Extract only the layouts and fields proven necessary by captured
device files and current product behaviour, then express them as reviewed Dart
types and constants.

The smallest robust direction is:

1. Keep header routing and supported layouts as Dart constants keyed by
   `(category, activity subtype, file kind, version)`. Add a route only after a
   captured snapshot or a required feature proves that it is needed.
2. Extract small typed layout helpers only for repeated binary shapes such as
   validity fields, fixed-width values, record series, GPS points, and HR
   recovery samples. Do not implement the full official JSON schema dialect.
3. Preserve four sport products separately in the domain: report, record, GPS,
   and HR recovery. Join them by workout identity/time only above parsing.
4. Expand the sport report model before redesigning the detail UI. The UI can
   then select applicable sections from available values instead of pretending
   that every activity consists only of duration, distance, calories, and HR.
5. Add floors, temperature, blood pressure, UV, weight/body composition, and ECG
   only with matching domain semantics and UI; do not flatten all of them into a
   generic numeric sample prematurely.
6. Use captured snapshots as regression fixtures for each exact header route.
   Report unsupported `(type, subtype, file kind, version)` values explicitly so
   coverage can be measured instead of silently lost.

The immediate priority for an official-like sport experience is report model
expansion plus sport record/GPS/HRR parsing. Adding more visual polish before
those data products exist will reproduce the official layout without the
official interaction depth.
