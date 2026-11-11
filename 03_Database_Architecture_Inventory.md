# SchoolDW Database Architecture Inventory

**Captured:** 2026-11-05  
**Database:** `SchoolDW`  
**Server:** local SQL Server connection (`Chamila`)  
**Purpose:** Read-only discovery before any assessment-model changes.

## Executive summary

SchoolDW uses `bronze`, `silver`, and `gold` schemas, with `audit`, `metadata`, and `dbo` supporting ingestion and operations. The live catalog contained 197 user tables, 18 views, 24 procedure modules, and no user-defined functions. Gold already has student, class, campus, date, staff, and parent dimensions plus attendance and Chronicle facts, but no assessment fact or loader.

The assessment tables have unique clustered primary keys on `SilverBusinessKey`, but neither assessment table has a foreign key to `gold.dimStudent`. Assessment ingestion has not resolved any row to `CompassPersonId`: all 3,246 assessment rows are `not_matched`, while Silver currently contains 2,043 current Compass student identifiers. The assessment-to-student mapping and Gold load are therefore unresolved dependencies, not safe assumptions.

## Catalog counts

| Area | Live count |
|---|---:|
| User tables | 197 |
| Views | 18 |
| Procedure modules | 24 |
| User-defined functions | 0 |
| Primary-key constraints | 188 |
| Unique constraints | 25 |
| Foreign keys | 71 |
| Physical user-table indexes | 303 |
| Total `sys.indexes` catalog entries | 485 |

`01_Database_Discovery.sql` enumerates the 303 physical indexes attached to user tables; the wider `sys.indexes` count also includes non-user-table catalog entries.

### Schemas

`audit`, `bronze`, `dbo`, `gold`, `metadata`, and `silver` are the application schemas. System and database-role schemas are present in the SQL Server catalog but are not part of the application table inventory.

| Schema | Tables |
|---|---:|
| `audit` | 5 |
| `bronze` | 33 |
| `dbo` | 3 |
| `gold` | 18 |
| `metadata` | 17 |
| `silver` | 121 |

## Gold model

### Dimensions and core entities

- `gold.dimStudent` — `StudentKey` surrogate key; `CompassPersonId`, `Username`, `StudentCode`, profile attributes, campus, source flags, and load timestamps.
- `gold.DimStudentCore` — separate student-core projection keyed by Compass identity; loaded independently from `dimStudent`.
- `gold.dimClass` and `gold.dim_class` — class models with different naming conventions. `dimClass` carries `ClassKey`, `CompassClassId`, `ClassCode`, `ClassName`, `ClassType`, and `IsCurrent`.
- `gold.dimCampus` — `CampusKey`, `CampusCode`, `CampusName`, current flag, and load metadata.
- `gold.dimDate` and `gold.dim_date` — duplicate naming conventions for date dimensions; the populated `dimDate` includes calendar, weekend, public holiday, and teaching-day attributes.
- `gold.dimStaff`, `gold.dimParent`, and `gold.dimAttendanceStatus`.

### Facts and bridges

- Attendance: `gold.fact_attendance_daily`, `gold.fact_attendance_period`.
- Chronicle: `gold.fact_chronicle_entry`, `gold.factChronicleEntry`, `gold.factChronicleEntryField`.
- Class/Chronicle bridge: `gold.bridgeChronicleEntryStudent`.
- Operational/support tables: `gold.LoadAudit`, `gold.ReconciliationResults`.
- No assessment fact table exists.

### Gold views

`gold.factStudentClassMembership`, `gold.factTeacherClass`, `gold.vw_chronicle_entry_enriched`, `gold.vw_chronicle_entry_fields`, `gold.vw_chronicle_entry_students`, `gold.vw_pipeline_load_summary`, `gold.vw_student_profile_enriched`, `gold.vw_StudentAttendanceSummary`, `gold.vw_StudentDataQualitySummary`, `gold.vw_StudentSourceCoverage`, `gold.vw_tablecolumndetails`, `gold.vwCampus`, and `gold.vwStaffDirectory`.

