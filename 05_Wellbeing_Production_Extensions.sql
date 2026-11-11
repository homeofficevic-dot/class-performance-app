USE SchoolDW;
GO

IF NOT EXISTS (SELECT 1 FROM sys.synonyms WHERE name = N'StaffRoleAssignment' AND schema_id = SCHEMA_ID(N'wellbeing'))
    CREATE SYNONYM wellbeing.StaffRoleAssignment FOR wellbeing.tblStaffAssignments;
IF NOT EXISTS (SELECT 1 FROM sys.synonyms WHERE name = N'SchoolLocation' AND schema_id = SCHEMA_ID(N'wellbeing'))
    CREATE SYNONYM wellbeing.SchoolLocation FOR wellbeing.tblSchoolLocations;
IF NOT EXISTS (SELECT 1 FROM sys.synonyms WHERE name = N'IncidentClassification' AND schema_id = SCHEMA_ID(N'wellbeing'))
    CREATE SYNONYM wellbeing.IncidentClassification FOR wellbeing.tblIncidentClassifications;
IF NOT EXISTS (SELECT 1 FROM sys.synonyms WHERE name = N'IncidentType' AND schema_id = SCHEMA_ID(N'wellbeing'))
    CREATE SYNONYM wellbeing.IncidentType FOR wellbeing.tblIncidentTypes;
IF NOT EXISTS (SELECT 1 FROM sys.synonyms WHERE name = N'BehaviourPolicyLevel' AND schema_id = SCHEMA_ID(N'wellbeing'))
    CREATE SYNONYM wellbeing.BehaviourPolicyLevel FOR wellbeing.tblBehaviourPolicyLevels;
IF NOT EXISTS (SELECT 1 FROM sys.synonyms WHERE name = N'Consequence' AND schema_id = SCHEMA_ID(N'wellbeing'))
    CREATE SYNONYM wellbeing.Consequence FOR wellbeing.tblConsequences;
GO

IF OBJECT_ID(N'wellbeing.WorkflowInstance', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.WorkflowInstance (
        WorkflowInstanceId BIGINT IDENTITY(1,1) PRIMARY KEY,
        ApprovalWorkflowId INT NOT NULL,
        IncidentId INT NULL,
        StatusCode NVARCHAR(30) NOT NULL DEFAULT N'OPEN',
        StartedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CompletedDate DATETIME2 NULL,
        EffectiveStartDate DATE NOT NULL DEFAULT CAST(GETUTCDATE() AS DATE),
        EffectiveEndDate DATE NULL,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255) NULL,
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255) NULL,
        CONSTRAINT CK_WorkflowInstance_DateRange CHECK (EffectiveEndDate IS NULL OR EffectiveEndDate >= EffectiveStartDate),
        CONSTRAINT FK_WorkflowInstance_Workflow FOREIGN KEY (ApprovalWorkflowId) REFERENCES wellbeing.ApprovalWorkflow(ApprovalWorkflowId),
        CONSTRAINT FK_WorkflowInstance_Incident FOREIGN KEY (IncidentId) REFERENCES wellbeing.factBehaviourIncident(IncidentId)
    );
END;
GO

IF OBJECT_ID(N'wellbeing.WorkflowTask', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.WorkflowTask (
        WorkflowTaskId BIGINT IDENTITY(1,1) PRIMARY KEY,
        WorkflowInstanceId BIGINT NOT NULL,
        ApprovalWorkflowStepId INT NOT NULL,
        AssignedStaffKey INT NULL,
        StatusCode NVARCHAR(30) NOT NULL DEFAULT N'PENDING',
        DueDate DATE NULL,
        CompletedDate DATETIME2 NULL,
        CompletedBy NVARCHAR(255) NULL,
        Notes NVARCHAR(MAX) NULL,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255) NULL,
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255) NULL,
        CONSTRAINT FK_WorkflowTask_Instance FOREIGN KEY (WorkflowInstanceId) REFERENCES wellbeing.WorkflowInstance(WorkflowInstanceId),
        CONSTRAINT FK_WorkflowTask_Step FOREIGN KEY (ApprovalWorkflowStepId) REFERENCES wellbeing.ApprovalWorkflowStep(ApprovalWorkflowStepId)
    );
