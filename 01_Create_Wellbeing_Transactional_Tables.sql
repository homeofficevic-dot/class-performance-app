-- ============================================================================
-- Student Wellbeing System - TRANSACTIONAL TABLES (Part 2)
-- ============================================================================
-- This script creates the fact tables for tracking incidents, consequences,
-- pastoral interventions, and wellbeing activities.
--
-- Run this script AFTER 00_Create_Wellbeing_Schema.sql
-- ============================================================================

USE SchoolDW;
GO

PRINT '';
PRINT '============================================================================';
PRINT 'PHASE 2: Creating Transactional/Fact Tables';
PRINT '============================================================================';
PRINT '';

-- ============================================================================
-- CORE INCIDENT FACT TABLE
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factBehaviourIncident') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.factBehaviourIncident (
        IncidentId INT PRIMARY KEY IDENTITY(1,1),
        IncidentNumber NVARCHAR(50) NOT NULL UNIQUE,  -- e.g., WB-2024-001234
        StudentKey INT NOT NULL,  -- Foreign key to gold.dimStudent.StudentKey
        ReportingStaffKey INT NOT NULL,  -- Who reported the incident
        ReceivingStaffKey INT,  -- Who is handling/processing
        LocationId INT NOT NULL,  -- Reference to wellbeing.tblSchoolLocations
        IncidentTypeId INT NOT NULL,  -- Reference to wellbeing.tblIncidentTypes
        ClassificationId INT NOT NULL,  -- Reference to wellbeing.tblIncidentClassifications
        PolicyLevelId INT NOT NULL,  -- Reference to wellbeing.tblBehaviourPolicyLevels
        IncidentStatusKey INT NOT NULL DEFAULT 1,  -- Reference to wellbeing.dimIncidentStatus (default DRAFT)
        
        -- Incident Details
        IncidentDate DATE NOT NULL,
        IncidentTime TIME,
        IncidentSummary NVARCHAR(500) NOT NULL,
        DetailedDescription NVARCHAR(MAX),
        WitnessCount INT,  -- Number of witnesses
        WitnessNames NVARCHAR(MAX),  -- Comma-separated or formatted list
        
        -- Incident Severity/Context
        SeverityIndicators NVARCHAR(500),  -- e.g., 'Violence', 'Weapons', 'Threats'
        ContextualFactors NVARCHAR(MAX),  -- Background circumstances
        StudentAttribution NVARCHAR(1000),  -- Student's explanation
        OtherStudentsInvolved NVARCHAR(MAX),  -- Names/IDs of other students
        
        -- Injury/Damage Assessment
        InjuryReported BIT DEFAULT 0,
        InjuryDescription NVARCHAR(500),
        PropertyDamageReported BIT DEFAULT 0,
        PropertyDamageDescription NVARCHAR(500),
        DamageEstimatedValue DECIMAL(10,2),
        
        -- Follow-up
        FollowUpRequired BIT DEFAULT 1,
        FollowUpDueDate DATE,
        FollowUpNotes NVARCHAR(MAX),
        
        -- Metadata
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),  -- User who created the record
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255),
        IsDeleted BIT NOT NULL DEFAULT 0,
        DeletedDate DATETIME2,
        
        -- Constraints
        CONSTRAINT CK_Incident_Dates CHECK (IncidentDate <= CAST(GETDATE() AS DATE)),
        CONSTRAINT CK_FollowUpDate CHECK (FollowUpDueDate IS NULL OR FollowUpDueDate >= IncidentDate)
    );
    
    CREATE NONCLUSTERED INDEX IX_FactBehaviourIncident_StudentKey ON wellbeing.factBehaviourIncident(StudentKey);
    CREATE NONCLUSTERED INDEX IX_FactBehaviourIncident_IncidentNumber ON wellbeing.factBehaviourIncident(IncidentNumber);
    CREATE NONCLUSTERED INDEX IX_FactBehaviourIncident_IncidentDate ON wellbeing.factBehaviourIncident(IncidentDate DESC);
    CREATE NONCLUSTERED INDEX IX_FactBehaviourIncident_Status ON wellbeing.factBehaviourIncident(IncidentStatusKey);
    CREATE NONCLUSTERED INDEX IX_FactBehaviourIncident_Classification ON wellbeing.factBehaviourIncident(ClassificationId);
    CREATE NONCLUSTERED INDEX IX_FactBehaviourIncident_ReportingStaff ON wellbeing.factBehaviourIncident(ReportingStaffKey);
    CREATE NONCLUSTERED INDEX IX_FactBehaviourIncident_LocationType ON wellbeing.factBehaviourIncident(LocationId, IncidentTypeId);
    CREATE NONCLUSTERED INDEX IX_FactBehaviourIncident_Deleted ON wellbeing.factBehaviourIncident(IsDeleted);
    
    PRINT 'Table [wellbeing.factBehaviourIncident] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.factBehaviourIncident] already exists.';
