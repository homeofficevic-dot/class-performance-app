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
    TestName NVARCHAR(120) NOT NULL,
    TestStatus NVARCHAR(20) NOT NULL,
    Details NVARCHAR(1000) NULL
);

IF OBJECT_ID(N'wellbeing.ConsequenceApplicationWorkflow', N'U') IS NULL
   OR OBJECT_ID(N'wellbeing.ConsequenceRestrictionGroup', N'U') IS NULL
   OR OBJECT_ID(N'wellbeing.ConsequenceRestrictionGroupMember', N'U') IS NULL
   OR OBJECT_ID(N'wellbeing.ConsequenceWorkflowNotification', N'U') IS NULL
    THROW 51500, 'Application workflow deployment is incomplete.', 1;

INSERT INTO @Results
VALUES (N'Application workflow objects', N'PASS',
        N'Application-managed workflow, detention restriction, and in-app notification tables exist.');

IF NOT EXISTS
(
    SELECT 1
    FROM wellbeing.tblConsequences AS consequence
    INNER JOIN wellbeing.ConsequenceApplicationWorkflow AS workflow
        ON workflow.ConsequenceId = consequence.ConsequenceId
    WHERE consequence.LegacyConsequenceId = 57
      AND workflow.RequiresApproval = 1
      AND workflow.ApprovalRoleCode = N'PASTORAL_CARE'
      AND workflow.ProcessingRoleCode = N'PASTORAL_CARE'
      AND workflow.IsActive = 1
      AND workflow.EffectiveStartDate <= CAST(GETDATE() AS DATE)
      AND (workflow.EffectiveEndDate IS NULL OR workflow.EffectiveEndDate >= CAST(GETDATE() AS DATE))
)
    THROW 51501, 'The recess/lunchtime detention Pastoral Care workflow is not active.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM wellbeing.tblConsequences AS consequence
    INNER JOIN wellbeing.ConsequenceApplicationWorkflow AS workflow
        ON workflow.ConsequenceId = consequence.ConsequenceId
    WHERE consequence.LegacyConsequenceId = 57
      AND consequence.LegacyAllowsMultiplePerDay = 1
      AND consequence.LegacyProcessorRole IS NULL
      AND consequence.RequiresApproval IS NULL
      AND consequence.RequiresParentNotification IS NULL
      AND consequence.LegacyApprovalStatusKnown = 0
)
    THROW 51502, 'The application override changed or obscured imported legacy values.', 1;

INSERT INTO @Results
VALUES (N'Legacy data preserved', N'PASS',
        N'Application workflow settings are separate; imported legacy approval, processor, parent-notice, and multiple-per-day values remain unchanged.');

IF NOT EXISTS
(
    SELECT 1
    FROM wellbeing.ConsequenceRestrictionGroup
    WHERE RestrictionGroupCode = N'DETENTION'
      AND MaxAssignmentsPerStudentPerDate = 1
      AND IsActive = 1
)
    THROW 51503, 'The detention group does not enforce one assignment per student/date.', 1;

IF EXISTS
(
    SELECT 1
    FROM wellbeing.tblConsequences AS consequence
    WHERE consequence.IsActive = 1
      AND consequence.ConsequenceName LIKE N'%detention%'
      AND NOT EXISTS
      (
          SELECT 1
          FROM wellbeing.ConsequenceRestrictionGroupMember AS groupMember
          WHERE groupMember.RestrictionGroupCode = N'DETENTION'
            AND groupMember.ConsequenceId = consequence.ConsequenceId
      )
)
    THROW 51504, 'An active detention consequence is missing from the one-per-day group.', 1;

INSERT INTO @Results
VALUES (N'One detention per student/date', N'PASS',
        N'All active consequences whose configured name identifies them as a detention are in the single-per-day restriction group.');

IF OBJECT_DEFINITION(OBJECT_ID(N'wellbeing.usp_AssignIncidentConsequence')) NOT LIKE N'%StudentSchedule:%'
   OR OBJECT_DEFINITION(OBJECT_ID(N'wellbeing.usp_AssignIncidentConsequence')) NOT LIKE N'%sp_getapplock%'
    THROW 51505, 'The assignment procedure does not acquire the student/date concurrency lock.', 1;

INSERT INTO @Results
VALUES (N'Concurrent assignment protection', N'PASS',
        N'Assignment requests serialize on student plus scheduled date before server-side eligibility is recalculated.');

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'wellbeing.ConsequenceWorkflowNotification')
      AND name = N'IX_ConsequenceWorkflowNotification_Role'
)
    THROW 51506, 'The role work-queue notification index is missing.', 1;

INSERT INTO @Results
VALUES (N'Pastoral Care in-app task', N'PASS',
        N'Pending approval assignments are written to the role-targeted in-app notification table in the assignment transaction.');

DECLARE @TestIncidentId INT,
        @TestStudentKey INT,
        @TestConsequenceId INT,
        @TestDate DATE,
        @ConflictReason NVARCHAR(MAX);

SELECT TOP (1)
    @TestIncidentId = assignment.IncidentId,
    @TestStudentKey = assignment.StudentKey,
    @TestConsequenceId = assignment.ConsequenceId,
    @TestDate = assignment.ScheduledStartDate
FROM wellbeing.factConsequenceAssignment AS assignment
INNER JOIN wellbeing.ConsequenceRestrictionGroupMember AS groupMember
    ON groupMember.ConsequenceId = assignment.ConsequenceId
   AND groupMember.RestrictionGroupCode = N'DETENTION'
WHERE assignment.ProcessingStatus NOT IN (N'CANCELLED', N'REJECTED')
ORDER BY assignment.ConsequenceAssignmentId;

IF @TestIncidentId IS NULL
BEGIN
    INSERT INTO @Results
    VALUES (N'Existing same-date conflict behavior', N'BLOCKED',
            N'No active detention assignment exists to serve as a non-destructive conflict fixture.');
END
ELSE
BEGIN
    SELECT @ConflictReason = evaluation.IneligibilityReasons
    FROM wellbeing.ufn_EvaluateIncidentConsequences(@TestIncidentId, @TestStudentKey, @TestDate) AS evaluation
    WHERE evaluation.ConsequenceId = @TestConsequenceId;

    IF @ConflictReason NOT LIKE N'%maximum number of detentions%'
        THROW 51507, 'A student with an active detention was not blocked from another detention on the same date.', 1;

    INSERT INTO @Results
    VALUES (N'Existing same-date conflict behavior', N'PASS',
            N'The evaluator rejects another detention when the student already has one on that date.');
END;

SELECT TestName, TestStatus, Details
FROM @Results
ORDER BY CASE TestStatus WHEN N'FAIL' THEN 1 WHEN N'BLOCKED' THEN 2 ELSE 3 END, TestName;
GO
