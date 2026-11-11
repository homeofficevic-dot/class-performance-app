USE [SchoolDW];
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID(N'gold.dimProgressionSyntheticStudent', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.dimProgressionSyntheticStudent
        (
            SyntheticStudentKey int IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_dimProgressionSyntheticStudent PRIMARY KEY,
            SyntheticStudentCode nvarchar(40) NOT NULL,
            DisplayName nvarchar(100) NOT NULL,
            CurrentYearLevel nvarchar(20) NOT NULL,
            IsSynthetic bit NOT NULL
                CONSTRAINT DF_dimProgressionSyntheticStudent_IsSynthetic DEFAULT (1),
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimProgressionSyntheticStudent_CreatedUTC DEFAULT SYSUTCDATETIME(),
            CONSTRAINT UQ_dimProgressionSyntheticStudent_Code UNIQUE (SyntheticStudentCode),
            CONSTRAINT CK_dimProgressionSyntheticStudent_IsSynthetic CHECK (IsSynthetic = 1)
        );
    END;

    IF OBJECT_ID(N'gold.dimCurriculumVersion', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.dimCurriculumVersion
        (
            CurriculumVersionId int IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_dimCurriculumVersion PRIMARY KEY,
            FrameworkCode nvarchar(40) NOT NULL,
            FrameworkName nvarchar(200) NOT NULL,
            VersionCode nvarchar(40) NOT NULL,
            VersionName nvarchar(200) NOT NULL,
            EffectiveStartDate date NULL,
            EffectiveEndDate date NULL,
            IsSynthetic bit NOT NULL
                CONSTRAINT DF_dimCurriculumVersion_IsSynthetic DEFAULT (0),
            IsActive bit NOT NULL
                CONSTRAINT DF_dimCurriculumVersion_IsActive DEFAULT (1),
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimCurriculumVersion_CreatedUTC DEFAULT SYSUTCDATETIME(),
            UpdatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimCurriculumVersion_UpdatedUTC DEFAULT SYSUTCDATETIME(),
            CONSTRAINT UQ_dimCurriculumVersion_Code UNIQUE (FrameworkCode, VersionCode),
            CONSTRAINT CK_dimCurriculumVersion_Dates CHECK
                (EffectiveEndDate IS NULL OR EffectiveStartDate IS NULL OR EffectiveEndDate >= EffectiveStartDate)
        );
    END;

    IF OBJECT_ID(N'gold.dimCurriculumSubject', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.dimCurriculumSubject
        (
            SubjectId int IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_dimCurriculumSubject PRIMARY KEY,
            CurriculumVersionId int NOT NULL,
            SubjectCode nvarchar(60) NOT NULL,
            SubjectName nvarchar(200) NOT NULL,
            DisplayOrder smallint NOT NULL
                CONSTRAINT DF_dimCurriculumSubject_DisplayOrder DEFAULT (0),
            IsActive bit NOT NULL
                CONSTRAINT DF_dimCurriculumSubject_IsActive DEFAULT (1),
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimCurriculumSubject_CreatedUTC DEFAULT SYSUTCDATETIME(),
            UpdatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimCurriculumSubject_UpdatedUTC DEFAULT SYSUTCDATETIME(),
            CONSTRAINT UQ_dimCurriculumSubject_Code UNIQUE (CurriculumVersionId, SubjectCode),
            CONSTRAINT UQ_dimCurriculumSubject_VersionId UNIQUE (CurriculumVersionId, SubjectId)
        );
    END;

    IF OBJECT_ID(N'gold.dimCurriculumDomain', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.dimCurriculumDomain
        (
            DomainId int IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_dimCurriculumDomain PRIMARY KEY,
            CurriculumVersionId int NOT NULL,
            SubjectId int NOT NULL,
            DomainCode nvarchar(80) NOT NULL,
            DomainName nvarchar(200) NOT NULL,
            DisplayOrder smallint NOT NULL
                CONSTRAINT DF_dimCurriculumDomain_DisplayOrder DEFAULT (0),
            IsActive bit NOT NULL
                CONSTRAINT DF_dimCurriculumDomain_IsActive DEFAULT (1),
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimCurriculumDomain_CreatedUTC DEFAULT SYSUTCDATETIME(),
            UpdatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimCurriculumDomain_UpdatedUTC DEFAULT SYSUTCDATETIME(),
            CONSTRAINT UQ_dimCurriculumDomain_Code UNIQUE (SubjectId, DomainCode),
            CONSTRAINT UQ_dimCurriculumDomain_Parent UNIQUE (CurriculumVersionId, SubjectId, DomainId)
        );
    END;

    IF OBJECT_ID(N'gold.dimCurriculumDimension', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.dimCurriculumDimension
        (
            DimensionId int IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_dimCurriculumDimension PRIMARY KEY,
            CurriculumVersionId int NOT NULL,
            SubjectId int NOT NULL,
            DomainId int NOT NULL,
            DimensionCode nvarchar(80) NOT NULL,
            DimensionName nvarchar(200) NOT NULL,
            DisplayOrder smallint NOT NULL
                CONSTRAINT DF_dimCurriculumDimension_DisplayOrder DEFAULT (0),
            IsActive bit NOT NULL
                CONSTRAINT DF_dimCurriculumDimension_IsActive DEFAULT (1),
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimCurriculumDimension_CreatedUTC DEFAULT SYSUTCDATETIME(),
            UpdatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimCurriculumDimension_UpdatedUTC DEFAULT SYSUTCDATETIME(),
            CONSTRAINT UQ_dimCurriculumDimension_Code UNIQUE (DomainId, DimensionCode),
            CONSTRAINT UQ_dimCurriculumDimension_Parent UNIQUE
                (CurriculumVersionId, SubjectId, DomainId, DimensionId)
        );
    END;

    IF OBJECT_ID(N'gold.dimProgressionPointScale', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.dimProgressionPointScale
        (
            ProgressionScaleId int IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_dimProgressionPointScale PRIMARY KEY,
            CurriculumVersionId int NOT NULL,
            SubjectId int NOT NULL,
            ScaleCode nvarchar(60) NOT NULL,
            ScaleName nvarchar(200) NOT NULL,
            MinimumValue decimal(9,3) NOT NULL,
            MaximumValue decimal(9,3) NOT NULL,
            StepValue decimal(9,3) NOT NULL,
            IsSynthetic bit NOT NULL
                CONSTRAINT DF_dimProgressionPointScale_IsSynthetic DEFAULT (0),
            IsActive bit NOT NULL
                CONSTRAINT DF_dimProgressionPointScale_IsActive DEFAULT (1),
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimProgressionPointScale_CreatedUTC DEFAULT SYSUTCDATETIME(),
            UpdatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimProgressionPointScale_UpdatedUTC DEFAULT SYSUTCDATETIME(),
            CONSTRAINT UQ_dimProgressionPointScale_Code UNIQUE
                (CurriculumVersionId, SubjectId, ScaleCode),
            CONSTRAINT UQ_dimProgressionPointScale_Parent UNIQUE
                (CurriculumVersionId, SubjectId, ProgressionScaleId),
            CONSTRAINT CK_dimProgressionPointScale_Range CHECK
                (MinimumValue <= MaximumValue AND StepValue > 0)
        );
    END;

    IF OBJECT_ID(N'gold.dimProgressionPoint', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.dimProgressionPoint
        (
            ProgressionPointId int IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_dimProgressionPoint PRIMARY KEY,
            CurriculumVersionId int NOT NULL,
            SubjectId int NOT NULL,
            ProgressionScaleId int NOT NULL,
            PointCode nvarchar(60) NOT NULL,
            PointLabel nvarchar(200) NOT NULL,
            NumericValue decimal(9,3) NOT NULL,
            DisplayOrder smallint NOT NULL
                CONSTRAINT DF_dimProgressionPoint_DisplayOrder DEFAULT (0),
            IsSynthetic bit NOT NULL
                CONSTRAINT DF_dimProgressionPoint_IsSynthetic DEFAULT (0),
            IsActive bit NOT NULL
                CONSTRAINT DF_dimProgressionPoint_IsActive DEFAULT (1),
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimProgressionPoint_CreatedUTC DEFAULT SYSUTCDATETIME(),
            UpdatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimProgressionPoint_UpdatedUTC DEFAULT SYSUTCDATETIME(),
            CONSTRAINT UQ_dimProgressionPoint_Code UNIQUE (ProgressionScaleId, PointCode),
            CONSTRAINT UQ_dimProgressionPoint_Value UNIQUE (ProgressionScaleId, NumericValue),
            CONSTRAINT UQ_dimProgressionPoint_Parent UNIQUE
                (CurriculumVersionId, SubjectId, ProgressionScaleId, ProgressionPointId)
        );
    END;

    IF OBJECT_ID(N'gold.dimAcademicYear', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.dimAcademicYear
        (
            AcademicYearId int IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_dimAcademicYear PRIMARY KEY,
            AcademicYearCode nvarchar(20) NOT NULL,
            AcademicYearName nvarchar(100) NOT NULL,
            YearSequence smallint NOT NULL,
            StartDate date NOT NULL,
            EndDate date NOT NULL,
            IsActive bit NOT NULL
                CONSTRAINT DF_dimAcademicYear_IsActive DEFAULT (1),
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimAcademicYear_CreatedUTC DEFAULT SYSUTCDATETIME(),
            UpdatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimAcademicYear_UpdatedUTC DEFAULT SYSUTCDATETIME(),
            CONSTRAINT UQ_dimAcademicYear_Code UNIQUE (AcademicYearCode),
            CONSTRAINT UQ_dimAcademicYear_Sequence UNIQUE (YearSequence),
            CONSTRAINT CK_dimAcademicYear_Dates CHECK (EndDate >= StartDate)
        );
    END;

    IF OBJECT_ID(N'gold.dimReportingPeriod', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.dimReportingPeriod
        (
            ReportingPeriodId int IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_dimReportingPeriod PRIMARY KEY,
            AcademicYearId int NOT NULL,
            PeriodCode nvarchar(40) NOT NULL,
            PeriodName nvarchar(100) NOT NULL,
            PeriodSequence smallint NOT NULL,
            StartDate date NOT NULL,
            EndDate date NOT NULL,
            IsActive bit NOT NULL
                CONSTRAINT DF_dimReportingPeriod_IsActive DEFAULT (1),
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimReportingPeriod_CreatedUTC DEFAULT SYSUTCDATETIME(),
            UpdatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimReportingPeriod_UpdatedUTC DEFAULT SYSUTCDATETIME(),
            CONSTRAINT UQ_dimReportingPeriod_Code UNIQUE (AcademicYearId, PeriodCode),
            CONSTRAINT UQ_dimReportingPeriod_Sequence UNIQUE (AcademicYearId, PeriodSequence),
            CONSTRAINT UQ_dimReportingPeriod_Parent UNIQUE (AcademicYearId, ReportingPeriodId),
            CONSTRAINT CK_dimReportingPeriod_Dates CHECK (EndDate >= StartDate)
        );
    END;

    IF OBJECT_ID(N'gold.dimProgressionAssessmentSource', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.dimProgressionAssessmentSource
        (
            AssessmentSourceId int IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_dimProgressionAssessmentSource PRIMARY KEY,
            SourceCode nvarchar(60) NOT NULL,
            SourceName nvarchar(200) NOT NULL,
            SourceType nvarchar(30) NOT NULL,
            Description nvarchar(1000) NULL,
            IsActive bit NOT NULL
                CONSTRAINT DF_dimProgressionAssessmentSource_IsActive DEFAULT (1),
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimProgressionAssessmentSource_CreatedUTC DEFAULT SYSUTCDATETIME(),
            UpdatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_dimProgressionAssessmentSource_UpdatedUTC DEFAULT SYSUTCDATETIME(),
            CONSTRAINT UQ_dimProgressionAssessmentSource_Code UNIQUE (SourceCode),
            CONSTRAINT CK_dimProgressionAssessmentSource_Type CHECK
                (SourceType IN (N'IMPORT', N'MANUAL', N'SYNTHETIC'))
        );
    END;

    IF OBJECT_ID(N'gold.factStudentProgressionAssessment', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.factStudentProgressionAssessment
        (
            ProgressionAssessmentId bigint IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_factStudentProgressionAssessment PRIMARY KEY,
            AssessmentBusinessKey varchar(128) NOT NULL,
            StudentKey bigint NULL,
            SyntheticStudentKey int NULL,
            CampusKey int NULL,
            CurriculumVersionId int NOT NULL,
            SubjectId int NOT NULL,
            DomainId int NOT NULL,
            DimensionId int NULL,
            ProgressionScaleId int NOT NULL,
            ProgressionPointId int NULL,
            AcademicYearId int NOT NULL,
            ReportingPeriodId int NOT NULL,
            HistoricalYearLevel nvarchar(20) NOT NULL,
            AssessmentDate date NOT NULL,
            AssessmentSourceId int NOT NULL,
            SourceResultKey nvarchar(200) NULL,
            ResultStatus nvarchar(20) NOT NULL,
            IsSynthetic bit NOT NULL
                CONSTRAINT DF_factStudentProgressionAssessment_IsSynthetic DEFAULT (0),
            ResultNotes nvarchar(1000) NULL,
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_factStudentProgressionAssessment_CreatedUTC DEFAULT SYSUTCDATETIME(),
            CreatedBy nvarchar(200) NOT NULL
                CONSTRAINT DF_factStudentProgressionAssessment_CreatedBy DEFAULT ORIGINAL_LOGIN(),
            UpdatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_factStudentProgressionAssessment_UpdatedUTC DEFAULT SYSUTCDATETIME(),
            UpdatedBy nvarchar(200) NOT NULL
                CONSTRAINT DF_factStudentProgressionAssessment_UpdatedBy DEFAULT ORIGINAL_LOGIN(),
            RowVersion rowversion NOT NULL,
            CONSTRAINT UQ_factStudentProgressionAssessment_BusinessKey UNIQUE (AssessmentBusinessKey),
            CONSTRAINT CK_factStudentProgressionAssessment_Student CHECK
                (
                    (IsSynthetic = 0 AND StudentKey IS NOT NULL AND SyntheticStudentKey IS NULL AND CampusKey IS NOT NULL)
                    OR (IsSynthetic = 1 AND StudentKey IS NULL AND SyntheticStudentKey IS NOT NULL)
                ),
            CONSTRAINT CK_factStudentProgressionAssessment_ResultStatus CHECK
                (
                    (ResultStatus = N'RECORDED' AND ProgressionPointId IS NOT NULL)
                    OR (ResultStatus IN (N'MISSING', N'NOT_ASSESSED') AND ProgressionPointId IS NULL)
                )
        );
    END;

    IF OBJECT_ID(N'gold.factExpectedProgressionBenchmark', N'U') IS NULL
    BEGIN
        CREATE TABLE gold.factExpectedProgressionBenchmark
        (
            ExpectedProgressionBenchmarkId bigint IDENTITY(1,1) NOT NULL
                CONSTRAINT PK_factExpectedProgressionBenchmark PRIMARY KEY,
            BenchmarkBusinessKey varchar(128) NOT NULL,
            CurriculumVersionId int NOT NULL,
            SubjectId int NOT NULL,
            DomainId int NOT NULL,
            DimensionId int NULL,
            ProgressionScaleId int NOT NULL,
            ExpectedProgressionPointId int NOT NULL,
            AcademicYearId int NOT NULL,
            ReportingPeriodId int NOT NULL,
            HistoricalYearLevel nvarchar(20) NOT NULL,
            IsSynthetic bit NOT NULL
                CONSTRAINT DF_factExpectedProgressionBenchmark_IsSynthetic DEFAULT (0),
            CreatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_factExpectedProgressionBenchmark_CreatedUTC DEFAULT SYSUTCDATETIME(),
            CreatedBy nvarchar(200) NOT NULL
                CONSTRAINT DF_factExpectedProgressionBenchmark_CreatedBy DEFAULT ORIGINAL_LOGIN(),
            UpdatedUTC datetime2(3) NOT NULL
                CONSTRAINT DF_factExpectedProgressionBenchmark_UpdatedUTC DEFAULT SYSUTCDATETIME(),
            UpdatedBy nvarchar(200) NOT NULL
                CONSTRAINT DF_factExpectedProgressionBenchmark_UpdatedBy DEFAULT ORIGINAL_LOGIN(),
            RowVersion rowversion NOT NULL,
            CONSTRAINT UQ_factExpectedProgressionBenchmark_BusinessKey UNIQUE (BenchmarkBusinessKey)
        );
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
