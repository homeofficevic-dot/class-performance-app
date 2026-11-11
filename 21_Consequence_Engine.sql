USE SchoolDW;
GO

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF COL_LENGTH(N'wellbeing.factConsequenceAssignment', N'ProcessingStatus') IS NULL
    ALTER TABLE wellbeing.factConsequenceAssignment ADD ProcessingStatus NVARCHAR(30) NOT NULL
        CONSTRAINT DF_factConsequenceAssignment_ProcessingStatus DEFAULT N'PENDING';
IF COL_LENGTH(N'wellbeing.factConsequenceAssignment', N'AssignedRoleCode') IS NULL
    ALTER TABLE wellbeing.factConsequenceAssignment ADD AssignedRoleCode NVARCHAR(50) NULL;
IF COL_LENGTH(N'wellbeing.factConsequenceAssignment', N'AssignedStaffKey') IS NULL
    ALTER TABLE wellbeing.factConsequenceAssignment ADD AssignedStaffKey INT NULL;
IF COL_LENGTH(N'wellbeing.factConsequenceAssignment', N'RoleResolutionStatus') IS NULL
    ALTER TABLE wellbeing.factConsequenceAssignment ADD RoleResolutionStatus NVARCHAR(40) NULL;
IF COL_LENGTH(N'wellbeing.factConsequenceAssignment', N'StudentYearLevelAtIncident') IS NULL
    ALTER TABLE wellbeing.factConsequenceAssignment ADD StudentYearLevelAtIncident NVARCHAR(50) NULL;
IF COL_LENGTH(N'wellbeing.factConsequenceAssignment', N'RuleVersion') IS NULL
    ALTER TABLE wellbeing.factConsequenceAssignment ADD RuleVersion NVARCHAR(40) NOT NULL
        CONSTRAINT DF_factConsequenceAssignment_RuleVersion DEFAULT N'LEGACY_REFERENCE_V1';
IF COL_LENGTH(N'wellbeing.factConsequenceAssignment', N'RulesAppliedJson') IS NULL
    ALTER TABLE wellbeing.factConsequenceAssignment ADD RulesAppliedJson NVARCHAR(MAX) NULL;
IF COL_LENGTH(N'wellbeing.factConsequenceAssignment', N'ApprovalConfigurationKnown') IS NULL
    ALTER TABLE wellbeing.factConsequenceAssignment ADD ApprovalConfigurationKnown BIT NOT NULL
        CONSTRAINT DF_factConsequenceAssignment_ApprovalConfigurationKnown DEFAULT 0;
IF COL_LENGTH(N'wellbeing.factConsequenceAssignment', N'WorkflowNotes') IS NULL
    ALTER TABLE wellbeing.factConsequenceAssignment ADD WorkflowNotes NVARCHAR(MAX) NULL;
IF COL_LENGTH(N'wellbeing.factConsequenceAssignment', N'IdempotencyKey') IS NULL
    ALTER TABLE wellbeing.factConsequenceAssignment ADD IdempotencyKey UNIQUEIDENTIFIER NULL;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'wellbeing.factConsequenceAssignment')
      AND name = N'FK_factConsequenceAssignment_AssignedStaff'
)
    ALTER TABLE wellbeing.factConsequenceAssignment WITH CHECK
        ADD CONSTRAINT FK_factConsequenceAssignment_AssignedStaff
        FOREIGN KEY (AssignedStaffKey) REFERENCES gold.dimStaff(StaffKey);
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'wellbeing.factConsequenceAssignment')
      AND name = N'UX_factConsequenceAssignment_IdempotencyKey'
)
    CREATE UNIQUE INDEX UX_factConsequenceAssignment_IdempotencyKey
        ON wellbeing.factConsequenceAssignment(IdempotencyKey)
        WHERE IdempotencyKey IS NOT NULL;
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'wellbeing.factConsequenceAssignment')
      AND name = N'IX_factConsequenceAssignment_StudentSchedule'
)
    CREATE INDEX IX_factConsequenceAssignment_StudentSchedule
        ON wellbeing.factConsequenceAssignment(StudentKey, ConsequenceId, ScheduledStartDate, ProcessingStatus);
GO

