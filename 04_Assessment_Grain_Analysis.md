# Assessment Grain Analysis

**Data source:** Live `SchoolDW.silver.PAT` and `SchoolDW.silver.EssentialAssessment`  
**Profile date:** 2026-11-05  
**Approach:** Aggregate-only profiling; no student-level records or JSON values were exported. JSON key names were inspected to determine whether finer-grained source entities are present.

## Executive conclusion

The loaded PAT rows represent **one overall scored student test result per observed test/date/instrument grouping**, not strand, focus-area, question, or skill rows. This is consistent with all 1,412 rows having a `ScaleScore`, and with no populated `Strand` or `FocusArea`. One row maps to each of the 1,412 distinct student/test/date groups. Treat this as the observed assessment-attempt/result grain for Gold, while retaining the source row identity: there is no explicit attempt number or attempt ID, so the feed does not prove that same-day retakes are impossible.

The loaded EssentialAssessment rows represent **focus-area results within a student assessment**. All 1,834 rows have both `Strand` and `FocusArea`; the raw JSON key profile also includes `focus area`, `strand`, and their achievement measures. Grouping by student, date, assessment type, and test name produces 1,777 assessment groups. Fifty-six groups contain multiple rows (maximum three); in all 56, the rows have distinct focus areas and no distinct strand values. Adding focus area to the grouping produces 1,834 unique row signatures. The effective score is `AssessmentPercentage`, not `ScaleScore`: all 1,834 `ScaleScore` values are null, but all 1,834 percentages are present.

Neither source exposes an individual question/skill identifier or an explicit attempt identifier in its mapped columns or observed top-level `SourceDataJson` keys. Do not model these rows as question-level facts, and do not collapse them to one student/date record.

## Actual row profiles

| Measure | PAT | EssentialAssessment |
|---|---:|---:|
| Total rows | 1,412 | 1,834 |
| Distinct `SilverBusinessKey` | 1,412 | 1,834 |
| Duplicate business-key groups / excess rows | 0 / 0 | 0 / 0 |
| Null business keys | 0 | 0 |
| Distinct `StudentSourceId` | 850 | 487 |
| Distinct `CompassPersonId` | 0 | 0 |
| Distinct `Username` | 850 | N/A — column absent |
| Distinct `CompassUsername` | 0 | 0 |
| Distinct `ClassName` | 0 | 43 |
| Distinct `YearLevel` | 6 | 4 |
| Distinct `TestType` | 2 | N/A — column absent |
| Distinct `AssessmentType` | 2 | 3 |
| Distinct `TestName` | 2 | 12 |
| Assessment date range | 2026-09-14 – 2026-09-14 | 2026-02-12 – 2026-09-07 |
| Null `ScaleScore` | 0 | 1,834 |
| Null `AssessmentPercentage` | 1,412 | 0 |
| Null effective score (`ScaleScore` or percentage) | 0 | 0 |
| Invalid score rows | 0 | 0 |
| Duplicate assessment signatures | 0 groups / 0 excess rows | 0 groups / 0 excess rows |
| Unmatched rows | 1,412 | 1,834 |
| Distinct unmatched source student identities | 850 | 487 |

`Invalid score` is deliberately defined in a way that respects the observed measures: numeric `ScaleScore < 0`, or `AssessmentPercentage` outside `[0,100]`. PAT scale scores are not capped at 100; the observed range was 56.3–188.5. EssentialAssessment percentages range from 0 to 100. Both source columns are numeric decimal types, so non-numeric parsing failures are not possible in these persisted tables.

## Match distributions

| Dataset | MatchStatus | Rows |
|---|---|---:|
| PAT | `not_matched` | 1,412 |
| EssentialAssessment | `not_matched` | 1,834 |

| Dataset | MatchMethod | Rows |
|---|---|---:|
| PAT | blank / null | 1,412 |
| EssentialAssessment | blank / null | 1,834 |

No persisted assessment row currently contains `CompassPersonId`. Identifier overlap checks found candidate values only: PAT source ID to Silver StudentCode 265 distinct values; PAT username to Silver username 265; PAT username to Gold username 286; EssentialAssessment source ID to Silver/Gold StudentCode 315. Since the stored match state remains `not_matched`, none of those candidates should be silently treated as a Gold student assignment.

## Row-grain tests

### PAT

- 1,412 rows form 1,412 distinct groups by student identity, test date, test type, assessment type, test name, and reporting window.
- Repeated rows within those groups: 0; maximum rows per group: 1.
- Non-null strand rows: 0; non-null focus-area rows: 0.
- Source JSON keys observed on all 1,412 rows include `test`, `date`, `scale score`, `band`, `unique id`, `username`, `year`, and student demographics. No question, skill, strand, focus-area, or attempt-ID key was present.

**Interpretation:** Overall PAT result/attempt grain is supported. Preserve `SourceKey`, `SourceFileName`, `SourceRowNumber`, `TestDate`, `TestType`, `TestName`, and `ReportingWindow`. The absence of an attempt ID means those attributes are the best available attempt-identifying context, not a guarantee of a globally unique source attempt.

### EssentialAssessment

- 1,777 groups by student identity, assessment date, assessment type, and test name.
- Fifty-six groups have multiple rows; maximum rows per group: 3.
- All 1,777 groups contain strand and focus-area values.
- In all 56 multirow groups, each row has a distinct focus area. No multirow group represents distinct strands.
- Grouping additionally by focus area results in 1,834 signatures, with 0 duplicate groups.
- `SourceDataJson` contains, on all 1,834 rows, `focus area`, `strand`, `assessment percentage`, `assessment achievement level`, `strand average achievement level`, `assessment range`, `assessment inlp`, and `growth`. It has no question, skill, or explicit attempt identifier key.

**Interpretation:** One row is a focus-area result, with strand as a parent classification. An assessment/date may have more than one focus-area row. `AssessmentPercentage` is the available score measure in this load; `ScaleScore` is not populated.

## Gold grain recommendation

Use the following source-specific grains, preserving the raw source grain:

1. `factAssessmentAttempt` (PAT): one student test result/attempt row as delivered by the source file, with instrument/test type, test name, assessment date, reporting window, scale score, band, and source lineage.
2. `factAssessmentFocusArea` (EssentialAssessment): one student + assessment instance + focus-area result row, with the parent strand, assessment percentage, achievement/range/INLP/growth attributes, and source lineage.

Share conformed `dimStudent`, `dimDate`, and a governed assessment/instrument dimension. Consider a `dimAssessmentArea` hierarchy for strand and focus area. Keep the two facts separate until score semantics and source keys are stable; combining them prematurely would create a misleading common score column and grain.

For exact source-row replay, retain `SilverBusinessKey` and the file/row lineage columns. For a stable assessment-instance key, obtain or define an upstream attempt identifier with the source owner. Do not use student + date alone: PAT and EssentialAssessment have multiple tests/types and EssentialAssessment has demonstrated multiple focus areas within an assessment/date group.

## Unresolved grain dependencies

1. Source owners must confirm whether PAT permits multiple attempts on the same test/date and identify the durable attempt identifier.
2. Source owners must confirm whether EssentialAssessment repeats a focus area across attempts/reporting windows; no explicit attempt key is currently mapped.
3. Student identity resolution must be defined and collision-checked; assessment rows currently have no Compass person match.
4. Validate that `AssessmentPercentage` is the intended EssentialAssessment measure and document its semantic scale before publishing metrics.
5. No question/skill grain can be represented from the fields and source JSON keys observed in this load.
