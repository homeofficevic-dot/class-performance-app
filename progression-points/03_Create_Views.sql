USE [SchoolDW];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER VIEW gold.vwStudentProgressionHistory
AS
SELECT
    assessment.ProgressionAssessmentId,
    assessment.AssessmentBusinessKey,
    CASE WHEN assessment.DimensionId IS NULL THEN N'DOMAIN' ELSE N'DIMENSION' END AS ResultLevel,
    assessment.StudentKey,
    assessment.SyntheticStudentKey,
    CASE WHEN assessment.IsSynthetic = 1
         THEN syntheticStudent.SyntheticStudentCode
         ELSE CONVERT(nvarchar(30), assessment.StudentKey)
    END AS StudentIdentifier,
    CASE WHEN assessment.IsSynthetic = 1
         THEN syntheticStudent.DisplayName
         ELSE CONCAT
              (
                  COALESCE(NULLIF(student.PreferredFirstName, N''), student.FirstName, N''),
                  CASE WHEN COALESCE(NULLIF(student.PreferredFirstName, N''), student.FirstName) IS NULL
                         OR COALESCE(NULLIF(student.PreferredLastName, N''), student.LastName) IS NULL
                       THEN N'' ELSE N' ' END,
                  COALESCE(NULLIF(student.PreferredLastName, N''), student.LastName, N'')
              )
    END AS StudentName,
    CASE WHEN assessment.IsSynthetic = 1
         THEN syntheticStudent.CurrentYearLevel
         ELSE CONVERT(nvarchar(20), student.YearLevel)
    END AS CurrentYearLevel,
    assessment.CampusKey,
    campus.CampusName,
    assessment.CurriculumVersionId,
    curriculumVersion.FrameworkCode,
    curriculumVersion.FrameworkName,
    curriculumVersion.VersionCode,
    curriculumVersion.VersionName AS CurriculumVersionName,
    assessment.SubjectId,
    subject.SubjectCode,
    subject.SubjectName,
    assessment.DomainId,
    domain.DomainCode,
    domain.DomainName,
    assessment.DimensionId,
    dimension.DimensionCode,
    dimension.DimensionName,
    assessment.ProgressionScaleId,
    progressionScale.ScaleCode,
    progressionScale.ScaleName,
    progressionScale.MinimumValue,
    progressionScale.MaximumValue,
    progressionScale.StepValue,
    assessment.ProgressionPointId,
    progressionPoint.PointCode,
    progressionPoint.PointLabel,
    progressionPoint.NumericValue AS ActualProgressionPoint,
    assessment.AcademicYearId,
    academicYear.AcademicYearCode,
    academicYear.AcademicYearName,
    academicYear.YearSequence,
    assessment.ReportingPeriodId,
    reportingPeriod.PeriodCode AS ReportingPeriodCode,
    reportingPeriod.PeriodName AS ReportingPeriodName,
    reportingPeriod.PeriodSequence,
    reportingPeriod.StartDate AS ReportingPeriodStartDate,
    reportingPeriod.EndDate AS ReportingPeriodEndDate,
    assessment.HistoricalYearLevel,
    assessment.AssessmentDate,
    assessment.AssessmentSourceId,
    assessmentSource.SourceCode AS AssessmentSourceCode,
    assessmentSource.SourceName AS AssessmentSourceName,
    assessment.SourceResultKey,
    assessment.ResultStatus,
    assessment.IsSynthetic,
    assessment.ResultNotes,
    assessment.CreatedUTC,
    assessment.UpdatedUTC
FROM gold.factStudentProgressionAssessment AS assessment
INNER JOIN gold.dimCurriculumVersion AS curriculumVersion
    ON curriculumVersion.CurriculumVersionId = assessment.CurriculumVersionId
INNER JOIN gold.dimCurriculumSubject AS subject
    ON subject.CurriculumVersionId = assessment.CurriculumVersionId
   AND subject.SubjectId = assessment.SubjectId
INNER JOIN gold.dimCurriculumDomain AS domain
    ON domain.CurriculumVersionId = assessment.CurriculumVersionId
   AND domain.SubjectId = assessment.SubjectId
   AND domain.DomainId = assessment.DomainId
LEFT JOIN gold.dimCurriculumDimension AS dimension
    ON dimension.CurriculumVersionId = assessment.CurriculumVersionId
   AND dimension.SubjectId = assessment.SubjectId
   AND dimension.DomainId = assessment.DomainId
   AND dimension.DimensionId = assessment.DimensionId
INNER JOIN gold.dimProgressionPointScale AS progressionScale
    ON progressionScale.ProgressionScaleId = assessment.ProgressionScaleId
INNER JOIN gold.dimAcademicYear AS academicYear
    ON academicYear.AcademicYearId = assessment.AcademicYearId
INNER JOIN gold.dimReportingPeriod AS reportingPeriod
    ON reportingPeriod.AcademicYearId = assessment.AcademicYearId
   AND reportingPeriod.ReportingPeriodId = assessment.ReportingPeriodId
INNER JOIN gold.dimProgressionAssessmentSource AS assessmentSource
    ON assessmentSource.AssessmentSourceId = assessment.AssessmentSourceId
LEFT JOIN gold.dimProgressionPoint AS progressionPoint
    ON progressionPoint.ProgressionPointId = assessment.ProgressionPointId
