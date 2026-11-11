-- ============================================================================
-- Student Wellbeing, Pastoral Care & Behaviour Management System
-- Database Schema Creation Script
-- ============================================================================
-- Purpose: Create the complete wellbeing schema with configuration and 
--          transactional tables for behaviour incident, pastoral care, 
--          and student support management.
-- 
-- Database: SchoolDW
-- Schema: wellbeing (new)
--
-- Execution Order:
--   1. Create schema
--   2. Create dimensions/status tables
--   3. Create configuration tables
--   4. Create fact tables
--   5. Create audit tables
--   6. Create indexes and foreign keys
--   7. Create views
--   8. Create stored procedures (separate file)
--
-- ============================================================================

USE SchoolDW;
GO

-- ============================================================================
-- STEP 1: CREATE SCHEMA
-- ============================================================================

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'wellbeing')
BEGIN
    EXEC sp_executesql N'CREATE SCHEMA wellbeing';
    PRINT 'Schema [wellbeing] created successfully.';
END
ELSE
    PRINT 'Schema [wellbeing] already exists.';
GO

-- ============================================================================
-- STEP 2: CREATE DIMENSION/STATUS TABLES
-- ============================================================================

-- Incident Status Dimension
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.dimIncidentStatus') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.dimIncidentStatus (
        IncidentStatusKey INT PRIMARY KEY IDENTITY(1,1),
        IncidentStatusCode NVARCHAR(50) NOT NULL UNIQUE,
        IncidentStatusName NVARCHAR(100) NOT NULL,
        IncidentStatusDescription NVARCHAR(500),
        DisplayOrder INT,
        IsActive BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    
    INSERT INTO wellbeing.dimIncidentStatus (IncidentStatusCode, IncidentStatusName, IncidentStatusDescription, DisplayOrder, IsActive)
    VALUES 
        ('DRAFT', 'Draft', 'Incident is in draft status - not yet submitted', 1, 1),
        ('SUBMITTED', 'Submitted', 'Incident submitted for review/processing', 2, 1),
        ('UNDER_REVIEW', 'Under Review', 'Incident is being reviewed by appropriate staff', 3, 1),
        ('APPROVED', 'Approved', 'Incident has been approved', 4, 1),
        ('REJECTED', 'Rejected', 'Incident has been rejected', 5, 1),
        ('CONSEQUENCE_ASSIGNED', 'Consequence Assigned', 'Consequence has been assigned', 6, 1),
        ('AWAITING_APPROVAL', 'Awaiting Approval', 'Consequence awaiting approval', 7, 1),
        ('COMPLETED', 'Completed', 'Incident and consequences completed', 8, 1),
        ('CLOSED', 'Closed', 'Incident is closed', 9, 1),
        ('ARCHIVED', 'Archived', 'Incident has been archived', 10, 1);
    
    PRINT 'Table [wellbeing.dimIncidentStatus] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.dimIncidentStatus] already exists.';
GO

-- Approval Status Dimension
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.dimApprovalStatus') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.dimApprovalStatus (
        ApprovalStatusKey INT PRIMARY KEY IDENTITY(1,1),
        ApprovalStatusCode NVARCHAR(50) NOT NULL UNIQUE,
        ApprovalStatusName NVARCHAR(100) NOT NULL,
        ApprovalStatusDescription NVARCHAR(500),
        DisplayOrder INT,
        IsActive BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE()
    );
    
    INSERT INTO wellbeing.dimApprovalStatus (ApprovalStatusCode, ApprovalStatusName, ApprovalStatusDescription, DisplayOrder, IsActive)
    VALUES 
        ('PENDING', 'Pending', 'Awaiting approval', 1, 1),
        ('APPROVED', 'Approved', 'Has been approved', 2, 1),
        ('REJECTED', 'Rejected', 'Has been rejected', 3, 1),
        ('DELEGATED', 'Delegated', 'Delegated to another approver', 4, 1),
        ('EXPIRED', 'Expired', 'Approval period has expired', 5, 1),
        ('OVERRIDDEN', 'Overridden', 'Approval has been overridden', 6, 1);
    
    PRINT 'Table [wellbeing.dimApprovalStatus] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.dimApprovalStatus] already exists.';