GO

-- ============================================================================
-- CONSEQUENCE ASSIGNMENT FACT TABLE
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factConsequenceAssignment') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.factConsequenceAssignment (
        ConsequenceAssignmentId INT PRIMARY KEY IDENTITY(1,1),
        ConsequenceAssignmentNumber NVARCHAR(50) NOT NULL UNIQUE,  -- e.g., CONS-2024-001234
        IncidentId INT NOT NULL,  -- Reference to wellbeing.factBehaviourIncident
        StudentKey INT NOT NULL,  -- Reference to gold.dimStudent
        AssigningStaffKey INT NOT NULL,  -- Who is assigning the consequence
        ConsequenceId INT NOT NULL,  -- Reference to wellbeing.tblConsequences
        
        -- Assignment Details
        AssignmentDate DATE NOT NULL DEFAULT CAST(GETDATE() AS DATE),
        AssignmentReason NVARCHAR(1000),
        ScheduledStartDate DATE,  -- When consequence should start
        ScheduledEndDate DATE,  -- When consequence should end
        EstimatedCompletionDate DATE,
        
        -- Approval Status
        RequiresApproval BIT NOT NULL,
        ApprovalStatusKey INT NOT NULL DEFAULT 1,  -- Reference to wellbeing.dimApprovalStatus (default PENDING)
        ApprovalDueDate DATE,
        
        -- Approval History
        ApprovedBy NVARCHAR(255),
        ApprovedDate DATETIME2,
        ApprovalNotes NVARCHAR(500),
        
        -- Override/Delegation
        OverriddenBy NVARCHAR(255),
        OverriddenDate DATETIME2,
        OverrideReason NVARCHAR(500),
        OverriddenToConsequenceId INT,  -- If overridden to a different consequence
        
        DelegatedTo NVARCHAR(255),
        DelegatedDate DATETIME2,
        DelegationReason NVARCHAR(500),
        
        -- Completion/Fulfillment
        CompletedDate DATETIME2,
        CompletedBy NVARCHAR(255),
        CompletionNotes NVARCHAR(500),
        ActualCompletionDate DATE,
        WasCompleted BIT NOT NULL DEFAULT 0,
        ComplianceNotes NVARCHAR(MAX),
        
        -- Metadata
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255),
        
        -- Constraints
        CONSTRAINT CK_ConsequenceAssignment_Dates CHECK (
            (ScheduledEndDate IS NULL OR ScheduledStartDate IS NULL OR ScheduledEndDate >= ScheduledStartDate) AND
            (EstimatedCompletionDate IS NULL OR EstimatedCompletionDate >= AssignmentDate)
        )
    );
    
    CREATE NONCLUSTERED INDEX IX_FactConsequenceAssignment_StudentKey ON wellbeing.factConsequenceAssignment(StudentKey);
    CREATE NONCLUSTERED INDEX IX_FactConsequenceAssignment_IncidentId ON wellbeing.factConsequenceAssignment(IncidentId);
    CREATE NONCLUSTERED INDEX IX_FactConsequenceAssignment_ConsequenceId ON wellbeing.factConsequenceAssignment(ConsequenceId);
    CREATE NONCLUSTERED INDEX IX_FactConsequenceAssignment_ApprovalStatus ON wellbeing.factConsequenceAssignment(ApprovalStatusKey);
    CREATE NONCLUSTERED INDEX IX_FactConsequenceAssignment_AssignmentDate ON wellbeing.factConsequenceAssignment(AssignmentDate DESC);
    CREATE NONCLUSTERED INDEX IX_FactConsequenceAssignment_Completion ON wellbeing.factConsequenceAssignment(WasCompleted, CompletedDate);
    
    PRINT 'Table [wellbeing.factConsequenceAssignment] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.factConsequenceAssignment] already exists.';