END;
GO

IF OBJECT_ID(N'wellbeing.WorkflowApproval', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.WorkflowApproval (
        WorkflowApprovalId BIGINT IDENTITY(1,1) PRIMARY KEY,
        WorkflowTaskId BIGINT NOT NULL,
        ApprovalStatusKey INT NOT NULL DEFAULT 1,
        ApproverStaffKey INT NULL,
        DecisionDate DATETIME2 NULL,
        DecisionNotes NVARCHAR(MAX) NULL,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255) NULL,
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255) NULL,
        CONSTRAINT FK_WorkflowApproval_Task FOREIGN KEY (WorkflowTaskId) REFERENCES wellbeing.WorkflowTask(WorkflowTaskId),
        CONSTRAINT FK_WorkflowApproval_Status FOREIGN KEY (ApprovalStatusKey) REFERENCES wellbeing.dimApprovalStatus(ApprovalStatusKey)
    );
END;
GO

IF OBJECT_ID(N'wellbeing.ParentNotification', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.ParentNotification (
        ParentNotificationId BIGINT IDENTITY(1,1) PRIMARY KEY,
        IncidentId INT NOT NULL,
        StudentKey INT NOT NULL,
        CommunicationTemplateId INT NULL,
        Channel NVARCHAR(30) NOT NULL,
        Recipient NVARCHAR(255) NULL,
        StatusCode NVARCHAR(30) NOT NULL DEFAULT N'PENDING',
        SentDate DATETIME2 NULL,
        MessageSubject NVARCHAR(500) NULL,
        MessageBody NVARCHAR(MAX) NULL,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255) NULL,
        ModifiedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        ModifiedBy NVARCHAR(255) NULL,
        CONSTRAINT FK_ParentNotification_Incident FOREIGN KEY (IncidentId) REFERENCES wellbeing.factBehaviourIncident(IncidentId),
        CONSTRAINT FK_ParentNotification_Template FOREIGN KEY (CommunicationTemplateId) REFERENCES wellbeing.CommunicationTemplate(CommunicationTemplateId)
    );
END;
GO