IF OBJECT_ID(N'wellbeing.ConsequenceRoleAssignment', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.ConsequenceRoleAssignment
    (
        ConsequenceRoleAssignmentId BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_ConsequenceRoleAssignment PRIMARY KEY,
        ConsequenceId INT NULL,
        IncidentRoleId INT NOT NULL,
        StaffKey INT NOT NULL,
        AssignmentType NVARCHAR(20) NOT NULL,
        EffectiveFrom DATE NOT NULL,
        EffectiveTo DATE NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_ConsequenceRoleAssignment_IsActive DEFAULT 1,
        DelegationReason NVARCHAR(500) NULL,
        CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_ConsequenceRoleAssignment_CreatedDate DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(200) NOT NULL,
        CONSTRAINT FK_ConsequenceRoleAssignment_Consequence FOREIGN KEY (ConsequenceId)
            REFERENCES wellbeing.tblConsequences(ConsequenceId),
        CONSTRAINT FK_ConsequenceRoleAssignment_Role FOREIGN KEY (IncidentRoleId)
            REFERENCES wellbeing.IncidentRole(IncidentRoleId),
        CONSTRAINT FK_ConsequenceRoleAssignment_Staff FOREIGN KEY (StaffKey)
            REFERENCES gold.dimStaff(StaffKey),
        CONSTRAINT CK_ConsequenceRoleAssignment_Type CHECK (AssignmentType IN (N'PRIMARY', N'DELEGATE')),
        CONSTRAINT CK_ConsequenceRoleAssignment_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
    );
    CREATE INDEX IX_ConsequenceRoleAssignment_Resolution
        ON wellbeing.ConsequenceRoleAssignment(IncidentRoleId, ConsequenceId, AssignmentType, EffectiveFrom, EffectiveTo)
        INCLUDE (StaffKey, IsActive);
END;
GO

IF OBJECT_ID(N'wellbeing.ConsequenceApplicationWorkflow', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.ConsequenceApplicationWorkflow
    (
        ConsequenceId INT NOT NULL
            CONSTRAINT PK_ConsequenceApplicationWorkflow PRIMARY KEY,
        RequiresApproval BIT NOT NULL,
        ApprovalRoleCode NVARCHAR(50) NULL,
        ProcessingRoleCode NVARCHAR(50) NULL,
        WorkflowDescription NVARCHAR(500) NOT NULL,
        EffectiveStartDate DATE NOT NULL,
        EffectiveEndDate DATE NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_ConsequenceApplicationWorkflow_IsActive DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_ConsequenceApplicationWorkflow_CreatedDate DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(200) NOT NULL,
        ModifiedDate DATETIME2 NULL,
        ModifiedBy NVARCHAR(200) NULL,
        CONSTRAINT FK_ConsequenceApplicationWorkflow_Consequence FOREIGN KEY (ConsequenceId)
            REFERENCES wellbeing.tblConsequences(ConsequenceId),
        CONSTRAINT CK_ConsequenceApplicationWorkflow_Roles CHECK
            (RequiresApproval = 0 OR NULLIF(LTRIM(RTRIM(ApprovalRoleCode)), N'') IS NOT NULL),
        CONSTRAINT CK_ConsequenceApplicationWorkflow_Dates CHECK
            (EffectiveEndDate IS NULL OR EffectiveEndDate >= EffectiveStartDate)
    );
    CREATE INDEX IX_ConsequenceApplicationWorkflow_ActiveDate
        ON wellbeing.ConsequenceApplicationWorkflow(IsActive, EffectiveStartDate, EffectiveEndDate)
        INCLUDE (ConsequenceId, RequiresApproval, ApprovalRoleCode, ProcessingRoleCode);
END;
GO

IF OBJECT_ID(N'wellbeing.ConsequenceRestrictionGroup', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.ConsequenceRestrictionGroup
    (
        RestrictionGroupCode NVARCHAR(50) NOT NULL
            CONSTRAINT PK_ConsequenceRestrictionGroup PRIMARY KEY,
        RestrictionGroupName NVARCHAR(100) NOT NULL,
        MaxAssignmentsPerStudentPerDate INT NOT NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_ConsequenceRestrictionGroup_IsActive DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_ConsequenceRestrictionGroup_CreatedDate DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(200) NOT NULL,
        CONSTRAINT CK_ConsequenceRestrictionGroup_MaxAssignments CHECK
            (MaxAssignmentsPerStudentPerDate > 0)
    );
END;
GO

IF OBJECT_ID(N'wellbeing.ConsequenceRestrictionGroupMember', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.ConsequenceRestrictionGroupMember
    (
        RestrictionGroupCode NVARCHAR(50) NOT NULL,
        ConsequenceId INT NOT NULL,
        CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_ConsequenceRestrictionGroupMember_CreatedDate DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(200) NOT NULL,
        CONSTRAINT PK_ConsequenceRestrictionGroupMember PRIMARY KEY (RestrictionGroupCode, ConsequenceId),
        CONSTRAINT FK_ConsequenceRestrictionGroupMember_Group FOREIGN KEY (RestrictionGroupCode)
            REFERENCES wellbeing.ConsequenceRestrictionGroup(RestrictionGroupCode),
        CONSTRAINT FK_ConsequenceRestrictionGroupMember_Consequence FOREIGN KEY (ConsequenceId)
            REFERENCES wellbeing.tblConsequences(ConsequenceId)
    );
    CREATE INDEX IX_ConsequenceRestrictionGroupMember_Consequence
        ON wellbeing.ConsequenceRestrictionGroupMember(ConsequenceId, RestrictionGroupCode);
END;
GO

IF OBJECT_ID(N'wellbeing.ConsequenceDecisionAudit', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.ConsequenceDecisionAudit
    (
        ConsequenceDecisionAuditId BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_ConsequenceDecisionAudit PRIMARY KEY,
        ConsequenceAssignmentId INT NULL,
        IncidentId INT NOT NULL,
        StudentKey INT NOT NULL,
        StudentYearLevelAtIncident NVARCHAR(50) NULL,
        ConsequenceId INT NULL,
        Decision NVARCHAR(40) NOT NULL,
        RulesAppliedJson NVARCHAR(MAX) NULL,
        AssignedRoleCode NVARCHAR(50) NULL,
        AssignedStaffKey INT NULL,
        Actor NVARCHAR(255) NOT NULL,
        EventDate DATETIME2 NOT NULL CONSTRAINT DF_ConsequenceDecisionAudit_EventDate DEFAULT SYSUTCDATETIME(),
        Notes NVARCHAR(1000) NULL,
        CONSTRAINT FK_ConsequenceDecisionAudit_Assignment FOREIGN KEY (ConsequenceAssignmentId)
            REFERENCES wellbeing.factConsequenceAssignment(ConsequenceAssignmentId),
        CONSTRAINT FK_ConsequenceDecisionAudit_Incident FOREIGN KEY (IncidentId)
            REFERENCES wellbeing.factBehaviourIncident(IncidentId),
        CONSTRAINT FK_ConsequenceDecisionAudit_IncidentStudent FOREIGN KEY (IncidentId, StudentKey)
            REFERENCES wellbeing.IncidentStudent(IncidentId, StudentKey),
        CONSTRAINT FK_ConsequenceDecisionAudit_Consequence FOREIGN KEY (ConsequenceId)
            REFERENCES wellbeing.tblConsequences(ConsequenceId),
        CONSTRAINT FK_ConsequenceDecisionAudit_AssignedStaff FOREIGN KEY (AssignedStaffKey)
            REFERENCES gold.dimStaff(StaffKey)
    );
    CREATE INDEX IX_ConsequenceDecisionAudit_Incident
        ON wellbeing.ConsequenceDecisionAudit(IncidentId, EventDate DESC);
    CREATE INDEX IX_ConsequenceDecisionAudit_Student
        ON wellbeing.ConsequenceDecisionAudit(StudentKey, EventDate DESC);
END;
GO

IF NOT EXISTS
(
    SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'wellbeing.ConsequenceDecisionAudit')
      AND name = N'FK_ConsequenceDecisionAudit_IncidentStudent'
)
    ALTER TABLE wellbeing.ConsequenceDecisionAudit WITH CHECK
        ADD CONSTRAINT FK_ConsequenceDecisionAudit_IncidentStudent
        FOREIGN KEY (IncidentId, StudentKey)
        REFERENCES wellbeing.IncidentStudent(IncidentId, StudentKey);
GO

IF OBJECT_ID(N'wellbeing.ConsequenceWorkflowNotification', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.ConsequenceWorkflowNotification
    (
        ConsequenceWorkflowNotificationId BIGINT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_ConsequenceWorkflowNotification PRIMARY KEY,
        ConsequenceAssignmentId INT NOT NULL,
        RoleCode NVARCHAR(50) NOT NULL,
        NotificationType NVARCHAR(40) NOT NULL,
        Channel NVARCHAR(20) NOT NULL,
        CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_ConsequenceWorkflowNotification_CreatedDate DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(200) NOT NULL,
        CONSTRAINT FK_ConsequenceWorkflowNotification_Assignment FOREIGN KEY (ConsequenceAssignmentId)
            REFERENCES wellbeing.factConsequenceAssignment(ConsequenceAssignmentId),
        CONSTRAINT UQ_ConsequenceWorkflowNotification_AssignmentRoleType
            UNIQUE (ConsequenceAssignmentId, RoleCode, NotificationType)
    );
    CREATE INDEX IX_ConsequenceWorkflowNotification_Role
        ON wellbeing.ConsequenceWorkflowNotification(RoleCode, CreatedDate DESC)
        INCLUDE (ConsequenceAssignmentId, NotificationType, Channel);
END;
GO

IF OBJECT_ID(N'wellbeing.ConsequenceCalendarRule', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.ConsequenceCalendarRule
    (
        ConsequenceCalendarRuleId INT IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_ConsequenceCalendarRule PRIMARY KEY,
        ConsequenceId INT NOT NULL,
        RequiresSchoolDay BIT NOT NULL,
        EffectiveStartDate DATE NOT NULL,
        EffectiveEndDate DATE NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_ConsequenceCalendarRule_IsActive DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_ConsequenceCalendarRule_CreatedDate DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(200) NOT NULL,
        CONSTRAINT FK_ConsequenceCalendarRule_Consequence FOREIGN KEY (ConsequenceId)
            REFERENCES wellbeing.tblConsequences(ConsequenceId),
        CONSTRAINT CK_ConsequenceCalendarRule_Dates CHECK
            (EffectiveEndDate IS NULL OR EffectiveEndDate >= EffectiveStartDate)
    );
    CREATE INDEX IX_ConsequenceCalendarRule_ActiveDate
        ON wellbeing.ConsequenceCalendarRule(ConsequenceId, IsActive, EffectiveStartDate, EffectiveEndDate)
        INCLUDE (RequiresSchoolDay);
END;
GO

CREATE OR ALTER FUNCTION wellbeing.ufn_EvaluateIncidentConsequences
(
    @IncidentId INT,
    @StudentKey INT,
    @ProposedDate DATE
)
RETURNS TABLE
AS
RETURN
(
    WITH Context AS
    (
        SELECT
            incident.IncidentId,
            incident.StudentKey,
            incident.IncidentDate,
            incident.IncidentTypeId,
            incident.ClassificationId,
            incident.PolicyLevelId AS IncidentPolicyLevelId,
            incident.LegacyIncidentLevel,
            studentLink.StudentYearLevelAtIncident,
            studentLink.StudentYearLevelIdAtIncident,
            studentLink.YearLevelResolutionStatus,
            TRY_CONVERT(INT, NULLIF(LTRIM(RTRIM(
                REPLACE(UPPER(studentLink.StudentYearLevelAtIncident), N'YEAR', N'')
            )), N'')) AS StudentYearLevelNumber
        FROM wellbeing.factBehaviourIncident AS incident
        INNER JOIN wellbeing.IncidentStudent AS studentLink
            ON studentLink.IncidentId = incident.IncidentId
           AND studentLink.StudentKey = @StudentKey
        WHERE incident.IncidentId = @IncidentId
          AND incident.IsDeleted = 0
    ),
    Candidates AS
    (
        SELECT
            context.IncidentId,
            context.StudentKey,
            context.IncidentDate,
            context.IncidentTypeId,
            context.ClassificationId,
            context.LegacyIncidentLevel,
            context.StudentYearLevelAtIncident,
            context.StudentYearLevelIdAtIncident,
            context.YearLevelResolutionStatus,
            context.StudentYearLevelNumber,
            consequence.ConsequenceId,
            consequence.LegacyConsequenceId,
            consequence.ConsequenceName,
            consequence.ConsequenceDescription,
            consequence.PolicyLevelId,
            consequence.SeverityLevel,
            consequence.RequiresApproval,
            consequence.ApprovalRoleRequired,
            consequence.RequiresParentNotification,
            consequence.LegacyAllowsMultiplePerDay,
            consequence.LegacyLength,
            consequence.LegacyProcessorRole,
            consequence.LegacyApprovalStatusKnown,
            appWorkflow.RequiresApproval AS ApplicationRequiresApproval,
            appWorkflow.ApprovalRoleCode AS ApplicationApprovalRoleCode,
            appWorkflow.ProcessingRoleCode AS ApplicationProcessingRoleCode,
            appWorkflow.WorkflowDescription AS ApplicationWorkflowDescription,
            COALESCE(dailyLimit.MaxAssignmentsPerStudentPerDate, 0) AS ApplicationMaxAssignmentsPerStudentPerDate,
            CONVERT(bit, CASE WHEN dailyLimit.MaxAssignmentsPerStudentPerDate = 1 THEN 1 ELSE 0 END) AS ApplicationSinglePerDay,
            COALESCE(calendarRule.RequiresSchoolDay, CONVERT(bit, 0)) AS RequiresSchoolDay,
            CONVERT(bit, CASE WHEN calendarRule.RuleCount > 0 THEN 1 ELSE 0 END) AS CalendarRuleConfigured,
            COALESCE(policy.ApprovalRequired, appWorkflow.RequiresApproval, consequence.RequiresApproval, CONVERT(bit, 0)) AS EffectiveRequiresApproval,
            CONVERT(bit, CASE WHEN consequence.LegacyApprovalStatusKnown = 1
                                   OR appWorkflow.ConsequenceId IS NOT NULL
                                   OR consequence.RequiresApproval = 1
                                   OR policy.ApprovalConfigurationKnown = 1
                              THEN 1 ELSE 0 END) AS ApprovalConfigurationKnown,
            roleConfig.AssignedRoleCode,
            CASE
                WHEN primaryStaff.StaffCount = 1 THEN primaryStaff.StaffKey
                WHEN primaryStaff.StaffCount > 1 THEN NULL
                WHEN delegateStaff.StaffCount = 1 THEN delegateStaff.StaffKey
                WHEN delegateStaff.StaffCount > 1 THEN NULL
                WHEN globalStaff.StaffCount = 1 THEN globalStaff.StaffKey
                ELSE NULL
            END AS AssignedStaffKey,
            CASE
                WHEN roleConfig.AssignedRoleCode IS NULL THEN N'UNASSIGNED_ROLE'
                WHEN primaryStaff.StaffCount > 1 THEN N'PRIMARY_STAFF_CONFLICT'
                WHEN primaryStaff.StaffCount = 1 THEN N'PRIMARY'
                WHEN delegateStaff.StaffCount > 1 THEN N'DELEGATE_STAFF_CONFLICT'
                WHEN delegateStaff.StaffCount = 1 THEN N'DELEGATED'
                WHEN globalStaff.StaffCount > 1 THEN N'ROLE_STAFF_CONFLICT'
                WHEN globalStaff.StaffCount = 1 THEN N'ROLE_ASSIGNED'
                ELSE N'UNASSIGNED_STAFF'
            END AS RoleResolutionStatus,
            @ProposedDate AS ProposedDate,
            CONVERT(INT, DATEDIFF(DAY, CONVERT(DATE, N'19000107'), @ProposedDate) % 7) AS ProposedDayNumber
        FROM Context AS context
        INNER JOIN wellbeing.IncidentTypeConsequence AS mapping
            ON mapping.IncidentTypeId = context.IncidentTypeId
           AND mapping.ClassificationId = context.ClassificationId
        INNER JOIN wellbeing.tblConsequences AS consequence
            ON consequence.ConsequenceId = mapping.ConsequenceId
        OUTER APPLY
        (
            SELECT
                MAX(CASE WHEN policyRule.IsEligible = 1 AND policyRule.RequiresApproval = 1 THEN 1
                         WHEN policyRule.IsEligible = 1 THEN 0 END) AS ApprovalRequired,
                CONVERT(bit, CASE WHEN SUM(CASE
                    WHEN policyRule.IsEligible = 1 AND policyRule.RequiresApproval IS NOT NULL THEN 1
                    ELSE 0 END) > 0 THEN 1 ELSE 0 END) AS ApprovalConfigurationKnown
            FROM wellbeing.ConsequencePolicyRule AS policyRule
            WHERE policyRule.ConsequenceId = consequence.ConsequenceId
              AND policyRule.EffectiveStartDate <= @ProposedDate
              AND (policyRule.EffectiveEndDate IS NULL OR policyRule.EffectiveEndDate >= @ProposedDate)
              AND (policyRule.PolicyLevelId IS NULL OR policyRule.PolicyLevelId = context.IncidentPolicyLevelId)
              AND (policyRule.IncidentTypeId IS NULL OR policyRule.IncidentTypeId = context.IncidentTypeId)
              AND (policyRule.ClassificationId IS NULL OR policyRule.ClassificationId = context.ClassificationId)
        ) AS policy
        OUTER APPLY
        (
            SELECT COUNT(*) AS RuleCount,
                   CONVERT(bit, MAX(CONVERT(INT, calendarRule.RequiresSchoolDay))) AS RequiresSchoolDay
            FROM wellbeing.ConsequenceCalendarRule AS calendarRule
            WHERE calendarRule.ConsequenceId = consequence.ConsequenceId
              AND calendarRule.IsActive = 1
              AND calendarRule.EffectiveStartDate <= @ProposedDate
              AND (calendarRule.EffectiveEndDate IS NULL OR calendarRule.EffectiveEndDate >= @ProposedDate)
        ) AS calendarRule
        OUTER APPLY
        (
            SELECT TOP (1) workflow.ConsequenceId, workflow.RequiresApproval,
                           workflow.ApprovalRoleCode, workflow.ProcessingRoleCode,
                           workflow.WorkflowDescription
            FROM wellbeing.ConsequenceApplicationWorkflow AS workflow
            WHERE workflow.ConsequenceId = consequence.ConsequenceId
              AND workflow.IsActive = 1
              AND workflow.EffectiveStartDate <= @ProposedDate
              AND (workflow.EffectiveEndDate IS NULL OR workflow.EffectiveEndDate >= @ProposedDate)
            ORDER BY workflow.EffectiveStartDate DESC
        ) AS appWorkflow
        OUTER APPLY
        (
            SELECT MIN(restrictionGroup.MaxAssignmentsPerStudentPerDate) AS MaxAssignmentsPerStudentPerDate
            FROM wellbeing.ConsequenceRestrictionGroupMember AS groupMember
            INNER JOIN wellbeing.ConsequenceRestrictionGroup AS restrictionGroup
                ON restrictionGroup.RestrictionGroupCode = groupMember.RestrictionGroupCode
               AND restrictionGroup.IsActive = 1
            WHERE groupMember.ConsequenceId = consequence.ConsequenceId
        ) AS dailyLimit
        CROSS APPLY
        (
            VALUES
            (
                CASE
                    WHEN UPPER(COALESCE(NULLIF(LTRIM(RTRIM(appWorkflow.ApprovalRoleCode)), N''),
                                        NULLIF(LTRIM(RTRIM(consequence.ApprovalRoleRequired)), N''),
                                        NULLIF(LTRIM(RTRIM(appWorkflow.ProcessingRoleCode)), N''),
                                        NULLIF(LTRIM(RTRIM(consequence.LegacyProcessorRole)), N''))) LIKE N'%HEAD%HOUSE%'
                        THEN N'HEAD_OF_HOUSE'
                    WHEN UPPER(COALESCE(NULLIF(LTRIM(RTRIM(appWorkflow.ApprovalRoleCode)), N''),
                                        NULLIF(LTRIM(RTRIM(consequence.ApprovalRoleRequired)), N''),
                                        NULLIF(LTRIM(RTRIM(appWorkflow.ProcessingRoleCode)), N''),
                                        NULLIF(LTRIM(RTRIM(consequence.LegacyProcessorRole)), N''))) LIKE N'%DEPUTY%'
                        THEN N'DEPUTY_PRINCIPAL'
                    WHEN UPPER(COALESCE(NULLIF(LTRIM(RTRIM(appWorkflow.ApprovalRoleCode)), N''),
                                        NULLIF(LTRIM(RTRIM(consequence.ApprovalRoleRequired)), N''),
                                        NULLIF(LTRIM(RTRIM(appWorkflow.ProcessingRoleCode)), N''),
                                        NULLIF(LTRIM(RTRIM(consequence.LegacyProcessorRole)), N''))) LIKE N'%PASTORAL%'
                        THEN N'PASTORAL_CARE'
                    WHEN UPPER(COALESCE(NULLIF(LTRIM(RTRIM(appWorkflow.ApprovalRoleCode)), N''),
                                        NULLIF(LTRIM(RTRIM(consequence.ApprovalRoleRequired)), N''),
                                        NULLIF(LTRIM(RTRIM(appWorkflow.ProcessingRoleCode)), N''),
                                        NULLIF(LTRIM(RTRIM(consequence.LegacyProcessorRole)), N''))) LIKE N'%ADMIN%'
                        THEN N'ADMINISTRATION'
                    ELSE NULL
                END
            )
        ) AS roleConfig(AssignedRoleCode)
        OUTER APPLY
        (
            SELECT COUNT(DISTINCT configured.StaffKey) AS StaffCount,
                   MIN(configured.StaffKey) AS StaffKey
            FROM wellbeing.ConsequenceRoleAssignment AS configured
            INNER JOIN wellbeing.IncidentRole AS assignedRole
                ON assignedRole.IncidentRoleId = configured.IncidentRoleId
               AND assignedRole.RoleCode = roleConfig.AssignedRoleCode
               AND assignedRole.IsActive = 1
            INNER JOIN gold.dimStaff AS assignedStaff
                ON assignedStaff.StaffKey = configured.StaffKey
               AND assignedStaff.IsCurrent = 1
               AND (assignedStaff.EffectiveToUtc IS NULL OR assignedStaff.EffectiveToUtc >= SYSUTCDATETIME())
            WHERE (configured.ConsequenceId IS NULL OR configured.ConsequenceId = consequence.ConsequenceId)
              AND configured.AssignmentType = N'PRIMARY'
              AND configured.IsActive = 1
              AND configured.EffectiveFrom <= CAST(SYSUTCDATETIME() AS DATE)
              AND (configured.EffectiveTo IS NULL OR configured.EffectiveTo >= CAST(SYSUTCDATETIME() AS DATE))
        ) AS primaryStaff
        OUTER APPLY
        (
            SELECT COUNT(DISTINCT configured.StaffKey) AS StaffCount,
                   MIN(configured.StaffKey) AS StaffKey
            FROM wellbeing.ConsequenceRoleAssignment AS configured
            INNER JOIN wellbeing.IncidentRole AS assignedRole
                ON assignedRole.IncidentRoleId = configured.IncidentRoleId
               AND assignedRole.RoleCode = roleConfig.AssignedRoleCode
               AND assignedRole.IsActive = 1
            INNER JOIN gold.dimStaff AS assignedStaff
                ON assignedStaff.StaffKey = configured.StaffKey
               AND assignedStaff.IsCurrent = 1
               AND (assignedStaff.EffectiveToUtc IS NULL OR assignedStaff.EffectiveToUtc >= SYSUTCDATETIME())
            WHERE (configured.ConsequenceId IS NULL OR configured.ConsequenceId = consequence.ConsequenceId)
              AND configured.AssignmentType = N'DELEGATE'
              AND configured.IsActive = 1
              AND configured.EffectiveFrom <= CAST(SYSUTCDATETIME() AS DATE)
              AND (configured.EffectiveTo IS NULL OR configured.EffectiveTo >= CAST(SYSUTCDATETIME() AS DATE))
        ) AS delegateStaff
        OUTER APPLY
        (
            SELECT COUNT(DISTINCT assignedStaff.StaffKey) AS StaffCount,
                   MIN(assignedStaff.StaffKey) AS StaffKey
            FROM wellbeing.IncidentRole AS assignedRole
            INNER JOIN wellbeing.IncidentStaffRole AS roleAssignment
                ON roleAssignment.IncidentRoleId = assignedRole.IncidentRoleId
               AND roleAssignment.IsActive = 1
               AND roleAssignment.EffectiveFrom <= CAST(SYSUTCDATETIME() AS DATE)
               AND (roleAssignment.EffectiveTo IS NULL OR roleAssignment.EffectiveTo >= CAST(SYSUTCDATETIME() AS DATE))
            INNER JOIN gold.dimStaff AS assignedStaff
                ON LOWER(assignedStaff.Username) = LOWER(roleAssignment.StaffUsername)
               AND assignedStaff.IsCurrent = 1
               AND assignedStaff.EffectiveFromUtc <= SYSUTCDATETIME()
               AND (assignedStaff.EffectiveToUtc IS NULL OR assignedStaff.EffectiveToUtc >= SYSUTCDATETIME())
            WHERE assignedRole.RoleCode = roleConfig.AssignedRoleCode
              AND assignedRole.IsActive = 1
        ) AS globalStaff
        WHERE consequence.IsActive = 1
    )
    SELECT
        candidate.IncidentId,
        candidate.StudentKey,
        candidate.IncidentDate,
        candidate.IncidentTypeId,
        candidate.ClassificationId,
        candidate.LegacyIncidentLevel,
        candidate.StudentYearLevelAtIncident,
        candidate.StudentYearLevelIdAtIncident,
        candidate.YearLevelResolutionStatus,
        candidate.StudentYearLevelNumber,
        candidate.ConsequenceId,
        candidate.LegacyConsequenceId,
        candidate.ConsequenceName,
        candidate.ConsequenceDescription,
        candidate.PolicyLevelId,
        candidate.SeverityLevel,
        candidate.EffectiveRequiresApproval AS RequiresApproval,
        candidate.ApprovalConfigurationKnown,
        candidate.RequiresParentNotification,
        candidate.LegacyAllowsMultiplePerDay,
        candidate.LegacyLength,
        candidate.LegacyProcessorRole,
        candidate.ApplicationRequiresApproval,
        candidate.ApplicationApprovalRoleCode,
        candidate.ApplicationProcessingRoleCode,
        candidate.ApplicationWorkflowDescription,
        candidate.ApplicationMaxAssignmentsPerStudentPerDate,
        candidate.ApplicationSinglePerDay,
        candidate.RequiresSchoolDay,
        candidate.CalendarRuleConfigured,
        candidate.AssignedRoleCode,
        candidate.AssignedStaffKey,
        candidate.RoleResolutionStatus,
        candidate.ProposedDate,
        candidate.ProposedDayNumber,
        N'LEGACY_REFERENCE_V1+APPLICATION_WORKFLOW_V1' AS RuleVersion,
        CONVERT(bit, CASE WHEN reasons.IneligibilityReasons IS NULL THEN 1 ELSE 0 END) AS IsEligible,
        reasons.IneligibilityReasons,
        communications.TemplateCount AS CommunicationTemplateCount,
        communications.CommunicationRoles
    FROM Candidates AS candidate
    OUTER APPLY
    (
        SELECT STRING_AGG(reason.Reason, N'; ') AS IneligibilityReasons
        FROM
        (
            VALUES
            (CASE WHEN candidate.YearLevelResolutionStatus IS NULL
                        OR candidate.YearLevelResolutionStatus = N'INVESTIGATION_REQUIRED'
                        OR candidate.StudentYearLevelNumber IS NULL
                  THEN N'Historical year level is not verified for the incident date.' END),
            (CASE WHEN EXISTS
                        (SELECT 1 FROM wellbeing.ConsequenceAllowedYearLevel AS allowed
                         WHERE allowed.ConsequenceId = candidate.ConsequenceId)
                       AND NOT EXISTS
                        (SELECT 1 FROM wellbeing.ConsequenceAllowedYearLevel AS allowed
                         WHERE allowed.ConsequenceId = candidate.ConsequenceId
                           AND allowed.YearLevel = candidate.StudentYearLevelNumber)
                  THEN N'Historical year level is not in this consequence''s allowed year levels.' END),
            (CASE WHEN EXISTS
                        (SELECT 1 FROM wellbeing.ConsequenceAllowedDay AS yearRule
                         WHERE yearRule.ConsequenceId = candidate.ConsequenceId
                           AND yearRule.LegacyYearLevel = candidate.StudentYearLevelNumber
                           AND yearRule.LegacyDay = 0
                           AND yearRule.IsAllowed = 0)
                  THEN N'The legacy consequence rules exclude this historical year level.' END),
            (CASE WHEN EXISTS
                        (SELECT 1 FROM wellbeing.ConsequenceAllowedDay AS cycleRule
                         WHERE cycleRule.ConsequenceId = candidate.ConsequenceId
                           AND cycleRule.IsCycleDay = 1
                           AND (cycleRule.LegacyYearLevel IS NULL
                                OR cycleRule.LegacyYearLevel = candidate.StudentYearLevelNumber))
                  THEN N'This consequence requires a cycle-day calendar mapping that is not configured.' END),
            (CASE WHEN EXISTS
                        (SELECT 1 FROM wellbeing.ConsequenceAllowedDay AS allowed
                         WHERE allowed.ConsequenceId = candidate.ConsequenceId
                           AND allowed.LegacyYearLevel IS NULL
                           AND allowed.IsCycleDay = 0
                           AND allowed.LegacyDay BETWEEN 0 AND 6
                           AND allowed.IsAllowed = 1)
                       AND NOT EXISTS
                        (SELECT 1 FROM wellbeing.ConsequenceAllowedDay AS allowed
                         WHERE allowed.ConsequenceId = candidate.ConsequenceId
                           AND allowed.LegacyYearLevel IS NULL
                           AND allowed.IsCycleDay = 0
                           AND allowed.LegacyDay = candidate.ProposedDayNumber
                           AND allowed.IsAllowed = 1)
                  THEN N'The proposed date is not an allowed weekday for this consequence.' END),
            (CASE WHEN EXISTS
                        (SELECT 1 FROM wellbeing.ConsequenceAllowedDay AS denied
                         WHERE denied.ConsequenceId = candidate.ConsequenceId
                           AND denied.LegacyYearLevel IS NULL
                           AND denied.IsCycleDay = 0
                           AND denied.LegacyDay = candidate.ProposedDayNumber
                           AND denied.IsAllowed = 0)
                  THEN N'The proposed weekday is explicitly excluded by this consequence''s rules.' END),
            (CASE WHEN candidate.RequiresSchoolDay = 1
                       AND NOT EXISTS
                        (SELECT 1 FROM wellbeing.SchoolCalendar AS calendarDate
                         WHERE calendarDate.CalendarDate = candidate.ProposedDate)
                  THEN N'The consequence requires a school-day calendar entry for the proposed date.' END),
            (CASE WHEN candidate.RequiresSchoolDay = 1
                       AND EXISTS
                        (SELECT 1 FROM wellbeing.SchoolCalendar AS calendarDate
                         WHERE calendarDate.CalendarDate = candidate.ProposedDate
                           AND calendarDate.IsSchoolDay = 0)
                  THEN N'The proposed date is a school holiday, student-free day, or other configured non-school day.' END),
            (CASE WHEN candidate.PolicyLevelId IS NOT NULL
                       AND NOT EXISTS
                        (SELECT 1 FROM wellbeing.factBehaviourIncident AS incident
                         WHERE incident.IncidentId = candidate.IncidentId
                           AND incident.PolicyLevelId = candidate.PolicyLevelId)
                  THEN N'The incident does not meet the consequence policy-level requirement.' END),
            (CASE WHEN EXISTS
                        (SELECT 1 FROM wellbeing.ConsequencePolicyRule AS policyRule
                         WHERE policyRule.ConsequenceId = candidate.ConsequenceId)
                       AND NOT EXISTS
                        (SELECT 1 FROM wellbeing.ConsequencePolicyRule AS policyRule
                         WHERE policyRule.ConsequenceId = candidate.ConsequenceId
                           AND policyRule.IsEligible = 1
                           AND policyRule.EffectiveStartDate <= candidate.ProposedDate
                           AND (policyRule.EffectiveEndDate IS NULL OR policyRule.EffectiveEndDate >= candidate.ProposedDate)
                           AND (policyRule.PolicyLevelId IS NULL OR policyRule.PolicyLevelId = (
                                SELECT incident.PolicyLevelId FROM wellbeing.factBehaviourIncident AS incident
                                WHERE incident.IncidentId = candidate.IncidentId))
                           AND (policyRule.IncidentTypeId IS NULL OR policyRule.IncidentTypeId = candidate.IncidentTypeId)
                           AND (policyRule.ClassificationId IS NULL OR policyRule.ClassificationId = candidate.ClassificationId))
                  THEN N'No active policy rule allows this consequence for the incident.' END),
            (CASE WHEN EXISTS
                        (SELECT 1 FROM wellbeing.ConsequencePolicyRule AS policyRule
                         WHERE policyRule.ConsequenceId = candidate.ConsequenceId
                           AND policyRule.IsEligible = 0
                           AND policyRule.EffectiveStartDate <= candidate.ProposedDate
                           AND (policyRule.EffectiveEndDate IS NULL OR policyRule.EffectiveEndDate >= candidate.ProposedDate)
                           AND (policyRule.PolicyLevelId IS NULL OR policyRule.PolicyLevelId = (
                                SELECT incident.PolicyLevelId FROM wellbeing.factBehaviourIncident AS incident
                                WHERE incident.IncidentId = candidate.IncidentId))
                           AND (policyRule.IncidentTypeId IS NULL OR policyRule.IncidentTypeId = candidate.IncidentTypeId)
                           AND (policyRule.ClassificationId IS NULL OR policyRule.ClassificationId = candidate.ClassificationId))
                  THEN N'An active policy rule explicitly excludes this consequence.' END),
            (CASE WHEN candidate.RoleResolutionStatus LIKE N'%CONFLICT%'
                  THEN N'Multiple active staff members resolve to the responsible role; an administrator must resolve the conflict.' END),
            (CASE WHEN candidate.LegacyAllowsMultiplePerDay IS NULL
                       AND candidate.ApplicationMaxAssignmentsPerStudentPerDate = 0
                  THEN N'The legacy multiple-per-day rule is unknown and requires review.' END),
            (CASE WHEN candidate.LegacyAllowsMultiplePerDay = 0
                       AND candidate.ApplicationMaxAssignmentsPerStudentPerDate = 0
                       AND EXISTS
                        (SELECT 1 FROM wellbeing.factConsequenceAssignment AS assignment
                         WHERE assignment.StudentKey = candidate.StudentKey
                           AND assignment.ConsequenceId = candidate.ConsequenceId
                           AND assignment.ScheduledStartDate = candidate.ProposedDate
                           AND assignment.ProcessingStatus NOT IN (N'CANCELLED', N'REJECTED'))
                  THEN N'This student already has this consequence scheduled or completed on the proposed date.' END),
            (CASE WHEN candidate.ApplicationMaxAssignmentsPerStudentPerDate > 0
                       AND
                        (
                            SELECT COUNT(*)
                            FROM wellbeing.factConsequenceAssignment AS assignment
                            INNER JOIN wellbeing.ConsequenceRestrictionGroupMember AS existingGroupMember
                                ON existingGroupMember.ConsequenceId = assignment.ConsequenceId
                            INNER JOIN wellbeing.ConsequenceRestrictionGroupMember AS candidateGroupMember
                                ON candidateGroupMember.RestrictionGroupCode = existingGroupMember.RestrictionGroupCode
                               AND candidateGroupMember.ConsequenceId = candidate.ConsequenceId
                            INNER JOIN wellbeing.ConsequenceRestrictionGroup AS restrictionGroup
                                ON restrictionGroup.RestrictionGroupCode = candidateGroupMember.RestrictionGroupCode
                               AND restrictionGroup.IsActive = 1
                            WHERE assignment.StudentKey = candidate.StudentKey
                              AND assignment.ScheduledStartDate = candidate.ProposedDate
                              AND assignment.ProcessingStatus NOT IN (N'CANCELLED', N'REJECTED')
                        ) >= candidate.ApplicationMaxAssignmentsPerStudentPerDate
                  THEN N'This student already has the maximum number of detentions scheduled or completed on the proposed date.' END)
        ) AS reason(Reason)
        WHERE reason.Reason IS NOT NULL
    ) AS reasons
    OUTER APPLY
    (
        SELECT COUNT(DISTINCT template.LegacyCommunicationTemplateId) AS TemplateCount,
               STRING_AGG(roleName.RoleName, N', ') AS CommunicationRoles
        FROM wellbeing.LegacyConsequenceCommunicationTemplate AS template
        CROSS APPLY
        (
            VALUES
                (CASE WHEN template.SendToStudent = 1 THEN N'Student' END),
                (CASE WHEN template.SendToParent = 1 THEN N'Parent/Guardian' END),
                (CASE WHEN template.SendToPastoralCareTeacher = 1 THEN N'Pastoral Care Teacher' END),
                (CASE WHEN template.SendToHeadOfHouse = 1 THEN N'Head of House' END),
                (CASE WHEN template.SendToDeputyPrincipal = 1 THEN N'Deputy Principal' END)
        ) AS roleName(RoleName)
        WHERE template.LegacyConsequenceId = candidate.LegacyConsequenceId
          AND roleName.RoleName IS NOT NULL
    ) AS communications
);
GO

CREATE OR ALTER PROCEDURE wellbeing.usp_GetEligibleIncidentConsequences
    @IncidentId INT,
    @StudentKey INT,
    @ProposedDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @ProposedDate IS NULL
        THROW 51200, 'A proposed consequence date is required.', 1;
    IF NOT EXISTS
    (
        SELECT 1 FROM wellbeing.factBehaviourIncident AS incident
        INNER JOIN wellbeing.IncidentStudent AS studentLink
            ON studentLink.IncidentId = incident.IncidentId
           AND studentLink.StudentKey = @StudentKey
        WHERE incident.IncidentId = @IncidentId
          AND incident.IsDeleted = 0
    )
        THROW 51201, 'The incident or linked student was not found.', 1;

    SELECT
        evaluation.ConsequenceId,
        evaluation.LegacyConsequenceId,
        evaluation.ConsequenceName,
        evaluation.ConsequenceDescription,
        evaluation.PolicyLevelId,
        evaluation.SeverityLevel,
        evaluation.RequiresApproval,
        evaluation.ApprovalConfigurationKnown,
        evaluation.RequiresParentNotification,
        evaluation.LegacyLength,
        evaluation.LegacyAllowsMultiplePerDay,
        evaluation.LegacyProcessorRole,
        evaluation.RequiresSchoolDay,
        evaluation.CalendarRuleConfigured,
        evaluation.AssignedRoleCode,
        evaluation.AssignedStaffKey,
        evaluation.RoleResolutionStatus,
        evaluation.ProposedDate,
        evaluation.ProposedDayNumber,
        evaluation.CommunicationTemplateCount,
        evaluation.CommunicationRoles,
        evaluation.StudentYearLevelAtIncident,
        evaluation.YearLevelResolutionStatus,
        N'LEGACY_REFERENCE_V1+APPLICATION_WORKFLOW_V1' AS RuleVersion
    FROM wellbeing.ufn_EvaluateIncidentConsequences(@IncidentId, @StudentKey, @ProposedDate) AS evaluation
    WHERE evaluation.IsEligible = 1
    ORDER BY evaluation.ConsequenceName, evaluation.ConsequenceId;
END;
GO

CREATE OR ALTER PROCEDURE wellbeing.usp_GetIncidentConsequenceEvaluations
    @IncidentId INT,
    @StudentKey INT,
    @ProposedDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    IF @ProposedDate IS NULL
        THROW 51200, 'A proposed consequence date is required.', 1;
    IF NOT EXISTS
    (
        SELECT 1 FROM wellbeing.factBehaviourIncident AS incident
        INNER JOIN wellbeing.IncidentStudent AS studentLink
            ON studentLink.IncidentId = incident.IncidentId
           AND studentLink.StudentKey = @StudentKey
        WHERE incident.IncidentId = @IncidentId
          AND incident.IsDeleted = 0
    )
        THROW 51201, 'The incident or linked student was not found.', 1;

    SELECT ConsequenceId, LegacyConsequenceId, ConsequenceName, IsEligible,
           IneligibilityReasons, StudentYearLevelAtIncident, YearLevelResolutionStatus,
           ProposedDate, AssignedRoleCode, RoleResolutionStatus, RequiresApproval,
           ApprovalConfigurationKnown, CommunicationRoles,
           ApplicationRequiresApproval, ApplicationApprovalRoleCode,
           ApplicationProcessingRoleCode, ApplicationWorkflowDescription,
           ApplicationMaxAssignmentsPerStudentPerDate, ApplicationSinglePerDay,
           RuleVersion = N'LEGACY_REFERENCE_V1+APPLICATION_WORKFLOW_V1'
    FROM wellbeing.ufn_EvaluateIncidentConsequences(@IncidentId, @StudentKey, @ProposedDate)
    ORDER BY ConsequenceName, ConsequenceId;
END;
GO

CREATE OR ALTER PROCEDURE wellbeing.usp_AssignIncidentConsequence
    @IncidentId INT,
    @StudentKey INT,
    @ConsequenceId INT,
    @ScheduledStartDate DATE,
    @AssigningStaffKey INT,
    @Actor NVARCHAR(255),
    @AssignmentReason NVARCHAR(1000) = NULL,
    @IdempotencyKey UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @ScheduledStartDate IS NULL
        THROW 51202, 'A scheduled consequence date is required.', 1;
    IF @IdempotencyKey IS NULL
        THROW 51203, 'An idempotency key is required.', 1;

    DECLARE @LockResult INT,
            @LockResource NVARCHAR(255),
            @AssignmentId INT,
            @Eligible BIT,
            @Reasons NVARCHAR(MAX),
            @YearLevel NVARCHAR(50),
            @AssignedRoleCode NVARCHAR(50),
            @AssignedStaffKey INT,
            @RoleResolutionStatus NVARCHAR(40),
            @RequiresApproval BIT,
            @ApprovalKnown BIT,
            @ProcessingStatus NVARCHAR(30),
            @ApprovalStatusKey INT,
            @RulesJson NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        SET @LockResource = CONCAT(N'StudentSchedule:', @StudentKey, N':', CONVERT(NVARCHAR(10), @ScheduledStartDate, 23));
        EXEC @LockResult = sys.sp_getapplock
            @Resource = @LockResource,
            @LockMode = N'Exclusive',
            @LockOwner = N'Transaction',
            @LockTimeout = 15000;
        IF @LockResult < 0
            THROW 51204, 'Could not obtain a lock to validate the student''s consequence schedule.', 1;

        SELECT @AssignmentId = assignment.ConsequenceAssignmentId
        FROM wellbeing.factConsequenceAssignment AS assignment WITH (UPDLOCK, HOLDLOCK)
        WHERE assignment.IdempotencyKey = @IdempotencyKey;

        IF @AssignmentId IS NOT NULL
        BEGIN
            IF NOT EXISTS
            (
                SELECT 1 FROM wellbeing.factConsequenceAssignment AS assignment
                WHERE assignment.ConsequenceAssignmentId = @AssignmentId
                  AND assignment.IncidentId = @IncidentId
                  AND assignment.StudentKey = @StudentKey
                  AND assignment.ConsequenceId = @ConsequenceId
                  AND assignment.ScheduledStartDate = @ScheduledStartDate
            )
                THROW 51205, 'This idempotency key was already used for a different consequence assignment.', 1;

            COMMIT TRANSACTION;
            SELECT assignment.ConsequenceAssignmentId, assignment.ConsequenceAssignmentNumber,
                   assignment.ProcessingStatus, assignment.ScheduledStartDate,
                   assignment.ConsequenceId, assignment.StudentKey, assignment.IncidentId,
                   CONVERT(bit, 1) AS DuplicateSubmission
            FROM wellbeing.factConsequenceAssignment AS assignment
            WHERE assignment.ConsequenceAssignmentId = @AssignmentId;
            RETURN;
        END;

        SELECT @Eligible = evaluation.IsEligible,
               @Reasons = evaluation.IneligibilityReasons,
               @YearLevel = evaluation.StudentYearLevelAtIncident,
               @AssignedRoleCode = evaluation.AssignedRoleCode,
               @AssignedStaffKey = evaluation.AssignedStaffKey,
               @RoleResolutionStatus = evaluation.RoleResolutionStatus,
               @RequiresApproval = evaluation.RequiresApproval,
               @ApprovalKnown = evaluation.ApprovalConfigurationKnown,
               @RulesJson =
                   (SELECT evaluation.ConsequenceId, evaluation.LegacyConsequenceId,
                           evaluation.IncidentTypeId, evaluation.ClassificationId,
                           evaluation.LegacyIncidentLevel, evaluation.StudentYearLevelAtIncident,
                           evaluation.YearLevelResolutionStatus, evaluation.ProposedDate,
                           evaluation.ProposedDayNumber, evaluation.LegacyAllowsMultiplePerDay,
                           evaluation.RequiresSchoolDay, evaluation.CalendarRuleConfigured,
                           evaluation.LegacyProcessorRole, evaluation.AssignedRoleCode,
                           evaluation.ApplicationRequiresApproval,
                           evaluation.ApplicationApprovalRoleCode,
                           evaluation.ApplicationProcessingRoleCode,
                           evaluation.ApplicationWorkflowDescription,
                           evaluation.ApplicationMaxAssignmentsPerStudentPerDate,
                           evaluation.RequiresApproval, evaluation.ApprovalConfigurationKnown,
                           evaluation.CommunicationTemplateCount, evaluation.CommunicationRoles,
                           evaluation.RuleVersion
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM wellbeing.ufn_EvaluateIncidentConsequences(@IncidentId, @StudentKey, @ScheduledStartDate) AS evaluation
        WHERE evaluation.ConsequenceId = @ConsequenceId;

        IF @Eligible IS NULL
            THROW 51206, 'The selected consequence is not mapped to this incident type and classification.', 1;
        IF @Eligible = 0
        BEGIN
            DECLARE @IneligibleMessage NVARCHAR(2048) =
                LEFT(COALESCE(@Reasons, N'The selected consequence is not eligible.'), 2048);
            THROW 51207, @IneligibleMessage, 1;
        END;

        SET @ProcessingStatus =
            CASE WHEN @ApprovalKnown = 0 THEN N'AWAITING_REVIEW'
                 WHEN @RequiresApproval = 1 THEN N'AWAITING_APPROVAL'
                 WHEN @AssignedRoleCode IS NULL OR @AssignedStaffKey IS NULL THEN N'UNASSIGNED'
                 ELSE N'SCHEDULED' END;
        SELECT @ApprovalStatusKey = ApprovalStatusKey
        FROM wellbeing.dimApprovalStatus
        WHERE ApprovalStatusCode =
            CASE WHEN @ProcessingStatus IN (N'AWAITING_APPROVAL', N'AWAITING_REVIEW') THEN N'PENDING' ELSE N'APPROVED' END;
        IF @ApprovalStatusKey IS NULL
            THROW 51208, 'The approval status reference data is not configured.', 1;

        INSERT INTO wellbeing.factConsequenceAssignment
        (
            ConsequenceAssignmentNumber, IncidentId, StudentKey, AssigningStaffKey, ConsequenceId,
            AssignmentDate, AssignmentReason, ScheduledStartDate, RequiresApproval, ApprovalStatusKey,
            AssignedRoleCode, AssignedStaffKey, RoleResolutionStatus, StudentYearLevelAtIncident,
            RuleVersion, RulesAppliedJson, ApprovalConfigurationKnown, ProcessingStatus,
            IdempotencyKey, CreatedDate, CreatedBy, ModifiedDate, ModifiedBy
        )
        VALUES
        (
            CONCAT(N'CONS-', YEAR(SYSUTCDATETIME()), N'-', REPLACE(CONVERT(NVARCHAR(36), NEWID()), N'-', N'')),
            @IncidentId, @StudentKey, @AssigningStaffKey, @ConsequenceId,
            CAST(SYSUTCDATETIME() AS DATE), @AssignmentReason, @ScheduledStartDate,
            COALESCE(@RequiresApproval, 0), @ApprovalStatusKey,
            @AssignedRoleCode, @AssignedStaffKey, @RoleResolutionStatus, @YearLevel,
            N'LEGACY_REFERENCE_V1+APPLICATION_WORKFLOW_V1', @RulesJson, COALESCE(@ApprovalKnown, 0), @ProcessingStatus,
            @IdempotencyKey, SYSUTCDATETIME(), @Actor, SYSUTCDATETIME(), @Actor
        );
        SET @AssignmentId = SCOPE_IDENTITY();

        INSERT INTO wellbeing.ConsequenceDecisionAudit
        (
            ConsequenceAssignmentId, IncidentId, StudentKey, StudentYearLevelAtIncident,
            ConsequenceId, Decision, RulesAppliedJson, AssignedRoleCode, AssignedStaffKey, Actor
        )
        VALUES
        (
            @AssignmentId, @IncidentId, @StudentKey, @YearLevel, @ConsequenceId,
            @ProcessingStatus, @RulesJson, @AssignedRoleCode, @AssignedStaffKey, @Actor
        );

        IF @ProcessingStatus IN (N'AWAITING_APPROVAL', N'AWAITING_REVIEW')
           AND @AssignedRoleCode IS NOT NULL
        BEGIN
            INSERT INTO wellbeing.ConsequenceWorkflowNotification
            (
                ConsequenceAssignmentId, RoleCode, NotificationType, Channel, CreatedBy
            )
            VALUES
            (
                @AssignmentId, @AssignedRoleCode,
                CASE WHEN @ProcessingStatus = N'AWAITING_APPROVAL' THEN N'APPROVAL_REQUIRED' ELSE N'MANUAL_REVIEW_REQUIRED' END,
                N'IN_APP', @Actor
            );
        END;

        COMMIT TRANSACTION;

        SELECT assignment.ConsequenceAssignmentId, assignment.ConsequenceAssignmentNumber,
               assignment.ProcessingStatus, assignment.ScheduledStartDate,
               assignment.ConsequenceId, assignment.StudentKey, assignment.IncidentId,
               assignment.RequiresApproval, assignment.ApprovalConfigurationKnown,
               assignment.AssignedRoleCode, assignment.AssignedStaffKey,
               assignment.RoleResolutionStatus, CONVERT(bit, 0) AS DuplicateSubmission
        FROM wellbeing.factConsequenceAssignment AS assignment
        WHERE assignment.ConsequenceAssignmentId = @AssignmentId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE wellbeing.usp_TransitionIncidentConsequence
    @ConsequenceAssignmentId INT,
    @Action NVARCHAR(20),
    @Actor NVARCHAR(255),
    @ActorStaffKey INT,
    @Notes NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @IncidentId INT, @StudentKey INT, @ConsequenceId INT,
            @YearLevel NVARCHAR(50), @AssignedRole NVARCHAR(50), @AssignedStaffKey INT,
            @CurrentStatus NVARCHAR(30), @NextStatus NVARCHAR(30),
            @ApprovalStatusKey INT, @RuleJson NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @IncidentId = assignment.IncidentId,
               @StudentKey = assignment.StudentKey,
               @ConsequenceId = assignment.ConsequenceId,
               @YearLevel = assignment.StudentYearLevelAtIncident,
               @AssignedRole = assignment.AssignedRoleCode,
               @AssignedStaffKey = assignment.AssignedStaffKey,
               @CurrentStatus = assignment.ProcessingStatus,
               @RuleJson = assignment.RulesAppliedJson
        FROM wellbeing.factConsequenceAssignment AS assignment WITH (UPDLOCK, HOLDLOCK)
        WHERE assignment.ConsequenceAssignmentId = @ConsequenceAssignmentId;

        IF @IncidentId IS NULL
            THROW 51210, 'Consequence assignment was not found.', 1;

        SET @NextStatus = CASE UPPER(@Action)
            WHEN N'APPROVE' THEN N'APPROVED'
            WHEN N'REJECT' THEN N'REJECTED'
            WHEN N'COMPLETE' THEN N'COMPLETED'
            WHEN N'CANCEL' THEN N'CANCELLED'
            ELSE NULL END;
        IF @NextStatus IS NULL
            THROW 51211, 'Action must be APPROVE, REJECT, COMPLETE, or CANCEL.', 1;

        IF UPPER(@Action) = N'APPROVE' AND @CurrentStatus NOT IN (N'AWAITING_APPROVAL', N'AWAITING_REVIEW')
            THROW 51212, 'Only consequences awaiting review or approval can be approved.', 1;
        IF UPPER(@Action) = N'REJECT' AND @CurrentStatus NOT IN (N'AWAITING_APPROVAL', N'AWAITING_REVIEW')
            THROW 51213, 'Only consequences awaiting review or approval can be rejected.', 1;
        IF UPPER(@Action) = N'COMPLETE' AND @CurrentStatus NOT IN (N'APPROVED', N'SCHEDULED', N'PROCESSING')
            THROW 51214, 'Only approved, scheduled, or processing consequences can be completed.', 1;
        IF UPPER(@Action) = N'CANCEL' AND @CurrentStatus IN (N'COMPLETED', N'CANCELLED', N'REJECTED')
            THROW 51215, 'A completed, cancelled, or rejected consequence cannot be cancelled again.', 1;

        SELECT @ApprovalStatusKey = ApprovalStatusKey
        FROM wellbeing.dimApprovalStatus
        WHERE ApprovalStatusCode =
            CASE UPPER(@Action) WHEN N'APPROVE' THEN N'APPROVED'
                                WHEN N'REJECT' THEN N'REJECTED'
                                ELSE N'PENDING' END;

        UPDATE wellbeing.factConsequenceAssignment
        SET ProcessingStatus = @NextStatus,
            ApprovalStatusKey = CASE WHEN UPPER(@Action) IN (N'APPROVE', N'REJECT')
                                     THEN @ApprovalStatusKey ELSE ApprovalStatusKey END,
            ApprovedBy = CASE WHEN UPPER(@Action) = N'APPROVE' THEN @Actor ELSE ApprovedBy END,
            ApprovedDate = CASE WHEN UPPER(@Action) = N'APPROVE' THEN SYSUTCDATETIME() ELSE ApprovedDate END,
            ApprovalNotes = CASE WHEN UPPER(@Action) IN (N'APPROVE', N'REJECT') THEN LEFT(@Notes, 500) ELSE ApprovalNotes END,
            CompletedBy = CASE WHEN UPPER(@Action) = N'COMPLETE' THEN @Actor ELSE CompletedBy END,
            CompletedDate = CASE WHEN UPPER(@Action) = N'COMPLETE' THEN SYSUTCDATETIME() ELSE CompletedDate END,
            ActualCompletionDate = CASE WHEN UPPER(@Action) = N'COMPLETE' THEN CAST(SYSUTCDATETIME() AS DATE) ELSE ActualCompletionDate END,
            WasCompleted = CASE WHEN UPPER(@Action) = N'COMPLETE' THEN 1 ELSE WasCompleted END,
            CompletionNotes = CASE WHEN UPPER(@Action) = N'COMPLETE' THEN LEFT(@Notes, 500) ELSE CompletionNotes END,
            WorkflowNotes = CASE WHEN @Notes IS NULL THEN WorkflowNotes
                                 WHEN WorkflowNotes IS NULL THEN @Notes
                                 ELSE CONCAT(WorkflowNotes, CHAR(13), CHAR(10), @Actor, N': ', @Notes) END,
            ModifiedDate = SYSUTCDATETIME(),
            ModifiedBy = @Actor
        WHERE ConsequenceAssignmentId = @ConsequenceAssignmentId;

        IF UPPER(@Action) IN (N'APPROVE', N'REJECT')
        BEGIN
            INSERT INTO wellbeing.factApprovalHistory
            (
                RecordType, RecordId, RequiredApproverRole, AssignedApproverKey,
                ApprovalStatusKey, ActionDate, ActionTakenBy, ApprovalNotes, CreatedDate
            )
            VALUES
            (
                N'Consequence', @ConsequenceAssignmentId, @AssignedRole, @ActorStaffKey,
                @ApprovalStatusKey, SYSUTCDATETIME(), @Actor, @Notes, SYSUTCDATETIME()
            );
        END;

        INSERT INTO wellbeing.ConsequenceDecisionAudit
        (
            ConsequenceAssignmentId, IncidentId, StudentKey, StudentYearLevelAtIncident,
            ConsequenceId, Decision, RulesAppliedJson, AssignedRoleCode, AssignedStaffKey, Actor, Notes
        )
        VALUES
        (
            @ConsequenceAssignmentId, @IncidentId, @StudentKey, @YearLevel,
            @ConsequenceId, @NextStatus, @RuleJson, @AssignedRole, @AssignedStaffKey, @Actor, @Notes
        );

        COMMIT TRANSACTION;

        SELECT ConsequenceAssignmentId, ProcessingStatus, ScheduledStartDate, CompletedDate,
               RequiresApproval, ApprovalConfigurationKnown, AssignedRoleCode, AssignedStaffKey
        FROM wellbeing.factConsequenceAssignment
        WHERE ConsequenceAssignmentId = @ConsequenceAssignmentId;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

SELECT N'Consequence engine schema and procedures deployed.' AS Result;
GO