GO

-- ============================================================================
-- APPROVAL HISTORY FACT TABLE
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factApprovalHistory') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.factApprovalHistory (
        ApprovalHistoryId INT PRIMARY KEY IDENTITY(1,1),
        RecordType NVARCHAR(50) NOT NULL,  -- 'Incident' or 'Consequence'
        RecordId INT NOT NULL,  -- IncidentId or ConsequenceAssignmentId
        WorkflowId INT,  -- Reference to wellbeing.tblApprovalWorkflows
        SequenceNumber INT,  -- Which step in workflow
        
        RequiredApproverRole NVARCHAR(100),
        AssignedApproverKey INT,  -- Reference to gold.dimStaff
        AssignedApproverEmail NVARCHAR(255),
        
        ApprovalStatusKey INT NOT NULL,  -- Reference to wellbeing.dimApprovalStatus
        ActionDate DATETIME2 NOT NULL,
        ActionTakenBy NVARCHAR(255),
        ApprovalNotes NVARCHAR(1000),
        
        DelegatedToKey INT,  -- If delegated to another approver
        DelegatedToEmail NVARCHAR(255),
        DelegationReason NVARCHAR(500),
        DelegationDate DATETIME2,
        
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    
    CREATE NONCLUSTERED INDEX IX_ApprovalHistory_RecordId ON wellbeing.factApprovalHistory(RecordType, RecordId);
    CREATE NONCLUSTERED INDEX IX_ApprovalHistory_ApproverKey ON wellbeing.factApprovalHistory(AssignedApproverKey);
    CREATE NONCLUSTERED INDEX IX_ApprovalHistory_Status ON wellbeing.factApprovalHistory(ApprovalStatusKey);
    CREATE NONCLUSTERED INDEX IX_ApprovalHistory_ActionDate ON wellbeing.factApprovalHistory(ActionDate DESC);
    
    PRINT 'Table [wellbeing.factApprovalHistory] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.factApprovalHistory] already exists.';
GO

-- ============================================================================
-- PASTORAL INTERVENTION FACT TABLE
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factPastoralIntervention') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.factPastoralIntervention (
        InterventionId INT PRIMARY KEY IDENTITY(1,1),
        InterventionNumber NVARCHAR(50) NOT NULL UNIQUE,
        StudentKey INT NOT NULL,  -- Reference to gold.dimStudent
        StaffKey INT NOT NULL,  -- Pastoral care staff member
        
        InterventionType NVARCHAR(100),  -- 'Counseling', 'Meeting', 'Support', 'Referral', etc.
        InterventionDate DATE NOT NULL,
        InterventionTime TIME,
        InterventionDuration INT,  -- Duration in minutes
        
        InterventionDetails NVARCHAR(MAX),
        Outcome NVARCHAR(MAX),
        RecommendedActions NVARCHAR(MAX),
        
        FollowUpRequired BIT DEFAULT 1,
        FollowUpDueDate DATE,
        FollowUpCompletedDate DATETIME2,
        
        RelatedIncidentId INT,  -- Reference to wellbeing.factBehaviourIncident if related
        
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
    
    CREATE NONCLUSTERED INDEX IX_PastoralIntervention_StudentKey ON wellbeing.factPastoralIntervention(StudentKey);
    CREATE NONCLUSTERED INDEX IX_PastoralIntervention_StaffKey ON wellbeing.factPastoralIntervention(StaffKey);
    CREATE NONCLUSTERED INDEX IX_PastoralIntervention_Date ON wellbeing.factPastoralIntervention(InterventionDate DESC);
    CREATE NONCLUSTERED INDEX IX_PastoralIntervention_FollowUp ON wellbeing.factPastoralIntervention(FollowUpRequired, FollowUpDueDate);
    
    PRINT 'Table [wellbeing.factPastoralIntervention] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.factPastoralIntervention] already exists.';
