USE SchoolDW;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH(N'gold.dimCampus', N'CompassCampusId') IS NULL
    ALTER TABLE gold.dimCampus ADD CompassCampusId uniqueidentifier NULL;
GO

;WITH SilverCampusByCode AS
(
    SELECT
        code,
        MIN(campus_id) AS CompassCampusId
    FROM silver.Campuses
    WHERE is_current = 1
      AND NULLIF(LTRIM(RTRIM(code)), N'') IS NOT NULL
    GROUP BY code
    HAVING COUNT(DISTINCT campus_id) = 1
),
GoldCampusByCode AS
(
    SELECT
        CampusCode,
        MIN(CampusKey) AS CampusKey
    FROM gold.dimCampus
    WHERE IsCurrent = 1
      AND NULLIF(LTRIM(RTRIM(CampusCode)), N'') IS NOT NULL
    GROUP BY CampusCode
    HAVING COUNT_BIG(*) = 1
)
UPDATE d
SET CompassCampusId = s.CompassCampusId
FROM gold.dimCampus AS d
INNER JOIN GoldCampusByCode AS g
    ON g.CampusKey = d.CampusKey
INNER JOIN SilverCampusByCode AS s
    ON s.code = d.CampusCode
WHERE d.CompassCampusId IS NULL
  AND NOT EXISTS
      (
          SELECT 1
          FROM gold.dimCampus AS existing
          WHERE existing.CompassCampusId = s.CompassCampusId
            AND existing.CampusKey <> d.CampusKey
      );
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'gold.dimCampus')
      AND name = N'UX_dimCampus_CompassCampusId'
)
BEGIN
    CREATE UNIQUE INDEX UX_dimCampus_CompassCampusId
        ON gold.dimCampus (CompassCampusId)
        WHERE CompassCampusId IS NOT NULL;
END;
GO

IF OBJECT_ID(N'gold.dimPATAssessment', N'U') IS NULL
BEGIN
    CREATE TABLE gold.dimPATAssessment
    (
        PATAssessmentKey int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dimPATAssessment PRIMARY KEY,
        AssessmentBusinessKey binary(32) NOT NULL,
        AssessmentType nvarchar(200) NULL,
        TestType nvarchar(10) NOT NULL,
        TestName nvarchar(300) NOT NULL,
        ReportingWindow int NULL,
        GoldCreatedUTC datetime2(3) NOT NULL
            CONSTRAINT DF_dimPATAssessment_GoldCreatedUTC DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_dimPATAssessment_BusinessKey UNIQUE (AssessmentBusinessKey)
    );
END;
GO

