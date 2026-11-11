USE SchoolDW;
GO

SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

DECLARE @Results TABLE
(
    TestName NVARCHAR(100) NOT NULL,
    TestStatus NVARCHAR(20) NOT NULL,
    Details NVARCHAR(1000) NULL
);

IF OBJECT_ID(N'wellbeing.ufn_EvaluateIncidentConsequences', N'IF') IS NULL
   OR OBJECT_ID(N'wellbeing.usp_GetEligibleIncidentConsequences', N'P') IS NULL
   OR OBJECT_ID(N'wellbeing.usp_AssignIncidentConsequence', N'P') IS NULL
   OR OBJECT_ID(N'wellbeing.usp_TransitionIncidentConsequence', N'P') IS NULL
   OR OBJECT_ID(N'wellbeing.ConsequenceDecisionAudit', N'U') IS NULL
   OR OBJECT_ID(N'wellbeing.ConsequenceRoleAssignment', N'U') IS NULL
   OR OBJECT_ID(N'wellbeing.ConsequenceCalendarRule', N'U') IS NULL
   OR OBJECT_ID(N'wellbeing.ConsequenceApplicationWorkflow', N'U') IS NULL
   OR OBJECT_ID(N'wellbeing.ConsequenceRestrictionGroup', N'U') IS NULL
   OR OBJECT_ID(N'wellbeing.ConsequenceRestrictionGroupMember', N'U') IS NULL
   OR OBJECT_ID(N'wellbeing.ConsequenceWorkflowNotification', N'U') IS NULL
    THROW 51300, 'Consequence engine deployment is incomplete.', 1;

INSERT INTO @Results VALUES
    (N'Deployed SQL objects', N'PASS', N'Eligibility function, assignment/workflow procedures, and audit/configuration tables exist.');

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'wellbeing.factConsequenceAssignment')
      AND name = N'UX_factConsequenceAssignment_IdempotencyKey'
      AND is_unique = 1
)
    THROW 51301, 'The unique idempotency index is missing.', 1;
IF NOT EXISTS
(
    SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'wellbeing.ConsequenceDecisionAudit')
      AND name = N'FK_ConsequenceDecisionAudit_IncidentStudent'
      AND is_not_trusted = 0
)
    THROW 51304, 'The consequence audit student relationship is missing or untrusted.', 1;

INSERT INTO @Results VALUES
    (N'Idempotency and audit constraints', N'PASS', N'The unique idempotency index and trusted incident/student audit foreign key exist.');

DECLARE @ExpectedError INT = NULL;
BEGIN TRY
    EXEC wellbeing.usp_GetEligibleIncidentConsequences
        @IncidentId = -1,
        @StudentKey = -1,
        @ProposedDate = '2026-03-10';
END TRY
BEGIN CATCH
    SET @ExpectedError = ERROR_NUMBER();
END CATCH;

IF @ExpectedError <> 51201
    THROW 51302, 'Invalid incident/student lookup did not fail with the expected validation error.', 1;

INSERT INTO @Results VALUES
    (N'Invalid incident/student', N'PASS', N'The eligibility procedure rejected an unlinked student with error 51201.');

DECLARE @TestIncidentId INT,
        @TestStudentKey INT,
        @TestIncidentTypeId INT,
        @TestClassificationId INT,
        @CandidateCount INT,
        @EligibleCount INT,
        @IneligibilityReasons NVARCHAR(MAX);

SELECT TOP (1)
    @TestIncidentId = incident.IncidentId,
    @TestStudentKey = studentLink.StudentKey
FROM wellbeing.factBehaviourIncident AS incident
INNER JOIN wellbeing.IncidentStudent AS studentLink
    ON studentLink.IncidentId = incident.IncidentId
WHERE incident.IsDeleted = 0
  AND (studentLink.YearLevelResolutionStatus IS NULL
       OR studentLink.YearLevelResolutionStatus <> N'VERIFIED'
       OR studentLink.StudentYearLevelAtIncident IS NULL)
ORDER BY incident.IncidentId;

SELECT TOP (1)
    @TestIncidentTypeId = mapping.IncidentTypeId,
    @TestClassificationId = mapping.ClassificationId
FROM wellbeing.IncidentTypeConsequence AS mapping
ORDER BY mapping.IncidentTypeId, mapping.ClassificationId;

IF @TestIncidentId IS NOT NULL AND @TestIncidentTypeId IS NOT NULL
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
        UPDATE wellbeing.factBehaviourIncident
        SET IncidentTypeId = @TestIncidentTypeId,
            ClassificationId = @TestClassificationId
        WHERE IncidentId = @TestIncidentId;

        SELECT @CandidateCount = COUNT(*),
               @EligibleCount = COALESCE(SUM(CONVERT(INT, evaluation.IsEligible)), 0),
               @IneligibilityReasons = MAX(evaluation.IneligibilityReasons)
        FROM wellbeing.ufn_EvaluateIncidentConsequences
            (@TestIncidentId, @TestStudentKey, CAST(GETDATE() AS DATE)) AS evaluation;

        IF @CandidateCount = 0
           OR @EligibleCount > 0
           OR @IneligibilityReasons NOT LIKE N'%Historical year level is not verified%'
            THROW 51303, 'The unresolved historical year-level fixture was not correctly blocked.', 1;

        ROLLBACK TRANSACTION;
        INSERT INTO @Results VALUES
            (N'Historical year-level fail-closed', N'PASS',
             N'A mapped incident with an unresolved snapshot produced candidates, but none were eligible.');
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END
ELSE
    INSERT INTO @Results VALUES
        (N'Historical year-level fail-closed', N'BLOCKED',
         N'No unresolved incident/student and mapped consequence fixture were available.');

IF EXISTS
(
    SELECT 1 FROM wellbeing.IncidentStudent
    WHERE YearLevelResolutionStatus = N'VERIFIED'
      AND StudentYearLevelAtIncident IS NOT NULL
)
BEGIN
    INSERT INTO @Results VALUES
        (N'Eligible assignment/workflow fixture', N'BLOCKED',
         N'At least one verified snapshot exists; run the controlled assignment, idempotency, workflow, and concurrent-request tests against a separately approved fixture.');
END
ELSE
BEGIN
    INSERT INTO @Results VALUES
        (N'Eligible assignment/workflow fixture', N'BLOCKED',
         N'No verified incident year-level snapshots exist. Valid assignments, transitions, duplicate-per-day, role resolution, and concurrency cannot be exercised without verified fixture data.');
END;

SELECT TestName, TestStatus, Details
FROM @Results
ORDER BY CASE TestStatus WHEN N'FAIL' THEN 1 WHEN N'BLOCKED' THEN 2 ELSE 3 END, TestName;
GO