`gold.factStudentClassMembership` is a view, not a persisted fact table. It joins `silver.StudentClasses` to `gold.dimStudent` on `CompassPersonId` and `gold.dimClass` on class sourced ID. Both dimensions are restricted to current rows.

## Student identities and related Silver structures

### Authoritative Compass identity

`silver.StudentsBasic.compass_person_id` is the canonical Compass person identifier used by the current StudentClasses-to-Gold join. In the live data:

- `silver.StudentsBasic`: 2,043 rows, all current, all non-null `compass_person_id`, and 2,043 distinct usernames and student codes.
- `gold.dimStudent`: 2,564 rows and 2,564 distinct `CompassPersonId` values. It has a unique constraint on `CompassPersonId`.
- Silver's `StudentsBasic` uniqueness is enforced by its ETL row/hash keys, not by a unique constraint on `compass_person_id`; current data is unique, but the ID invariant is not enforced there.
- All 2,043 Silver Basic identities occur in `gold.dimStudent`; 521 Gold identities have no current Silver Basic counterpart.
- `silver.Students` and its normalized child tables carry detailed student and historic/current profile data. `silver.StudentsBasic_ImportIdentifiers` carries Compass import identifiers and has an enforced parent FK to `silver.StudentsBasic`.
- `gold.DimStudentCore` is a separate, independently loaded student projection. It is not interchangeable with `gold.dimStudent` without explicit reconciliation.

`CompassPersonId` should be the durable person-level join key. `Username`, `StudentCode`, and Compass import identifiers are useful candidate crosswalk values, but are not substitutes for the person ID unless the mapping is demonstrated unique and current.

### Student-related tables

The application has the following major student objects:

- Identity and payload roots: `silver.Students`, `silver.StudentsBasic`, `silver.GetStudents`, `silver.Get_Students`, `silver.Student_Identifications`, and `silver.StudentsLearningNeeds`.
- Student substructures: `silver.Students_*`, `silver.Student_*`, `silver.silver_GetStudents_*`, and `silver.StudentsLearningNeeds_*` tables shown in the full inventory below.
- Import identifiers: `silver.Students_ImportIdentifiers`, `silver.StudentsBasic_ImportIdentifiers`, and `silver.StudentsLearningNeeds_ImportIdentifiers`.
- Class allocation/membership: `silver.StudentClasses`, `silver.class_student_membership`.
- Gold: `gold.dimStudent`, `gold.DimStudentCore`, and views `gold.vw_student_profile_enriched`, `gold.vw_StudentDataQualitySummary`, and `gold.vw_StudentSourceCoverage`.

### Assessment identity coverage

Both assessment tables currently have zero distinct Compass person IDs and every row has `MatchStatus = 'not_matched'` and a blank `MatchMethod`. Candidate string comparisons found:

- PAT `StudentSourceId` to Silver `student_code`: 265 distinct values; PAT `Username` to Silver username: 265.
- PAT `Username` to Gold username: 286.
- EssentialAssessment `StudentSourceId` to Silver/Gold `StudentCode`: 315.

These are diagnostic overlaps only. The ETL did not use them to populate `CompassPersonId`, and they do not prove that the original source identifiers have the same semantics. Preserve the source ID and implement a governed, collision-checked identity crosswalk before assigning `StudentKey`.

## Compass classes and membership

Two membership shapes exist:

1. Compass allocation shape: `silver.StudentClasses` has `CompassPersonId`, `ClassSourcedId`, class code/title, subject, year level, and `IsActive`.
2. OneRoster shape: `silver.class` has `class_sourced_id`, title/code/type, `school_sourced_id`, and term JSON; `silver.class_student_membership` has `class_sourced_id` and `student_sourced_id`.

Live counts and joins:

