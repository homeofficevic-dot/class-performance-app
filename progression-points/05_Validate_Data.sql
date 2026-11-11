USE [SchoolDW];
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'gold.factStudentProgressionAssessment', N'U') IS NULL
    THROW 51100, N'Progression tables are not deployed. Run scripts 01 and 02 first.', 1;
IF OBJECT_ID(N'gold.vwStudentProgressionHistory', N'V') IS NULL
    THROW 51101, N'Progression views are not deployed. Run script 03 first.', 1;

DECLARE @ExpectedSyntheticStudents bigint = 3;
DECLARE @ExpectedSyntheticDomains bigint = 3;
DECLARE @ExpectedSyntheticDimensions bigint = 6;
DECLARE @ExpectedSyntheticPeriods bigint = 6;
DECLARE @ExpectedSyntheticAssessments bigint = 162;

IF (SELECT COUNT_BIG(*) FROM gold.dimProgressionSyntheticStudent WHERE IsSynthetic = 1) <> @ExpectedSyntheticStudents
    THROW 51102, N'Synthetic progression student fixture count is unexpected.', 1;

IF (SELECT COUNT_BIG(*) FROM gold.dimCurriculumDomain WHERE DomainCode LIKE N'SYN-%') <> @ExpectedSyntheticDomains
    THROW 51103, N'Synthetic curriculum domain count is unexpected.', 1;

IF (SELECT COUNT_BIG(*) FROM gold.dimCurriculumDimension WHERE DimensionCode LIKE N'SYN-%') <> @ExpectedSyntheticDimensions
    THROW 51104, N'Synthetic curriculum dimension count is unexpected.', 1;

IF (SELECT COUNT_BIG(*) FROM gold.dimReportingPeriod WHERE PeriodCode LIKE N'SYN-%') <> @ExpectedSyntheticPeriods
    THROW 51105, N'Synthetic reporting period count is unexpected.', 1;

IF (SELECT COUNT_BIG(*) FROM gold.factStudentProgressionAssessment WHERE IsSynthetic = 1) <> @ExpectedSyntheticAssessments
    THROW 51106, N'Synthetic assessment row count is unexpected.', 1;

IF EXISTS
(
    SELECT AssessmentBusinessKey
    FROM gold.factStudentProgressionAssessment
    GROUP BY AssessmentBusinessKey
    HAVING COUNT_BIG(*) > 1
)
    THROW 51107, N'Duplicate progression assessment business keys were found.', 1;

IF EXISTS
(
    SELECT AssessmentSourceId, SourceResultKey
    FROM gold.factStudentProgressionAssessment
    WHERE SourceResultKey IS NOT NULL
    GROUP BY AssessmentSourceId, SourceResultKey
    HAVING COUNT_BIG(*) > 1
)
    THROW 51108, N'Duplicate progression source result keys were found.', 1;

IF EXISTS
(
    SELECT 1
    FROM gold.factStudentProgressionAssessment AS assessment
    LEFT JOIN gold.dimProgressionPoint AS point
        ON point.ProgressionPointId = assessment.ProgressionPointId
    LEFT JOIN gold.dimProgressionPointScale AS scale
        ON scale.ProgressionScaleId = assessment.ProgressionScaleId
    WHERE (assessment.ResultStatus = N'RECORDED'
           AND (point.ProgressionPointId IS NULL
                OR point.NumericValue < scale.MinimumValue
                OR point.NumericValue > scale.MaximumValue
                OR (point.NumericValue - scale.MinimumValue) / scale.StepValue
                   <> FLOOR((point.NumericValue - scale.MinimumValue) / scale.StepValue)))
       OR (assessment.ResultStatus IN (N'MISSING', N'NOT_ASSESSED')
           AND assessment.ProgressionPointId IS NOT NULL)
)
    THROW 51109, N'Progression point range, step, or missing-result validation failed.', 1;

IF EXISTS
(
    SELECT 1
    FROM gold.factStudentProgressionAssessment AS assessment
    LEFT JOIN gold.dimStudent AS student ON student.StudentKey = assessment.StudentKey
    LEFT JOIN gold.dimProgressionSyntheticStudent AS syntheticStudent
        ON syntheticStudent.SyntheticStudentKey = assessment.SyntheticStudentKey
    WHERE (assessment.IsSynthetic = 0 AND
           (student.StudentKey IS NULL
            OR assessment.HistoricalYearLevel IS NULL
            OR assessment.CampusKey IS NULL))
       OR (assessment.IsSynthetic = 1 AND
           (syntheticStudent.SyntheticStudentKey IS NULL
            OR syntheticStudent.IsSynthetic <> 1
            OR assessment.HistoricalYearLevel IS NULL))
)
    THROW 51110, N'Historical year-level or student identity validation failed.', 1;

