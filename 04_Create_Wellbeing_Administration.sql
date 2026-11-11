-- Policy-driven administration and workflow foundation.
USE SchoolDW;
GO

IF COL_LENGTH('wellbeing.tblConsequences', 'RequiresParentNotification') IS NULL
BEGIN
    ALTER TABLE wellbeing.tblConsequences
        ADD RequiresParentNotification BIT NOT NULL CONSTRAINT DF_tblConsequences_RequiresParentNotification DEFAULT 0;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.House') AND type = 'U')
BEGIN
    CREATE TABLE wellbeing.House (
        HouseId INT IDENTITY(1,1) PRIMARY KEY,
        HouseCode NVARCHAR(50) NOT NULL UNIQUE,
        HouseName NVARCHAR(150) NOT NULL,
        Description NVARCHAR(500),
        IsActive BIT NOT NULL DEFAULT 1,
        EffectiveStartDate DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
        EffectiveEndDate DATE,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255),
        CONSTRAINT CK_House_DateRange CHECK (EffectiveEndDate IS NULL OR EffectiveEndDate >= EffectiveStartDate)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.IncidentDefinition') AND type = 'U')
BEGIN
    CREATE TABLE wellbeing.IncidentDefinition (
        IncidentDefinitionId INT IDENTITY(1,1) PRIMARY KEY,
        DefinitionCode NVARCHAR(50) NOT NULL UNIQUE,
        DefinitionName NVARCHAR(150) NOT NULL,
        Description NVARCHAR(MAX),
        ClassificationId INT,
        IncidentTypeId INT,
        PolicyLevelId INT,
        ApplicableYearLevels NVARCHAR(500),
        ApplicableLocationIds NVARCHAR(1000),
        IsActive BIT NOT NULL DEFAULT 1,
        EffectiveStartDate DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
        EffectiveEndDate DATE,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255),
        CONSTRAINT CK_IncidentDefinition_DateRange CHECK (EffectiveEndDate IS NULL OR EffectiveEndDate >= EffectiveStartDate),
        CONSTRAINT FK_IncidentDefinition_Classification FOREIGN KEY (ClassificationId) REFERENCES wellbeing.tblIncidentClassifications(ClassificationId),
        CONSTRAINT FK_IncidentDefinition_Type FOREIGN KEY (IncidentTypeId) REFERENCES wellbeing.tblIncidentTypes(IncidentTypeId),
        CONSTRAINT FK_IncidentDefinition_PolicyLevel FOREIGN KEY (PolicyLevelId) REFERENCES wellbeing.tblBehaviourPolicyLevels(PolicyLevelId)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.ConsequencePolicyRule') AND type = 'U')
BEGIN
    CREATE TABLE wellbeing.ConsequencePolicyRule (
        ConsequencePolicyRuleId INT IDENTITY(1,1) PRIMARY KEY,
        ConsequenceId INT NOT NULL,
        PolicyLevelId INT,
        IncidentTypeId INT,
        ClassificationId INT,
        IsEligible BIT NOT NULL DEFAULT 1,
        RequiresApproval BIT NOT NULL DEFAULT 1,
        EffectiveStartDate DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
        EffectiveEndDate DATE,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255),
        CONSTRAINT CK_ConsequencePolicyRule_DateRange CHECK (EffectiveEndDate IS NULL OR EffectiveEndDate >= EffectiveStartDate),
        CONSTRAINT FK_ConsequencePolicyRule_Consequence FOREIGN KEY (ConsequenceId) REFERENCES wellbeing.tblConsequences(ConsequenceId),
        CONSTRAINT FK_ConsequencePolicyRule_PolicyLevel FOREIGN KEY (PolicyLevelId) REFERENCES wellbeing.tblBehaviourPolicyLevels(PolicyLevelId),
        CONSTRAINT FK_ConsequencePolicyRule_Type FOREIGN KEY (IncidentTypeId) REFERENCES wellbeing.tblIncidentTypes(IncidentTypeId),
        CONSTRAINT FK_ConsequencePolicyRule_Classification FOREIGN KEY (ClassificationId) REFERENCES wellbeing.tblIncidentClassifications(ClassificationId)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.ApprovalWorkflow') AND type = 'U')