- `silver.class`: 1,388 rows; `gold.dimClass`: 1,388 rows.
- `silver.StudentClasses`: 13,692 rows; all 13,692 `ClassSourcedId` values have a Silver class match.
- `silver.class_student_membership`: 13,740 rows; all 13,740 student sourced IDs match `silver.StudentsBasic.compass_person_id`.
- The existing Gold class-membership view uses the Compass `StudentClasses` shape, not the OneRoster membership table.

`silver.class.school_sourced_id` had no matches to `silver.Campuses.campus_id` (0 of 1,388). A class-school-to-campus mapping is not demonstrated and must not be inferred from class names.

## Campus relationships

`silver.Campuses` has 11 rows and includes the Compass `campus_id` GUID. All 2,043 `silver.StudentsBasic.home_campus` values match a campus GUID after case/whitespace normalization. `gold.dimCampus` also has 11 rows, but its exposed business attributes are `CampusCode` and `CampusName`; the current `gold.vwCampus` joins Gold to Silver by `CampusName` to recover `CampusGuid`.

The name-based bridge is fragile. Persist `campus_id` as a Gold alternate/business key and join by GUID; keep campus code/name as attributes. The class `school_sourced_id` relationship remains unresolved independently of student home campus.

## Academic year, term, and date

`silver.Terms` and `silver.OneRosterTerms` each contain four 2026 terms. `silver.OneRosterTerms` identifies them as active `Term 1` through `Term 4`:

| Term | Start | End |
|---|---|---|
| Term 1 | 2026-01-29 | 2026-04-02 |
| Term 2 | 2026-04-20 | 2026-06-26 |
| Term 3 | 2026-07-13 | 2026-09-18 |
| Term 4 | 2026-10-05 | 2026-12-11 |

`silver.Calendar` and `gold.dimDate` each contain 365 rows. `gold.dimDate` is the existing date dimension; neither it nor `gold.dim_date` exposes a term or academic-year key. Add term/year attribution through a governed calendar/term dimension or date-to-term bridge rather than deriving it from calendar year alone.

## Keys, foreign keys, and indexes

- PAT and EssentialAssessment each have one clustered primary-key index on `SilverBusinessKey` (`char(64)`). Both keys are non-null and unique in the current data. No additional index exists on either assessment table.
- Gold dimensions have surrogate primary keys. `gold.dimStudent` has a unique constraint on `CompassPersonId`; `gold.dimClass` on `CompassClassId`; `gold.dimCampus` on `CampusCode`; and `gold.dimDate` on `Date`.
- The live database has 71 foreign keys overall. Relevant student/campus parent FKs include `silver.StudentsBasic_ImportIdentifiers -> silver.StudentsBasic` and `silver.Campuses_Identifications -> silver.Campuses`.
- No FK ties either assessment source to Gold students; no FK enforces the Silver/Gold student, class, campus, or term relationships used by the reporting views.
- The full key, FK enforcement/trust state, and index definitions are emitted by `01_Database_Discovery.sql`.

## Stored procedures and ETL dependencies

There are 24 procedure modules. The main Gold orchestration is `gold.usp_LoadGold`, which calls the dimension, attendance, Chronicle, bridge, and student-class-membership loaders. Catalog dependencies confirmed:

- `gold.usp_LoadDimStudent` reads `silver.Students` and loads `gold.dimStudent`.
- `gold.usp_LoadDimStudentCore` reads `silver.GetStudents`, `silver.Students`, and `silver.StudentsBasic`.
- `gold.usp_LoadDimClass` reads `silver.class`; `gold.usp_LoadDimCampus` reads `silver.Campuses`.
- `gold.usp_LoadFactStudentClassMembership` is associated with `silver.StudentClasses`.
- No stored module references `silver.PAT` or `silver.EssentialAssessment`; no assessment-specific Gold loader exists.

