USE [SchoolDW];
GO

SET NOCOUNT ON;
GO

/*
Score validation:
  - ScaleScore and AssessmentPercentage are numeric DECIMAL columns.
  - ScaleScore has no universal fixed upper bound across PAT instruments; only
    negative ScaleScore values are flagged.
  - AssessmentPercentage is invalid outside [0, 100].
  - Effective score is present if either measure is present.
*/

WITH AssessmentRows AS (
    SELECT
        CONVERT(nvarchar(32), 'PAT') AS Dataset,
        SilverBusinessKey,
        StudentSourceId,
        CompassPersonId,
        Username,
        CompassUsername,
        ClassName,
        YearLevel,
        TestType,
        AssessmentType,
        TestName,
        COALESCE(TestDate, AssessmentDate) AS AssessmentDate,
        ReportingWindow,
        ScaleScore,
        AssessmentPercentage,
        Strand,
        FocusArea,
        MatchStatus,
        MatchMethod
    FROM silver.PAT
    UNION ALL
    SELECT
        CONVERT(nvarchar(32), 'EssentialAssessment'),
        SilverBusinessKey,
        StudentSourceId,
        CompassPersonId,
        CONVERT(nvarchar(400), NULL) AS Username,
        CompassUsername,
        ClassName,
        YearLevel,
        CONVERT(nvarchar(20), NULL) AS TestType,
        AssessmentType,
        TestName,
        AssessmentDate,
        CONVERT(nvarchar(400), NULL) AS ReportingWindow,
        ScaleScore,
        AssessmentPercentage,
        Strand,
        FocusArea,
        MatchStatus,
        MatchMethod
    FROM silver.EssentialAssessment
),
BusinessKeyGroups AS (
    SELECT Dataset, SilverBusinessKey, COUNT_BIG(*) AS RowsPerKey
    FROM AssessmentRows
    WHERE SilverBusinessKey IS NOT NULL
    GROUP BY Dataset, SilverBusinessKey
),
BusinessKeyDuplicates AS (
    SELECT
        Dataset,
        SUM(CASE WHEN RowsPerKey > 1 THEN 1 ELSE 0 END) AS DuplicateKeyGroups,
        SUM(CASE WHEN RowsPerKey > 1 THEN RowsPerKey - 1 ELSE 0 END) AS DuplicateKeyRows
    FROM BusinessKeyGroups
    GROUP BY Dataset
)
SELECT
    a.Dataset,
    COUNT_BIG(*) AS TotalRows,
    COUNT(DISTINCT a.SilverBusinessKey) AS DistinctSilverBusinessKey,
    COALESCE(d.DuplicateKeyGroups, 0) AS DuplicateSilverBusinessKeyGroups,
    COALESCE(d.DuplicateKeyRows, 0) AS DuplicateSilverBusinessKeyRows,
    SUM(CASE WHEN a.SilverBusinessKey IS NULL THEN 1 ELSE 0 END) AS NullBusinessKeyRows,
    COUNT(DISTINCT a.StudentSourceId) AS DistinctStudentSourceId,
    COUNT(DISTINCT a.CompassPersonId) AS DistinctCompassPersonId,
    CASE WHEN a.Dataset = 'PAT' THEN COUNT(DISTINCT a.Username) END AS DistinctUsername,
    COUNT(DISTINCT a.CompassUsername) AS DistinctCompassUsername,
    COUNT(DISTINCT a.ClassName) AS DistinctClassName,
    COUNT(DISTINCT a.YearLevel) AS DistinctYearLevel,
    CASE WHEN a.Dataset = 'PAT' THEN COUNT(DISTINCT a.TestType) END AS DistinctTestType,
    COUNT(DISTINCT a.AssessmentType) AS DistinctAssessmentType,
    COUNT(DISTINCT a.TestName) AS DistinctTestName,
    MIN(a.AssessmentDate) AS AssessmentDateMin,
    MAX(a.AssessmentDate) AS AssessmentDateMax,
    SUM(CASE WHEN a.ScaleScore IS NULL AND a.AssessmentPercentage IS NULL THEN 1 ELSE 0 END) AS NullEffectiveScoreRows,
    SUM(CASE WHEN a.ScaleScore IS NULL THEN 1 ELSE 0 END) AS NullScaleScoreRows,
    SUM(CASE WHEN a.AssessmentPercentage IS NULL THEN 1 ELSE 0 END) AS NullAssessmentPercentageRows,
    SUM(CASE
        WHEN a.ScaleScore < 0 OR a.AssessmentPercentage < 0 OR a.AssessmentPercentage > 100
        THEN 1 ELSE 0
    END) AS InvalidScoreRows,
    COUNT(DISTINCT CASE
        WHEN LOWER(LTRIM(RTRIM(a.MatchStatus))) IN ('not_matched', 'unmatched')
          OR a.CompassPersonId IS NULL
        THEN COALESCE(
            NULLIF(LTRIM(RTRIM(a.StudentSourceId)), ''),
            NULLIF(LTRIM(RTRIM(a.CompassPersonId)), ''),
            NULLIF(LTRIM(RTRIM(a.Username)), ''),
            NULLIF(LTRIM(RTRIM(a.CompassUsername)), '')
        )
    END) AS UnmatchedStudentIdentities