GO

-- ============================================================================
-- STEP 3: CREATE CONFIGURATION TABLES
-- ============================================================================

-- Staff Assignments (roles and responsibilities)
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.tblStaffAssignments') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.tblStaffAssignments (
        StaffAssignmentId INT PRIMARY KEY IDENTITY(1,1),
        StaffKey INT NOT NULL,  -- Foreign key to gold.dimStaff.StaffKey
        CompassStaffId NVARCHAR(50) NOT NULL,  -- Compass identifier for reference
        StaffEmail NVARCHAR(255),
        AssignedRole NVARCHAR(100) NOT NULL,  -- e.g., 'Head of House', 'Pastoral Care Staff', 'Admin'
        HouseAssignment NVARCHAR(100),  -- e.g., 'Blake', 'Dalton', etc.
        YearLevelResponsibility NVARCHAR(50),  -- e.g., '7', '8-10', NULL for all
        EffectiveStartDate DATE NOT NULL,
        EffectiveEndDate DATE,
        IsActive BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255),
        CONSTRAINT CK_StaffAssignments_DateRange CHECK (EffectiveEndDate IS NULL OR EffectiveEndDate >= EffectiveStartDate)
    );
    
    CREATE INDEX IX_StaffAssignments_StaffKey ON wellbeing.tblStaffAssignments(StaffKey);
    CREATE INDEX IX_StaffAssignments_Role_House ON wellbeing.tblStaffAssignments(AssignedRole, HouseAssignment);
    CREATE INDEX IX_StaffAssignments_Active ON wellbeing.tblStaffAssignments(IsActive);
    
    PRINT 'Table [wellbeing.tblStaffAssignments] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.tblStaffAssignments] already exists.';
GO

-- School Locations
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.tblSchoolLocations') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.tblSchoolLocations (
        LocationId INT PRIMARY KEY IDENTITY(1,1),
        LocationCode NVARCHAR(50) NOT NULL UNIQUE,
        LocationName NVARCHAR(100) NOT NULL,
        LocationDescription NVARCHAR(500),
        LocationCategory NVARCHAR(100),  -- e.g., 'Classroom', 'Playground', 'Sports Facility'
        ResponsibleDepartment NVARCHAR(100),
        ResponsibleStaffKey INT,  -- Reference to gold.dimStaff
        IsActive BIT NOT NULL DEFAULT 1,
        DisplayOrder INT,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
    
    CREATE INDEX IX_SchoolLocations_Category ON wellbeing.tblSchoolLocations(LocationCategory);
    CREATE INDEX IX_SchoolLocations_Active ON wellbeing.tblSchoolLocations(IsActive);
    
    PRINT 'Table [wellbeing.tblSchoolLocations] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.tblSchoolLocations] already exists.';
GO