GO

-- ============================================================================
-- STUDENT SUPPORT PLAN FACT TABLE
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factStudentSupportPlan') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.factStudentSupportPlan (
        SupportPlanId INT PRIMARY KEY IDENTITY(1,1),
        SupportPlanNumber NVARCHAR(50) NOT NULL UNIQUE,
        StudentKey INT NOT NULL,  -- Reference to gold.dimStudent
        CreatedByStaffKey INT NOT NULL,
        ApprovedByStaffKey INT,
        
        PlanType NVARCHAR(100),  -- 'Behavior Support', 'Wellbeing Plan', 'Intervention Plan'
        CreatedDate DATE NOT NULL,
        EffectiveStartDate DATE NOT NULL,
        EffectiveEndDate DATE,
        ReviewDate DATE,
        
        PlanObjectives NVARCHAR(MAX),  -- Goals/objectives of the plan
        StrategyDetails NVARCHAR(MAX),  -- Strategies to support student
        KeyStaffResponsibilities NVARCHAR(MAX),
        StudentResponsibilities NVARCHAR(MAX),
        ParentResponsibilities NVARCHAR(MAX),
        
        MonitoringFrequency NVARCHAR(100),  -- 'Weekly', 'Fortnightly', 'Monthly'
        SuccessCriteria NVARCHAR(MAX),
        ReviewOutcome NVARCHAR(MAX),
        
        IsActive BIT NOT NULL DEFAULT 1,
        PlanStatus NVARCHAR(50),  -- 'Draft', 'Active', 'Under Review', 'Completed'
        
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
    
    CREATE NONCLUSTERED INDEX IX_SupportPlan_StudentKey ON wellbeing.factStudentSupportPlan(StudentKey);
    CREATE NONCLUSTERED INDEX IX_SupportPlan_Active ON wellbeing.factStudentSupportPlan(IsActive);
    CREATE NONCLUSTERED INDEX IX_SupportPlan_ReviewDate ON wellbeing.factStudentSupportPlan(ReviewDate);
    
    PRINT 'Table [wellbeing.factStudentSupportPlan] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.factStudentSupportPlan] already exists.';
GO

-- ============================================================================
-- WELLBEING NOTE FACT TABLE (For general observations)
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factWellbeingNote') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.factWellbeingNote (
        WellbeingNoteId INT PRIMARY KEY IDENTITY(1,1),
        StudentKey INT NOT NULL,  -- Reference to gold.dimStudent
        StaffKey INT NOT NULL,  -- Who created the note
        
        NoteType NVARCHAR(50),  -- 'General', 'Concern', 'Positive', 'Medical', 'Safeguarding'
        NoteDate DATE NOT NULL,
        NoteContent NVARCHAR(MAX),
        
        IsConfidential BIT DEFAULT 0,
        RequiresFollowUp BIT DEFAULT 0,
        FollowUpDueDate DATE,
        
        RelatedIncidentId INT,  -- If related to an incident
        
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
    
    CREATE NONCLUSTERED INDEX IX_WellbeingNote_StudentKey ON wellbeing.factWellbeingNote(StudentKey);
    CREATE NONCLUSTERED INDEX IX_WellbeingNote_NoteDate ON wellbeing.factWellbeingNote(NoteDate DESC);
    CREATE NONCLUSTERED INDEX IX_WellbeingNote_NoteType ON wellbeing.factWellbeingNote(NoteType);
    
    PRINT 'Table [wellbeing.factWellbeingNote] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.factWellbeingNote] already exists.';
