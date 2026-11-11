USE [SchoolDW];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_dimCurriculumSubject_Version')
        ALTER TABLE gold.dimCurriculumSubject WITH CHECK
        ADD CONSTRAINT FK_dimCurriculumSubject_Version
            FOREIGN KEY (CurriculumVersionId)
            REFERENCES gold.dimCurriculumVersion (CurriculumVersionId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_dimCurriculumDomain_Subject')
        ALTER TABLE gold.dimCurriculumDomain WITH CHECK
        ADD CONSTRAINT FK_dimCurriculumDomain_Subject
            FOREIGN KEY (CurriculumVersionId, SubjectId)
            REFERENCES gold.dimCurriculumSubject (CurriculumVersionId, SubjectId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_dimCurriculumDimension_Domain')
        ALTER TABLE gold.dimCurriculumDimension WITH CHECK
        ADD CONSTRAINT FK_dimCurriculumDimension_Domain
            FOREIGN KEY (CurriculumVersionId, SubjectId, DomainId)
            REFERENCES gold.dimCurriculumDomain (CurriculumVersionId, SubjectId, DomainId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_dimProgressionPointScale_Subject')
        ALTER TABLE gold.dimProgressionPointScale WITH CHECK
        ADD CONSTRAINT FK_dimProgressionPointScale_Subject
            FOREIGN KEY (CurriculumVersionId, SubjectId)
            REFERENCES gold.dimCurriculumSubject (CurriculumVersionId, SubjectId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_dimProgressionPoint_Scale')
        ALTER TABLE gold.dimProgressionPoint WITH CHECK
        ADD CONSTRAINT FK_dimProgressionPoint_Scale
            FOREIGN KEY (CurriculumVersionId, SubjectId, ProgressionScaleId)
            REFERENCES gold.dimProgressionPointScale (CurriculumVersionId, SubjectId, ProgressionScaleId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_dimReportingPeriod_AcademicYear')
        ALTER TABLE gold.dimReportingPeriod WITH CHECK
        ADD CONSTRAINT FK_dimReportingPeriod_AcademicYear
            FOREIGN KEY (AcademicYearId)
            REFERENCES gold.dimAcademicYear (AcademicYearId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factStudentProgressionAssessment_Student')
        ALTER TABLE gold.factStudentProgressionAssessment WITH CHECK
        ADD CONSTRAINT FK_factStudentProgressionAssessment_Student
            FOREIGN KEY (StudentKey) REFERENCES gold.dimStudent (StudentKey);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factStudentProgressionAssessment_SyntheticStudent')
        ALTER TABLE gold.factStudentProgressionAssessment WITH CHECK
        ADD CONSTRAINT FK_factStudentProgressionAssessment_SyntheticStudent
            FOREIGN KEY (SyntheticStudentKey)
            REFERENCES gold.dimProgressionSyntheticStudent (SyntheticStudentKey);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factStudentProgressionAssessment_Campus')
        ALTER TABLE gold.factStudentProgressionAssessment WITH CHECK
        ADD CONSTRAINT FK_factStudentProgressionAssessment_Campus
            FOREIGN KEY (CampusKey) REFERENCES gold.dimCampus (CampusKey);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factStudentProgressionAssessment_Domain')
        ALTER TABLE gold.factStudentProgressionAssessment WITH CHECK
        ADD CONSTRAINT FK_factStudentProgressionAssessment_Domain
            FOREIGN KEY (CurriculumVersionId, SubjectId, DomainId)
            REFERENCES gold.dimCurriculumDomain (CurriculumVersionId, SubjectId, DomainId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factStudentProgressionAssessment_Dimension')
        ALTER TABLE gold.factStudentProgressionAssessment WITH CHECK
        ADD CONSTRAINT FK_factStudentProgressionAssessment_Dimension
            FOREIGN KEY (CurriculumVersionId, SubjectId, DomainId, DimensionId)
            REFERENCES gold.dimCurriculumDimension (CurriculumVersionId, SubjectId, DomainId, DimensionId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factStudentProgressionAssessment_Scale')
        ALTER TABLE gold.factStudentProgressionAssessment WITH CHECK
        ADD CONSTRAINT FK_factStudentProgressionAssessment_Scale
            FOREIGN KEY (CurriculumVersionId, SubjectId, ProgressionScaleId)
            REFERENCES gold.dimProgressionPointScale (CurriculumVersionId, SubjectId, ProgressionScaleId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factStudentProgressionAssessment_Point')
        ALTER TABLE gold.factStudentProgressionAssessment WITH CHECK
        ADD CONSTRAINT FK_factStudentProgressionAssessment_Point
            FOREIGN KEY (CurriculumVersionId, SubjectId, ProgressionScaleId, ProgressionPointId)
            REFERENCES gold.dimProgressionPoint
                (CurriculumVersionId, SubjectId, ProgressionScaleId, ProgressionPointId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factStudentProgressionAssessment_Period')
        ALTER TABLE gold.factStudentProgressionAssessment WITH CHECK
        ADD CONSTRAINT FK_factStudentProgressionAssessment_Period
            FOREIGN KEY (AcademicYearId, ReportingPeriodId)
            REFERENCES gold.dimReportingPeriod (AcademicYearId, ReportingPeriodId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factStudentProgressionAssessment_Source')
        ALTER TABLE gold.factStudentProgressionAssessment WITH CHECK
        ADD CONSTRAINT FK_factStudentProgressionAssessment_Source
            FOREIGN KEY (AssessmentSourceId)
            REFERENCES gold.dimProgressionAssessmentSource (AssessmentSourceId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factExpectedProgressionBenchmark_Domain')
        ALTER TABLE gold.factExpectedProgressionBenchmark WITH CHECK
        ADD CONSTRAINT FK_factExpectedProgressionBenchmark_Domain
            FOREIGN KEY (CurriculumVersionId, SubjectId, DomainId)
            REFERENCES gold.dimCurriculumDomain (CurriculumVersionId, SubjectId, DomainId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factExpectedProgressionBenchmark_Dimension')
        ALTER TABLE gold.factExpectedProgressionBenchmark WITH CHECK
        ADD CONSTRAINT FK_factExpectedProgressionBenchmark_Dimension
            FOREIGN KEY (CurriculumVersionId, SubjectId, DomainId, DimensionId)
            REFERENCES gold.dimCurriculumDimension (CurriculumVersionId, SubjectId, DomainId, DimensionId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factExpectedProgressionBenchmark_Scale')
        ALTER TABLE gold.factExpectedProgressionBenchmark WITH CHECK
        ADD CONSTRAINT FK_factExpectedProgressionBenchmark_Scale
            FOREIGN KEY (CurriculumVersionId, SubjectId, ProgressionScaleId)
            REFERENCES gold.dimProgressionPointScale (CurriculumVersionId, SubjectId, ProgressionScaleId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factExpectedProgressionBenchmark_Point')
        ALTER TABLE gold.factExpectedProgressionBenchmark WITH CHECK
        ADD CONSTRAINT FK_factExpectedProgressionBenchmark_Point
            FOREIGN KEY (CurriculumVersionId, SubjectId, ProgressionScaleId, ExpectedProgressionPointId)
            REFERENCES gold.dimProgressionPoint
                (CurriculumVersionId, SubjectId, ProgressionScaleId, ProgressionPointId);

    IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_factExpectedProgressionBenchmark_Period')
        ALTER TABLE gold.factExpectedProgressionBenchmark WITH CHECK
        ADD CONSTRAINT FK_factExpectedProgressionBenchmark_Period
            FOREIGN KEY (AcademicYearId, ReportingPeriodId)
            REFERENCES gold.dimReportingPeriod (AcademicYearId, ReportingPeriodId);

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'gold.factStudentProgressionAssessment') AND name = N'UX_factStudentProgressionAssessment_SourceResult')
        CREATE UNIQUE INDEX UX_factStudentProgressionAssessment_SourceResult
            ON gold.factStudentProgressionAssessment (AssessmentSourceId, SourceResultKey)
            WHERE SourceResultKey IS NOT NULL;

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'gold.factStudentProgressionAssessment') AND name = N'IX_factStudentProgressionAssessment_StudentDomainDate')
        CREATE INDEX IX_factStudentProgressionAssessment_StudentDomainDate
            ON gold.factStudentProgressionAssessment
                (StudentKey, CurriculumVersionId, SubjectId, DomainId, AssessmentDate DESC, ProgressionAssessmentId DESC)
            INCLUDE (DimensionId, ProgressionPointId, AcademicYearId, ReportingPeriodId, HistoricalYearLevel, ResultStatus, CampusKey)
            WHERE IsSynthetic = 0;

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'gold.factStudentProgressionAssessment') AND name = N'IX_factStudentProgressionAssessment_StudentDimensionDate')
        CREATE INDEX IX_factStudentProgressionAssessment_StudentDimensionDate
            ON gold.factStudentProgressionAssessment
                (StudentKey, CurriculumVersionId, SubjectId, DomainId, DimensionId, AssessmentDate DESC, ProgressionAssessmentId DESC)
            INCLUDE (ProgressionPointId, AcademicYearId, ReportingPeriodId, HistoricalYearLevel, ResultStatus, CampusKey)
            WHERE IsSynthetic = 0 AND DimensionId IS NOT NULL;

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'gold.factStudentProgressionAssessment') AND name = N'IX_factStudentProgressionAssessment_PeriodCampus')
        CREATE INDEX IX_factStudentProgressionAssessment_PeriodCampus
            ON gold.factStudentProgressionAssessment
                (AcademicYearId, ReportingPeriodId, CampusKey, SubjectId, DomainId)
            INCLUDE (StudentKey, DimensionId, ProgressionPointId, AssessmentDate, HistoricalYearLevel, ResultStatus)
            WHERE IsSynthetic = 0;

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'gold.factStudentProgressionAssessment') AND name = N'IX_factStudentProgressionAssessment_Synthetic')
        CREATE INDEX IX_factStudentProgressionAssessment_Synthetic
            ON gold.factStudentProgressionAssessment
                (SyntheticStudentKey, CurriculumVersionId, SubjectId, DomainId, DimensionId, AssessmentDate DESC)
            INCLUDE (ProgressionPointId, AcademicYearId, ReportingPeriodId, HistoricalYearLevel, ResultStatus)
            WHERE IsSynthetic = 1;

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'gold.factExpectedProgressionBenchmark') AND name = N'UX_factExpectedProgressionBenchmark_Domain')
        CREATE UNIQUE INDEX UX_factExpectedProgressionBenchmark_Domain
            ON gold.factExpectedProgressionBenchmark
                (CurriculumVersionId, SubjectId, DomainId, AcademicYearId, ReportingPeriodId, HistoricalYearLevel)
            WHERE DimensionId IS NULL AND IsSynthetic = 0;

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'gold.factExpectedProgressionBenchmark') AND name = N'UX_factExpectedProgressionBenchmark_Dimension')
        CREATE UNIQUE INDEX UX_factExpectedProgressionBenchmark_Dimension
            ON gold.factExpectedProgressionBenchmark
                (CurriculumVersionId, SubjectId, DomainId, DimensionId, AcademicYearId, ReportingPeriodId, HistoricalYearLevel)
            WHERE DimensionId IS NOT NULL AND IsSynthetic = 0;

    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'gold.factExpectedProgressionBenchmark') AND name = N'IX_factExpectedProgressionBenchmark_Synthetic')
        CREATE INDEX IX_factExpectedProgressionBenchmark_Synthetic
            ON gold.factExpectedProgressionBenchmark
                (CurriculumVersionId, SubjectId, DomainId, DimensionId, AcademicYearId, ReportingPeriodId, HistoricalYearLevel)
            INCLUDE (ExpectedProgressionPointId)
            WHERE IsSynthetic = 1;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