IF OBJECT_ID(N'gold.factPAT', N'U') IS NULL
BEGIN
    CREATE TABLE gold.factPAT
    (
        FactPATKey bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_factPAT PRIMARY KEY,
        SilverBusinessKey char(64) NOT NULL,
        SourceKey char(64) NOT NULL,
        SourceSystem nvarchar(40) NOT NULL,
        SourceFileName nvarchar(260) NOT NULL,
        SourceRowNumber int NOT NULL,
        StudentKey bigint NULL,
        PATAssessmentKey int NOT NULL,
        AssessmentDateKey int NOT NULL,
        TestDateKey int NULL,
        ClassKey int NULL,
        CampusKey int NULL,
        StudentSourceId nvarchar(200) NULL,
        ExternalStudentId nvarchar(200) NULL,
        UniqueId nvarchar(200) NULL,
        Username nvarchar(200) NULL,
        CompassUsername nvarchar(200) NULL,
        StudentResolutionMethod nvarchar(40) NULL,
        SourceMatchMethod nvarchar(40) NULL,
        SourceMatchScore decimal(6,5) NULL,
        SourceMatchStatus nvarchar(40) NOT NULL,
        AssessmentDate date NOT NULL,
        TestDate date NULL,
        ExportedDate date NULL,
        AssessmentType nvarchar(200) NULL,
        TestType nvarchar(10) NOT NULL,
        TestName nvarchar(300) NOT NULL,
        ReportingWindow int NULL,
        YearLevel nvarchar(100) NULL,
        ClassName nvarchar(200) NULL,
        ScaleScore decimal(12,4) NOT NULL,
        Band nvarchar(100) NULL,
        Strand nvarchar(300) NULL,
        FocusArea nvarchar(300) NULL,
        AssessmentRange nvarchar(200) NULL,
        AssessmentPercentage decimal(12,4) NULL,
        AchievementLevel nvarchar(200) NULL,
        AssessmentINLP nvarchar(200) NULL,
        StrandAverageAchievementLevel nvarchar(200) NULL,
        Growth decimal(12,4) NULL,
        DataQualityNotes nvarchar(max) NOT NULL,
        SourceRowHash binary(32) NOT NULL,
        SourceLoadedAtUtc datetime2 NOT NULL,
        GoldCreatedUTC datetime2(3) NOT NULL
            CONSTRAINT DF_factPAT_GoldCreatedUTC DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_factPAT_SilverBusinessKey UNIQUE (SilverBusinessKey),
        CONSTRAINT CK_factPAT_ScaleScore CHECK (ScaleScore >= 0),
        CONSTRAINT CK_factPAT_AssessmentPercentage
            CHECK (AssessmentPercentage IS NULL OR AssessmentPercentage BETWEEN 0 AND 100),
        CONSTRAINT FK_factPAT_Student
            FOREIGN KEY (StudentKey) REFERENCES gold.dimStudent (StudentKey),
        CONSTRAINT FK_factPAT_Assessment
            FOREIGN KEY (PATAssessmentKey) REFERENCES gold.dimPATAssessment (PATAssessmentKey),
        CONSTRAINT FK_factPAT_AssessmentDate
            FOREIGN KEY (AssessmentDateKey) REFERENCES gold.dimDate (DateKey),
        CONSTRAINT FK_factPAT_TestDate
            FOREIGN KEY (TestDateKey) REFERENCES gold.dimDate (DateKey),
        CONSTRAINT FK_factPAT_Class
            FOREIGN KEY (ClassKey) REFERENCES gold.dimClass (ClassKey),
        CONSTRAINT FK_factPAT_Campus
            FOREIGN KEY (CampusKey) REFERENCES gold.dimCampus (CampusKey)
    );
END;
GO

IF OBJECT_ID(N'gold.PATLoadIssue', N'U') IS NULL
BEGIN
    CREATE TABLE gold.PATLoadIssue
    (
        PATLoadIssueKey bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_PATLoadIssue PRIMARY KEY,
        LoadAuditId bigint NOT NULL,
        SilverBusinessKey char(64) NOT NULL,
        SourceKey char(64) NOT NULL,
        SourceFileName nvarchar(260) NOT NULL,
        SourceRowNumber int NOT NULL,
        IssueCode varchar(50) NOT NULL,
        IssueMessage nvarchar(1000) NOT NULL,
        IsBlocking bit NOT NULL,
        CreatedUTC datetime2(3) NOT NULL
            CONSTRAINT DF_PATLoadIssue_CreatedUTC DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_PATLoadIssue_LoadAudit
            FOREIGN KEY (LoadAuditId) REFERENCES gold.LoadAudit (LoadAuditId),
        CONSTRAINT UQ_PATLoadIssue_RunRowCode
            UNIQUE (LoadAuditId, SourceFileName, SourceRowNumber, IssueCode)
    );
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'gold.factPAT')
      AND name = N'IX_factPAT_StudentAssessmentDate'
)
BEGIN
    CREATE INDEX IX_factPAT_StudentAssessmentDate
        ON gold.factPAT (StudentKey, AssessmentDateKey)
        INCLUDE (PATAssessmentKey, ScaleScore, Band);
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'gold.PATLoadIssue')
      AND name = N'IX_PATLoadIssue_AuditIssue'
)
BEGIN
    CREATE INDEX IX_PATLoadIssue_AuditIssue
        ON gold.PATLoadIssue (LoadAuditId, IssueCode)
        INCLUDE (SilverBusinessKey, IsBlocking);
END;
GO