LEFT JOIN gold.dimStudent AS student
    ON student.StudentKey = assessment.StudentKey
LEFT JOIN gold.dimProgressionSyntheticStudent AS syntheticStudent
    ON syntheticStudent.SyntheticStudentKey = assessment.SyntheticStudentKey
LEFT JOIN gold.dimCampus AS campus
    ON campus.CampusKey = assessment.CampusKey;
GO

CREATE OR ALTER VIEW gold.vwDomainProgressionResults
AS
SELECT *
FROM gold.vwStudentProgressionHistory
WHERE ResultLevel = N'DOMAIN';
GO

CREATE OR ALTER VIEW gold.vwDimensionProgressionResults
AS
SELECT *
FROM gold.vwStudentProgressionHistory
WHERE ResultLevel = N'DIMENSION';
GO

CREATE OR ALTER VIEW gold.vwStudentProgressionGrowth
AS
WITH RecordedResults AS
(
    SELECT
        history.ProgressionAssessmentId,
        history.ActualProgressionPoint,
        LAG(history.ActualProgressionPoint) OVER
        (
            PARTITION BY
                history.StudentKey,
                history.SyntheticStudentKey,
                history.CurriculumVersionId,
                history.SubjectId,
                history.DomainId,
                history.DimensionId
            ORDER BY
                history.YearSequence,
                history.PeriodSequence,
                history.AssessmentDate,
                history.ProgressionAssessmentId
        ) AS PreviousProgressionPoint
    FROM gold.vwStudentProgressionHistory AS history
    WHERE history.ResultStatus = N'RECORDED'
      AND history.ActualProgressionPoint IS NOT NULL
)
SELECT
    history.*,
    recorded.PreviousProgressionPoint,
    CASE
        WHEN history.ResultStatus = N'RECORDED'
         AND history.ActualProgressionPoint IS NOT NULL
         AND recorded.PreviousProgressionPoint IS NOT NULL
        THEN history.ActualProgressionPoint - recorded.PreviousProgressionPoint
    END AS Growth
FROM gold.vwStudentProgressionHistory AS history
LEFT JOIN RecordedResults AS recorded
    ON recorded.ProgressionAssessmentId = history.ProgressionAssessmentId;
GO

CREATE OR ALTER VIEW gold.vwActualVsExpectedProgression
AS
SELECT
    history.*,
    benchmark.ExpectedProgressionBenchmarkId,
    expectedPoint.PointCode AS ExpectedPointCode,
    expectedPoint.PointLabel AS ExpectedPointLabel,
    expectedPoint.NumericValue AS ExpectedProgressionPoint,
    CASE
        WHEN history.ActualProgressionPoint IS NOT NULL
         AND expectedPoint.NumericValue IS NOT NULL
        THEN history.ActualProgressionPoint - expectedPoint.NumericValue
    END AS VarianceFromExpected
FROM gold.vwStudentProgressionGrowth AS history
LEFT JOIN gold.factExpectedProgressionBenchmark AS benchmark
    ON benchmark.CurriculumVersionId = history.CurriculumVersionId
   AND benchmark.SubjectId = history.SubjectId
   AND benchmark.DomainId = history.DomainId
   AND
       (
           benchmark.DimensionId = history.DimensionId
           OR (benchmark.DimensionId IS NULL AND history.DimensionId IS NULL)
       )
   AND benchmark.AcademicYearId = history.AcademicYearId
   AND benchmark.ReportingPeriodId = history.ReportingPeriodId
   AND benchmark.HistoricalYearLevel = history.HistoricalYearLevel
   AND benchmark.IsSynthetic = history.IsSynthetic
LEFT JOIN gold.dimProgressionPoint AS expectedPoint
    ON expectedPoint.ProgressionPointId = benchmark.ExpectedProgressionPointId;
GO

CREATE OR ALTER VIEW gold.vwHistoricalStudentProgression
AS
SELECT *
FROM gold.vwActualVsExpectedProgression;
GO

CREATE OR ALTER VIEW gold.vwLatestDomainProgression
AS
WITH Ranked AS
(
    SELECT
        result.*,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                result.StudentKey,
                result.SyntheticStudentKey,
                result.CurriculumVersionId,
                result.SubjectId,
                result.DomainId
            ORDER BY
                result.YearSequence DESC,
                result.PeriodSequence DESC,
                result.AssessmentDate DESC,
                result.ProgressionAssessmentId DESC
        ) AS LatestRank
    FROM gold.vwActualVsExpectedProgression AS result
    WHERE result.ResultLevel = N'DOMAIN'
)
SELECT *
FROM Ranked
WHERE LatestRank = 1;
GO

CREATE OR ALTER VIEW gold.vwLatestDimensionProgression
AS
WITH Ranked AS
(
    SELECT
        result.*,
        ROW_NUMBER() OVER
        (
            PARTITION BY
                result.StudentKey,
                result.SyntheticStudentKey,
                result.CurriculumVersionId,
                result.SubjectId,
                result.DomainId,
                result.DimensionId
            ORDER BY
                result.YearSequence DESC,
                result.PeriodSequence DESC,
                result.AssessmentDate DESC,
                result.ProgressionAssessmentId DESC
        ) AS LatestRank
    FROM gold.vwActualVsExpectedProgression AS result
    WHERE result.ResultLevel = N'DIMENSION'
)
SELECT *
FROM Ranked
WHERE LatestRank = 1;
GO
