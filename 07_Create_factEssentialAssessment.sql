USE SchoolDW;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/*
  Grain: one EssentialAssessment focus-area result for a student assessment
  (student + assessment date + assessment type + test name + strand + focus area).
  Measure: AssessmentPercentage (0-100). Silver ScaleScore is not persisted here;
  it is null for every source row and is not a measure of this fact.
  Rows are never dropped for unresolved students: StudentKey stays NULL and the
  gap is logged in gold.EssentialAssessmentLoadIssue.
*/

IF OBJECT_ID(N'gold.dimEssentialAssessment', N'U') IS NULL
BEGIN
    CREATE TABLE gold.dimEssentialAssessment
    (
        EssentialAssessmentKey int IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_dimEssentialAssessment PRIMARY KEY,
        AssessmentBusinessKey binary(32) NOT NULL,
        AssessmentType nvarchar(200) NULL,
        TestName nvarchar(300) NOT NULL,
        GoldCreatedUTC datetime2(3) NOT NULL
            CONSTRAINT DF_dimEssentialAssessment_GoldCreatedUTC DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_dimEssentialAssessment_BusinessKey UNIQUE (AssessmentBusinessKey)
    );
END;
GO

IF OBJECT_ID(N'gold.factEssentialAssessment', N'U') IS NULL
BEGIN
    CREATE TABLE gold.factEssentialAssessment
    (
        FactEssentialAssessmentKey bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_factEssentialAssessment PRIMARY KEY,
        SilverBusinessKey char(64) NOT NULL,
        SourceKey char(64) NOT NULL,
        SourceSystem nvarchar(40) NOT NULL,
        SourceFileName nvarchar(260) NOT NULL,
        SourceRowNumber int NOT NULL,
        StudentKey bigint NULL,
        EssentialAssessmentKey int NOT NULL,
        AssessmentDateKey int NOT NULL,
        ClassKey int NULL,
        CampusKey int NULL,
        StudentSourceId nvarchar(200) NULL,
        ExternalStudentId nvarchar(200) NULL,
        CompassUsername nvarchar(200) NULL,
        StudentResolutionMethod nvarchar(40) NULL,
        SourceMatchMethod nvarchar(40) NULL,
        SourceMatchScore decimal(6,5) NULL,
        SourceMatchStatus nvarchar(40) NOT NULL,
        AssessmentDate date NOT NULL,
        AssessmentType nvarchar(200) NULL,
        TestName nvarchar(300) NOT NULL,
        YearLevel nvarchar(100) NULL,
        ClassName nvarchar(200) NULL,
        Strand nvarchar(300) NOT NULL,
        FocusArea nvarchar(300) NOT NULL,
        AssessmentPercentage decimal(12,4) NOT NULL,
        AssessmentRange nvarchar(200) NULL,
        AchievementLevel nvarchar(200) NULL,
        AssessmentINLP nvarchar(200) NULL,
        StrandAverageAchievementLevel nvarchar(200) NULL,
        Growth decimal(12,4) NULL,
        DataQualityNotes nvarchar(max) NOT NULL,
        SourceRowHash binary(32) NOT NULL,
        SourceLoadedAtUtc datetime2 NOT NULL,
        GoldCreatedUTC datetime2(3) NOT NULL
            CONSTRAINT DF_factEssentialAssessment_GoldCreatedUTC DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_factEssentialAssessment_SilverBusinessKey UNIQUE (SilverBusinessKey),
        CONSTRAINT CK_factEssentialAssessment_Percentage
            CHECK (AssessmentPercentage BETWEEN 0 AND 100),
        CONSTRAINT FK_factEssentialAssessment_Student
            FOREIGN KEY (StudentKey) REFERENCES gold.dimStudent (StudentKey),
        CONSTRAINT FK_factEssentialAssessment_Assessment
            FOREIGN KEY (EssentialAssessmentKey) REFERENCES gold.dimEssentialAssessment (EssentialAssessmentKey),
        CONSTRAINT FK_factEssentialAssessment_AssessmentDate
            FOREIGN KEY (AssessmentDateKey) REFERENCES gold.dimDate (DateKey),
        CONSTRAINT FK_factEssentialAssessment_Class
            FOREIGN KEY (ClassKey) REFERENCES gold.dimClass (ClassKey),
        CONSTRAINT FK_factEssentialAssessment_Campus
            FOREIGN KEY (CampusKey) REFERENCES gold.dimCampus (CampusKey)
    );
END;
GO