GO

-- ============================================================================
-- INCIDENT NOTIFICATION FACT TABLE
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factIncidentNotification') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.factIncidentNotification (
        NotificationId INT PRIMARY KEY IDENTITY(1,1),
        IncidentId INT NOT NULL,  -- Reference to wellbeing.factBehaviourIncident
        StudentKey INT NOT NULL,
        ParentGuardianId INT,  -- Reference to parent/guardian (gold.dimParent)
        
        NotificationType NVARCHAR(100),  -- 'Email', 'SMS', 'Letter', 'Phone Call'
        TemplateId INT,  -- Reference to wellbeing.tblCommunicationTemplates
        
        RecipientName NVARCHAR(255),
        RecipientEmail NVARCHAR(255),
        RecipientPhone NVARCHAR(20),
        
        NotificationDate DATETIME2 NOT NULL,
        NotificationSentDate DATETIME2,
        NotificationStatus NVARCHAR(50),  -- 'Pending', 'Sent', 'Failed', 'Delivered', 'Bounced'
        StatusMessage NVARCHAR(500),
        
        NotificationContent NVARCHAR(MAX),
        ParentAcknowledged BIT DEFAULT 0,
        AcknowledgedDate DATETIME2,
        AcknowledgmentMethod NVARCHAR(100),  -- 'Email Reply', 'Phone Call', 'In Person'
        
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255)
    );
    
    CREATE NONCLUSTERED INDEX IX_IncidentNotification_IncidentId ON wellbeing.factIncidentNotification(IncidentId);
    CREATE NONCLUSTERED INDEX IX_IncidentNotification_StudentKey ON wellbeing.factIncidentNotification(StudentKey);
    CREATE NONCLUSTERED INDEX IX_IncidentNotification_Status ON wellbeing.factIncidentNotification(NotificationStatus);
    CREATE NONCLUSTERED INDEX IX_IncidentNotification_Date ON wellbeing.factIncidentNotification(NotificationDate DESC);
    
    PRINT 'Table [wellbeing.factIncidentNotification] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.factIncidentNotification] already exists.';
GO

-- ============================================================================
-- AUDIT TRAIL TABLE
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factAuditTrail') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.factAuditTrail (
        AuditId BIGINT PRIMARY KEY IDENTITY(1,1),
        AuditDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        AuditUser NVARCHAR(255) NOT NULL,
        AuditAction NVARCHAR(50) NOT NULL,  -- 'INSERT', 'UPDATE', 'DELETE'
        AuditTable NVARCHAR(100) NOT NULL,
        RecordId INT NOT NULL,
        FieldName NVARCHAR(100),
        OldValue NVARCHAR(MAX),
        NewValue NVARCHAR(MAX),
        IPAddress NVARCHAR(50),
        ApplicationModule NVARCHAR(100),
        AdditionalNotes NVARCHAR(500)
    );
    
    CREATE NONCLUSTERED INDEX IX_AuditTrail_Date ON wellbeing.factAuditTrail(AuditDate DESC);
    CREATE NONCLUSTERED INDEX IX_AuditTrail_Table ON wellbeing.factAuditTrail(AuditTable);
    CREATE NONCLUSTERED INDEX IX_AuditTrail_User ON wellbeing.factAuditTrail(AuditUser);
    CREATE NONCLUSTERED INDEX IX_AuditTrail_RecordId ON wellbeing.factAuditTrail(AuditTable, RecordId);
    
    PRINT 'Table [wellbeing.factAuditTrail] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.factAuditTrail] already exists.';
GO

PRINT '';
PRINT '============================================================================';
PRINT 'PHASE 2: Transactional Tables - COMPLETED';
PRINT '============================================================================';
PRINT '';