-- Incident Types
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.tblIncidentTypes') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.tblIncidentTypes (
        IncidentTypeId INT PRIMARY KEY IDENTITY(1,1),
        IncidentTypeCode NVARCHAR(50) NOT NULL UNIQUE,
        IncidentTypeName NVARCHAR(100) NOT NULL,
        IncidentTypeDescription NVARCHAR(500),
        IsActive BIT NOT NULL DEFAULT 1,
        DisplayOrder INT,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
    
    -- Sample incident types
    INSERT INTO wellbeing.tblIncidentTypes (IncidentTypeCode, IncidentTypeName, IncidentTypeDescription, DisplayOrder, IsActive)
    VALUES 
        ('DISRUPTIVE', 'Disruptive Behaviour', 'Disruptive behavior in classroom or school', 1, 1),
        ('PHYSICAL_AGG', 'Physical Aggression', 'Physical aggression or violence', 2, 1),
        ('VERBAL_AGG', 'Verbal Aggression', 'Verbal aggression or abusive language', 3, 1),
        ('BULLYING', 'Bullying', 'Bullying behavior towards other students', 4, 1),
        ('CYBERBULLY', 'Cyberbullying', 'Cyberbullying or online harassment', 5, 1),
        ('PROPERTY_DMG', 'Property Damage', 'Damage to school property', 6, 1),
        ('INAP_LANG', 'Inappropriate Language', 'Use of inappropriate or offensive language', 7, 1),
        ('REFUSAL', 'Refusal to Follow Instructions', 'Refusal to follow instructions', 8, 1),
        ('UNSAFE', 'Unsafe Behaviour', 'Unsafe behavior or risk to safety', 9, 1),
        ('REPEAT_DISRUPT', 'Repeated Classroom Disruption', 'Repeated disruption in class', 10, 1),
        ('HARASSMENT', 'Harassment', 'Harassment of students or staff', 11, 1),
        ('OTHER', 'Other', 'Other incidents not listed above', 12, 1);
    
    CREATE INDEX IX_IncidentTypes_Active ON wellbeing.tblIncidentTypes(IsActive);
    
    PRINT 'Table [wellbeing.tblIncidentTypes] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.tblIncidentTypes] already exists.';
GO

-- Incident Classifications
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.tblIncidentClassifications') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.tblIncidentClassifications (
        ClassificationId INT PRIMARY KEY IDENTITY(1,1),
        ClassificationCode NVARCHAR(50) NOT NULL UNIQUE,
        ClassificationName NVARCHAR(100) NOT NULL,
        ClassificationDescription NVARCHAR(500),
        SeverityLevel INT,  -- 1=Low, 2=Medium, 3=High, 4=Critical
        PolicyReference NVARCHAR(500),
        RequiresApproval BIT NOT NULL DEFAULT 1,
        RequiresParentNotification BIT NOT NULL DEFAULT 1,
        ApprovalRoleRequired NVARCHAR(100),  -- e.g., 'Head of House', 'Principal'
        IsActive BIT NOT NULL DEFAULT 1,
        DisplayOrder INT,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
    
    -- Sample classifications based on severity
    INSERT INTO wellbeing.tblIncidentClassifications (ClassificationCode, ClassificationName, ClassificationDescription, SeverityLevel, RequiresApproval, RequiresParentNotification, ApprovalRoleRequired, DisplayOrder, IsActive)
    VALUES 
        ('MINOR', 'Minor Incident', 'Minor behavioral incident - handled by classroom teacher', 1, 0, 0, 'Classroom Teacher', 1, 1),
        ('MODERATE', 'Moderate Incident', 'Moderate incident requiring house/pastoral intervention', 2, 1, 1, 'Head of House', 2, 1),
        ('SERIOUS', 'Serious Incident', 'Serious incident requiring leadership review', 3, 1, 1, 'Deputy Principal', 3, 1),
        ('CRITICAL', 'Critical Incident', 'Critical incident requiring immediate principal involvement', 4, 1, 1, 'Principal', 4, 1);
    
    CREATE INDEX IX_Classifications_Severity ON wellbeing.tblIncidentClassifications(SeverityLevel);
    CREATE INDEX IX_Classifications_Active ON wellbeing.tblIncidentClassifications(IsActive);
    
    PRINT 'Table [wellbeing.tblIncidentClassifications] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.tblIncidentClassifications] already exists.';
GO