FROM AssessmentRows AS a
LEFT JOIN BusinessKeyDuplicates AS d ON d.Dataset = a.Dataset
GROUP BY a.Dataset, d.DuplicateKeyGroups, d.DuplicateKeyRows
ORDER BY a.Dataset;

-- Match status distribution
WITH MatchRows AS (
    SELECT CONVERT(nvarchar(32), 'PAT') AS Dataset, MatchStatus, COUNT_BIG(*) AS RowsInStatus
    FROM silver.PAT
    GROUP BY MatchStatus
    UNION ALL
    SELECT CONVERT(nvarchar(32), 'EssentialAssessment'), MatchStatus, COUNT_BIG(*)
    FROM silver.EssentialAssessment
    GROUP BY MatchStatus
)
SELECT Dataset, COALESCE(NULLIF(LTRIM(RTRIM(MatchStatus)), ''), '[NULL/blank]') AS MatchStatus, RowsInStatus
FROM MatchRows
ORDER BY Dataset, MatchStatus;

-- Match method distribution
WITH MatchRows AS (
    SELECT CONVERT(nvarchar(32), 'PAT') AS Dataset, MatchMethod, COUNT_BIG(*) AS RowsInMethod
    FROM silver.PAT
    GROUP BY MatchMethod
    UNION ALL
    SELECT CONVERT(nvarchar(32), 'EssentialAssessment'), MatchMethod, COUNT_BIG(*)
    FROM silver.EssentialAssessment
    GROUP BY MatchMethod
)
SELECT Dataset, COALESCE(NULLIF(LTRIM(RTRIM(MatchMethod)), ''), '[NULL/blank]') AS MatchMethod, RowsInMethod
FROM MatchRows
ORDER BY Dataset, MatchMethod;

-- Duplicate assessment candidates at the observed business grain.
-- Score values are deliberately excluded from this signature so score changes
-- do not hide repeated records for the same student, test, date, and detail.
WITH AssessmentRows AS (
    SELECT
        CONVERT(nvarchar(32), 'PAT') AS Dataset,
        StudentSourceId,
        CompassPersonId,
        Username AS StudentUsername,
        CompassUsername,
        COALESCE(TestDate, AssessmentDate) AS AssessmentDate,
        TestType,
        AssessmentType,
        TestName,
        ReportingWindow,
        Strand,
        FocusArea
    FROM silver.PAT
    UNION ALL
    SELECT
        CONVERT(nvarchar(32), 'EssentialAssessment'),
        StudentSourceId,
        CompassPersonId,
        CONVERT(nvarchar(400), NULL),
        CompassUsername,
        AssessmentDate,
        CONVERT(nvarchar(20), NULL),
        AssessmentType,
        TestName,
        CONVERT(nvarchar(400), NULL),
        Strand,
        FocusArea
    FROM silver.EssentialAssessment
),
SignatureGroups AS (
    SELECT
        Dataset,
        COALESCE(
            NULLIF(LTRIM(RTRIM(CompassPersonId)), ''),
            NULLIF(LTRIM(RTRIM(StudentSourceId)), ''),
            NULLIF(LTRIM(RTRIM(StudentUsername)), ''),
            NULLIF(LTRIM(RTRIM(CompassUsername)), '')
        ) AS StudentIdentity,
        AssessmentDate,
        TestType,
        AssessmentType,
        TestName,
        ReportingWindow,
        Strand,
        FocusArea,
        COUNT_BIG(*) AS RowsPerSignature
    FROM AssessmentRows
    GROUP BY
        Dataset,
        COALESCE(
            NULLIF(LTRIM(RTRIM(CompassPersonId)), ''),
            NULLIF(LTRIM(RTRIM(StudentSourceId)), ''),
            NULLIF(LTRIM(RTRIM(StudentUsername)), ''),
            NULLIF(LTRIM(RTRIM(CompassUsername)), '')
        ),
        AssessmentDate,
        TestType,
        AssessmentType,
        TestName,
        ReportingWindow,
        Strand,
        FocusArea
)
SELECT
    Dataset,
    COUNT_BIG(*) AS DistinctAssessmentSignatures,
    SUM(CASE WHEN RowsPerSignature > 1 THEN RowsPerSignature - 1 ELSE 0 END) AS DuplicateAssessmentRows,
    SUM(CASE WHEN RowsPerSignature > 1 THEN 1 ELSE 0 END) AS DuplicateAssessmentGroups,
    MAX(RowsPerSignature) AS MaximumRowsPerSignature
FROM SignatureGroups
GROUP BY Dataset
ORDER BY Dataset;