IF EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name LIKE N'FK_%Progression%'
      AND is_not_trusted = 1
)
    THROW 51111, N'One or more progression foreign keys are not trusted.', 1;

IF EXISTS
(
    SELECT 1
    FROM gold.vwStudentProgressionGrowth
    WHERE ResultStatus IN (N'MISSING', N'NOT_ASSESSED')
      AND (ActualProgressionPoint IS NOT NULL OR Growth IS NOT NULL)
)
    THROW 51112, N'Missing assessment results must not be interpreted as zero or produce growth.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM gold.vwStudentProgressionGrowth
    WHERE IsSynthetic = 1 AND ResultLevel = N'DOMAIN' AND Growth > 0
)
    THROW 51113, N'Synthetic positive growth scenario was not produced.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM gold.vwStudentProgressionGrowth
    WHERE IsSynthetic = 1 AND ResultLevel = N'DOMAIN' AND Growth = 0
)
    THROW 51114, N'Synthetic zero growth scenario was not produced.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM gold.vwStudentProgressionGrowth
    WHERE IsSynthetic = 1 AND ResultLevel = N'DOMAIN' AND Growth < 0
)
    THROW 51115, N'Synthetic negative growth scenario was not produced.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM gold.vwActualVsExpectedProgression
    WHERE IsSynthetic = 1
      AND ActualProgressionPoint IS NOT NULL
      AND ExpectedProgressionPoint IS NOT NULL
      AND VarianceFromExpected = ActualProgressionPoint - ExpectedProgressionPoint
)
    THROW 51116, N'Synthetic actual-versus-expected comparison was not produced.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM gold.vwStudentProgressionHistory AS history
    INNER JOIN gold.dimProgressionSyntheticStudent AS student
        ON student.SyntheticStudentKey = history.SyntheticStudentKey
    WHERE history.IsSynthetic = 1
      AND history.HistoricalYearLevel <> student.CurrentYearLevel
)
    THROW 51117, N'Synthetic historical year-level change scenario was not produced.', 1;

IF EXISTS
(
    SELECT 1
    FROM gold.vwLatestDomainProgression
    WHERE LatestRank <> 1
)
    THROW 51118, N'Latest domain progression view returned a non-latest row.', 1;

IF EXISTS
(
    SELECT 1
    FROM gold.vwLatestDimensionProgression
    WHERE LatestRank <> 1
)
    THROW 51119, N'Latest dimension progression view returned a non-latest row.', 1;

SELECT
    N'SYNTHETIC TEST DATA ONLY' AS DataClassification,
    COUNT_BIG(*) AS AssessmentRows,
    SUM(CASE WHEN ResultLevel = N'DOMAIN' THEN CONVERT(bigint, 1) ELSE 0 END) AS DomainRows,
    SUM(CASE WHEN ResultLevel = N'DIMENSION' THEN CONVERT(bigint, 1) ELSE 0 END) AS DimensionRows,
    SUM(CASE WHEN ResultStatus = N'MISSING' THEN CONVERT(bigint, 1) ELSE 0 END) AS MissingResults,
    COUNT(DISTINCT SyntheticStudentKey) AS SyntheticStudents,
    MIN(AssessmentDate) AS FirstAssessmentDate,
    MAX(AssessmentDate) AS LastAssessmentDate
FROM gold.vwStudentProgressionHistory
WHERE IsSynthetic = 1;

SELECT
    ResultLevel,
    GrowthDirection = CASE
        WHEN Growth > 0 THEN N'POSITIVE'
        WHEN Growth = 0 THEN N'ZERO'
        WHEN Growth < 0 THEN N'NEGATIVE'
        ELSE N'NO PREVIOUS RECORDED RESULT'
    END,
    COUNT_BIG(*) AS AssessmentRows
FROM gold.vwStudentProgressionGrowth
WHERE IsSynthetic = 1
GROUP BY ResultLevel,
    CASE
        WHEN Growth > 0 THEN N'POSITIVE'
        WHEN Growth = 0 THEN N'ZERO'
        WHEN Growth < 0 THEN N'NEGATIVE'
        ELSE N'NO PREVIOUS RECORDED RESULT'
    END
ORDER BY ResultLevel, GrowthDirection;

SELECT
    N'All progression deployment validations passed.' AS ValidationResult,
    SYSUTCDATETIME() AS ValidatedUTC;
GO