ETL/control tables include `metadata.control_api_config`, `metadata.control_load_strategy`, `metadata.control_pipeline_config`, `metadata.control_dependency`, Gold load/entity configuration and run tables, audit logs, watermarks, and load logs. Live row counts include `control_api_config` 188, `control_load_strategy` 12, `control_pipeline_config` 1, `etl_batch` 15, and `metadata.control_dependency`, `control_column_config`, `control_data_quality`, Gold load/entity configs/runs, `gold_column_mapping`, `etl_endpoint_run`, `etl_schema_change`, and `etl_watermark` at 0. Assessment source-to-Gold dependencies and their identity policy are therefore not represented in those empty metadata controls.

## Full table inventory

### `audit` (5)

`error_log`, `load_log`, `schema_history`, `silver_column_mapping`, `watermark`

### `bronze` (33)

`api_payload`, `AttendancePeriodLines`, `Campuses`, `ChronicleApiResponseCache`, `ChronicleApiResponseCacheRuns`, `ChronicleEntriesRaw`, `CompassAnalyticsRaw`, `endpoint_table_map`, `EssentialAssessment`, `Get_Students`, `Getchronicleentries`, `GetCustomFields`, `Getcustomfieldsdata`, `GetEvents`, `GetLines`, `GetNotes`, `GetParents`, `GetPeriodLines`, `GetStaff`, `GetStudents`, `ImportWatermarks`, `OneRoster_OneRosterGetTerms`, `PAT`, `Person_GetStudentsBasic`, `raw_api_payload`, `Reference_GetCodeSet`, `Schedule_GetTerms`, `schema_field_history`, `schema_history`, `StaffBasic`, `StudentClasses`, `StudentLearningNeeds`, `TeacherClasses`

### `dbo` (3)

`DW_LoadRunLog`, `DW_LoadTableLog`, `DW_TableLoadConfig`

### `gold` (18)

`bridgeChronicleEntryStudent`, `dim_class`, `dim_date`, `dimAttendanceStatus`, `dimCampus`, `dimClass`, `dimDate`, `dimParent`, `dimStaff`, `dimStudent`, `DimStudentCore`, `fact_attendance_daily`, `fact_attendance_period`, `fact_chronicle_entry`, `factChronicleEntry`, `factChronicleEntryField`, `LoadAudit`, `ReconciliationResults`

### `metadata` (17)

`api_table_mapping`, `control_api_config`, `control_column_config`, `control_data_quality`, `control_dependency`, `control_load_strategy`, `control_pipeline_config`, `etl_batch`, `etl_endpoint_run`, `etl_schema_change`, `etl_watermark`, `gold_column_mapping`, `gold_entity_config`, `gold_entity_run`, `gold_load_config`, `gold_load_run`, `watermark_tracking`

### `silver` (121)