-- Grain evidence: row multiplicity at student + assessment/date + instrument.
WITH AssessmentRows AS (
    SELECT
        CONVERT(nvarchar(32), 'PAT') AS Dataset,
        StudentSourceId,
        CompassPersonId,
        Username AS StudentUsername,
        CompassUsername,
        COALESCE(TestDate, AssessmentDate) AS AssessmentDate,
        TestType,
        AssessmentType,
        TestName,
        ReportingWindow,
        Strand,
        FocusArea
    FROM silver.PAT
    UNION ALL
    SELECT
        CONVERT(nvarchar(32), 'EssentialAssessment'),
        StudentSourceId,
        CompassPersonId,
        CONVERT(nvarchar(400), NULL),
        CompassUsername,
        AssessmentDate,
        CONVERT(nvarchar(20), NULL),
        AssessmentType,
        TestName,
        CONVERT(nvarchar(400), NULL),
        Strand,
        FocusArea
    FROM silver.EssentialAssessment
),
AssessmentGroups AS (
    SELECT
        Dataset,
        COALESCE(
            NULLIF(LTRIM(RTRIM(CompassPersonId)), ''),
            NULLIF(LTRIM(RTRIM(StudentSourceId)), ''),
            NULLIF(LTRIM(RTRIM(StudentUsername)), ''),
            NULLIF(LTRIM(RTRIM(CompassUsername)), '')
        ) AS StudentIdentity,
        AssessmentDate,
        TestType,
        AssessmentType,
        TestName,
        ReportingWindow,
        COUNT_BIG(*) AS RowsPerGroup,
        COUNT(DISTINCT Strand) AS DistinctStrands,
        COUNT(DISTINCT FocusArea) AS DistinctFocusAreas
    FROM AssessmentRows
    GROUP BY
        Dataset,
        COALESCE(
            NULLIF(LTRIM(RTRIM(CompassPersonId)), ''),
            NULLIF(LTRIM(RTRIM(StudentSourceId)), ''),
            NULLIF(LTRIM(RTRIM(StudentUsername)), ''),
            NULLIF(LTRIM(RTRIM(CompassUsername)), '')
        ),
        AssessmentDate,
        TestType,
        AssessmentType,
        TestName,
        ReportingWindow
)
SELECT
    Dataset,
    COUNT_BIG(*) AS StudentAssessmentDateGroups,
    SUM(RowsPerGroup) AS SourceRows,
    SUM(CASE WHEN RowsPerGroup > 1 THEN 1 ELSE 0 END) AS GroupsWithMultipleRows,
    MAX(RowsPerGroup) AS MaximumRowsPerGroup,
    SUM(CASE WHEN DistinctStrands > 0 THEN 1 ELSE 0 END) AS GroupsWithStrandValues,
    SUM(CASE WHEN DistinctFocusAreas > 0 THEN 1 ELSE 0 END) AS GroupsWithFocusAreaValues
FROM AssessmentGroups
GROUP BY Dataset
ORDER BY Dataset;

-- SourceDataJson key names only (no source values) to expose source-level detail.
WITH SourceJsonKeys AS (
    SELECT
        CONVERT(nvarchar(32), 'PAT') AS Dataset,
        j.[key] AS SourceJsonKey,
        COUNT_BIG(*) AS RowsContainingKey
    FROM silver.PAT AS a
    CROSS APPLY OPENJSON(
        CASE WHEN ISJSON(a.SourceDataJson) = 1 THEN a.SourceDataJson ELSE N'{}' END
    ) AS j
    GROUP BY j.[key]
    UNION ALL
    SELECT
        CONVERT(nvarchar(32), 'EssentialAssessment'),
        j.[key],
        COUNT_BIG(*)
    FROM silver.EssentialAssessment AS a
    CROSS APPLY OPENJSON(
        CASE WHEN ISJSON(a.SourceDataJson) = 1 THEN a.SourceDataJson ELSE N'{}' END
    ) AS j
    GROUP BY j.[key]
)
SELECT TOP (100)
    Dataset,
    SourceJsonKey,
    RowsContainingKey
FROM SourceJsonKeys
ORDER BY Dataset, RowsContainingKey DESC, SourceJsonKey;

-- Candidate identity coverage. These are diagnostics, not approved identity
-- rules; a match must be confirmed as unique before loading a Gold StudentKey.
SELECT
    (SELECT COUNT(DISTINCT a.StudentSourceId)
     FROM silver.PAT AS a
     WHERE EXISTS (
         SELECT 1 FROM silver.StudentsBasic AS s
         WHERE UPPER(LTRIM(RTRIM(a.StudentSourceId))) =
               UPPER(LTRIM(RTRIM(s.student_code)))
     )) AS PATSourceIdMatchingSilverStudentCode,
    (SELECT COUNT(DISTINCT a.Username)
     FROM silver.PAT AS a
     WHERE EXISTS (
         SELECT 1 FROM silver.StudentsBasic AS s
         WHERE UPPER(LTRIM(RTRIM(a.Username))) =
               UPPER(LTRIM(RTRIM(s.username)))
     )) AS PATUsernameMatchingSilverUsername,
    (SELECT COUNT(DISTINCT a.StudentSourceId)
     FROM silver.EssentialAssessment AS a
     WHERE EXISTS (
         SELECT 1 FROM silver.StudentsBasic AS s
         WHERE UPPER(LTRIM(RTRIM(a.StudentSourceId))) =
               UPPER(LTRIM(RTRIM(s.student_code)))
     )) AS EASourceIdMatchingSilverStudentCode;
GO