BEGIN
    CREATE TABLE wellbeing.ApprovalWorkflow (
        ApprovalWorkflowId INT IDENTITY(1,1) PRIMARY KEY,
        WorkflowCode NVARCHAR(50) NOT NULL UNIQUE,
        WorkflowName NVARCHAR(150) NOT NULL,
        Description NVARCHAR(MAX),
        TriggerCondition NVARCHAR(MAX),
        IsActive BIT NOT NULL DEFAULT 1,
        EffectiveStartDate DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
        EffectiveEndDate DATE,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.ApprovalWorkflowStep') AND type = 'U')
BEGIN
    CREATE TABLE wellbeing.ApprovalWorkflowStep (
        ApprovalWorkflowStepId INT IDENTITY(1,1) PRIMARY KEY,
        ApprovalWorkflowId INT NOT NULL,
        StepOrder INT NOT NULL,
        RequiredRole NVARCHAR(100) NOT NULL,
        RequiredStaffKey INT,
        IsRequired BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CONSTRAINT FK_ApprovalWorkflowStep_Workflow FOREIGN KEY (ApprovalWorkflowId) REFERENCES wellbeing.ApprovalWorkflow(ApprovalWorkflowId)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.CommunicationTemplate') AND type = 'U')
BEGIN
    CREATE TABLE wellbeing.CommunicationTemplate (
        CommunicationTemplateId INT IDENTITY(1,1) PRIMARY KEY,
        TemplateCode NVARCHAR(50) NOT NULL UNIQUE,
        TemplateName NVARCHAR(150) NOT NULL,
        Channel NVARCHAR(30) NOT NULL,
        SubjectTemplate NVARCHAR(500),
        BodyTemplate NVARCHAR(MAX) NOT NULL,
        RecipientRule NVARCHAR(MAX),
        IsActive BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.SchoolCalendar') AND type = 'U')
BEGIN
    CREATE TABLE wellbeing.SchoolCalendar (
        SchoolCalendarId INT IDENTITY(1,1) PRIMARY KEY,
        CalendarDate DATE NOT NULL,
        CalendarType NVARCHAR(50) NOT NULL,
        CalendarName NVARCHAR(150) NOT NULL,
        IsSchoolDay BIT NOT NULL DEFAULT 1,
        Notes NVARCHAR(500),
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        CONSTRAINT UQ_SchoolCalendar_Date UNIQUE (CalendarDate, CalendarType)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.DetentionSchedule') AND type = 'U')
BEGIN
    CREATE TABLE wellbeing.DetentionSchedule (
        DetentionScheduleId INT IDENTITY(1,1) PRIMARY KEY,
        ScheduleName NVARCHAR(150) NOT NULL,
        ScheduleDate DATE NOT NULL,
        StartTime TIME NOT NULL,
        EndTime TIME NOT NULL,
        LocationId INT,
        Capacity INT,
        IsActive BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        CONSTRAINT CK_DetentionSchedule_TimeRange CHECK (EndTime > StartTime),
        CONSTRAINT FK_DetentionSchedule_Location FOREIGN KEY (LocationId) REFERENCES wellbeing.tblSchoolLocations(LocationId)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.AuditEvent') AND type = 'U')
BEGIN
    CREATE TABLE wellbeing.AuditEvent (
        AuditEventId BIGINT IDENTITY(1,1) PRIMARY KEY,
        EventDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        Actor NVARCHAR(255) NOT NULL,
        Action NVARCHAR(50) NOT NULL,
        EntityName NVARCHAR(150) NOT NULL,
        EntityId NVARCHAR(100) NOT NULL,
        BeforeJson NVARCHAR(MAX),
        AfterJson NVARCHAR(MAX),
        CorrelationId NVARCHAR(100),
        IpAddress NVARCHAR(50)
    );
    CREATE INDEX IX_AuditEvent_Date ON wellbeing.AuditEvent(EventDate DESC);
    CREATE INDEX IX_AuditEvent_Entity ON wellbeing.AuditEvent(EntityName, EntityId);
END;
GO
