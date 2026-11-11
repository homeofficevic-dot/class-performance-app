USE [SchoolDW];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT gold.dimProgressionSyntheticStudent
        (SyntheticStudentCode, DisplayName, CurrentYearLevel)
    SELECT seed.SyntheticStudentCode, seed.DisplayName, seed.CurrentYearLevel
    FROM
    (
        VALUES
            (N'SYN-VC-001', N'Synthetic Student 001', N'10'),
            (N'SYN-VC-002', N'Synthetic Student 002', N'8'),
            (N'SYN-VC-003', N'Synthetic Student 003', N'7')
    ) AS seed (SyntheticStudentCode, DisplayName, CurrentYearLevel)
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM gold.dimProgressionSyntheticStudent AS existing WITH (UPDLOCK, HOLDLOCK)
        WHERE existing.SyntheticStudentCode = seed.SyntheticStudentCode
    );

    INSERT gold.dimCurriculumVersion
        (FrameworkCode, FrameworkName, VersionCode, VersionName, IsSynthetic, IsActive)
    SELECT N'SYNTHETIC-DEMO', N'Synthetic Victorian Curriculum demonstration',
           N'SYN-1', N'Synthetic demonstration version 1', 1, 1
    WHERE NOT EXISTS
    (
        SELECT 1 FROM gold.dimCurriculumVersion WITH (UPDLOCK, HOLDLOCK)
        WHERE FrameworkCode = N'SYNTHETIC-DEMO' AND VersionCode = N'SYN-1'
    );

    DECLARE @CurriculumVersionId int =
    (
        SELECT CurriculumVersionId
        FROM gold.dimCurriculumVersion
        WHERE FrameworkCode = N'SYNTHETIC-DEMO' AND VersionCode = N'SYN-1'
    );

    INSERT gold.dimCurriculumSubject
        (CurriculumVersionId, SubjectCode, SubjectName, DisplayOrder, IsActive)
    SELECT @CurriculumVersionId, N'MATHS', N'Mathematics (synthetic example)', 1, 1
    WHERE NOT EXISTS
    (
        SELECT 1 FROM gold.dimCurriculumSubject WITH (UPDLOCK, HOLDLOCK)
        WHERE CurriculumVersionId = @CurriculumVersionId AND SubjectCode = N'MATHS'
    );

    DECLARE @SubjectId int =
    (
        SELECT SubjectId FROM gold.dimCurriculumSubject
        WHERE CurriculumVersionId = @CurriculumVersionId AND SubjectCode = N'MATHS'
    );

    INSERT gold.dimCurriculumDomain
        (CurriculumVersionId, SubjectId, DomainCode, DomainName, DisplayOrder, IsActive)
    SELECT @CurriculumVersionId, @SubjectId, seed.DomainCode, seed.DomainName, seed.DisplayOrder, 1
    FROM
    (
        VALUES
            (N'SYN-NUM-ALG', N'Number and Algebra (synthetic example)', CONVERT(smallint, 1)),
            (N'SYN-MEA-GEO', N'Measurement and Geometry (synthetic example)', CONVERT(smallint, 2)),
            (N'SYN-STA-PRO', N'Statistics and Probability (synthetic example)', CONVERT(smallint, 3))
    ) AS seed (DomainCode, DomainName, DisplayOrder)
    WHERE NOT EXISTS
    (
        SELECT 1 FROM gold.dimCurriculumDomain AS existing WITH (UPDLOCK, HOLDLOCK)
        WHERE existing.SubjectId = @SubjectId AND existing.DomainCode = seed.DomainCode
    );

    INSERT gold.dimCurriculumDimension
        (CurriculumVersionId, SubjectId, DomainId, DimensionCode, DimensionName, DisplayOrder, IsActive)
    SELECT @CurriculumVersionId, @SubjectId, domain.DomainId,
           seed.DimensionCode, seed.DimensionName, seed.DisplayOrder, 1
    FROM gold.dimCurriculumDomain AS domain
    INNER JOIN
    (
        VALUES
            (N'SYN-NUM-ALG', N'SYN-NA-NUMBER', N'Number (synthetic example)', CONVERT(smallint, 1)),
            (N'SYN-NUM-ALG', N'SYN-NA-ALGEBRA', N'Algebra (synthetic example)', CONVERT(smallint, 2)),
            (N'SYN-MEA-GEO', N'SYN-MG-MEASUREMENT', N'Measurement (synthetic example)', CONVERT(smallint, 1)),
            (N'SYN-MEA-GEO', N'SYN-MG-GEOMETRY', N'Geometry (synthetic example)', CONVERT(smallint, 2)),
            (N'SYN-STA-PRO', N'SYN-SP-STATISTICS', N'Statistics (synthetic example)', CONVERT(smallint, 1)),
            (N'SYN-STA-PRO', N'SYN-SP-PROBABILITY', N'Probability (synthetic example)', CONVERT(smallint, 2))
    ) AS seed (DomainCode, DimensionCode, DimensionName, DisplayOrder)
        ON seed.DomainCode = domain.DomainCode
    WHERE domain.SubjectId = @SubjectId
      AND NOT EXISTS
      (
          SELECT 1 FROM gold.dimCurriculumDimension AS existing WITH (UPDLOCK, HOLDLOCK)
          WHERE existing.DomainId = domain.DomainId
            AND existing.DimensionCode = seed.DimensionCode
      );

    INSERT gold.dimProgressionPointScale
        (CurriculumVersionId, SubjectId, ScaleCode, ScaleName, MinimumValue, MaximumValue, StepValue, IsSynthetic, IsActive)
    SELECT @CurriculumVersionId, @SubjectId, N'SYN-NUMERIC-1', N'Synthetic numeric demonstration scale',
           1.000, 10.000, 0.500, 1, 1
    WHERE NOT EXISTS
    (
        SELECT 1 FROM gold.dimProgressionPointScale WITH (UPDLOCK, HOLDLOCK)
        WHERE CurriculumVersionId = @CurriculumVersionId
          AND SubjectId = @SubjectId
          AND ScaleCode = N'SYN-NUMERIC-1'
    );

    DECLARE @ProgressionScaleId int =
    (
        SELECT ProgressionScaleId FROM gold.dimProgressionPointScale
        WHERE CurriculumVersionId = @CurriculumVersionId
          AND SubjectId = @SubjectId
          AND ScaleCode = N'SYN-NUMERIC-1'
    );

    ;WITH PointValues AS
    (
        SELECT CONVERT(decimal(9,3), 1.000) AS NumericValue
        UNION ALL
        SELECT CONVERT(decimal(9,3), NumericValue + 0.500)
        FROM PointValues
        WHERE NumericValue < 10.000
    )
    INSERT gold.dimProgressionPoint
        (CurriculumVersionId, SubjectId, ProgressionScaleId, PointCode, PointLabel,
         NumericValue, DisplayOrder, IsSynthetic, IsActive)
    SELECT @CurriculumVersionId, @SubjectId, @ProgressionScaleId,
           CONCAT(N'SYN-PP-', CONVERT(varchar(20), NumericValue)),
           CONCAT(N'Synthetic point ', CONVERT(varchar(20), NumericValue)),
           NumericValue, CONVERT(smallint, NumericValue * 2), 1, 1
    FROM PointValues
    WHERE NOT EXISTS
    (
        SELECT 1 FROM gold.dimProgressionPoint AS existing WITH (UPDLOCK, HOLDLOCK)
        WHERE existing.ProgressionScaleId = @ProgressionScaleId
          AND existing.NumericValue = PointValues.NumericValue
    )
    OPTION (MAXRECURSION 100);

    INSERT gold.dimAcademicYear
        (AcademicYearCode, AcademicYearName, YearSequence, StartDate, EndDate, IsActive)
    SELECT seed.AcademicYearCode, seed.AcademicYearName, seed.YearSequence, seed.StartDate, seed.EndDate, 1
    FROM
    (
        VALUES
            (N'SYN-2024', N'Synthetic 2024', CONVERT(smallint, 2024), CONVERT(date, '20240101'), CONVERT(date, '20241231')),
            (N'SYN-2025', N'Synthetic 2025', CONVERT(smallint, 2025), CONVERT(date, '20250101'), CONVERT(date, '20251231')),
            (N'SYN-2026', N'Synthetic 2026', CONVERT(smallint, 2026), CONVERT(date, '20260101'), CONVERT(date, '20261231'))
    ) AS seed (AcademicYearCode, AcademicYearName, YearSequence, StartDate, EndDate)
    WHERE NOT EXISTS
    (
        SELECT 1 FROM gold.dimAcademicYear AS existing WITH (UPDLOCK, HOLDLOCK)
        WHERE existing.AcademicYearCode = seed.AcademicYearCode
    );

    INSERT gold.dimReportingPeriod
        (AcademicYearId, PeriodCode, PeriodName, PeriodSequence, StartDate, EndDate, IsActive)
    SELECT academicYear.AcademicYearId, seed.PeriodCode, seed.PeriodName, seed.PeriodSequence,
           seed.StartDate, seed.EndDate, 1
    FROM
    (
        VALUES
            (N'SYN-2024', N'SYN-T1', N'Synthetic Term 1', CONVERT(smallint, 1), CONVERT(date, '20240101'), CONVERT(date, '20240630')),
            (N'SYN-2024', N'SYN-T3', N'Synthetic Term 3', CONVERT(smallint, 2), CONVERT(date, '20240701'), CONVERT(date, '20241231')),
            (N'SYN-2025', N'SYN-T1', N'Synthetic Term 1', CONVERT(smallint, 1), CONVERT(date, '20250101'), CONVERT(date, '20250630')),
            (N'SYN-2025', N'SYN-T3', N'Synthetic Term 3', CONVERT(smallint, 2), CONVERT(date, '20250701'), CONVERT(date, '20251231')),
            (N'SYN-2026', N'SYN-T1', N'Synthetic Term 1', CONVERT(smallint, 1), CONVERT(date, '20260101'), CONVERT(date, '20260630')),
            (N'SYN-2026', N'SYN-T3', N'Synthetic Term 3', CONVERT(smallint, 2), CONVERT(date, '20260701'), CONVERT(date, '20261231'))
    ) AS seed (AcademicYearCode, PeriodCode, PeriodName, PeriodSequence, StartDate, EndDate)
    INNER JOIN gold.dimAcademicYear AS academicYear
        ON academicYear.AcademicYearCode = seed.AcademicYearCode
    WHERE NOT EXISTS
    (
        SELECT 1 FROM gold.dimReportingPeriod AS existing WITH (UPDLOCK, HOLDLOCK)
        WHERE existing.AcademicYearId = academicYear.AcademicYearId
          AND existing.PeriodCode = seed.PeriodCode
    );

    INSERT gold.dimProgressionAssessmentSource
        (SourceCode, SourceName, SourceType, Description, IsActive)
    SELECT N'SYNTHETIC_TEST', N'Synthetic test data', N'SYNTHETIC',
           N'Test-only values; not actual student assessment results or an official curriculum scale.', 1
    WHERE NOT EXISTS
    (
        SELECT 1 FROM gold.dimProgressionAssessmentSource WITH (UPDLOCK, HOLDLOCK)
        WHERE SourceCode = N'SYNTHETIC_TEST'
    );

    DECLARE @AssessmentSourceId int =
    (
        SELECT AssessmentSourceId FROM gold.dimProgressionAssessmentSource
        WHERE SourceCode = N'SYNTHETIC_TEST'
    );

    ;WITH SeedCohort AS
    (
        SELECT student.SyntheticStudentKey, student.SyntheticStudentCode,
               year.AcademicYearId, year.AcademicYearCode, year.YearSequence,
               period.ReportingPeriodId, period.PeriodCode, period.PeriodSequence, period.EndDate,
               domain.DomainId, domain.DomainCode, domain.DisplayOrder AS DomainOrder,
               CONVERT(nvarchar(20),
                   CASE student.SyntheticStudentCode
                       WHEN N'SYN-VC-001' THEN year.YearSequence - 2017
                       WHEN N'SYN-VC-002' THEN year.YearSequence - 2018
                       ELSE year.YearSequence - 2016
                   END) AS HistoricalYearLevel
        FROM gold.dimProgressionSyntheticStudent AS student
        CROSS JOIN gold.dimAcademicYear AS year
        INNER JOIN gold.dimReportingPeriod AS period
            ON period.AcademicYearId = year.AcademicYearId
        CROSS JOIN gold.dimCurriculumDomain AS domain
        WHERE student.SyntheticStudentCode IN (N'SYN-VC-001', N'SYN-VC-002', N'SYN-VC-003')
          AND year.AcademicYearCode IN (N'SYN-2024', N'SYN-2025', N'SYN-2026')
          AND period.PeriodCode IN (N'SYN-T1', N'SYN-T3')
          AND domain.SubjectId = @SubjectId
          AND domain.DomainCode LIKE N'SYN-%'
    ),
    DomainRows AS
    (
        SELECT cohort.*,
               CONVERT(decimal(9,3),
                   CASE cohort.SyntheticStudentCode
                       WHEN N'SYN-VC-001' THEN 1 + sequence.PeriodOffset + cohort.DomainOrder - 1
                       WHEN N'SYN-VC-002' THEN 4
                       ELSE 8 - sequence.PeriodOffset + cohort.DomainOrder - 1
                   END) AS NumericValue,
               CASE WHEN cohort.SyntheticStudentCode = N'SYN-VC-003'
                          AND cohort.AcademicYearCode = N'SYN-2025'
                          AND cohort.PeriodCode = N'SYN-T3'
                          AND cohort.DomainCode = N'SYN-NUM-ALG'
                    THEN N'MISSING' ELSE N'RECORDED' END AS ResultStatus
        FROM SeedCohort AS cohort
        CROSS APPLY
        (
            SELECT CONVERT(int, (cohort.YearSequence - 2024) * 2 + cohort.PeriodSequence - 1) AS PeriodOffset
        ) AS sequence
    )
    INSERT gold.factStudentProgressionAssessment
    (
        AssessmentBusinessKey, StudentKey, SyntheticStudentKey, CampusKey,
        CurriculumVersionId, SubjectId, DomainId, DimensionId,
        ProgressionScaleId, ProgressionPointId, AcademicYearId, ReportingPeriodId,
        HistoricalYearLevel, AssessmentDate, AssessmentSourceId, SourceResultKey,
        ResultStatus, IsSynthetic, ResultNotes
    )
    SELECT
        CONCAT(N'SYN|DOMAIN|', rowData.SyntheticStudentCode, N'|', rowData.AcademicYearCode,
               N'|', rowData.PeriodCode, N'|', rowData.DomainCode),
        NULL, rowData.SyntheticStudentKey, NULL,
        @CurriculumVersionId, @SubjectId, rowData.DomainId, NULL,
        @ProgressionScaleId, point.ProgressionPointId,
        rowData.AcademicYearId, rowData.ReportingPeriodId,
        rowData.HistoricalYearLevel, DATEADD(day, -7, rowData.EndDate),
        @AssessmentSourceId,
        CONCAT(N'SYN|DOMAIN|', rowData.SyntheticStudentCode, N'|', rowData.AcademicYearCode,
               N'|', rowData.PeriodCode, N'|', rowData.DomainCode),
        rowData.ResultStatus, 1,
        N'Synthetic test observation; not an actual student result or official Victorian Curriculum progression point.'
    FROM DomainRows AS rowData
    LEFT JOIN gold.dimProgressionPoint AS point
        ON point.ProgressionScaleId = @ProgressionScaleId
       AND point.NumericValue = rowData.NumericValue
       AND rowData.ResultStatus = N'RECORDED'
    WHERE NOT EXISTS
    (
        SELECT 1 FROM gold.factStudentProgressionAssessment AS existing WITH (UPDLOCK, HOLDLOCK)
        WHERE existing.AssessmentBusinessKey =
            CONCAT(N'SYN|DOMAIN|', rowData.SyntheticStudentCode, N'|', rowData.AcademicYearCode,
                   N'|', rowData.PeriodCode, N'|', rowData.DomainCode)
    );

    ;WITH SeedCohort AS
    (
        SELECT student.SyntheticStudentKey, student.SyntheticStudentCode,
               year.AcademicYearId, year.AcademicYearCode, year.YearSequence,
               period.ReportingPeriodId, period.PeriodCode, period.PeriodSequence, period.EndDate,
               domain.DomainId, domain.DomainCode, domain.DisplayOrder AS DomainOrder,
               dimension.DimensionId, dimension.DimensionCode, dimension.DisplayOrder AS DimensionOrder,
               CONVERT(nvarchar(20),
                   CASE student.SyntheticStudentCode
                       WHEN N'SYN-VC-001' THEN year.YearSequence - 2017
                       WHEN N'SYN-VC-002' THEN year.YearSequence - 2018
                       ELSE year.YearSequence - 2016
                   END) AS HistoricalYearLevel
        FROM gold.dimProgressionSyntheticStudent AS student
        CROSS JOIN gold.dimAcademicYear AS year
        INNER JOIN gold.dimReportingPeriod AS period
            ON period.AcademicYearId = year.AcademicYearId
        INNER JOIN gold.dimCurriculumDomain AS domain
            ON domain.SubjectId = @SubjectId
        INNER JOIN gold.dimCurriculumDimension AS dimension
            ON dimension.DomainId = domain.DomainId
        WHERE student.SyntheticStudentCode IN (N'SYN-VC-001', N'SYN-VC-002', N'SYN-VC-003')
          AND year.AcademicYearCode IN (N'SYN-2024', N'SYN-2025', N'SYN-2026')
          AND period.PeriodCode IN (N'SYN-T1', N'SYN-T3')
          AND domain.DomainCode LIKE N'SYN-%'
          AND dimension.DimensionCode LIKE N'SYN-%'
    ),
    DimensionRows AS
    (
        SELECT cohort.*,
               CONVERT(decimal(9,3),
                   CASE cohort.SyntheticStudentCode
                       WHEN N'SYN-VC-001' THEN 1 + sequence.PeriodOffset + cohort.DomainOrder - 1 + cohort.DimensionOrder - 1
                       WHEN N'SYN-VC-002' THEN 4
                       ELSE 7 - sequence.PeriodOffset + cohort.DomainOrder - 1 + cohort.DimensionOrder - 1
                   END) AS NumericValue,
               CASE WHEN cohort.SyntheticStudentCode = N'SYN-VC-002'
                          AND cohort.AcademicYearCode = N'SYN-2026'
                          AND cohort.PeriodCode = N'SYN-T1'
                          AND cohort.DimensionCode = N'SYN-SP-PROBABILITY'
                    THEN N'MISSING' ELSE N'RECORDED' END AS ResultStatus
        FROM SeedCohort AS cohort
        CROSS APPLY
        (
            SELECT CONVERT(int, (cohort.YearSequence - 2024) * 2 + cohort.PeriodSequence - 1) AS PeriodOffset
        ) AS sequence
    )
    INSERT gold.factStudentProgressionAssessment
    (
        AssessmentBusinessKey, StudentKey, SyntheticStudentKey, CampusKey,
        CurriculumVersionId, SubjectId, DomainId, DimensionId,
        ProgressionScaleId, ProgressionPointId, AcademicYearId, ReportingPeriodId,
        HistoricalYearLevel, AssessmentDate, AssessmentSourceId, SourceResultKey,
        ResultStatus, IsSynthetic, ResultNotes
    )
    SELECT
        CONCAT(N'SYN|DIM|', rowData.SyntheticStudentCode, N'|', rowData.AcademicYearCode,
               N'|', rowData.PeriodCode, N'|', rowData.DimensionCode),
        NULL, rowData.SyntheticStudentKey, NULL,
        @CurriculumVersionId, @SubjectId, rowData.DomainId, rowData.DimensionId,
        @ProgressionScaleId, point.ProgressionPointId,
        rowData.AcademicYearId, rowData.ReportingPeriodId,
        rowData.HistoricalYearLevel, DATEADD(day, -7, rowData.EndDate),
        @AssessmentSourceId,
        CONCAT(N'SYN|DIM|', rowData.SyntheticStudentCode, N'|', rowData.AcademicYearCode,
               N'|', rowData.PeriodCode, N'|', rowData.DimensionCode),
        rowData.ResultStatus, 1,
        N'Synthetic test observation; not an actual student result or official Victorian Curriculum progression point.'
    FROM DimensionRows AS rowData
    LEFT JOIN gold.dimProgressionPoint AS point
        ON point.ProgressionScaleId = @ProgressionScaleId
       AND point.NumericValue = rowData.NumericValue
       AND rowData.ResultStatus = N'RECORDED'
    WHERE NOT EXISTS
    (
        SELECT 1 FROM gold.factStudentProgressionAssessment AS existing WITH (UPDLOCK, HOLDLOCK)
        WHERE existing.AssessmentBusinessKey =
            CONCAT(N'SYN|DIM|', rowData.SyntheticStudentCode, N'|', rowData.AcademicYearCode,
                   N'|', rowData.PeriodCode, N'|', rowData.DimensionCode)
    );

    ;WITH SyntheticLevels AS
    (
        SELECT DISTINCT
            student.SyntheticStudentKey,
            student.SyntheticStudentCode,
            student.CurrentYearLevel,
            year.AcademicYearId,
            year.AcademicYearCode,
            year.YearSequence,
            period.ReportingPeriodId,
            period.PeriodCode,
            period.PeriodSequence,
            domain.DomainId,
            domain.DomainCode,
            dimension.DimensionId,
            dimension.DimensionCode,
            CONVERT(nvarchar(20),
                CASE student.SyntheticStudentCode
                    WHEN N'SYN-VC-001' THEN year.YearSequence - 2017
                    WHEN N'SYN-VC-002' THEN year.YearSequence - 2018
                    ELSE year.YearSequence - 2016
                END) AS HistoricalYearLevel
        FROM gold.dimProgressionSyntheticStudent AS student
        CROSS JOIN gold.dimAcademicYear AS year
        INNER JOIN gold.dimReportingPeriod AS period
            ON period.AcademicYearId = year.AcademicYearId
        INNER JOIN gold.dimCurriculumDomain AS domain
            ON domain.SubjectId = @SubjectId
        LEFT JOIN gold.dimCurriculumDimension AS dimension
            ON dimension.DomainId = domain.DomainId
        WHERE student.SyntheticStudentCode IN (N'SYN-VC-001', N'SYN-VC-002', N'SYN-VC-003')
          AND year.AcademicYearCode IN (N'SYN-2024', N'SYN-2025', N'SYN-2026')
          AND period.PeriodCode IN (N'SYN-T1', N'SYN-T3')
          AND domain.DomainCode LIKE N'SYN-%'
    ),
    Benchmarks AS
    (
        SELECT
            levels.*,
            CONVERT(decimal(9,3),
                1 + ((levels.YearSequence + levels.PeriodSequence
                    + TRY_CONVERT(int, levels.HistoricalYearLevel)
                    + CASE WHEN levels.DimensionId IS NULL THEN 0 ELSE 1 END) % 10)) AS ExpectedValue
        FROM SyntheticLevels AS levels
    )
    INSERT gold.factExpectedProgressionBenchmark
    (
        BenchmarkBusinessKey, CurriculumVersionId, SubjectId, DomainId, DimensionId,
        ProgressionScaleId, ExpectedProgressionPointId, AcademicYearId, ReportingPeriodId,
        HistoricalYearLevel, IsSynthetic
    )
    SELECT
        CONCAT(N'SYN|EXPECTED|', benchmark.DomainCode, N'|',
               COALESCE(benchmark.DimensionCode, N'DOMAIN'), N'|',
               benchmark.AcademicYearCode, N'|', benchmark.PeriodCode, N'|',
               benchmark.HistoricalYearLevel),
        @CurriculumVersionId, @SubjectId, benchmark.DomainId, benchmark.DimensionId,
        @ProgressionScaleId, point.ProgressionPointId,
        benchmark.AcademicYearId, benchmark.ReportingPeriodId,
        benchmark.HistoricalYearLevel, 1
    FROM Benchmarks AS benchmark
    INNER JOIN gold.dimProgressionPoint AS point
        ON point.ProgressionScaleId = @ProgressionScaleId
       AND point.NumericValue = benchmark.ExpectedValue
    WHERE NOT EXISTS
    (
        SELECT 1 FROM gold.factExpectedProgressionBenchmark AS existing WITH (UPDLOCK, HOLDLOCK)
        WHERE existing.BenchmarkBusinessKey =
            CONCAT(N'SYN|EXPECTED|', benchmark.DomainCode, N'|',
                   COALESCE(benchmark.DimensionCode, N'DOMAIN'), N'|',
                   benchmark.AcademicYearCode, N'|', benchmark.PeriodCode, N'|',
                   benchmark.HistoricalYearLevel)
    );

    COMMIT TRANSACTION;

    SELECT
        (SELECT COUNT_BIG(*) FROM gold.factStudentProgressionAssessment WHERE IsSynthetic = 1) AS SyntheticAssessmentRows,
        (SELECT COUNT_BIG(*) FROM gold.factExpectedProgressionBenchmark WHERE IsSynthetic = 1) AS SyntheticBenchmarkRows,
        (SELECT COUNT_BIG(*) FROM gold.dimProgressionSyntheticStudent WHERE IsSynthetic = 1) AS SyntheticStudents,
        (SELECT COUNT_BIG(*) FROM gold.dimCurriculumDomain WHERE DomainCode LIKE N'SYN-%') AS SyntheticDomains,
        (SELECT COUNT_BIG(*) FROM gold.dimCurriculumDimension WHERE DimensionCode LIKE N'SYN-%') AS SyntheticDimensions;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
