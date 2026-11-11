/*
  Chronicle insights (student + class level): Wellbeing, NCCD, Outreach.
  Grain: one row per (Chronicle entry, student). Source: gold.fact_chronicle_entry
  (already student-resolved) enriched with classification and selected field values.
  Safe to re-run.
*/
USE SchoolDW;
GO

CREATE OR ALTER VIEW gold.vwChronicleInsightEntry
AS
WITH entry AS (
    SELECT
        e.ChronicleEntryKey, e.EntryId, e.SilverKey, e.StudentKey, e.StaffKey,
        Category = LTRIM(RTRIM(e.Category)),
        Template = LTRIM(RTRIM(e.Template)),
        e.Rating, e.Points, e.IsResolved, e.Archived,
        e.PrimaryFieldName, e.PrimaryFieldData,
        -- Future-dated incidents are data-entry errors; fall back to the recorded date.
        EventDate = CASE WHEN e.DateOfIncident IS NULL OR e.DateOfIncident > SYSDATETIME()
                         THEN e.DateRecorded ELSE e.DateOfIncident END,
        e.DateRecorded,
        rn = ROW_NUMBER() OVER (PARTITION BY e.EntryId, e.StudentKey ORDER BY e.ChronicleEntryKey)
    FROM gold.fact_chronicle_entry AS e
    WHERE e.StudentKey IS NOT NULL AND e.StudentKey > 0
),
classified AS (
    SELECT e.*,
        InsightDomain = CASE
            WHEN e.Category LIKE 'NCCD%' OR e.Template LIKE '%NCCD%'                    THEN 'NCCD'
            WHEN e.Category LIKE '%Outreach%' OR e.Template LIKE '%Outreach%'          THEN 'OUTREACH'
            WHEN e.Category LIKE 'Wellbeing%' OR e.Template LIKE '%Wellbeing%'
              OR e.Template LIKE 'Disclosure%'                                         THEN 'WELLBEING'
            WHEN e.Category = 'Inclusive Education'                                    THEN 'INCLUSION'
            WHEN e.Category = 'Attitude/Behaviour'                                     THEN 'BEHAVIOUR'
            WHEN e.Category LIKE 'Attendance%'                                         THEN 'ATTENDANCE'
            ELSE 'OTHER' END
    FROM entry AS e
    WHERE e.rn = 1
)
SELECT
    c.ChronicleEntryKey, c.EntryId, c.StudentKey, c.StaffKey,
    c.InsightDomain, c.Category, c.Template, c.Rating, c.Points,
    c.IsResolved, c.Archived, c.EventDate, c.DateRecorded,
    c.PrimaryFieldName, c.PrimaryFieldData,
    IsHighRisk = CAST(CASE WHEN c.Rating = 'Red' THEN 1 ELSE 0 END AS bit),
    IsDisclosure = CAST(CASE WHEN c.Template LIKE 'Disclosure%' THEN 1 ELSE 0 END AS bit),
    OutreachEngagement = CASE WHEN c.InsightDomain = 'OUTREACH' THEN
        (SELECT TOP 1 NULLIF(LTRIM(RTRIM(LEFT(f.FieldValue, CHARINDEX('(', f.FieldValue + '(') - 1))), '')
         FROM gold.factChronicleEntryField AS f
         WHERE f.SilverKey = c.SilverKey AND f.FieldKey = 'Engagement of young person') END,
    OutreachLocation = CASE WHEN c.InsightDomain = 'OUTREACH' THEN
        (SELECT TOP 1 NULLIF(LTRIM(RTRIM(f.FieldValue)), '')
         FROM gold.factChronicleEntryField AS f
         WHERE f.SilverKey = c.SilverKey AND f.FieldKey = 'Location of Meeting') END,
    IsAssertiveOutreach = CAST(CASE WHEN c.InsightDomain = 'OUTREACH' AND EXISTS (
        SELECT 1 FROM gold.factChronicleEntryField AS f
        WHERE f.SilverKey = c.SilverKey AND f.FieldKey = 'Assertive Outreach'
          AND LTRIM(RTRIM(f.FieldValue)) = 'true') THEN 1 ELSE 0 END AS bit),
    NccdCategory = CASE WHEN c.InsightDomain = 'NCCD' THEN
        -- "Current" fields hold a JSON option list; keep only the ticked options.
        COALESCE(
            (SELECT TOP 1 CASE WHEN ISJSON(f.FieldValue) = 1 THEN
                (SELECT STRING_AGG(j.valueOption, ', ')
                 FROM OPENJSON(f.FieldValue) WITH (valueOption nvarchar(100), isChecked bit) AS j
                 WHERE j.isChecked = 1)
                ELSE NULLIF(LTRIM(RTRIM(f.FieldValue)), '') END
             FROM gold.factChronicleEntryField AS f
             WHERE f.SilverKey = c.SilverKey AND f.FieldKey = 'NCCD Category (Current)'),
            (SELECT TOP 1 NULLIF(LTRIM(RTRIM(a.FieldValue)), '')
             FROM gold.factChronicleEntryField AS q
             INNER JOIN gold.factChronicleEntryField AS a
                ON a.SilverKey = q.SilverKey AND a.FieldOrdinal = q.FieldOrdinal + 1 AND a.FieldKey = 'answer'
             WHERE q.SilverKey = c.SilverKey AND q.FieldKey = 'question'
               AND LTRIM(RTRIM(q.FieldValue)) = 'Disability category?')) END,
    NccdLevelOfAdjustment = CASE WHEN c.InsightDomain = 'NCCD' THEN
        (SELECT TOP 1 CASE WHEN ISJSON(f.FieldValue) = 1 THEN
            (SELECT STRING_AGG(j.valueOption, ', ')
             FROM OPENJSON(f.FieldValue) WITH (valueOption nvarchar(100), isChecked bit) AS j
             WHERE j.isChecked = 1)
            ELSE NULLIF(LTRIM(RTRIM(f.FieldValue)), '') END
         FROM gold.factChronicleEntryField AS f
         WHERE f.SilverKey = c.SilverKey AND f.FieldKey = 'NCCD Level of Adjustment (Current)') END
FROM classified AS c;
GO

-- Class/student lookups filter by StudentKey and date.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_fact_chronicle_entry_Student_Category'
               AND object_id = OBJECT_ID('gold.fact_chronicle_entry'))
    CREATE NONCLUSTERED INDEX IX_fact_chronicle_entry_Student_Category
        ON gold.fact_chronicle_entry (StudentKey, DateOfIncident)
        INCLUDE (EntryId, SilverKey, StaffKey, Category, Template, Rating, Points, IsResolved, Archived, DateRecorded);
GO