-- Behaviour Policy Levels
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.tblBehaviourPolicyLevels') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.tblBehaviourPolicyLevels (
        PolicyLevelId INT PRIMARY KEY IDENTITY(1,1),
        PolicyLevelCode NVARCHAR(50) NOT NULL UNIQUE,
        PolicyLevelName NVARCHAR(100) NOT NULL,
        PolicyLevelDescription NVARCHAR(500),
        SeverityScore INT,  -- Numeric score for escalation logic
        IsActive BIT NOT NULL DEFAULT 1,
        DisplayOrder INT,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
    
    INSERT INTO wellbeing.tblBehaviourPolicyLevels (PolicyLevelCode, PolicyLevelName, PolicyLevelDescription, SeverityScore, DisplayOrder, IsActive)
    VALUES 
        ('LEVEL_1', 'Level 1 - Classroom Management', 'Handled by classroom teacher', 1, 1, 1),
        ('LEVEL_2', 'Level 2 - Form Tutor/Year Coordinator', 'Escalated to form tutor/year coordinator', 2, 2, 1),
        ('LEVEL_3', 'Level 3 - Head of House', 'Escalated to Head of House', 3, 3, 1),
        ('LEVEL_4', 'Level 4 - Senior Leadership', 'Escalated to Deputy Principal/Principal', 4, 4, 1),
        ('LEVEL_5', 'Level 5 - Formal Process', 'Formal disciplinary process', 5, 5, 1);
    
    CREATE INDEX IX_PolicyLevels_Severity ON wellbeing.tblBehaviourPolicyLevels(SeverityScore);
    CREATE INDEX IX_PolicyLevels_Active ON wellbeing.tblBehaviourPolicyLevels(IsActive);
    
    PRINT 'Table [wellbeing.tblBehaviourPolicyLevels] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.tblBehaviourPolicyLevels] already exists.';
GO

-- Consequences (configurable consequences that can be assigned)
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.tblConsequences') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.tblConsequences (
        ConsequenceId INT PRIMARY KEY IDENTITY(1,1),
        ConsequenceCode NVARCHAR(50) NOT NULL UNIQUE,
        ConsequenceName NVARCHAR(100) NOT NULL,
        ConsequenceDescription NVARCHAR(500),
        PolicyLevelId INT NOT NULL,  -- Linked to behaviour policy level
        SeverityLevel INT,  -- 1-5 scale
        RequiresApproval BIT NOT NULL DEFAULT 0,
        ApprovalRoleRequired NVARCHAR(100),
        EstimatedDurationDays INT,  -- e.g., detention for X days
        CanBeOverridden BIT NOT NULL DEFAULT 0,
        IsActive BIT NOT NULL DEFAULT 1,
        DisplayOrder INT,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
    
    INSERT INTO wellbeing.tblConsequences (ConsequenceCode, ConsequenceName, ConsequenceDescription, PolicyLevelId, SeverityLevel, RequiresApproval, DisplayOrder, IsActive)
    VALUES 
        ('REPRIMAND', 'Verbal Reprimand', 'Verbal warning/reprimand', 1, 1, 0, 1, 1),
        ('WARNING', 'Written Warning', 'Formal written warning', 2, 2, 0, 2, 1),
        ('DETENTION', 'Detention', 'After-school detention', 2, 2, 0, 3, 1),
        ('DETENTION_LUNCH', 'Lunch Detention', 'Lunch-time detention', 2, 2, 0, 4, 1),
        ('PARENT_CONTACT', 'Parent Contact', 'Contact parents/guardians', 2, 2, 0, 5, 1),
        ('SUSPENSION', 'Suspension', 'Temporary suspension from school', 3, 4, 1, 6, 1),
        ('EXCLUSION', 'Permanent Exclusion', 'Permanent exclusion from school', 4, 5, 1, 7, 1),
        ('RESTORATIVE', 'Restorative Meeting', 'Restorative justice meeting', 3, 3, 0, 8, 1),
        ('BEHAVIOR_PLAN', 'Behavior Support Plan', 'Formal behavior support plan', 3, 3, 0, 9, 1),
        ('COUNSELLING', 'Counselling Referral', 'Referral for counselling/support', 2, 2, 0, 10, 1);
    
    CREATE INDEX IX_Consequences_PolicyLevel ON wellbeing.tblConsequences(PolicyLevelId);
    CREATE INDEX IX_Consequences_Severity ON wellbeing.tblConsequences(SeverityLevel);
    CREATE INDEX IX_Consequences_Active ON wellbeing.tblConsequences(IsActive);
    
    PRINT 'Table [wellbeing.tblConsequences] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.tblConsequences] already exists.';