`AnalyticsCycleTypes`, `AnalyticsMeasureOptions`, `AnalyticsMeasures`, `AttendanceLines`, `AttendancePeriodLines`, `Calendar`, `Campuses`, `Campuses_Identifications`, `ChronicleEntries`, `ChronicleEntryFieldOptions`, `ChronicleEntryFields`, `ChronicleEntryStudents`, `class`, `class_student_membership`, `CodeSet`, `CodeSet_Mappings`, `column_type_map`, `CompassStaffBasic`, `endpoint_table_map`, `entity_record`, `EssentialAssessment`, `FieldsData`, `FieldsData_Fields`, `FlagAssignments`, `FlagDefinitions`, `Get_Students`, `GetLines`, `GetNotes`, `GetPeriodLines`, `GetStaff`, `GetStudents`, `OneRosterTerms`, `Parents`, `Parents_AccessRestrictions`, `Parents_Addresses`, `Parents_AdultToStudentRelationships`, `Parents_Identifications`, `Parents_Identifications_Attachments`, `Parents_ImportIdentifiers`, `Parents_Languages`, `Parents_OrganisationMilestones`, `Parents_ParentDetails`, `Parents_ParentDetails_CustomGroups`, `PAT`, `silver_GetStudents_addresses`, `silver_GetStudents_adultToStudentRelationships`, `silver_GetStudents_emergencyContacts`, `silver_GetStudents_identifications`, `silver_GetStudents_immunisations`, `silver_GetStudents_importIdentifiers`, `silver_GetStudents_languages`, `silver_GetStudents_medicalConditions`, `silver_GetStudents_organisationMilestones`, `silver_GetStudents_studentDetails`, `Staff`, `Staff_Addresses`, `Staff_CustomFields`, `Staff_EmergencyContacts`, `Staff_ImportIdentifiers`, `Staff_OrganisationMilestones`, `Staff_SchoolHistory`, `Staff_StaffDetails`, `Staff_StaffDetails_CustomGroups`, `Staff_StaffDetails_OrganisationTitles`, `StaffBasic`, `StaffBasic_ImportIdentifiers`, `StaffBasicImportIdentifier`, `Statuses`, `Student_Addresses`, `Student_EmergencyContacts`, `Student_Identifications`, `Student_MedicalConditions`, `StudentClasses`, `Students`, `Students_AccessRestrictions`, `Students_Addresses`, `Students_AdultToStudentRelationships`, `Students_Doctors`, `Students_EmergencyContacts`, `Students_Identifications`, `Students_Identifications_Attachments`, `Students_Immunisations`, `Students_ImportIdentifiers`, `Students_Languages`, `Students_MedicalAttachments`, `Students_MedicalConditions`, `Students_MedicalConditions_Attachments`, `Students_MedicalConditions_Medications`, `Students_OrganisationMilestones`, `Students_SchoolHistory`, `Students_StudentDetails`, `Students_StudentDetails_CustomGroups`, `StudentsBasic`, `StudentsBasic_ImportIdentifiers`, `StudentsLearningNeeds`, `StudentsLearningNeeds_AccessRestrictions`, `StudentsLearningNeeds_Addresses`, `StudentsLearningNeeds_CustomFields`, `StudentsLearningNeeds_Doctors`, `StudentsLearningNeeds_EmergencyContacts`, `StudentsLearningNeeds_Identifications`, `StudentsLearningNeeds_Identifications_Attachments`, `StudentsLearningNeeds_ImportIdentifiers`, `StudentsLearningNeeds_Languages`, `StudentsLearningNeeds_LearningNeeds`, `StudentsLearningNeeds_MedicalAttachments`, `StudentsLearningNeeds_MedicalConditions`, `StudentsLearningNeeds_MedicalConditions_Attachments`, `StudentsLearningNeeds_MedicalConditions_Medications`, `StudentsLearningNeeds_MedicationConsents`, `StudentsLearningNeeds_OrganisationMilestones`, `StudentsLearningNeeds_Relationships`, `StudentsLearningNeeds_SchoolHistory`, `StudentsLearningNeeds_StudentDetails`, `Subjects`, `Subjects_ActivityCodes`, `TeacherClasses`, `Terms`

## Full view inventory (18)

- `audit.vw_LatestEndpointSchema`
- `bronze.vw_Bronz_dataCHeck`, `bronze.vw_bronzeTableColumns`, `bronze.vw_MappingStatus`
- `dbo.vw_attendancePercentage`
- `gold.factStudentClassMembership`, `gold.factTeacherClass`, `gold.vw_chronicle_entry_enriched`, `gold.vw_chronicle_entry_fields`, `gold.vw_chronicle_entry_students`, `gold.vw_pipeline_load_summary`, `gold.vw_student_profile_enriched`, `gold.vw_StudentAttendanceSummary`, `gold.vw_StudentDataQualitySummary`, `gold.vw_StudentSourceCoverage`, `gold.vw_tablecolumndetails`, `gold.vwCampus`, `gold.vwStaffDirectory`