CREATE OR ALTER PROCEDURE gold.usp_Load_factPAT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @ProcedureName sysname = N'gold.usp_Load_factPAT',
        @SourceObject nvarchar(256) = N'silver.PAT',
        @TargetObject nvarchar(256) = N'gold.factPAT',
        @EndpointKey nvarchar(200) = N'SchoolDW.silver.PAT',
        @StartedUTC datetime2(3) = SYSUTCDATETIME(),
        @FinishedUTC datetime2(3),
        @ExistingWatermark nvarchar(4000),
        @WatermarkUTC datetime2(3),
        @NewWatermark datetime2(3),
        @SourceRowCount bigint = 0,
        @InsertedRowCount bigint = 0,
        @IssueCount bigint = 0,
        @RejectedRowCount bigint = 0,
        @UnmatchedStudentCount bigint = 0,
        @LoadAuditId bigint,
        @RunStatus varchar(20),
        @AppLockResult int,
        @ErrorNumber int,
        @ErrorMessage nvarchar(4000),
        @AuditErrorMessage nvarchar(4000),
        @CombinedErrorMessage nvarchar(4000);

    BEGIN TRY
        BEGIN TRANSACTION;

        EXEC @AppLockResult = sys.sp_getapplock
            @Resource = N'gold.usp_Load_factPAT',
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 60000;

        IF @AppLockResult < 0
            THROW 51000, N'Could not obtain the PAT Gold load application lock.', 1;

        SELECT @ExistingWatermark = watermark_value
        FROM metadata.etl_watermark WITH (UPDLOCK, HOLDLOCK)
        WHERE endpoint_key = @EndpointKey;

        IF NULLIF(@ExistingWatermark, N'') IS NOT NULL
        BEGIN
            SET @WatermarkUTC = TRY_CONVERT(datetime2(3), @ExistingWatermark, 126);

            IF @WatermarkUTC IS NULL
                THROW 51001, N'The silver.PAT watermark is not a valid ISO datetime value.', 1;
        END;

        SELECT
            p.*,
            COUNT_BIG(*) OVER (PARTITION BY p.SilverBusinessKey) AS BusinessKeyCount,
            HASHBYTES
            (
                'SHA2_256',
                CONVERT(varbinary(max), payload.SemanticJson)
            ) AS SourceRowHash,
            HASHBYTES
            (
                'SHA2_256',
                CONVERT(varbinary(max), payload.AssessmentJson)
            ) AS AssessmentBusinessKey
        INTO #Stage
        FROM silver.PAT AS p
        CROSS APPLY
        (
            SELECT
                (
                    SELECT
                        p.SilverBusinessKey, p.SourceKey, p.SourceSystem,
                        p.SourceFileName, p.SourceRowNumber, p.StudentSourceId,
                        p.StudentName, p.StudentFirstName, p.StudentLastName,
                        p.ExternalStudentId, p.AssessmentType, p.AssessmentDate,
                        p.TestName, p.YearLevel, p.ClassName, p.ScaleScore,
                        p.Band, p.Strand, p.FocusArea, p.AssessmentRange,
                        p.AssessmentPercentage, p.AchievementLevel, p.AssessmentINLP,
                        p.StrandAverageAchievementLevel, p.Growth, p.CompassPersonId,
                        p.CompassUsername, p.MatchMethod, p.MatchScore, p.MatchStatus,
                        p.DataQualityNotes, p.SourceDataJson, p.FamilyName,
                        p.GivenName, p.MiddleNames, p.UniqueId, p.Username,
                        p.DateOfBirth, p.Gender, p.ReportingWindow, p.ExportedDate,
                        p.TestDate, p.TestType
                    FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
                ) AS SemanticJson,
                (
                    SELECT
                        p.AssessmentType, p.TestType, p.TestName, p.ReportingWindow
                    FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
                ) AS AssessmentJson
        ) AS payload
        WHERE @WatermarkUTC IS NULL
           OR p.LoadedAtUtc >= @WatermarkUTC
           OR NOT EXISTS
              (
                  SELECT 1
                  FROM gold.factPAT AS f
                  WHERE f.SilverBusinessKey = p.SilverBusinessKey
              );

        SET @SourceRowCount = @@ROWCOUNT;

        CREATE TABLE #Issue
        (
            SilverBusinessKey char(64) NOT NULL,
            SourceKey char(64) NOT NULL,
            SourceFileName nvarchar(260) NOT NULL,
            SourceRowNumber int NOT NULL,
            IssueCode varchar(50) NOT NULL,
            IssueMessage nvarchar(1000) NOT NULL,
            IsBlocking bit NOT NULL
        );

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            s.SilverBusinessKey, s.SourceKey, s.SourceFileName, s.SourceRowNumber,
            'INVALID_BUSINESS_KEY',
            N'SilverBusinessKey must contain exactly 64 hexadecimal characters.',
            1
        FROM #Stage AS s
        WHERE LEN(RTRIM(s.SilverBusinessKey)) <> 64
           OR TRY_CONVERT(varbinary(32), CONVERT(varchar(64), RTRIM(s.SilverBusinessKey)), 2) IS NULL;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            s.SilverBusinessKey, s.SourceKey, s.SourceFileName, s.SourceRowNumber,
            'INVALID_SOURCE_KEY',
            N'SourceKey must contain exactly 64 hexadecimal characters.',
            1
        FROM #Stage AS s
        WHERE LEN(RTRIM(s.SourceKey)) <> 64
           OR TRY_CONVERT(varbinary(32), CONVERT(varchar(64), RTRIM(s.SourceKey)), 2) IS NULL;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            s.SilverBusinessKey, s.SourceKey, s.SourceFileName, s.SourceRowNumber,
            'DUPLICATE_BUSINESS_KEY',
            N'Multiple Silver PAT rows share this SilverBusinessKey; no row was selected.',
            1
        FROM #Stage AS s
        WHERE s.BusinessKeyCount > 1;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            s.SilverBusinessKey, s.SourceKey, s.SourceFileName, s.SourceRowNumber,
            'MISSING_ASSESSMENT_DATE',
            N'AssessmentDate is required to resolve AssessmentDateKey.',
            1
        FROM #Stage AS s
        WHERE s.AssessmentDate IS NULL;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            s.SilverBusinessKey, s.SourceKey, s.SourceFileName, s.SourceRowNumber,
            'ASSESSMENT_DATE_NOT_IN_DIM',
            N'AssessmentDate has no matching row in gold.dimDate.',
            1
        FROM #Stage AS s
        WHERE s.AssessmentDate IS NOT NULL
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM gold.dimDate AS d
                  WHERE d.Date = s.AssessmentDate
              );

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            s.SilverBusinessKey, s.SourceKey, s.SourceFileName, s.SourceRowNumber,
            'TEST_DATE_NOT_IN_DIM',
            N'TestDate has no matching row in gold.dimDate.',
            1
        FROM #Stage AS s
        WHERE s.TestDate IS NOT NULL
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM gold.dimDate AS d
                  WHERE d.Date = s.TestDate
              );

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            s.SilverBusinessKey, s.SourceKey, s.SourceFileName, s.SourceRowNumber,
            'MISSING_TEST_TYPE',
            N'TestType is required to identify the PAT assessment.',
            1
        FROM #Stage AS s
        WHERE NULLIF(LTRIM(RTRIM(s.TestType)), N'') IS NULL;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            s.SilverBusinessKey, s.SourceKey, s.SourceFileName, s.SourceRowNumber,
            'MISSING_TEST_NAME',
            N'TestName is required to identify the PAT assessment.',
            1
        FROM #Stage AS s
        WHERE NULLIF(LTRIM(RTRIM(s.TestName)), N'') IS NULL;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            s.SilverBusinessKey, s.SourceKey, s.SourceFileName, s.SourceRowNumber,
            'MISSING_SCALE_SCORE',
            N'ScaleScore is required for a PAT overall assessment result.',
            1
        FROM #Stage AS s
        WHERE s.ScaleScore IS NULL;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            s.SilverBusinessKey, s.SourceKey, s.SourceFileName, s.SourceRowNumber,
            'INVALID_SCALE_SCORE',
            N'ScaleScore cannot be negative; no upper bound of 100 is applied.',
            1
        FROM #Stage AS s
        WHERE s.ScaleScore < 0;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            s.SilverBusinessKey, s.SourceKey, s.SourceFileName, s.SourceRowNumber,
            'INVALID_ASSESSMENT_PERCENTAGE',
            N'AssessmentPercentage must be between 0 and 100 when populated.',
            1
        FROM #Stage AS s
        WHERE s.AssessmentPercentage < 0
           OR s.AssessmentPercentage > 100;

        INSERT gold.dimPATAssessment
        (
            AssessmentBusinessKey, AssessmentType, TestType, TestName, ReportingWindow
        )
        SELECT DISTINCT
            s.AssessmentBusinessKey, s.AssessmentType, s.TestType,
            s.TestName, s.ReportingWindow
        FROM #Stage AS s
        WHERE NOT EXISTS
              (
                  SELECT 1
                  FROM #Issue AS i
                  WHERE i.SourceFileName = s.SourceFileName
                    AND i.SourceRowNumber = s.SourceRowNumber
                    AND i.IsBlocking = 1
              )
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM gold.dimPATAssessment AS d WITH (UPDLOCK, HOLDLOCK)
                  WHERE d.AssessmentBusinessKey = s.AssessmentBusinessKey
              );

        SELECT
            s.*,
            patAssessment.PATAssessmentKey,
            assessmentDate.DateKey AS AssessmentDateKey,
            testDate.DateKey AS TestDateKey,
            studentResolution.StudentKey,
            studentResolution.ResolutionMethod,
            compassMatch.StudentKey AS CompassCandidateStudentKey,
            compassMatch.MatchCount AS CompassCandidateCount,
            usernameMatch.StudentKey AS UsernameCandidateStudentKey,
            usernameMatch.MatchCount AS UsernameCandidateCount,
            classMatch.ClassKey,
            classMatch.MatchCount AS ClassCandidateCount,
            campusMatch.CampusKey,
            campusMatch.MatchCount AS CampusCandidateCount,
            student.HomeCampus
        INTO #Resolved
        FROM #Stage AS s
        LEFT JOIN gold.dimPATAssessment AS patAssessment
            ON patAssessment.AssessmentBusinessKey = s.AssessmentBusinessKey
        LEFT JOIN gold.dimDate AS assessmentDate
            ON assessmentDate.Date = s.AssessmentDate
        LEFT JOIN gold.dimDate AS testDate
            ON testDate.Date = s.TestDate
        OUTER APPLY
        (
            SELECT MIN(d.StudentKey) AS StudentKey, COUNT_BIG(*) AS MatchCount
            FROM gold.dimStudent AS d
            WHERE NULLIF(LTRIM(RTRIM(s.CompassPersonId)), N'') IS NOT NULL
              AND d.CompassPersonId = LTRIM(RTRIM(s.CompassPersonId))
        ) AS compassMatch
        OUTER APPLY
        (
            SELECT MIN(d.StudentKey) AS StudentKey, COUNT_BIG(*) AS MatchCount
            FROM gold.dimStudent AS d
            WHERE NULLIF(LTRIM(RTRIM(s.Username)), N'') IS NOT NULL
              AND NULLIF(LTRIM(RTRIM(d.Username)), N'') = LTRIM(RTRIM(s.Username))
        ) AS usernameMatch
        CROSS APPLY
        (
            SELECT
                CASE
                    WHEN compassMatch.MatchCount = 1 THEN compassMatch.StudentKey
                    WHEN usernameMatch.MatchCount = 1 THEN usernameMatch.StudentKey
                END AS StudentKey,
                CASE
                    WHEN compassMatch.MatchCount = 1 THEN N'COMPASS_PERSON_ID'
                    WHEN usernameMatch.MatchCount = 1 THEN N'USERNAME_EXACT_UNIQUE'
                END AS ResolutionMethod
        ) AS studentResolution
        OUTER APPLY
        (
            SELECT MIN(c.ClassKey) AS ClassKey, COUNT_BIG(*) AS MatchCount
            FROM gold.dimClass AS c
            WHERE c.IsCurrent = 1
              AND NULLIF(LTRIM(RTRIM(s.ClassName)), N'') IS NOT NULL
              AND NULLIF(LTRIM(RTRIM(c.ClassName)), N'') = LTRIM(RTRIM(s.ClassName))
        ) AS classMatch
        OUTER APPLY
        (
            SELECT d.HomeCampus
            FROM gold.dimStudent AS d
            WHERE d.StudentKey = studentResolution.StudentKey
        ) AS student
        OUTER APPLY
        (
            SELECT MIN(candidates.CampusKey) AS CampusKey, COUNT_BIG(*) AS MatchCount
            FROM
            (
                SELECT DISTINCT c.CampusKey
                FROM gold.dimCampus AS c
                WHERE c.CompassCampusId = student.HomeCampus
                  AND c.IsCurrent = 1
            ) AS candidates
        ) AS campusMatch;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            r.SilverBusinessKey, r.SourceKey, r.SourceFileName, r.SourceRowNumber,
            'STUDENT_UNMATCHED',
            N'No unique CompassPersonId or exact unique Gold Username match was found.',
            0
        FROM #Resolved AS r
        WHERE r.StudentKey IS NULL;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            r.SilverBusinessKey, r.SourceKey, r.SourceFileName, r.SourceRowNumber,
            'STUDENT_IDENTIFIER_CONFLICT',
            N'CompassPersonId and exact Username resolve to different Gold students; CompassPersonId was used.',
            0
        FROM #Resolved AS r
        WHERE r.CompassCandidateCount = 1
          AND r.UsernameCandidateCount = 1
          AND r.CompassCandidateStudentKey <> r.UsernameCandidateStudentKey;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            r.SilverBusinessKey, r.SourceKey, r.SourceFileName, r.SourceRowNumber,
            'COMPASS_ID_UNRESOLVED_USERNAME_FALLBACK',
            N'CompassPersonId was missing or did not resolve uniquely; an exact unique Username fallback was used.',
            0
        FROM #Resolved AS r
        WHERE r.ResolutionMethod = N'USERNAME_EXACT_UNIQUE'
          AND NULLIF(LTRIM(RTRIM(r.CompassPersonId)), N'') IS NOT NULL;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            r.SilverBusinessKey, r.SourceKey, r.SourceFileName, r.SourceRowNumber,
            'CLASS_UNRESOLVED',
            N'ClassName did not resolve to exactly one current gold.dimClass row; ClassKey was left NULL.',
            0
        FROM #Resolved AS r
        WHERE NULLIF(LTRIM(RTRIM(r.ClassName)), N'') IS NOT NULL
          AND r.ClassCandidateCount <> 1;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            r.SilverBusinessKey, r.SourceKey, r.SourceFileName, r.SourceRowNumber,
            'CAMPUS_UNRESOLVED',
            N'The resolved student HomeCampus did not map uniquely to gold.dimCampus.CompassCampusId; CampusKey was left NULL.',
            0
        FROM #Resolved AS r
        WHERE r.StudentKey IS NOT NULL
          AND r.HomeCampus IS NOT NULL
          AND r.CampusCandidateCount <> 1;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            r.SilverBusinessKey, r.SourceKey, r.SourceFileName, r.SourceRowNumber,
            'ASSESSMENT_KEY_UNRESOLVED',
            N'No gold.dimPATAssessment row was found for the validated PAT assessment attributes.',
            1
        FROM #Resolved AS r
        WHERE r.PATAssessmentKey IS NULL;

        INSERT #Issue
        (
            SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            r.SilverBusinessKey, r.SourceKey, r.SourceFileName, r.SourceRowNumber,
            'SOURCE_CHANGE_NOT_APPLIED',
            N'The Silver row or its resolved student key differs from the existing fact. Insert-only policy left Gold unchanged.',
            0
        FROM #Resolved AS r
        INNER JOIN gold.factPAT AS f
            ON f.SilverBusinessKey = r.SilverBusinessKey
        WHERE f.SourceRowHash <> r.SourceRowHash
           OR ISNULL(f.StudentKey, CONVERT(bigint, -1)) <>
              ISNULL(r.StudentKey, CONVERT(bigint, -1));

        INSERT gold.factPAT
        (
            SilverBusinessKey, SourceKey, SourceSystem, SourceFileName, SourceRowNumber,
            StudentKey, PATAssessmentKey, AssessmentDateKey, TestDateKey, ClassKey, CampusKey,
            StudentSourceId, ExternalStudentId, UniqueId, Username, CompassUsername,
            StudentResolutionMethod, SourceMatchMethod, SourceMatchScore, SourceMatchStatus,
            AssessmentDate, TestDate, ExportedDate, AssessmentType, TestType, TestName,
            ReportingWindow, YearLevel, ClassName, ScaleScore, Band, Strand, FocusArea,
            AssessmentRange, AssessmentPercentage, AchievementLevel, AssessmentINLP,
            StrandAverageAchievementLevel, Growth, DataQualityNotes, SourceRowHash,
            SourceLoadedAtUtc
        )
        SELECT
            r.SilverBusinessKey, r.SourceKey, r.SourceSystem, r.SourceFileName, r.SourceRowNumber,
            r.StudentKey, r.PATAssessmentKey, r.AssessmentDateKey, r.TestDateKey,
            CASE WHEN r.ClassCandidateCount = 1 THEN r.ClassKey END,
            CASE WHEN r.CampusCandidateCount = 1 THEN r.CampusKey END,
            r.StudentSourceId, r.ExternalStudentId, r.UniqueId, r.Username, r.CompassUsername,
            r.ResolutionMethod, r.MatchMethod, r.MatchScore, r.MatchStatus,
            r.AssessmentDate, r.TestDate, r.ExportedDate, r.AssessmentType, r.TestType,
            r.TestName, r.ReportingWindow, r.YearLevel, r.ClassName, r.ScaleScore, r.Band,
            r.Strand, r.FocusArea, r.AssessmentRange, r.AssessmentPercentage,
            r.AchievementLevel, r.AssessmentINLP, r.StrandAverageAchievementLevel,
            r.Growth, r.DataQualityNotes, r.SourceRowHash, r.LoadedAtUtc
        FROM #Resolved AS r
        WHERE r.PATAssessmentKey IS NOT NULL
          AND r.AssessmentDateKey IS NOT NULL
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM #Issue AS i
                  WHERE i.SourceFileName = r.SourceFileName
                    AND i.SourceRowNumber = r.SourceRowNumber
                    AND i.IsBlocking = 1
              )
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM gold.factPAT AS f WITH (UPDLOCK, HOLDLOCK)
                  WHERE f.SilverBusinessKey = r.SilverBusinessKey
              );

        SET @InsertedRowCount = @@ROWCOUNT;

        SELECT @NewWatermark = MAX(LoadedAtUtc)
        FROM #Stage;

        IF @NewWatermark IS NOT NULL
           AND (@WatermarkUTC IS NULL OR @NewWatermark >= @WatermarkUTC)
        BEGIN
            IF EXISTS
            (
                SELECT 1
                FROM metadata.etl_watermark
                WHERE endpoint_key = @EndpointKey
            )
            BEGIN
                UPDATE metadata.etl_watermark
                SET watermark_value = CONVERT(nvarchar(33), @NewWatermark, 126),
                    updated_at_utc = SYSUTCDATETIME(),
                    last_success_batch_id = NEWID()
                WHERE endpoint_key = @EndpointKey;
            END
            ELSE
            BEGIN
                INSERT metadata.etl_watermark
                (
                    endpoint_key, watermark_value, updated_at_utc, last_success_batch_id
                )
                VALUES
                (
                    @EndpointKey, CONVERT(nvarchar(33), @NewWatermark, 126),
                    SYSUTCDATETIME(), NEWID()
                );
            END;
        END;

        SELECT @IssueCount = COUNT_BIG(*) FROM #Issue;
        SELECT @RejectedRowCount = COUNT_BIG(*)
        FROM
        (
            SELECT DISTINCT SourceFileName, SourceRowNumber
            FROM #Issue
            WHERE IsBlocking = 1
        ) AS rejected;
        SELECT @UnmatchedStudentCount = COUNT_BIG(*)
        FROM #Issue
        WHERE IssueCode = 'STUDENT_UNMATCHED';

        IF @WatermarkUTC IS NOT NULL
           AND (@NewWatermark IS NULL OR @WatermarkUTC > @NewWatermark)
            SET @NewWatermark = @WatermarkUTC;

        SET @FinishedUTC = SYSUTCDATETIME();
        SET @RunStatus =
            CASE WHEN @IssueCount > 0 THEN 'SUCCEEDED_ISSUES' ELSE 'SUCCEEDED' END;

        EXEC gold.usp_WriteLoadAudit
            @ProcedureName = @ProcedureName,
            @SourceObject = @SourceObject,
            @TargetObject = @TargetObject,
            @StartedUTC = @StartedUTC,
            @FinishedUTC = @FinishedUTC,
            @SourceRowCount = @SourceRowCount,
            @InsertedRowCount = @InsertedRowCount,
            @UpdatedRowCount = 0,
            @ErrorNumber = NULL,
            @ErrorMessage = NULL,
            @RunStatus = @RunStatus;

        SELECT TOP (1) @LoadAuditId = LoadAuditId
        FROM gold.LoadAudit
        WHERE ProcedureName = @ProcedureName
          AND SourceObject = @SourceObject
          AND TargetObject = @TargetObject
          AND StartedUTC = @StartedUTC
        ORDER BY LoadAuditId DESC;

        IF @LoadAuditId IS NULL
            THROW 51002, N'The PAT load audit row could not be located after writing it.', 1;

        INSERT gold.PATLoadIssue
        (
            LoadAuditId, SilverBusinessKey, SourceKey, SourceFileName, SourceRowNumber,
            IssueCode, IssueMessage, IsBlocking
        )
        SELECT
            @LoadAuditId, i.SilverBusinessKey, i.SourceKey, i.SourceFileName, i.SourceRowNumber,
            i.IssueCode, i.IssueMessage, i.IsBlocking
        FROM #Issue AS i;

        COMMIT TRANSACTION;

        SELECT
            @LoadAuditId AS LoadAuditId,
            @SourceRowCount AS SourceRowCount,
            @InsertedRowCount AS InsertedRowCount,
            CONVERT(bigint, 0) AS UpdatedRowCount,
            @RejectedRowCount AS RejectedSourceRows,
            @UnmatchedStudentCount AS UnmatchedStudentRows,
            @IssueCount AS IssueCount,
            CONVERT(nvarchar(33), @NewWatermark, 126) AS WatermarkValue;
    END TRY
    BEGIN CATCH
        SET @ErrorNumber = ERROR_NUMBER();
        SET @ErrorMessage = ERROR_MESSAGE();

        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @FinishedUTC = SYSUTCDATETIME();
        SET @InsertedRowCount = 0;
        SET @AuditErrorMessage = NULL;

        BEGIN TRY
            EXEC gold.usp_WriteLoadAudit
                @ProcedureName = @ProcedureName,
                @SourceObject = @SourceObject,
                @TargetObject = @TargetObject,
                @StartedUTC = @StartedUTC,
                @FinishedUTC = @FinishedUTC,
                @SourceRowCount = @SourceRowCount,
                @InsertedRowCount = @InsertedRowCount,
                @UpdatedRowCount = 0,
                @ErrorNumber = @ErrorNumber,
                @ErrorMessage = @ErrorMessage,
                @RunStatus = 'FAILED';
        END TRY
        BEGIN CATCH
            SET @AuditErrorMessage = ERROR_MESSAGE();
        END CATCH;

        IF @AuditErrorMessage IS NOT NULL
        BEGIN
            SET @CombinedErrorMessage =
                LEFT(CONCAT(N'PAT load failed: ', @ErrorMessage,
                            N'; failure audit also failed: ', @AuditErrorMessage), 4000);
            THROW 51003, @CombinedErrorMessage, 1;
        END;

        THROW;
    END CATCH;
END;
GO