GO

-- Approval Workflow Configuration
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.tblApprovalWorkflows') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.tblApprovalWorkflows (
        WorkflowId INT PRIMARY KEY IDENTITY(1,1),
        WorkflowName NVARCHAR(100) NOT NULL,
        WorkflowDescription NVARCHAR(500),
        TriggerCondition NVARCHAR(500),  -- e.g., 'Classification = SERIOUS'
        SequenceOrder INT,
        RequiredApproverRole NVARCHAR(100),  -- e.g., 'Head of House'
        ApprovalTimeoutDays INT DEFAULT 3,
        RequiresEachApprover BIT DEFAULT 0,  -- If true, all specified approvers must approve
        AllowDelegation BIT DEFAULT 1,  -- Allow approver to delegate
        AllowOverride BIT DEFAULT 1,  -- Allow override to next level
        IsActive BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
    
    INSERT INTO wellbeing.tblApprovalWorkflows (WorkflowName, WorkflowDescription, TriggerCondition, SequenceOrder, RequiredApproverRole, ApprovalTimeoutDays, DisplayOrder, IsActive)
    VALUES 
        ('Minor Incident', 'Minor incidents - no approval required', 'Classification = MINOR', 0, 'Teacher', 1, 1, 1),
        ('Moderate Incident', 'Moderate incidents - Head of House approval', 'Classification = MODERATE', 1, 'Head of House', 3, 2, 1),
        ('Serious Incident', 'Serious incidents - Deputy Principal approval', 'Classification = SERIOUS', 1, 'Deputy Principal', 2, 3, 1),
        ('Critical Incident', 'Critical incidents - Principal approval', 'Classification = CRITICAL', 1, 'Principal', 1, 4, 1);
    
    CREATE INDEX IX_Workflows_Trigger ON wellbeing.tblApprovalWorkflows(TriggerCondition);
    CREATE INDEX IX_Workflows_Active ON wellbeing.tblApprovalWorkflows(IsActive);
    
    PRINT 'Table [wellbeing.tblApprovalWorkflows] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.tblApprovalWorkflows] already exists.';
GO

-- Communication Templates
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.tblCommunicationTemplates') AND type in (N'U'))
BEGIN
    CREATE TABLE wellbeing.tblCommunicationTemplates (
        TemplateId INT PRIMARY KEY IDENTITY(1,1),
        TemplateName NVARCHAR(100) NOT NULL,
        TemplateCode NVARCHAR(50) NOT NULL UNIQUE,
        TemplateDescription NVARCHAR(500),
        CommunicationType NVARCHAR(50),  -- 'Email', 'SMS', 'Letter'
        TemplateSubject NVARCHAR(255),
        TemplateBody NVARCHAR(MAX),  -- Contains placeholders like {{StudentName}}, {{IncidentDate}}
        RecipientType NVARCHAR(50),  -- 'Parent', 'Staff', 'Student'
        IsDefault BIT DEFAULT 0,
        IsActive BIT NOT NULL DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255),
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255)
    );
    
    CREATE INDEX IX_CommunicationTemplates_Type ON wellbeing.tblCommunicationTemplates(CommunicationType);
    CREATE INDEX IX_CommunicationTemplates_Active ON wellbeing.tblCommunicationTemplates(IsActive);
    
    PRINT 'Table [wellbeing.tblCommunicationTemplates] created successfully.';
END
ELSE
    PRINT 'Table [wellbeing.tblCommunicationTemplates] already exists.';
GO

PRINT '';
PRINT '============================================================================';
PRINT 'PHASE 1: Configuration Tables - COMPLETED';
PRINT '============================================================================';
PRINT '';