IF OBJECT_ID(N'wellbeing.ParentConsentResponse', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.ParentConsentResponse (
        ParentConsentResponseId BIGINT IDENTITY(1,1) PRIMARY KEY,
        ParentNotificationId BIGINT NOT NULL,
        ResponseCode NVARCHAR(30) NOT NULL,
        ResponseDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        RespondentName NVARCHAR(255) NULL,
        Notes NVARCHAR(MAX) NULL,
        CreatedDate DATETIME2 NOT NULL DEFAULT GETUTCDATE(),
        CreatedBy NVARCHAR(255) NULL,
        CONSTRAINT FK_ParentConsentResponse_Notification FOREIGN KEY (ParentNotificationId) REFERENCES wellbeing.ParentNotification(ParentNotificationId)
    );
END;
GO

CREATE INDEX IX_WorkflowInstance_Incident ON wellbeing.WorkflowInstance(IncidentId);
CREATE INDEX IX_WorkflowTask_Instance ON wellbeing.WorkflowTask(WorkflowInstanceId);
CREATE INDEX IX_WorkflowApproval_Task ON wellbeing.WorkflowApproval(WorkflowTaskId);
CREATE INDEX IX_ParentNotification_Incident ON wellbeing.ParentNotification(IncidentId);
CREATE INDEX IX_ParentConsentResponse_Notification ON wellbeing.ParentConsentResponse(ParentNotificationId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Incident_Location')
    ALTER TABLE wellbeing.factBehaviourIncident WITH CHECK ADD CONSTRAINT FK_Incident_Location FOREIGN KEY (LocationId) REFERENCES wellbeing.tblSchoolLocations(LocationId);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Incident_Type')
    ALTER TABLE wellbeing.factBehaviourIncident WITH CHECK ADD CONSTRAINT FK_Incident_Type FOREIGN KEY (IncidentTypeId) REFERENCES wellbeing.tblIncidentTypes(IncidentTypeId);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Incident_Classification')
    ALTER TABLE wellbeing.factBehaviourIncident WITH CHECK ADD CONSTRAINT FK_Incident_Classification FOREIGN KEY (ClassificationId) REFERENCES wellbeing.tblIncidentClassifications(ClassificationId);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Incident_PolicyLevel')
    ALTER TABLE wellbeing.factBehaviourIncident WITH CHECK ADD CONSTRAINT FK_Incident_PolicyLevel FOREIGN KEY (PolicyLevelId) REFERENCES wellbeing.tblBehaviourPolicyLevels(PolicyLevelId);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Incident_Status')
    ALTER TABLE wellbeing.factBehaviourIncident WITH CHECK ADD CONSTRAINT FK_Incident_Status FOREIGN KEY (IncidentStatusKey) REFERENCES wellbeing.dimIncidentStatus(IncidentStatusKey);
GO

IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = N'IncidentNumberSequence' AND schema_id = SCHEMA_ID(N'wellbeing'))
    EXEC(N'CREATE SEQUENCE wellbeing.IncidentNumberSequence AS INT START WITH 1 INCREMENT BY 1;');
GO

IF COL_LENGTH(N'gold.dimStudent', N'CampusYearlevel') IS NULL
    ALTER TABLE gold.dimStudent ADD CampusYearlevel varchar(10) NULL;
GO

CREATE OR ALTER VIEW wellbeing.vwStudentDirectory
AS
SELECT
    s.StudentKey,
    s.CompassPersonId,
    s.StudentCode,
    s.Username,
    COALESCE(NULLIF(s.PreferredFirstName, N''), s.FirstName) AS StudentFirstName,
    COALESCE(NULLIF(s.PreferredLastName, N''), s.LastName) AS StudentLastName,
    CONCAT(
        COALESCE(NULLIF(s.PreferredFirstName, N''), s.FirstName),
        CASE WHEN COALESCE(NULLIF(s.PreferredFirstName, N''), s.FirstName) IS NULL
                  OR COALESCE(NULLIF(s.PreferredLastName, N''), s.LastName) IS NULL THEN N'' ELSE N' ' END,
        COALESCE(NULLIF(s.PreferredLastName, N''), s.LastName)
    ) AS StudentName,
    s.YearLevel,
    s.CampusYearlevel,
    s.EmailAddress,
    s.SchoolEmail,
    c.CampusKey,
    c.CampusCode,
    c.CampusName,
    c.CompassCampusId
FROM gold.dimStudent AS s
LEFT JOIN gold.dimCampus AS c ON c.CompassCampusId = s.HomeCampus AND c.IsCurrent = 1;
GO

CREATE OR ALTER VIEW wellbeing.vwStaffDirectory
AS
SELECT
    s.StaffKey,
    s.CompassPersonId,
    s.StaffCode,
    s.Username,
    CONCAT(s.FirstName, CASE WHEN s.FirstName IS NULL OR s.LastName IS NULL THEN N'' ELSE N' ' END, s.LastName) AS StaffName,
    s.FirstName,
    s.LastName,
    s.EmailAddress
FROM gold.dimStaff AS s
WHERE s.IsCurrent = 1;
GO

CREATE OR ALTER VIEW wellbeing.vwParentDirectory
AS
SELECT
    p.ParentKey,
    p.CompassPersonId,
    p.ParentCode,
    p.Username,
    CONCAT(p.FirstName, CASE WHEN p.FirstName IS NULL OR p.LastName IS NULL THEN N'' ELSE N' ' END, p.LastName) AS ParentName,
    p.FirstName,
    p.LastName,
    p.EmailAddress,
    p.MobileNumber
FROM gold.dimParent AS p
WHERE p.IsCurrent = 1;
GO

IF OBJECT_ID(N'wellbeing.IncidentStudent', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.IncidentStudent (
        IncidentId INT NOT NULL,
        StudentKey INT NOT NULL,
        IsPrimary BIT NOT NULL CONSTRAINT DF_IncidentStudent_IsPrimary DEFAULT 0,
        CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_IncidentStudent_CreatedDate DEFAULT GETDATE(),
        CONSTRAINT PK_IncidentStudent PRIMARY KEY (IncidentId, StudentKey),
        CONSTRAINT FK_IncidentStudent_Incident FOREIGN KEY (IncidentId) REFERENCES wellbeing.factBehaviourIncident(IncidentId)
    );
    CREATE INDEX IX_IncidentStudent_Student ON wellbeing.IncidentStudent(StudentKey, IncidentId);
END;
GO

CREATE OR ALTER VIEW wellbeing.vwIncidentDirectory
AS
SELECT
    i.IncidentId,
    i.IncidentNumber,
    i.StudentKey,
    COALESCE(agg.StudentNames, sd.StudentName) AS StudentName,
    sd.StudentCode,
    i.ReportingStaffKey,
    rs.StaffName AS ReportingStaffName,
    i.ReceivingStaffKey,
    rcv.StaffName AS ReceivingStaffName,
    i.LocationId,
    loc.LocationName,
    i.IncidentTypeId,
    it.IncidentTypeName,
    i.ClassificationId,
    ic.ClassificationName,
    i.PolicyLevelId,
    pl.PolicyLevelName,
    i.IncidentStatusKey,
    ist.IncidentStatusName,
    i.IncidentDate,
    i.IncidentTime,
    i.IncidentSummary,
    i.DetailedDescription,
    i.FollowUpNotes,
    i.WitnessCount,
    i.WitnessNames,
    i.SeverityIndicators,
    i.ContextualFactors,
    i.CreatedDate,
    i.CreatedBy,
    i.ModifiedDate,
    i.ModifiedBy,
    sd.CampusKey,
    sd.CampusCode,
    sd.CampusName
FROM wellbeing.factBehaviourIncident AS i
INNER JOIN wellbeing.vwStudentDirectory AS sd ON sd.StudentKey = i.StudentKey
OUTER APPLY (
    SELECT STRING_AGG(x.StudentName, N', ') AS StudentNames
    FROM (
        SELECT DISTINCT d.StudentName
        FROM wellbeing.IncidentStudent AS j
        INNER JOIN wellbeing.vwStudentDirectory AS d ON d.StudentKey = j.StudentKey
        WHERE j.IncidentId = i.IncidentId
    ) AS x
) AS agg
LEFT JOIN wellbeing.vwStaffDirectory AS rs ON rs.StaffKey = i.ReportingStaffKey
LEFT JOIN wellbeing.vwStaffDirectory AS rcv ON rcv.StaffKey = i.ReceivingStaffKey
LEFT JOIN wellbeing.tblSchoolLocations AS loc ON loc.LocationId = i.LocationId
LEFT JOIN wellbeing.tblIncidentTypes AS it ON it.IncidentTypeId = i.IncidentTypeId
LEFT JOIN wellbeing.tblIncidentClassifications AS ic ON ic.ClassificationId = i.ClassificationId
LEFT JOIN wellbeing.tblBehaviourPolicyLevels AS pl ON pl.PolicyLevelId = i.PolicyLevelId
LEFT JOIN wellbeing.dimIncidentStatus AS ist ON ist.IncidentStatusKey = i.IncidentStatusKey
WHERE i.IsDeleted = 0;
GO

CREATE INDEX IX_factBehaviourIncident_CampusDate
ON wellbeing.factBehaviourIncident (StudentKey, IncidentDate DESC, IncidentId DESC)
INCLUDE (IncidentNumber, ReportingStaffKey, IncidentTypeId, ClassificationId, PolicyLevelId, IncidentStatusKey);
GO

IF OBJECT_ID(N'wellbeing.IncidentStudent', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.IncidentStudent (
        IncidentId INT NOT NULL,
        StudentKey INT NOT NULL,
        IsPrimary BIT NOT NULL CONSTRAINT DF_IncidentStudent_IsPrimary DEFAULT 0,
        CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_IncidentStudent_CreatedDate DEFAULT GETDATE(),
        CONSTRAINT PK_IncidentStudent PRIMARY KEY (IncidentId, StudentKey),
        CONSTRAINT FK_IncidentStudent_Incident FOREIGN KEY (IncidentId) REFERENCES wellbeing.factBehaviourIncident(IncidentId)
    );
    CREATE INDEX IX_IncidentStudent_Student ON wellbeing.IncidentStudent(StudentKey, IncidentId);
END;
GO