IF OBJECT_ID(N'gold.EssentialAssessmentLoadIssue', N'U') IS NULL
BEGIN
    CREATE TABLE gold.EssentialAssessmentLoadIssue
    (
        EssentialAssessmentLoadIssueKey bigint IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_EssentialAssessmentLoadIssue PRIMARY KEY,
        LoadAuditId bigint NOT NULL,
        SilverBusinessKey char(64) NOT NULL,
        SourceKey char(64) NOT NULL,
        SourceFileName nvarchar(260) NOT NULL,
        SourceRowNumber int NOT NULL,
        IssueCode varchar(50) NOT NULL,
        IssueMessage nvarchar(1000) NOT NULL,
        IsBlocking bit NOT NULL,
        CreatedUTC datetime2(3) NOT NULL
            CONSTRAINT DF_EssentialAssessmentLoadIssue_CreatedUTC DEFAULT SYSUTCDATETIME(),
        CONSTRAINT FK_EssentialAssessmentLoadIssue_LoadAudit
            FOREIGN KEY (LoadAuditId) REFERENCES gold.LoadAudit (LoadAuditId),
        CONSTRAINT UQ_EssentialAssessmentLoadIssue_RunRowCode
            UNIQUE (LoadAuditId, SourceFileName, SourceRowNumber, IssueCode)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'gold.factEssentialAssessment') AND name = N'IX_factEssentialAssessment_StudentDate')
    CREATE INDEX IX_factEssentialAssessment_StudentDate
        ON gold.factEssentialAssessment (StudentKey, AssessmentDateKey)
        INCLUDE (EssentialAssessmentKey, AssessmentPercentage, AchievementLevel);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'gold.factEssentialAssessment') AND name = N'IX_factEssentialAssessment_AssessmentDate')
    CREATE INDEX IX_factEssentialAssessment_AssessmentDate
        ON gold.factEssentialAssessment (EssentialAssessmentKey, AssessmentDateKey)
        INCLUDE (StudentKey, AssessmentPercentage);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'gold.EssentialAssessmentLoadIssue') AND name = N'IX_EssentialAssessmentLoadIssue_AuditIssue')
    CREATE INDEX IX_EssentialAssessmentLoadIssue_AuditIssue
        ON gold.EssentialAssessmentLoadIssue (LoadAuditId, IssueCode)
        INCLUDE (SilverBusinessKey, IsBlocking);
GO

