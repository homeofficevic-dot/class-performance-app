USE SchoolDW;
GO

SET XACT_ABORT ON;
SET NOCOUNT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @ConsequenceId INT,
            @ConsequenceCount INT,
            @PastoralCareRoleId INT;

    SELECT @ConsequenceCount = COUNT(*),
           @ConsequenceId = MIN(ConsequenceId)
    FROM wellbeing.tblConsequences
    WHERE LegacyConsequenceId = 57
      AND IsActive = 1;

    IF @ConsequenceCount <> 1
        THROW 51400, 'Expected one active consequence for verified legacy consequence ID 57.', 1;

    SELECT @PastoralCareRoleId = IncidentRoleId
    FROM wellbeing.IncidentRole
    WHERE RoleCode = N'PASTORAL_CARE'
      AND IsActive = 1;

    IF @PastoralCareRoleId IS NULL
        THROW 51401, 'The active PASTORAL_CARE role is not configured.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM wellbeing.ConsequenceRestrictionGroup
        WHERE RestrictionGroupCode = N'DETENTION'
    )
    BEGIN
        INSERT INTO wellbeing.ConsequenceRestrictionGroup
            (RestrictionGroupCode, RestrictionGroupName, MaxAssignmentsPerStudentPerDate, CreatedBy)
        VALUES
            (N'DETENTION', N'Detention', 1, N'23_Configure_Application_Detention_Workflow');
    END
    ELSE
        UPDATE wellbeing.ConsequenceRestrictionGroup
        SET RestrictionGroupName = N'Detention',
            MaxAssignmentsPerStudentPerDate = 1,
            IsActive = 1
        WHERE RestrictionGroupCode = N'DETENTION'
          AND (RestrictionGroupName <> N'Detention'
               OR MaxAssignmentsPerStudentPerDate <> 1
               OR IsActive <> 1);

    INSERT INTO wellbeing.ConsequenceRestrictionGroupMember
        (RestrictionGroupCode, ConsequenceId, CreatedBy)
    SELECT N'DETENTION', consequence.ConsequenceId, N'23_Configure_Application_Detention_Workflow'
    FROM wellbeing.tblConsequences AS consequence
    WHERE consequence.IsActive = 1
      AND consequence.ConsequenceName LIKE N'%detention%'
      AND NOT EXISTS
      (
          SELECT 1
          FROM wellbeing.ConsequenceRestrictionGroupMember AS existing
          WHERE existing.RestrictionGroupCode = N'DETENTION'
            AND existing.ConsequenceId = consequence.ConsequenceId
      );

    IF NOT EXISTS
    (
        SELECT 1
        FROM wellbeing.ConsequenceRestrictionGroupMember
        WHERE RestrictionGroupCode = N'DETENTION'
          AND ConsequenceId = @ConsequenceId
    )
        THROW 51402, 'The verified recess/lunchtime detention was not added to the detention restriction group.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM wellbeing.ConsequenceApplicationWorkflow
        WHERE ConsequenceId = @ConsequenceId
    )
    BEGIN
        UPDATE wellbeing.ConsequenceApplicationWorkflow
        SET RequiresApproval = 1,
            ApprovalRoleCode = N'PASTORAL_CARE',
            ProcessingRoleCode = N'PASTORAL_CARE',
            WorkflowDescription = N'Pastoral Care reviews and approves the detention, then processes it. An in-app role task is created; outbound email is not configured.',
            EffectiveEndDate = NULL,
            IsActive = 1,
            ModifiedDate = SYSUTCDATETIME(),
            ModifiedBy = N'23_Configure_Application_Detention_Workflow'
        WHERE ConsequenceId = @ConsequenceId
          AND (RequiresApproval <> 1
               OR ISNULL(ApprovalRoleCode, N'') <> N'PASTORAL_CARE'
               OR ISNULL(ProcessingRoleCode, N'') <> N'PASTORAL_CARE'
               OR ISNULL(WorkflowDescription, N'') <> N'Pastoral Care reviews and approves the detention, then processes it. An in-app role task is created; outbound email is not configured.'
               OR EffectiveEndDate IS NOT NULL
               OR IsActive <> 1);
    END
    ELSE
    BEGIN
        INSERT INTO wellbeing.ConsequenceApplicationWorkflow
        (
            ConsequenceId, RequiresApproval, ApprovalRoleCode, ProcessingRoleCode,
            WorkflowDescription, EffectiveStartDate, CreatedBy
        )
        VALUES
        (
            @ConsequenceId, 1, N'PASTORAL_CARE', N'PASTORAL_CARE',
            N'Pastoral Care reviews and approves the detention, then processes it. An in-app role task is created; outbound email is not configured.',
            CAST(GETDATE() AS DATE), N'23_Configure_Application_Detention_Workflow'
        );
    END;

    COMMIT TRANSACTION;

    SELECT
        consequence.ConsequenceId,
        consequence.LegacyConsequenceId,
        consequence.ConsequenceName,
        consequence.LegacyAllowsMultiplePerDay,
        workflow.RequiresApproval AS ApplicationRequiresApproval,
        workflow.ApprovalRoleCode,
        workflow.ProcessingRoleCode,
        restrictionGroup.MaxAssignmentsPerStudentPerDate,
        (
            SELECT COUNT(*)
            FROM wellbeing.ConsequenceRestrictionGroupMember AS allMembers
            WHERE allMembers.RestrictionGroupCode = N'DETENTION'
        ) AS DetentionConsequencesInRule
    FROM wellbeing.tblConsequences AS consequence
    INNER JOIN wellbeing.ConsequenceApplicationWorkflow AS workflow
        ON workflow.ConsequenceId = consequence.ConsequenceId
    INNER JOIN wellbeing.ConsequenceRestrictionGroupMember AS groupMember
        ON groupMember.ConsequenceId = consequence.ConsequenceId
       AND groupMember.RestrictionGroupCode = N'DETENTION'
    INNER JOIN wellbeing.ConsequenceRestrictionGroup AS restrictionGroup
        ON restrictionGroup.RestrictionGroupCode = groupMember.RestrictionGroupCode
    WHERE consequence.ConsequenceId = @ConsequenceId;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
