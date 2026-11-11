# Gold Assessment Architecture Recommendations

## Decision

Do not add an assessment result as a single undifferentiated fact at student/date grain. The live assessment sources have two different atomic grains and incompatible score measures:

- PAT is an overall test-result/attempt row with a `ScaleScore`.
- EssentialAssessment is a focus-area result row with an `AssessmentPercentage`; all persisted `ScaleScore` values are null.

Preserve these at separate fact grains, conformed through shared dimensions. This prevents focus-area detail from being double counted as whole-test outcomes and avoids treating PAT scaled scores as percentages.

## Proposed Gold objects

### Shared dimensions

1. **`gold.dimStudent`** — reuse `StudentKey` and join through governed `CompassPersonId`. Keep unknown/unresolved and not-applicable members distinct. Do not name-match student rows in Gold.
2. **`gold.dimDate`** — reuse `DateKey` for assessment date, with role-playing dates only if export/test/load date analytics are requested.
3. **`gold.dimAssessmentInstrument`** — stable descriptor for source system, assessment family/type, test type, and test name. Track source-specific labels and effective dates rather than normalizing labels by guesswork.
4. **`gold.dimAssessmentArea`** — optional hierarchy for EssentialAssessment strand/focus area. Keep source labels/keys and parent-child lineage.
5. **`gold.dimCampus`** — extend with Compass `campus_id` as a unique alternate key. Use GUID joins, not campus names.
6. **Academic term attribution** — use a maintained `dimAcademicTerm` or `bridgeDateAcademicTerm` sourced from `silver.OneRosterTerms`/`silver.Terms`; current `dimDate` has no term/year dimension and the two Silver term structures must be reconciled.

### Facts

#### `gold.factAssessmentAttempt`

**Grain:** One PAT assessment result row from the source export (the observed overall attempt/result grain).

Suggested keys/attributes:

- `StudentKey`, `AssessmentDateKey`, `AssessmentInstrumentKey`
- Source `TestType`, `AssessmentType`, `TestName`, `ReportingWindow`
- `ScaleScore`, `Band`, optional source achievement/growth measures
- `SilverBusinessKey`, `SourceSystem`, `SourceFileName`, `SourceRowNumber`
- `MatchStatus`, `MatchMethod`, and load batch lineage
- A source attempt identifier when the source owner confirms and supplies one

Do not store a PAT score in a 0–100 percentage column. Do not collapse multiple source rows into student/date.

#### `gold.factAssessmentFocusArea`

**Grain:** One EssentialAssessment focus-area result for a student assessment instance.

Suggested keys/attributes:

- `StudentKey`, `AssessmentDateKey`, `AssessmentInstrumentKey`, `AssessmentAreaKey`
- `AssessmentPercentage`, achievement level, assessment range, INLP, growth, and strand average achievement level
- `SilverBusinessKey`, source file/row, source system, batch lineage
- Match status/method and source attempt/instance identifier when available

The current profile has all 1,834 `ScaleScore` values null and all `AssessmentPercentage` values present. Model percentage explicitly and retain its original source name.

## Identity resolution and load safeguards

1. Define an approved source-ID-to-Compass crosswalk. `silver.StudentsBasic.compass_person_id` is the durable person ID; `StudentCode`, username, and import identifiers are candidate lookup attributes only.
2. Measure uniqueness and match cardinality before using any candidate. Current match statuses are `not_matched` for every assessment row, despite partial code/username overlaps. Do not overwrite that evidence with implicit name or token matching.
3. Load unresolved assessment records with an explicit unknown/unresolved `StudentKey` and retain the original identifiers plus match diagnostics; never discard rows through an inner join.
4. Add reconciliation assertions for source row count, distinct `SilverBusinessKey`, no duplicate keys, matched/unmatched counts, and measure-null/validity counts.
5. Make the assessment load idempotent on source business key, but separately identify business grain/attempt duplicates. A unique hash key is a row identity mechanism, not proof that the chosen business grain is correct.
6. Add source/dimension FKs after identity and unknown-member handling are stable. There are currently no assessment-to-student FKs or assessment Gold ETL dependencies.

## Source dependencies and blockers

| Dependency | Current evidence | Required before production Gold load |
|---|---|---|
| Student identity mapping | 0 assessment `CompassPersonId` values; all assessment statuses are `not_matched`; partial source-code/username overlaps only | Approved and collision-tested crosswalk; quantify matched, ambiguous, and unmatched records |
| PAT attempt key | No attempt identifier in mapped columns or observed JSON keys | Source-owner confirmation and durable attempt identifier, or explicit documented natural-key policy |
| EssentialAssessment instance key | Multiple focus-area rows within student/date/test groups; no attempt ID observed | Confirm repeated attempts/reporting semantics; define source assessment-instance key |
| Score semantics | PAT has `ScaleScore`; EA has percent (not `ScaleScore`) | Confirm units, permitted ranges, and how null/zero are interpreted |
| Class-to-campus | 0 of 1,388 `silver.class.school_sourced_id` values match current `silver.Campuses.campus_id` | Identify OneRoster school-to-Compass-campus crosswalk or confirm no campus attribution |
| Academic term attribution | 2026 terms exist in both Silver term tables; Gold date dimension has no term key | Reconcile term sources, effective dates, and date boundary conventions |
| ETL orchestration | No stored module references PAT or EssentialAssessment; metadata dependency/config tables are empty for Gold/source mapping | Add explicit pipeline dependency, load config, error/reconciliation logging, and Gold loader |

## Physical design

- Keep the source `SilverBusinessKey` as a unique lineage key in each fact (or retain a source-key bridge if fact merges are expected).
- Add nonclustered indexes only after the load/query pattern is established. Initial candidates: `(StudentKey, AssessmentDateKey)` and `(AssessmentInstrumentKey, AssessmentDateKey)` with measures as included columns; validate against representative reports and execution plans.
- Enforce uniqueness at confirmed natural grain only. For PAT, do not add a unique constraint on student + date alone. For EssentialAssessment, include the assessment instance and focus-area key.
- Use `gold.dimDate` rather than duplicating its date key. Resolve duplicate naming variants (`dim_date`/`dimDate`, `dim_class`/`dimClass`) before adding more parallel dimensions.
- Store load-run, source file, and row-level lineage with the facts so a business-key hash can be traced back to the source export.

## Phased implementation

1. Resolve student IDs and assessment attempt/instance semantics with owners; publish a match-quality baseline.
2. Specify both fact grains and measure definitions, including acceptance ranges and null handling.
3. Implement staging-to-Gold loads with full-row retention, match diagnostics, and reconciliation metrics.
4. Add the date-to-term relationship and GUID-based campus alternate key; resolve the class-school mapping separately.
5. Add uniqueness/FKs and query indexes only after historical duplicates and unknown-member behavior are tested.
6. Add the procedures and metadata rows to `gold.usp_LoadGold` orchestration and validate restart/idempotency behavior.