CREATE OR ALTER PROCEDURE gold.usp_Load_factEssentialAssessment
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @ProcedureName sysname = N'gold.usp_Load_factEssentialAssessment',
        @SourceObject nvarchar(256) = N'silver.EssentialAssessment',
        @TargetObject nvarchar(256) = N'gold.factEssentialAssessment',
        @EndpointKey nvarchar(200) = N'SchoolDW.silver.EssentialAssessment',
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
            @Resource = N'gold.usp_Load_factEssentialAssessment',
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 60000;

        IF @AppLockResult < 0
            THROW 51011, N'Could not acquire the EssentialAssessment load lock.', 1;

        SELECT @ExistingWatermark = watermark_value
        FROM metadata.etl_watermark WITH (UPDLOCK, HOLDLOCK)
        WHERE endpoint_key = @EndpointKey;

        IF NULLIF(@ExistingWatermark, N'') IS NOT NULL
        BEGIN
            SET @WatermarkUTC = TRY_CONVERT(datetime2(3), @ExistingWatermark, 126);

            IF @WatermarkUTC IS NULL
                THROW 51012, N'The silver.EssentialAssessment watermark is not a valid ISO datetime value.', 1;
        END;

        SELECT
            e.*,
            COUNT_BIG(*) OVER (PARTITION BY e.SilverBusinessKey) AS BusinessKeyCount,
            HASHBYTES('SHA2_256', CONVERT(varbinary(max), payload.SemanticJson)) AS SourceRowHash,
            HASHBYTES('SHA2_256', CONVERT(varbinary(max), payload.AssessmentJson)) AS AssessmentBusinessKey
        INTO #Stage
        FROM silver.EssentialAssessment AS e
        CROSS APPLY
        (
            SELECT
                (
                    SELECT
                        e.SilverBusinessKey, e.SourceKey, e.SourceSystem, e.SourceFileName,
                        e.SourceRowNumber, e.StudentSourceId, e.StudentName, e.StudentFirstName,
                        e.StudentLastName, e.ExternalStudentId, e.AssessmentType, e.AssessmentDate,
                        e.TestName, e.YearLevel, e.ClassName, e.ScaleScore, e.Band, e.Strand,
                        e.FocusArea, e.AssessmentRange, e.AssessmentPercentage, e.AchievementLevel,
                        e.AssessmentINLP, e.StrandAverageAchievementLevel, e.Growth,
                        e.CompassPersonId, e.CompassUsername, e.MatchMethod, e.MatchScore,
                        e.MatchStatus, e.DataQualityNotes, e.SourceDataJson
                    FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
                ) AS SemanticJson,
                (
                    SELECT e.AssessmentType, e.TestName
                    FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER
                ) AS AssessmentJson
        ) AS payload
        WHERE @WatermarkUTC IS NULL
           OR e.LoadedAtUtc >= @WatermarkUTC
           OR NOT EXISTS
              (
                  SELECT 1
                  FROM gold.factEssentialAssessment AS f
                  WHERE f.SilverBusinessKey = e.SilverBusinessKey
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
            v.IssueCode, v.IssueMessage, 1
        FROM #Stage AS s
        CROSS APPLY
        (
            VALUES
            (
                CASE WHEN LEN(RTRIM(s.SilverBusinessKey)) <> 64
                       OR TRY_CONVERT(varbinary(32), CONVERT(varchar(64), RTRIM(s.SilverBusinessKey)), 2) IS NULL
                     THEN 1 ELSE 0 END,
                'INVALID_BUSINESS_KEY',
                N'SilverBusinessKey must contain exactly 64 hexadecimal characters.'
            ),
            (
                CASE WHEN LEN(RTRIM(s.SourceKey)) <> 64
                       OR TRY_CONVERT(varbinary(32), CONVERT(varchar(64), RTRIM(s.SourceKey)), 2) IS NULL
                     THEN 1 ELSE 0 END,
                'INVALID_SOURCE_KEY',
                N'SourceKey must contain exactly 64 hexadecimal characters.'
            ),
            (
                CASE WHEN s.BusinessKeyCount > 1 THEN 1 ELSE 0 END,
                'DUPLICATE_BUSINESS_KEY',
                N'Multiple Silver EssentialAssessment rows share this SilverBusinessKey; no row was selected.'
            ),
            (
                CASE WHEN s.AssessmentDate IS NULL THEN 1 ELSE 0 END,
                'MISSING_ASSESSMENT_DATE',
                N'AssessmentDate is required to resolve AssessmentDateKey.'
            ),
            (
                CASE WHEN s.AssessmentDate IS NOT NULL
                      AND NOT EXISTS (SELECT 1 FROM gold.dimDate AS d WHERE d.Date = s.AssessmentDate)
                     THEN 1 ELSE 0 END,
                'ASSESSMENT_DATE_NOT_IN_DIM',
                N'AssessmentDate has no matching row in gold.dimDate.'
            ),
            (
                CASE WHEN NULLIF(LTRIM(RTRIM(s.TestName)), N'') IS NULL THEN 1 ELSE 0 END,
                'MISSING_TEST_NAME',
                N'TestName is required to identify the EssentialAssessment.'
            ),
            (
                CASE WHEN NULLIF(LTRIM(RTRIM(s.Strand)), N'') IS NULL THEN 1 ELSE 0 END,
                'MISSING_STRAND',
                N'Strand is required at the focus-area result grain.'
            ),
            (
                CASE WHEN NULLIF(LTRIM(RTRIM(s.FocusArea)), N'') IS NULL THEN 1 ELSE 0 END,
                'MISSING_FOCUS_AREA',
                N'FocusArea is required at the focus-area result grain.'
            ),
            (
                CASE WHEN s.AssessmentPercentage IS NULL THEN 1 ELSE 0 END,
                'MISSING_ASSESSMENT_PERCENTAGE',
                N'AssessmentPercentage is the EssentialAssessment measure and is required.'
            ),
            (
                CASE WHEN s.AssessmentPercentage < 0 OR s.AssessmentPercentage > 100 THEN 1 ELSE 0 END,
                'INVALID_ASSESSMENT_PERCENTAGE',
                N'AssessmentPercentage must be between 0 and 100.'
            )
        ) AS v (IsIssue, IssueCode, IssueMessage)
        WHERE v.IsIssue = 1;

        INSERT gold.dimEssentialAssessment (AssessmentBusinessKey, AssessmentType, TestName)
        SELECT DISTINCT s.AssessmentBusinessKey, s.AssessmentType, s.TestName
        FROM #Stage AS s
        WHERE NULLIF(LTRIM(RTRIM(s.TestName)), N'') IS NOT NULL
          AND NOT EXISTS
              (
                  SELECT 1 FROM #Issue AS i
                  WHERE i.SilverBusinessKey = s.SilverBusinessKey
                    AND i.IsBlocking = 1
              )
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM gold.dimEssentialAssessment AS d WITH (UPDLOCK, HOLDLOCK)
                  WHERE d.AssessmentBusinessKey = s.AssessmentBusinessKey
              );

        SELECT
            s.*,
            ea.EssentialAssessmentKey,
            ad.DateKey AS AssessmentDateKey,
            sr.StudentKey,
            sr.ResolutionMethod,
            compassMatch.MatchCount AS CompassCandidateCount,
            compassMatch.StudentKey AS CompassCandidateStudentKey,
            usernameMatch.MatchCount AS UsernameCandidateCount,
            usernameMatch.StudentKey AS UsernameCandidateStudentKey,
            classMatch.ClassKey,
            classMatch.MatchCount AS ClassCandidateCount,
            campusMatch.CampusKey,
            campusMatch.MatchCount AS CampusCandidateCount,
            student.HomeCampus
        INTO #Resolved
        FROM #Stage AS s
        LEFT JOIN gold.dimEssentialAssessment AS ea
            ON ea.AssessmentBusinessKey = s.AssessmentBusinessKey
        LEFT JOIN gold.dimDate AS ad
            ON ad.Date = s.AssessmentDate
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
            WHERE NULLIF(LTRIM(RTRIM(s.CompassUsername)), N'') IS NOT NULL
              AND NULLIF(LTRIM(RTRIM(d.Username)), N'') = LTRIM(RTRIM(s.CompassUsername))
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
        ) AS sr
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
            WHERE d.StudentKey = sr.StudentKey
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
            v.IssueCode, v.IssueMessage, v.IsBlocking
        FROM #Resolved AS r
        CROSS APPLY
        (
            VALUES
            (
                CASE WHEN r.StudentKey IS NULL THEN 1 ELSE 0 END,
                'STUDENT_UNMATCHED',
                N'No unique CompassPersonId or exact unique Gold Username match was found; StudentKey left NULL.',
                CONVERT(bit, 0)
            ),
            (
                CASE WHEN r.CompassCandidateCount = 1 AND r.UsernameCandidateCount = 1
                      AND r.CompassCandidateStudentKey <> r.UsernameCandidateStudentKey
                     THEN 1 ELSE 0 END,
                'STUDENT_IDENTIFIER_CONFLICT',
                N'CompassPersonId and exact Username resolve to different Gold students; CompassPersonId was used.',
                CONVERT(bit, 0)
            ),
            (
                CASE WHEN r.ResolutionMethod = N'USERNAME_EXACT_UNIQUE'
                      AND NULLIF(LTRIM(RTRIM(r.CompassPersonId)), N'') IS NOT NULL
                     THEN 1 ELSE 0 END,
                'COMPASS_ID_UNRESOLVED_USERNAME_FALLBACK',
                N'CompassPersonId did not resolve uniquely; an exact unique Username fallback was used.',
                CONVERT(bit, 0)
            ),
            (
                CASE WHEN NULLIF(LTRIM(RTRIM(r.ClassName)), N'') IS NOT NULL
                      AND r.ClassCandidateCount <> 1
                     THEN 1 ELSE 0 END,
                'CLASS_UNRESOLVED',
                N'ClassName did not resolve to exactly one current gold.dimClass row; ClassKey left NULL.',
                CONVERT(bit, 0)
            ),
            (
                CASE WHEN r.StudentKey IS NOT NULL AND r.HomeCampus IS NOT NULL
                      AND r.CampusCandidateCount <> 1
                     THEN 1 ELSE 0 END,
                'CAMPUS_UNRESOLVED',
                N'Resolved student HomeCampus did not map uniquely to gold.dimCampus.CompassCampusId; CampusKey left NULL.',
                CONVERT(bit, 0)
            ),
            (
                CASE WHEN r.EssentialAssessmentKey IS NULL
                      AND NOT EXISTS (SELECT 1 FROM #Issue AS i WHERE i.SilverBusinessKey = r.SilverBusinessKey AND i.IsBlocking = 1)
                     THEN 1 ELSE 0 END,
                'ASSESSMENT_KEY_UNRESOLVED',
                N'No gold.dimEssentialAssessment row was found for the validated assessment attributes.',
                CONVERT(bit, 1)
            ),
            (
                CASE WHEN EXISTS
                          (
                              SELECT 1
                              FROM gold.factEssentialAssessment AS f
                              WHERE f.SilverBusinessKey = r.SilverBusinessKey
                                AND (f.SourceRowHash <> r.SourceRowHash
                                     OR ISNULL(f.StudentKey, CONVERT(bigint, -1)) <> ISNULL(r.StudentKey, CONVERT(bigint, -1)))
                          )
                     THEN 1 ELSE 0 END,
                'SOURCE_CHANGE_NOT_APPLIED',
                N'The Silver row or its resolved student key differs from the existing fact. Insert-only policy left Gold unchanged.',
                CONVERT(bit, 0)
            )
        ) AS v (IsIssue, IssueCode, IssueMessage, IsBlocking)
        WHERE v.IsIssue = 1;

        INSERT gold.factEssentialAssessment
        (
            SilverBusinessKey, SourceKey, SourceSystem, SourceFileName, SourceRowNumber,
            StudentKey, EssentialAssessmentKey, AssessmentDateKey, ClassKey, CampusKey,
            StudentSourceId, ExternalStudentId, CompassUsername, StudentResolutionMethod,
            SourceMatchMethod, SourceMatchScore, SourceMatchStatus, AssessmentDate,
            AssessmentType, TestName, YearLevel, ClassName, Strand, FocusArea,
            AssessmentPercentage, AssessmentRange, AchievementLevel, AssessmentINLP,
            StrandAverageAchievementLevel, Growth, DataQualityNotes, SourceRowHash,
            SourceLoadedAtUtc
        )
        SELECT
            r.SilverBusinessKey, r.SourceKey, r.SourceSystem, r.SourceFileName, r.SourceRowNumber,
            r.StudentKey, r.EssentialAssessmentKey, r.AssessmentDateKey,
            CASE WHEN r.ClassCandidateCount = 1 THEN r.ClassKey END,
            CASE WHEN r.CampusCandidateCount = 1 THEN r.CampusKey END,
            r.StudentSourceId, r.ExternalStudentId, r.CompassUsername, r.ResolutionMethod,
            r.MatchMethod, r.MatchScore, r.MatchStatus, r.AssessmentDate,
            r.AssessmentType, r.TestName, r.YearLevel, r.ClassName, r.Strand, r.FocusArea,
            r.AssessmentPercentage, r.AssessmentRange, r.AchievementLevel, r.AssessmentINLP,
            r.StrandAverageAchievementLevel, r.Growth, r.DataQualityNotes, r.SourceRowHash,
            r.LoadedAtUtc
        FROM #Resolved AS r
        WHERE r.EssentialAssessmentKey IS NOT NULL
          AND r.AssessmentDateKey IS NOT NULL
          AND NOT EXISTS
              (
                  SELECT 1 FROM #Issue AS i
                  WHERE i.SilverBusinessKey = r.SilverBusinessKey
                    AND i.IsBlocking = 1
              )
          AND NOT EXISTS
              (
                  SELECT 1
                  FROM gold.factEssentialAssessment AS f WITH (UPDLOCK, HOLDLOCK)
                  WHERE f.SilverBusinessKey = r.SilverBusinessKey
              );

        SET @InsertedRowCount = @@ROWCOUNT;

        SELECT @NewWatermark = MAX(LoadedAtUtc) FROM #Stage;

        IF @NewWatermark IS NOT NULL
           AND (@WatermarkUTC IS NULL OR @NewWatermark >= @WatermarkUTC)
        BEGIN
            IF EXISTS (SELECT 1 FROM metadata.etl_watermark WHERE endpoint_key = @EndpointKey)
                UPDATE metadata.etl_watermark
                SET watermark_value = CONVERT(nvarchar(33), @NewWatermark, 126),
                    updated_at_utc = SYSUTCDATETIME(),
                    last_success_batch_id = NEWID()
                WHERE endpoint_key = @EndpointKey;
            ELSE
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

        SELECT @IssueCount = COUNT_BIG(*) FROM #Issue;
        SELECT @RejectedRowCount = COUNT_BIG(DISTINCT SilverBusinessKey)
        FROM #Issue
        WHERE IsBlocking = 1;
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
            THROW 51013, N'The EssentialAssessment load audit row could not be located after writing it.', 1;

        INSERT gold.EssentialAssessmentLoadIssue
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
                LEFT(CONCAT(N'EssentialAssessment load failed: ', @ErrorMessage,
                            N'; failure audit also failed: ', @AuditErrorMessage), 4000);
            THROW 51014, @CombinedErrorMessage, 1;
        END;

        THROW;
    END CATCH;
END;
GO
