-- Migrates the verified reference rows supplied in Incident concequnces.txt.
-- Source IDs and relationship rows are preserved. No incident history is migrated
-- because the supplied export contains no Incident result set.
USE SchoolDW;
GO

SET XACT_ABORT ON;
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF COL_LENGTH(N'wellbeing.tblSchoolLocations', N'LegacyIncidentLocationId') IS NULL
    ALTER TABLE wellbeing.tblSchoolLocations ADD LegacyIncidentLocationId INT NULL;
IF COL_LENGTH(N'wellbeing.tblIncidentClassifications', N'LegacyGeneralClassificationId') IS NULL
    ALTER TABLE wellbeing.tblIncidentClassifications ADD LegacyGeneralClassificationId INT NULL;
IF COL_LENGTH(N'wellbeing.tblIncidentClassifications', N'LegacyLocationId') IS NULL
    ALTER TABLE wellbeing.tblIncidentClassifications ADD LegacyLocationId INT NULL;
IF COL_LENGTH(N'wellbeing.tblIncidentTypes', N'LegacyIncidentTypeId') IS NULL
    ALTER TABLE wellbeing.tblIncidentTypes ADD LegacyIncidentTypeId INT NULL;
IF COL_LENGTH(N'wellbeing.tblIncidentTypes', N'LegacyIncidentLevel') IS NULL
    ALTER TABLE wellbeing.tblIncidentTypes ADD LegacyIncidentLevel INT NULL;
IF COL_LENGTH(N'wellbeing.tblConsequences', N'LegacyConsequenceId') IS NULL
    ALTER TABLE wellbeing.tblConsequences ADD LegacyConsequenceId INT NULL;
IF COL_LENGTH(N'wellbeing.tblConsequences', N'LegacyAllowsMultiplePerDay') IS NULL
    ALTER TABLE wellbeing.tblConsequences ADD LegacyAllowsMultiplePerDay BIT NULL;
IF COL_LENGTH(N'wellbeing.tblConsequences', N'LegacyLength') IS NULL
    ALTER TABLE wellbeing.tblConsequences ADD LegacyLength INT NULL;
IF COL_LENGTH(N'wellbeing.tblConsequences', N'LegacyProcessorRole') IS NULL
    ALTER TABLE wellbeing.tblConsequences ADD LegacyProcessorRole NVARCHAR(255) NULL;
IF COL_LENGTH(N'wellbeing.tblConsequences', N'LegacyApprovalStatusKnown') IS NULL
    ALTER TABLE wellbeing.tblConsequences ADD LegacyApprovalStatusKnown BIT NOT NULL
        CONSTRAINT DF_tblConsequences_LegacyApprovalStatusKnown DEFAULT (0);
IF COL_LENGTH(N'wellbeing.factBehaviourIncident', N'LegacyIncidentLevel') IS NULL
    ALTER TABLE wellbeing.factBehaviourIncident ADD LegacyIncidentLevel INT NULL;
IF COL_LENGTH(N'wellbeing.factBehaviourIncident', N'IdempotencyKey') IS NULL
    ALTER TABLE wellbeing.factBehaviourIncident ADD IdempotencyKey UNIQUEIDENTIFIER NULL;
IF COL_LENGTH(N'wellbeing.IncidentStudent', N'StudentNameAtIncident') IS NULL
    ALTER TABLE wellbeing.IncidentStudent ADD StudentNameAtIncident NVARCHAR(300) NULL;
IF COL_LENGTH(N'wellbeing.IncidentStudent', N'StudentNameSnapshotStatus') IS NULL
    ALTER TABLE wellbeing.IncidentStudent ADD StudentNameSnapshotStatus NVARCHAR(40) NULL;
IF COL_LENGTH(N'wellbeing.IncidentStudent', N'StudentYearLevelAtIncident') IS NULL
    ALTER TABLE wellbeing.IncidentStudent ADD StudentYearLevelAtIncident NVARCHAR(50) NULL;
IF COL_LENGTH(N'wellbeing.IncidentStudent', N'StudentYearLevelIdAtIncident') IS NULL
    ALTER TABLE wellbeing.IncidentStudent ADD StudentYearLevelIdAtIncident NVARCHAR(100) NULL;
IF COL_LENGTH(N'wellbeing.IncidentStudent', N'StudentClassAtIncident') IS NULL
    ALTER TABLE wellbeing.IncidentStudent ADD StudentClassAtIncident NVARCHAR(100) NULL;
IF COL_LENGTH(N'wellbeing.IncidentStudent', N'YearLevelResolutionStatus') IS NULL
    ALTER TABLE wellbeing.IncidentStudent ADD YearLevelResolutionStatus NVARCHAR(40) NOT NULL
        CONSTRAINT DF_IncidentStudent_YearLevelResolutionStatus DEFAULT (N'INVESTIGATION_REQUIRED');
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'wellbeing.factBehaviourIncident') AND name=N'PolicyLevelId' AND is_nullable=0)
    ALTER TABLE wellbeing.factBehaviourIncident ALTER COLUMN PolicyLevelId INT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'wellbeing.factBehaviourIncident') AND name=N'UX_factBehaviourIncident_IdempotencyKey')
    CREATE UNIQUE INDEX UX_factBehaviourIncident_IdempotencyKey ON wellbeing.factBehaviourIncident(IdempotencyKey) WHERE IdempotencyKey IS NOT NULL;
GO

IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'wellbeing.tblIncidentClassifications') AND name=N'RequiresApproval' AND is_nullable=0)
    ALTER TABLE wellbeing.tblIncidentClassifications ALTER COLUMN RequiresApproval BIT NULL;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'wellbeing.tblIncidentClassifications') AND name=N'RequiresParentNotification' AND is_nullable=0)
    ALTER TABLE wellbeing.tblIncidentClassifications ALTER COLUMN RequiresParentNotification BIT NULL;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'wellbeing.tblConsequences') AND name=N'PolicyLevelId' AND is_nullable=0)
    ALTER TABLE wellbeing.tblConsequences ALTER COLUMN PolicyLevelId INT NULL;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'wellbeing.tblConsequences') AND name=N'RequiresApproval' AND is_nullable=0)
    ALTER TABLE wellbeing.tblConsequences ALTER COLUMN RequiresApproval BIT NULL;
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id=OBJECT_ID(N'wellbeing.tblConsequences') AND name=N'RequiresParentNotification' AND is_nullable=0)
    ALTER TABLE wellbeing.tblConsequences ALTER COLUMN RequiresParentNotification BIT NULL;
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
    i.LegacyIncidentLevel,
    agg.StudentYearLevelsAtIncident,
    agg.StudentYearLevelIdsAtIncident,
    agg.YearLevelResolutionStatuses,
    i.IncidentStatusKey,
    CASE WHEN i.IsDeleted = 1 THEN N'Cancelled' ELSE ist.IncidentStatusName END AS IncidentStatusName,
    i.IsDeleted,
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
LEFT JOIN wellbeing.vwStudentDirectory AS sd ON sd.StudentKey = i.StudentKey
OUTER APPLY (
    SELECT
        STRING_AGG(studentSnapshots.StudentNameAtIncident, N', ') AS StudentNames,
        STRING_AGG(studentSnapshots.StudentYearLevelAtIncident, N', ') AS StudentYearLevelsAtIncident,
        STRING_AGG(studentSnapshots.StudentYearLevelIdAtIncident, N', ') AS StudentYearLevelIdsAtIncident,
        STRING_AGG(studentSnapshots.YearLevelResolutionStatus, N', ') AS YearLevelResolutionStatuses
    FROM (
        SELECT DISTINCT
            COALESCE(j.StudentNameAtIncident, d.StudentName) AS StudentNameAtIncident,
            j.StudentYearLevelAtIncident,
            j.StudentYearLevelIdAtIncident,
            j.YearLevelResolutionStatus
        FROM wellbeing.IncidentStudent AS j
        LEFT JOIN wellbeing.vwStudentDirectory AS d ON d.StudentKey = j.StudentKey
        WHERE j.IncidentId = i.IncidentId
    ) AS studentSnapshots
) AS agg
LEFT JOIN wellbeing.vwStaffDirectory AS rs ON rs.StaffKey = i.ReportingStaffKey
LEFT JOIN wellbeing.vwStaffDirectory AS rcv ON rcv.StaffKey = i.ReceivingStaffKey
LEFT JOIN wellbeing.tblSchoolLocations AS loc ON loc.LocationId = i.LocationId
LEFT JOIN wellbeing.tblIncidentTypes AS it ON it.IncidentTypeId = i.IncidentTypeId
LEFT JOIN wellbeing.tblIncidentClassifications AS ic ON ic.ClassificationId = i.ClassificationId
LEFT JOIN wellbeing.tblBehaviourPolicyLevels AS pl ON pl.PolicyLevelId = i.PolicyLevelId
LEFT JOIN wellbeing.dimIncidentStatus AS ist ON ist.IncidentStatusKey = i.IncidentStatusKey
;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'wellbeing.tblSchoolLocations') AND name = N'UX_SchoolLocations_LegacyId')
    CREATE UNIQUE INDEX UX_SchoolLocations_LegacyId ON wellbeing.tblSchoolLocations(LegacyIncidentLocationId) WHERE LegacyIncidentLocationId IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'wellbeing.tblIncidentClassifications') AND name = N'UX_IncidentClassifications_LegacyId')
    CREATE UNIQUE INDEX UX_IncidentClassifications_LegacyId ON wellbeing.tblIncidentClassifications(LegacyGeneralClassificationId) WHERE LegacyGeneralClassificationId IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'wellbeing.tblIncidentTypes') AND name = N'UX_IncidentTypes_LegacyId')
    CREATE UNIQUE INDEX UX_IncidentTypes_LegacyId ON wellbeing.tblIncidentTypes(LegacyIncidentTypeId) WHERE LegacyIncidentTypeId IS NOT NULL;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'wellbeing.tblConsequences') AND name = N'UX_Consequences_LegacyId')
    CREATE UNIQUE INDEX UX_Consequences_LegacyId ON wellbeing.tblConsequences(LegacyConsequenceId) WHERE LegacyConsequenceId IS NOT NULL;
GO

IF OBJECT_ID(N'wellbeing.IncidentClassificationLocation', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.IncidentClassificationLocation (
        ClassificationId INT NOT NULL,
        LocationId INT NOT NULL,
        LegacyGeneralClassificationId INT NOT NULL,
        CONSTRAINT PK_IncidentClassificationLocation PRIMARY KEY (ClassificationId, LocationId),
        CONSTRAINT UQ_IncidentClassificationLocation_LegacyId UNIQUE (LegacyGeneralClassificationId),
        CONSTRAINT FK_IncidentClassificationLocation_Classification FOREIGN KEY (ClassificationId) REFERENCES wellbeing.tblIncidentClassifications(ClassificationId),
        CONSTRAINT FK_IncidentClassificationLocation_Location FOREIGN KEY (LocationId) REFERENCES wellbeing.tblSchoolLocations(LocationId)
    );
END;
IF OBJECT_ID(N'wellbeing.IncidentTypeClassification', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.IncidentTypeClassification (
        IncidentTypeId INT NOT NULL,
        ClassificationId INT NOT NULL,
        LegacyIncidentTypeId INT NOT NULL,
        LegacyGeneralClassificationId INT NOT NULL,
        CONSTRAINT PK_IncidentTypeClassification PRIMARY KEY (IncidentTypeId, ClassificationId),
        CONSTRAINT FK_IncidentTypeClassification_Type FOREIGN KEY (IncidentTypeId) REFERENCES wellbeing.tblIncidentTypes(IncidentTypeId),
        CONSTRAINT FK_IncidentTypeClassification_Classification FOREIGN KEY (ClassificationId) REFERENCES wellbeing.tblIncidentClassifications(ClassificationId)
    );
END;
IF OBJECT_ID(N'wellbeing.IncidentTypeConsequence', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.IncidentTypeConsequence (
        IncidentTypeId INT NOT NULL,
        ClassificationId INT NOT NULL,
        ConsequenceId INT NOT NULL,
        CONSTRAINT PK_IncidentTypeConsequence PRIMARY KEY (IncidentTypeId, ClassificationId, ConsequenceId),
        CONSTRAINT FK_IncidentTypeConsequence_Type FOREIGN KEY (IncidentTypeId) REFERENCES wellbeing.tblIncidentTypes(IncidentTypeId),
        CONSTRAINT FK_IncidentTypeConsequence_Classification FOREIGN KEY (ClassificationId) REFERENCES wellbeing.tblIncidentClassifications(ClassificationId),
        CONSTRAINT FK_IncidentTypeConsequence_Consequence FOREIGN KEY (ConsequenceId) REFERENCES wellbeing.tblConsequences(ConsequenceId)
    );
END;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'wellbeing.IncidentTypeConsequence') AND name=N'FK_IncidentTypeConsequence_TypeClassification')
    ALTER TABLE wellbeing.IncidentTypeConsequence DROP CONSTRAINT FK_IncidentTypeConsequence_TypeClassification;
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'wellbeing.IncidentTypeConsequence') AND name=N'FK_IncidentTypeConsequence_Type')
    ALTER TABLE wellbeing.IncidentTypeConsequence WITH CHECK ADD CONSTRAINT FK_IncidentTypeConsequence_Type FOREIGN KEY (IncidentTypeId) REFERENCES wellbeing.tblIncidentTypes(IncidentTypeId);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'wellbeing.IncidentTypeConsequence') AND name=N'FK_IncidentTypeConsequence_Classification')
    ALTER TABLE wellbeing.IncidentTypeConsequence WITH CHECK ADD CONSTRAINT FK_IncidentTypeConsequence_Classification FOREIGN KEY (ClassificationId) REFERENCES wellbeing.tblIncidentClassifications(ClassificationId);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE parent_object_id=OBJECT_ID(N'wellbeing.IncidentTypeConsequence') AND name=N'FK_IncidentTypeConsequence_Consequence')
    ALTER TABLE wellbeing.IncidentTypeConsequence WITH CHECK ADD CONSTRAINT FK_IncidentTypeConsequence_Consequence FOREIGN KEY (ConsequenceId) REFERENCES wellbeing.tblConsequences(ConsequenceId);
IF OBJECT_ID(N'wellbeing.ConsequenceAllowedDay', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.ConsequenceAllowedDay (
        LegacyAllowedDayId INT NOT NULL PRIMARY KEY,
        ConsequenceId INT NOT NULL,
        IsAllowed BIT NOT NULL,
        IsCycleDay BIT NOT NULL,
        LegacyDay INT NOT NULL,
        LegacyYearLevel INT NULL,
        CONSTRAINT FK_ConsequenceAllowedDay_Consequence FOREIGN KEY (ConsequenceId) REFERENCES wellbeing.tblConsequences(ConsequenceId)
    );
END;
IF OBJECT_ID(N'wellbeing.ConsequenceAllowedYearLevel', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.ConsequenceAllowedYearLevel (
        LegacyAllowedYearLevelId INT NOT NULL PRIMARY KEY,
        ConsequenceId INT NOT NULL,
        YearLevel INT NOT NULL,
        CONSTRAINT FK_ConsequenceAllowedYearLevel_Consequence FOREIGN KEY (ConsequenceId) REFERENCES wellbeing.tblConsequences(ConsequenceId)
    );
END;
IF OBJECT_ID(N'wellbeing.LegacyConsequenceCommunicationTemplate', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.LegacyConsequenceCommunicationTemplate (
        LegacyCommunicationTemplateId INT NOT NULL PRIMARY KEY,
        TemplateDescription NVARCHAR(MAX) NULL,
        TemplateSubject NVARCHAR(MAX) NULL,
        TemplateMessage NVARCHAR(MAX) NULL,
        LegacyConsequenceId INT NULL,
        SendToStudent BIT NULL,
        SendToParent BIT NULL,
        SendToPastoralCareTeacher BIT NULL,
        SendToHeadOfHouse BIT NULL,
        SendToDeputyPrincipal BIT NULL,
        EventType NVARCHAR(100) NULL
    );
END;
IF OBJECT_ID(N'wellbeing.LegacyCommunicationTemplateDataField', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.LegacyCommunicationTemplateDataField (
        LegacyDataFieldId INT NOT NULL PRIMARY KEY,
        LegacyCommunicationTemplateId INT NOT NULL,
        FieldName NVARCHAR(255) NOT NULL,
        FieldType NVARCHAR(100) NULL,
        FieldDescription NVARCHAR(MAX) NULL,
        CONSTRAINT FK_LegacyCommunicationTemplateDataField_Template FOREIGN KEY (LegacyCommunicationTemplateId) REFERENCES wellbeing.LegacyConsequenceCommunicationTemplate(LegacyCommunicationTemplateId)
    );
END;
IF OBJECT_ID(N'wellbeing.LegacyReferenceMigrationLog', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.LegacyReferenceMigrationLog (
        MigrationRunId BIGINT IDENTITY(1,1) PRIMARY KEY,
        SourceName NVARCHAR(255) NOT NULL,
        StartedAt DATETIME2 NOT NULL,
        CompletedAt DATETIME2 NOT NULL,
        Outcome NVARCHAR(30) NOT NULL,
        ImportedLocations INT NOT NULL,
        ImportedClassifications INT NOT NULL,
        ImportedIncidentTypes INT NOT NULL,
        ImportedTypeClassifications INT NOT NULL,
        ImportedConsequences INT NOT NULL,
        ImportedTypeConsequences INT NOT NULL,
        ImportedAllowedDays INT NOT NULL,
        ImportedAllowedYearLevels INT NOT NULL,
        ImportedCommunicationTemplates INT NOT NULL,
        Notes NVARCHAR(1000) NOT NULL
    );
END;
IF OBJECT_ID(N'wellbeing.LegacyReferenceMigrationException', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.LegacyReferenceMigrationException (
        ExceptionId BIGINT IDENTITY(1,1) PRIMARY KEY,
        MigrationRunId BIGINT NULL,
        SourceTable NVARCHAR(150) NOT NULL,
        SourceIdentifiers NVARCHAR(250) NOT NULL,
        ExceptionType NVARCHAR(80) NOT NULL,
        Details NVARCHAR(1000) NOT NULL,
        DetectedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END;
GO

CREATE OR ALTER VIEW wellbeing.vwIncidentStudentHistoricalSnapshot
AS
SELECT
    incident.IncidentId,
    incident.IncidentNumber,
    incident.IncidentDate,
    incidentStudent.StudentKey,
    incidentStudent.StudentNameAtIncident,
    incidentStudent.StudentNameSnapshotStatus,
    incidentStudent.StudentYearLevelAtIncident,
    incidentStudent.StudentClassAtIncident,
    incidentStudent.YearLevelResolutionStatus
FROM wellbeing.factBehaviourIncident AS incident
JOIN wellbeing.IncidentStudent AS incidentStudent
    ON incidentStudent.IncidentId=incident.IncidentId
;
GO

DECLARE @StartedAt DATETIME2 = SYSUTCDATETIME();
DECLARE @LocationCount INT, @ClassificationCount INT, @TypeCount INT, @TypeClassificationCount INT,
        @ConsequenceCount INT, @TypeConsequenceCount INT, @AllowedDayCount INT, @AllowedYearCount INT,
        @TemplateCount INT;

DECLARE @Locations TABLE (LegacyId INT PRIMARY KEY, Name NVARCHAR(100), DisplayOrder INT);
INSERT INTO @Locations VALUES
(1,N'Bus',1),
(2,N'Campus Incident',2),
(3,N'Classroom Incident',3),
(4,N'Off Campus Incident',4),
(5,N'School Work',5),
(6,N'Notebook',6);

DECLARE @Classifications TABLE (LegacyId INT PRIMARY KEY, LocationLegacyId INT, Name NVARCHAR(100), DisplayOrder INT);
INSERT INTO @Classifications VALUES
(1,1,N'Damage to Property',1),
(2,1,N'Inappropriate Behaviour',2),
(3,1,N'Dangerous/Violent Behaviour',3),
(4,2,N'Damage to property',1),
(5,2,N'Inappropriate Behaviour',2),
(6,2,N'Violent behaviour',3),
(7,2,N'Uniform Infringements',4),
(8,2,N'General',5),
(9,3,N'Damage to property',1),
(10,3,N'Damage to student property',2),
(11,3,N'Disrespectful Behaviour',3),
(12,3,N'Disruptive Behaviour',4),
(13,3,N'General',6),
(14,4,N'Damage to property',1),
(15,4,N'Inappropriate Behaviour ',2),
(16,4,N'Violent Behaviour',3),
(17,4,N'General',4),
(18,5,N'Class work',1),
(19,5,N'Assessment tasks',2),
(20,5,N'Homework',3),
(21,5,N'General',4),
(22,6,N'Damage',1),
(23,6,N'Inappropriate use',2),
(24,6,N'Inappropriate material',3),
(25,6,N'Software issue',4),
(31,3,N'Dangerous/Violent Behaviour',5);

DECLARE @IncidentTypes TABLE (LegacyId INT PRIMARY KEY, Name NVARCHAR(100), LegacyLevel INT);
INSERT INTO @IncidentTypes VALUES
(89,N'Careless behaviour',1),
(90,N'Causing damage to another student''s computer',2),
(91,N'Diary Infringement',1),
(92,N'Disobeying staff request or instruction',1),
(93,N'Disrespectful behaviour including teasing or name calling',1),
(94,N'Disrupting teaching and learning environment',1),
(95,N'Distracting others',1),
(96,N'Extracting student from seat',1),
(97,N'Failing to attend to a notebook problem',1),
(98,N'Failing to bring all necessary equipment to class',1),
(99,N'Late Arrival to Class',1),
(100,N'Late Arrival to School',1),
(101,N'Late submission of assessable work',1),
(102,N'Lighter or matches',1),
(103,N'Litter',1),
(104,N'Misplacing a notebook',1),
(105,N'Moderate swearing or inappropriate language',1),
(106,N'No Notebook ID Tag',1),
(107,N'Not completing classwork',1),
(108,N'Opening a computer on the bus',1),
(109,N'Other',1),
(110,N'PE Uniform Infringement',1),
(111,N'Spitting',1),
(112,N'Stacks on',1),
(113,N'Talking in class',1),
(114,N'Tampering with the configuration of a notebook',1),
(115,N'Unattended Notebook',1),
(116,N'Uniform infringement at College',1),
(117,N'Using a notebook without permission',1),
(118,N'Using an application without permission (eg email, internet)',1),
(119,N'Wasting time during class',1),
(120,N'Arguing with a staff member',2),
(121,N'Careless use of property, resources, facilities or equipment',2),
(122,N'Cheating',2),
(123,N'Deliberate and substantial reconfiguration of a notebook',2),
(124,N'Failure to attend lunchtime detention',2),
(125,N'Failure to report serious damage to a notebook',2),
(126,N'Forging or false representation',2),
(127,N'Inappropriate material',2),
(128,N'Interfering with another student''s property',2),
(129,N'Involvement in a food fight',2),
(130,N'Lying',2),
(131,N'Mobile phone',2),
(132,N'Offensive language or behaviour',2),
(133,N'Out of bounds',2),
(134,N'Plagiarism or copyright infringement',2),
(135,N'Playing computer games',2),
(136,N'Reckless and/or dangerous behaviour',2),
(137,N'Repeated failure to submit set work',2),
(138,N'Sending nuisance emails or network messages',2),
(139,N'Smoking (first offence)',2),
(140,N'Throwing objects within a bus',2),
(141,N'Truancy -Missing scheduled class(es) or sport activity',2),
(142,N'Unauthorised software on a notebook',2),
(143,N'Uncooperative, disobedient or rude behaviour',2),
(144,N'Uniform infringement in a public place',2),
(145,N'Absent from College without permission',3),
(146,N'Bullying or harassment',3),
(147,N'Damaging the reputation of the College',3),
(148,N'Defying a staff member',3),
(149,N'Deliberate inappropriate use of property, resources, facilities or equipment',3),
(150,N'Failure to attend a major College event',3),
(151,N'Failure to attend after school detention',3),
(152,N'Failure to attend an after school Study Detention',3),
(153,N'General failure to comply with expectations',3),
(154,N'Inappropriate language to a staff member',3),
(155,N'Physical assault',3),
(156,N'Repeated after school Study Detentions',3),
(157,N'Throwing objects from a bus window',3),
(158,N'Causing damage to College bus property',4),
(159,N'Offensive behaviour towards a staff member',4),
(160,N'Operating the emergency door release',4),
(161,N'Physical violence or violent behaviour',4),
(162,N'Pornographic or offensive material',4),
(163,N'Possession or use of alcohol',4),
(164,N'Theft',4),
(165,N'Vandalism or wilful damage to property, resources, facilities or equipment',4),
(166,N'Major theft',5),
(167,N'Possession or use of a weapon',5),
(168,N'Possession or use of an illegal substance',5),
(169,N'Serious criminal offence',5),
(170,N'Serious wilful damage to property, resources, facilities or equipment',5),
(171,N'Severe physical violence',5),
(172,N'Trafficking in an illegal substance',5),
(175,N'Not completing homework',1),
(176,N'Repeated Uniform infringement at College',2),
(177,N'Truancy -Missing scheduled class(es) or sport activity',3),
(178,N'General failure to comply with expectations',4),
(179,N'Reckless or dangerous behaviour',4),
(180,N'Persistent failure to bring all necessary equipment to class',2),
(181,N'Persistent failure to arrive  at class on time',2),
(182,N'Persistent failure to attend pastoral care on time',2),
(183,N'Inappropriate Behaviour Teasing and Name calling',2),
(184,N'Offensive language or behaviour',3),
(185,N'Offensive language or behaviour',4),
(186,N'Damaging the reputation of the College',4),
(188,N'Failure to comply with expectations',2),
(189,N'Vilification',2),
(190,N'Vilification',3),
(191,N'Failure to comply with expectations',3),
(192,N'Hairstyle',1),
(194,N'Shaving/Personal grooming',1),
(195,N'Repeated failure to comply with expectations',2),
(196,N'Sexual Harassment of a staff member',4),
(197,N'Sexual Harassment of a student',4),
(198,N'Abuse/offensive language to a member of the public',3),
(199,N'Abuse/offensive language to a member of the public',4),
(200,N'Sexual harassment of a staff member',3),
(202,N'Sexual harassment of a staff member',5),
(203,N'Sexual harassment of a student',3),
(204,N'Sexual harassment of a student',5),
(205,N'Sexual harassment of a member of the public',3),
(206,N'Sexual harassment of a member of the public',4),
(207,N'Sexual harassment of a member of the public',5),
(208,N'Failure to comply with expectations',4),
(209,N'Non-submission of assessment task',1),
(210,N'Repeated non-submission of assessment task',2),
(211,N'Failure to comply with expectations',1),
(212,N'SunSmart Infringement',1);

DECLARE @TypeClassifications TABLE (TypeLegacyId INT, ClassificationLegacyId INT, PRIMARY KEY(TypeLegacyId, ClassificationLegacyId));
INSERT INTO @TypeClassifications VALUES
(89,2),
(89,5),
(89,11),
(89,15),
(90,1),
(90,4),
(90,10),
(90,22),
(91,13),
(91,21),
(92,2),
(92,5),
(92,8),
(92,12),
(92,15),
(92,21),
(93,2),
(93,5),
(93,11),
(93,12),
(93,15),
(94,12),
(95,12),
(96,2),
(97,22),
(98,13),
(98,18),
(99,13),
(100,8),
(101,19),
(102,8),
(102,17),
(103,8),
(103,17),
(104,8),
(104,23),
(105,2),
(105,5),
(105,11),
(105,15),
(106,23),
(107,18),
(108,2),
(108,23),
(109,8),
(110,7),
(110,13),
(111,5),
(111,17),
(112,8),
(113,12),
(114,23),
(115,8),
(115,23),
(116,7),
(116,13),
(117,23),
(118,23),
(119,12),
(119,18),
(120,2),
(120,5),
(120,11),
(120,15),
(121,1),
(121,4),
(121,9),
(121,14),
(121,23),
(122,21),
(123,23),
(123,25),
(124,8),
(125,22),
(126,8),
(126,13),
(126,21),
(127,2),
(127,8),
(127,13),
(127,17),
(127,21),
(127,23),
(127,24),
(127,25),
(128,1),
(128,4),
(128,10),
(128,14),
(128,22),
(129,2),
(129,5),
(129,17),
(130,2),
(130,5),
(130,11),
(130,15),
(130,21),
(131,8),
(131,13),
(131,15),
(132,2),
(132,5),
(132,11),
(132,15),
(133,8),
(133,17),
(134,21),
(135,23),
(135,25),
(136,3),
(136,5),
(136,11),
(136,15),
(137,20),
(137,21),
(138,23),
(139,8),
(139,17),
(140,2),
(140,3),
(141,8),
(142,23),
(142,25),
(143,2),
(143,5),
(143,11),
(143,12),
(143,15),
(144,2),
(144,17),
(145,8),
(145,17),
(146,2),
(146,5),
(146,6),
(146,12),
(146,15),
(147,2),
(147,5),
(147,6),
(147,17),
(148,2),
(148,5),
(148,11),
(148,15),
(149,1),
(149,4),
(149,9),
(149,14),
(149,23),
(149,24),
(150,8),
(151,8),
(152,8),
(153,2),
(153,5),
(153,13),
(153,17),
(154,2),
(154,5),
(154,11),
(154,15),
(155,6),
(155,12),
(155,16),
(156,8),
(157,3),
(158,1),
(158,4),
(158,14),
(159,2),
(159,5),
(159,11),
(159,15),
(160,3),
(161,3),
(161,6),
(161,11),
(161,16),
(162,8),
(162,11),
(162,15),
(162,17),
(162,24),
(162,25),
(163,8),
(163,15),
(164,5),
(164,13),
(164,15),
(165,1),
(165,4),
(165,9),
(165,14),
(165,22),
(166,5),
(166,13),
(166,15),
(167,8),
(167,13),
(167,17),
(168,8),
(168,13),
(168,17),
(169,8),
(169,17),
(170,1),
(170,4),
(170,9),
(170,14),
(170,22),
(171,3),
(171,6),
(171,16),
(172,8),
(172,17),
(175,20),
(176,7),
(176,8),
(176,13),
(177,8),
(178,8),
(178,17),
(179,8),
(180,8),
(180,13),
(181,8),
(181,13),
(182,8),
(182,13),
(183,8),
(183,13),
(183,17),
(186,17),
(188,8),
(189,5),
(189,8),
(189,11),
(189,13),
(189,15),
(189,17),
(190,5),
(190,8),
(190,11),
(190,13),
(190,15),
(190,17),
(191,8),
(192,7),
(194,7),
(195,7),
(196,2),
(196,5),
(197,2),
(197,5),
(198,2),
(198,15),
(199,2),
(199,15),
(200,2),
(200,5),
(202,2),
(202,5),
(203,2),
(203,5),
(204,5),
(205,2),
(206,2),
(207,2),
(208,5),
(209,19),
(210,19),
(211,13),
(212,13)

DECLARE @Consequences TABLE (LegacyId INT PRIMARY KEY, Name NVARCHAR(255), AllowsMultiplePerDay BIT, LegacyLength INT, ProcessorRole NVARCHAR(255));
INSERT INTO @Consequences VALUES
(33,N'Removal From College',0,0,N'Deputy Principal'),
(34,N'Negotiated Transfer',0,0,N'Deputy Principal'),
(35,N'Withdrawal From College',0,0,N'Deputy Principal'),
(36,N'Suspension From College',0,2,N'Deputy Principal'),
(37,N'Referral To Police',1,0,N'Deputy Principal'),
(38,N'Parental Interview',1,0,N'Head Of House'),
(39,N'College Service',1,0,N'Head Of House'),
(40,N'Student Agreement',1,0,N'Head Of House'),
(41,N'Suspension From Classes',1,1,N'Deputy Principal'),
(42,N'Saturday Detention',0,1,N'Deputy Principal'),
(43,N'Student Free Day Detention',0,1,N'Deputy Principal'),
(44,N'Verbal Or Written Apology',1,0,N'NULL'),
(45,N'Send To DP (Student)',1,0,N'NULL'),
(46,N'After School Detention',0,1,N'Head Of House'),
(47,N'Phone Call To parent',1,0,N'NULL'),
(48,N'Daily Or Weekly Agreement',1,0,N'NULL'),
(49,N'Send Home To Change',0,1,N'Head Of House'),
(50,N'Confiscation',1,0,N'NULL'),
(51,N'Send To House Leader',1,0,N'NULL'),
(52,N'Verbal Correction Or Reprimand',1,0,N'NULL'),
(53,N'Move Seat Within Classroom',1,0,N'NULL'),
(56,N'Supervised yard duty (by issuing teacher) at recess or lunch',1,1,N'NULL'),
(57,N'Recess or lunchtime detention  (supervised by issuing teacher)',1,1,N'NULL'),
(58,N'Send out of class (5 min max)',1,0,N'NULL'),
(59,N'Send to another class for rest of period',1,0,N'NULL'),
(61,N'Change Of Bus',0,0,N'NULL'),
(62,N'Suspension From College Buses',0,7,N'Head Of House'),
(67,N'Suspension From Buses Until Further Notice',0,1,N'Deputy Principal'),
(68,N'After School Study Detention',0,1,N'Head Of House'),
(69,N'Saturday Study Detention',0,1,N'Deputy Principal'),
(70,N'Detention - Lunchtime Yard Duty',0,1,N'NULL'),
(71,N'Email To Parent - Non Submission Of Work',1,0,N'NULL'),
(72,N'Email To Parent - VCE Non Submission Of Work',1,0,N'NULL'),
(78,N'Referred to College Counsellor',1,0,N'NULL'),
(79,N'International Students Friday Study Detention',0,1,N'Head Of House'),
(80,N'Email To Parent -HairStyle/Shaving',1,1,N'NULL'),
(81,N'After School Study Intervention',0,1,N'Head Of House'),
(82,N'After School Detention - Mobile Phone',0,1,N'Head Of House'),
(83,N'Email To Parent SunSmart Infringement',0,0,N'NULL')

DECLARE @TypeConsequences TABLE (TypeLegacyId INT, ClassificationLegacyId INT, ConsequenceLegacyId INT, PRIMARY KEY(TypeLegacyId, ClassificationLegacyId, ConsequenceLegacyId));
INSERT INTO @TypeConsequences VALUES
(89,2,44),
(89,5,44),
(89,11,44),
(89,15,44),
(89,5,50),
(89,2,52),
(89,5,52),
(89,11,52),
(89,15,52),
(89,11,53),
(89,5,56),
(89,11,56),
(89,15,56),
(89,5,57),
(89,11,57),
(89,11,58),
(89,11,59),
(89,2,61),
(89,2,62),
(90,1,44),
(90,4,44),
(90,1,46),
(90,4,46),
(90,10,46),
(90,22,46),
(90,1,47),
(90,4,47),
(90,10,47),
(90,22,47),
(90,1,51),
(90,4,51),
(90,10,51),
(90,22,51),
(90,1,61),
(90,1,62),
(91,13,44),
(91,21,44),
(91,13,52),
(91,21,52),
(91,13,56),
(91,13,57),
(91,21,57),
(91,13,70),
(91,21,70),
(92,2,44),
(92,5,44),
(92,8,44),
(92,12,44),
(92,15,44),
(92,21,44),
(92,2,52),
(92,5,52),
(92,8,52),
(92,12,52),
(92,15,52),
(92,21,52),
(92,12,53),
(92,21,53),
(92,5,56),
(92,8,56),
(92,12,56),
(92,15,56),
(92,21,56),
(92,5,57),
(92,8,57),
(92,12,57),
(92,21,57),
(92,12,58),
(92,21,58),
(92,12,59),
(92,21,59),
(92,2,61),
(92,2,62),
(93,2,44),
(93,5,44),
(93,11,44),
(93,12,44),
(93,15,44),
(93,2,52),
(93,5,52),
(93,11,52),
(93,12,52),
(93,15,52),
(93,11,53),
(93,12,53),
(93,5,56),
(93,11,56),
(93,12,56),
(93,15,56),
(93,5,57),
(93,11,57),
(93,12,57),
(93,11,58),
(93,12,58),
(93,11,59),
(93,12,59),
(93,2,61),
(93,2,62),
(94,12,44),
(94,11,48),
(94,12,52),
(94,12,53),
(94,12,56),
(94,12,57),
(94,12,58),
(94,12,59),
(95,12,44),
(95,12,52),
(95,12,53),
(95,12,56),
(95,12,57),
(95,12,58),
(95,12,59),
(96,2,44),
(96,2,52),
(96,2,61),
(96,2,62),
(97,22,52),
(97,22,56),
(97,22,57),
(98,13,44),
(98,18,44),
(98,13,52),
(98,18,52),
(98,13,53),
(98,18,53),
(98,13,56),
(98,18,56),
(98,13,57),
(98,18,57),
(98,13,58),
(98,18,58),
(98,18,59),
(99,13,44),
(99,13,52),
(99,13,53),
(99,13,57),
(99,13,70),
(100,8,52),
(100,8,70),
(101,19,71),
(101,19,72),
(102,8,46),
(102,8,50),
(102,17,50),
(102,8,51),
(102,8,52),
(102,17,52),
(102,8,57),
(103,8,52),
(103,17,52),
(103,8,56),
(103,17,56),
(103,8,57),
(103,8,70),
(103,17,70),
(104,8,52),
(104,23,52),
(104,8,56),
(104,23,56),
(104,8,57),
(104,23,57),
(105,2,44),
(105,5,44),
(105,11,44),
(105,15,44),
(105,2,52),
(105,5,52),
(105,11,52),
(105,15,52),
(105,11,53),
(105,5,56),
(105,11,56),
(105,15,56),
(105,5,57),
(105,11,57),
(105,11,58),
(105,2,61),
(105,2,62),
(106,23,52),
(106,23,56),
(106,23,57),
(106,23,70),
(107,18,44),
(107,18,52),
(107,18,53),
(107,18,56),
(107,18,57),
(107,18,58),
(108,2,44),
(108,2,52),
(108,23,52),
(108,2,61),
(109,8,44),
(109,8,52),
(109,8,57),
(110,7,70),
(110,13,70),
(111,5,44),
(111,17,44),
(111,5,52),
(111,17,52),
(111,5,56),
(111,17,56),
(111,5,57),
(112,8,44),
(112,8,52),
(112,8,56),
(112,8,57),
(113,12,44),
(113,12,52),
(113,12,53),
(113,12,56),
(113,12,57),
(113,12,58),
(113,12,59),
(114,23,52),
(115,8,52),
(115,23,52),
(115,8,56),
(115,23,56),
(115,8,57),
(115,23,57),
(115,8,70),
(115,23,70),
(116,7,49),
(116,7,70),
(116,13,70),
(117,23,44),
(117,23,52),
(117,23,53),
(117,23,56),
(117,23,57),
(117,23,58),
(118,23,44),
(118,23,52),
(118,23,53),
(118,23,56),
(118,23,57),
(118,23,58),
(119,12,44),
(119,18,44),
(119,12,52),
(119,18,52),
(119,12,53),
(119,18,53),
(119,12,56),
(119,18,56),
(119,12,57),
(119,18,57),
(119,12,58),
(119,18,58),
(119,12,59),
(119,18,59),
(120,2,44),
(120,5,44),
(120,11,44),
(120,15,44),
(120,2,46),
(120,5,46),
(120,11,46),
(120,15,46),
(120,2,47),
(120,5,47),
(120,11,47),
(120,15,47),
(120,11,48),
(120,15,48),
(120,2,51),
(120,5,51),
(120,11,51),
(120,15,51),
(120,2,61),
(120,2,62),
(121,1,44),
(121,4,44),
(121,9,44),
(121,1,46),
(121,4,46),
(121,9,46),
(121,14,46),
(121,23,46),
(121,1,47),
(121,4,47),
(121,9,47),
(121,14,47),
(121,23,47),
(121,1,51),
(121,4,51),
(121,9,51),
(121,14,51),
(121,23,51),
(121,1,61),
(121,1,62),
(122,21,44),
(122,21,46),
(122,21,47),
(122,21,51),
(123,23,46),
(123,25,46),
(123,23,47),
(123,25,47),
(123,25,50),
(123,23,51),
(123,25,51),
(124,8,46),
(124,8,47),
(124,8,51),
(125,22,46),
(125,22,47),
(125,22,51),
(126,21,44),
(126,8,46),
(126,13,46),
(126,21,46),
(126,8,47),
(126,13,47),
(126,21,47),
(126,13,50),
(126,8,51),
(126,13,51),
(126,21,51),
(127,2,44),
(127,13,44),
(127,24,44),
(127,2,46),
(127,8,46),
(127,13,46),
(127,17,46),
(127,21,46),
(127,23,46),
(127,24,46),
(127,25,46),
(127,2,47),
(127,8,47),
(127,13,47),
(127,17,47),
(127,21,47),
(127,23,47),
(127,24,47),
(127,25,47),
(127,13,50),
(127,23,50),
(127,24,50),
(127,2,51),
(127,8,51),
(127,13,51),
(127,17,51),
(127,21,51),
(127,23,51),
(127,24,51),
(127,25,51),
(127,2,61),
(127,2,62),
(128,1,44),
(128,4,44),
(128,1,46),
(128,4,46),
(128,10,46),
(128,14,46),
(128,22,46),
(128,1,47),
(128,4,47),
(128,10,47),
(128,14,47),
(128,22,47),
(128,1,51),
(128,4,51),
(128,10,51),
(128,14,51),
(128,22,51),
(128,1,61),
(128,1,62),
(129,2,44),
(129,2,46),
(129,5,46),
(129,17,46),
(129,2,47),
(129,5,47),
(129,17,47),
(129,2,51),
(129,5,51),
(129,17,51),
(129,2,61),
(129,2,62),
(130,2,44),
(130,11,44),
(130,15,44),
(130,2,46),
(130,5,46),
(130,11,46),
(130,15,46),
(130,21,46),
(130,2,47),
(130,5,47),
(130,11,47),
(130,15,47),
(130,21,47),
(130,2,51),
(130,5,51),
(130,11,51),
(130,15,51),
(130,21,51),
(130,5,57),
(130,2,61),
(130,2,62),
(131,15,46),
(131,8,47),
(131,13,47),
(131,15,47),
(131,8,50),
(131,13,50),
(131,15,50),
(131,8,51),
(131,13,51),
(131,15,51),
(131,8,82),
(132,2,44),
(132,11,44),
(132,2,46),
(132,5,46),
(132,11,46),
(132,15,46),
(132,2,47),
(132,5,47),
(132,11,47),
(132,15,47),
(132,11,48),
(132,15,48),
(132,2,51),
(132,5,51),
(132,11,51),
(132,15,51),
(132,5,57),
(132,2,61),
(132,2,62),
(133,8,46),
(133,17,46),
(133,8,47),
(133,17,47),
(133,8,51),
(133,17,51),
(134,21,46),
(134,21,47),
(134,21,51),
(135,23,46),
(135,25,46),
(135,23,47),
(135,25,47),
(135,23,50),
(135,23,51),
(135,25,51),
(136,3,44),
(136,3,46),
(136,5,46),
(136,11,46),
(136,15,46),
(136,3,47),
(136,5,47),
(136,11,47),
(136,15,47),
(136,3,51),
(136,5,51),
(136,11,51),
(136,15,51),
(136,3,61),
(136,3,62),
(137,20,47),
(137,21,47),
(137,20,51),
(137,21,51),
(137,21,68),
(137,20,69),
(137,21,69),
(137,21,79),
(138,23,46),
(138,23,47),
(138,23,51),
(139,8,46),
(139,17,46),
(139,8,47),
(139,17,47),
(139,8,50),
(139,17,50),
(139,8,51),
(139,17,51),
(140,2,44),
(140,3,44),
(140,2,46),
(140,3,46),
(140,2,47),
(140,3,47),
(140,2,51),
(140,3,51),
(140,2,61),
(140,3,61),
(140,2,62),
(140,3,62),
(141,8,46),
(141,8,47),
(141,8,51),
(142,23,46),
(142,25,46),
(142,23,47),
(142,25,47),
(142,23,51),
(142,25,51),
(143,2,44),
(143,5,44),
(143,11,44),
(143,12,44),
(143,2,46),
(143,5,46),
(143,11,46),
(143,12,46),
(143,15,46),
(143,2,47),
(143,5,47),
(143,11,47),
(143,12,47),
(143,15,47),
(143,11,48),
(143,12,48),
(143,15,48),
(143,2,51),
(143,5,51),
(143,11,51),
(143,12,51),
(143,15,51),
(143,5,57),
(143,2,61),
(143,2,62),
(144,2,44),
(144,2,46),
(144,17,46),
(144,2,47),
(144,17,47),
(144,2,51),
(144,17,51),
(144,2,61),
(144,2,62),
(145,8,38),
(145,17,38),
(145,8,39),
(145,17,39),
(145,8,40),
(145,17,40),
(145,8,42),
(145,17,42),
(145,8,43),
(145,17,43),
(145,8,45),
(145,17,45),
(146,5,36),
(146,6,36),
(146,2,38),
(146,5,38),
(146,6,38),
(146,12,38),
(146,15,38),
(146,2,39),
(146,5,39),
(146,6,39),
(146,12,39),
(146,15,39),
(146,2,40),
(146,5,40),
(146,6,40),
(146,12,40),
(146,15,40),
(146,5,41),
(146,6,41),
(146,2,42),
(146,5,42),
(146,6,42),
(146,12,42),
(146,15,42),
(146,2,43),
(146,5,43),
(146,6,43),
(146,12,43),
(146,15,43),
(146,2,44),
(146,5,44),
(146,6,44),
(146,12,44),
(146,2,45),
(146,5,45),
(146,6,45),
(146,12,45),
(146,15,45),
(146,2,61),
(146,2,62),
(146,2,67),
(146,5,78),
(146,6,78),
(147,5,36),
(147,2,38),
(147,5,38),
(147,6,38),
(147,17,38),
(147,2,39),
(147,5,39),
(147,6,39),
(147,17,39),
(147,2,40),
(147,5,40),
(147,6,40),
(147,17,40),
(147,5,41),
(147,2,42),
(147,5,42),
(147,6,42),
(147,17,42),
(147,2,43),
(147,5,43),
(147,6,43),
(147,17,43),
(147,2,44),
(147,5,44),
(147,6,44),
(147,2,45),
(147,5,45),
(147,6,45),
(147,17,45),
(147,2,61),
(147,2,62),
(147,2,67),
(148,5,36),
(148,2,38),
(148,5,38),
(148,11,38),
(148,15,38),
(148,2,39),
(148,5,39),
(148,11,39),
(148,15,39),
(148,2,40),
(148,5,40),
(148,11,40),
(148,15,40),
(148,5,41),
(148,2,42),
(148,5,42),
(148,11,42),
(148,15,42),
(148,2,43),
(148,5,43),
(148,11,43),
(148,15,43),
(148,2,44),
(148,5,44),
(148,2,45),
(148,5,45),
(148,11,45),
(148,15,45),
(148,2,61),
(148,2,62),
(148,2,67),
(149,4,36),
(149,1,38),
(149,4,38),
(149,9,38),
(149,14,38),
(149,23,38),
(149,24,38),
(149,1,39),
(149,4,39),
(149,9,39),
(149,14,39),
(149,23,39),
(149,24,39),
(149,1,40),
(149,4,40),
(149,9,40),
(149,14,40),
(149,23,40),
(149,24,40),
(149,4,41),
(149,1,42),
(149,4,42),
(149,9,42),
(149,14,42),
(149,23,42),
(149,24,42),
(149,1,43),
(149,4,43),
(149,9,43),
(149,14,43),
(149,23,43),
(149,24,43),
(149,24,44),
(149,1,45),
(149,4,45),
(149,9,45),
(149,14,45),
(149,23,45),
(149,24,45),
(149,4,46),
(149,1,61),
(149,1,62),
(149,1,67),
(150,8,38),
(150,8,39),
(150,8,40),
(150,8,42),
(150,8,43),
(150,8,45),
(151,8,38),
(151,8,40),
(151,8,42),
(151,8,43),
(151,8,45),
(152,8,38),
(152,8,40),
(152,8,43),
(152,8,45),
(152,8,69),
(153,5,36),
(153,2,38),
(153,5,38),
(153,13,38),
(153,17,38),
(153,2,39),
(153,5,39),
(153,13,39),
(153,17,39),
(153,2,40),
(153,5,40),
(153,13,40),
(153,17,40),
(153,5,41),
(153,2,42),
(153,5,42),
(153,13,42),
(153,17,42),
(153,2,43),
(153,5,43),
(153,13,43),
(153,17,43),
(153,2,45),
(153,5,45),
(153,13,45),
(153,17,45),
(153,2,61),
(153,2,62),
(153,2,67),
(154,5,36),
(154,2,38),
(154,5,38),
(154,11,38),
(154,15,38),
(154,2,39),
(154,5,39),
(154,11,39),
(154,15,39),
(154,2,40),
(154,5,40),
(154,11,40),
(154,15,40),
(154,5,41),
(154,2,42),
(154,5,42),
(154,11,42),
(154,15,42),
(154,2,43),
(154,5,43),
(154,11,43),
(154,15,43),
(154,2,44),
(154,5,44),
(154,11,44),
(154,2,45),
(154,5,45),
(154,11,45),
(154,15,45),
(154,2,61),
(154,2,62),
(154,2,67),
(155,6,38),
(155,12,38),
(155,16,38),
(155,6,39),
(155,12,39),
(155,16,39),
(155,6,40),
(155,12,40),
(155,16,40),
(155,6,42),
(155,12,42),
(155,16,42),
(155,6,43),
(155,12,43),
(155,16,43),
(155,12,44),
(155,6,45),
(155,12,45),
(155,16,45),
(155,6,78),
(155,12,78),
(155,16,78),
(156,8,38),
(156,8,40),
(156,8,43),
(156,8,45),
(156,8,69),
(157,3,38),
(157,3,39),
(157,3,40),
(157,3,42),
(157,3,43),
(157,3,45),
(157,3,61),
(157,3,62),
(157,3,67),
(158,1,36),
(158,4,36),
(158,14,36),
(158,1,38),
(158,4,38),
(158,14,38),
(158,1,39),
(158,4,39),
(158,14,39),
(158,1,40),
(158,4,40),
(158,14,40),
(158,1,41),
(158,4,41),
(158,14,41),
(158,1,61),
(158,1,62),
(158,1,67),
(159,2,36),
(159,5,36),
(159,11,36),
(159,15,36),
(159,2,38),
(159,5,38),
(159,11,38),
(159,15,38),
(159,2,39),
(159,5,39),
(159,11,39),
(159,15,39),
(159,2,40),
(159,5,40),
(159,11,40),
(159,15,40),
(159,2,41),
(159,5,41),
(159,11,41),
(159,15,41),
(159,2,61),
(159,2,62),
(159,2,67),
(160,3,36),
(160,3,38),
(160,3,39),
(160,3,40),
(160,3,41),
(160,3,61),
(160,3,62),
(160,3,67),
(161,3,36),
(161,6,36),
(161,16,36),
(161,31,36),
(161,3,38),
(161,6,38),
(161,16,38),
(161,31,38),
(161,3,39),
(161,6,39),
(161,16,39),
(161,31,39),
(161,3,40),
(161,6,40),
(161,16,40),
(161,31,40),
(161,3,41),
(161,6,41),
(161,16,41),
(161,31,41),
(161,3,61),
(161,3,62),
(161,3,67),
(161,3,78),
(161,11,78),
(161,16,78),
(162,8,36),
(162,11,36),
(162,15,36),
(162,17,36),
(162,24,36),
(162,25,36),
(162,8,38),
(162,11,38),
(162,15,38),
(162,17,38),
(162,24,38),
(162,25,38),
(162,8,39),
(162,11,39),
(162,15,39),
(162,17,39),
(162,24,39),
(162,25,39),
(162,8,40),
(162,11,40),
(162,15,40),
(162,17,40),
(162,24,40),
(162,25,40),
(162,8,41),
(162,11,41),
(162,15,41),
(162,17,41),
(162,24,41),
(162,25,41),
(163,8,36),
(163,15,36),
(163,8,38),
(163,15,38),
(163,8,39),
(163,15,39),
(163,8,40),
(163,15,40),
(163,8,41),
(163,15,41),
(164,5,36),
(164,13,36),
(164,15,36),
(164,5,38),
(164,13,38),
(164,15,38),
(164,5,39),
(164,13,39),
(164,15,39),
(164,5,40),
(164,13,40),
(164,15,40),
(164,5,41),
(164,13,41),
(164,15,41),
(165,1,36),
(165,4,36),
(165,9,36),
(165,14,36),
(165,22,36),
(165,1,38),
(165,4,38),
(165,9,38),
(165,14,38),
(165,22,38),
(165,1,39),
(165,4,39),
(165,9,39),
(165,14,39),
(165,22,39),
(165,1,40),
(165,4,40),
(165,9,40),
(165,14,40),
(165,22,40),
(165,1,41),
(165,4,41),
(165,9,41),
(165,14,41),
(165,22,41),
(165,1,61),
(165,1,62),
(165,1,67),
(166,5,33),
(166,13,33),
(166,15,33),
(166,5,34),
(166,13,34),
(166,15,34),
(166,5,35),
(166,13,35),
(166,15,35),
(166,5,36),
(166,13,36),
(166,15,36),
(166,5,37),
(166,13,37),
(166,15,37),
(166,5,38),
(166,13,38),
(166,15,38),
(166,5,39),
(166,13,39),
(166,15,39),
(167,8,33),
(167,13,33),
(167,17,33),
(167,8,34),
(167,13,34),
(167,17,34)

DECLARE @AllowedDays TABLE (LegacyId INT PRIMARY KEY, ConsequenceLegacyId INT, IsAllowed BIT, IsCycleDay BIT, LegacyDay INT, LegacyYearLevel INT NULL);
INSERT INTO @AllowedDays VALUES
(1,42,1,0,6,NULL),
(2,69,1,0,6,NULL),
(3,46,1,0,5,NULL),
(4,68,1,0,5,NULL),
(5,70,0,0,0,9),
(6,70,0,0,0,10),
(7,70,0,0,0,11),
(8,70,0,0,0,12),
(9,70,0,0,0,7),
(10,70,0,0,0,8),
(11,79,1,0,5,NULL),
(12,82,0,1,5,NULL),
(13,81,1,0,5,NULL)

DECLARE @AllowedYears TABLE (LegacyId INT PRIMARY KEY, ConsequenceLegacyId INT, YearLevel INT);
INSERT INTO @AllowedYears VALUES
(1,71,7),
(2,71,8),
(3,71,9),
(4,71,10),
(5,71,11),
(6,71,12)

DECLARE @Templates TABLE (LegacyId INT PRIMARY KEY, TemplateDescription NVARCHAR(MAX), TemplateSubject NVARCHAR(MAX), TemplateMessage NVARCHAR(MAX), ConsequenceLegacyId INT, SendToStudent BIT, SendToParent BIT, SendToPCT BIT, SendToHOH BIT, SendToDP BIT, EventType NVARCHAR(100));
INSERT INTO @Templates VALUES
(2,N'Student in Yrs 7 - 10 Failed to submit an item of work',N'Notification of Non-Submission of Work For',N'Dear  Parent/Guardian,<div><p><span>This email is to inform you that {@StudentpreferredName} has failed to submit his {@WorkItem} which was due for {@Class}  on {@SubmissionDate}. <br />  <br /> It is the responsibility of {@StudentpreferredName} to submit the assessment task by {@NewSubmissionDate} so that it can be assessed and feedback provided through Whitefriars Learn and Engage. A 10% penalty per day will be deducted from his final grade until the task is submitted.<br/><br/>If not submitted within two days, {@StudentpreferredName} will receive the score of zero (0 - UG). <br/><br /> If you have any queries regarding this matter, please do not hesitate to contact me via email. <br/><br/></span>    </p><p><span >Yours sincerely,</span></p></div><p></p></div><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p></body>',71,0,1,1,1,0,N'insert'),
(3,N'Student in Yrs 11-12 Failed to submit an item of work',N'Notification of VCE Non Submission of Work For',N'<p>Dear  Parent/Guardian,<br /><br />This email is to inform you that {@StudentpreferredName} has failed to submit his {@WorkItem} which was due to be submitted for {@Class} on {@SubmissionDate}. The details are as follows:<br /></P><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr><td>Class:</td><td>{@Class}</td></tr><tr><td>Work Item:</td><td>{@WorkItem}</td></tr><tr><td>Orginal Submission Date:</td><td>{@SubmissionDate}</td></tr><tr><td>New Submission Date:</td><td>{@NewSubmissionDate}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>Please note that unless his work is submitted by <span style="font-style: italic">{@NewSubmissionDate}</span> it will not be assessed. Please also note failure to submit required tasks may impact on satisfactory completion of this unit.<br /><br />If you have any queries regarding this matter, please do not hesitate to contact me at the College.</p><p>Yours sincerely,</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',72,1,1,1,1,0,N'insert'),
(5,N'Study Detention - After School',N'Notification of Study Detention after School For',N'<p>Dear  Parent/Guardian,</p><p>This email is to inform you that {@StudentpreferredName} is required to attend After School Study Detention as outlined below:</p><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr><td>Detention Date:</td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>Please note that failure to attend this After School Study Detention will result in the issuing of a Saturday Detention.<br />Please <a href="https://ack.whitefriars.vic.edu.au/ack/?gid={@gid}">click here</a> to acknowledge receipt of this notification and {@StudentgivenName}&#39;s attendance at this detention.<br /></p><table style="border-style: solid; border-width: 2px; padding: 1px 4px"><tr><td style="text-align: center"><strong>After School Study Detention Procedures</strong></td></tr><tr><td><ul><li>
Students must present themselves to the supervising teacher at Student Reception at 3:25pm</li><li>Students are expected to bring materials necessary for them to complete work set by one or more of their subject teachers.</li></ul></td></tr></table><p>Yours sincerely</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',68,0,1,1,1,0,N'insert'),
(6,N'Saturday study detention',N'Notification of Saturday study detention For',N'<p>Dear  Parent/Guardian,</p><p>This email is to inform you that {@StudentpreferredName} is required to attend Saturday Morning Study Detention from 8:30am to 10:30am on Saturday {@concequenceDateStart} for the following (as outlined below):</p><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@IncidentType}</td></tr><tr><td>Detention Date:</td><td>Saturday {@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>{@StudentpreferredName} is required to report to Student Reception at   8:30am in full College academic uniform and will engage in academic study.&nbsp; He is required to bring his College Notebook and any other necessary items required for set work.&nbsp; He will also need to bring food and a drink for break time.<br /><br />Please note that Saturday Morning Detention is regarded by the college as a very serious matter.<br />Failure to attend will result in further severe disciplinary consequences.<br /><br />Please <a href="https://ack.whitefriars.vic.edu.au/ack/?gid={@gid}">click here</a> to acknowledge receipt of this notification and {@StudentgivenName}&#39;s attendance at this detention.<br /></p><p>Yours sincerely</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',69,0,1,1,1,0,N'insert'),
(8,N'After School Detention',N'Notification of After School Detention For',N'Dear  Parent/Guardian,</p><p>This email is to inform you that {@StudentpreferredName} is required to attend an After School Detention as outlined below:</p><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr><td>Detention Date:</td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr><tr><td>   House Leader:</td><td>{@HOHqualifier} {@HOHpreferedName} {@HOHsurname}</td></tr></table><p>Please <a href="https://ack.whitefriars.vic.edu.au/ack/?gid={@gid}">click here</a> to acknowledge receipt of this notification and {@StudentgivenName}&#39;s attendance at this detention.</p><p><strong><em>Please note - failure to attend this After School Detention will result in the issuing of a Saturday Detention.</em></strong><br /></p><table style="border-style: solid; border-width: 2px; padding: 1px 4px"><tr><td style="text-align: center"><strong>After School Detention Procedures</strong></td></tr><tr><td><ul><li>Students must present themselves to the supervising teacher   at Student Reception at 3:25PM</li><li>Students are expected to bring a pen and work in silence in the room.</li><li>Work may be set by the supervising teacher or by the teacher issuing the detention</li><li>Students may be required to undertake College service at this time.</li></ul></td></tr></table><p>Yours sincerely</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',46,0,1,1,1,0,N'insert'),
(11,N'Saturday Detention',N'Notification of Saturday Detention For',N'<p>Dear  Parent/Guardian,</p><p>This email is to inform you that {@StudentpreferredName} is required to attend Saturday Morning Detention from 8:30am to 10:30am  on Saturday {@concequenceDateStart} for the following (as outlined below):</p><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr><td>Detention Date:</td><td>Saturday {@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>{@StudentpreferredName} is required to report to Student Reception at 8:30am.&nbsp; He is required to bring pens for writing tasks and food and a drink for break time.<br />Notebook computers are not to be brought to Saturday Detentions.<br /><br />Please note that Saturday morning detention is regarded by the College as a very serious matter.<br />Failure to attend, without a valid reason, will result in severe disciplinary consequences.<br /><br />Please <a href="https://ack.whitefriars.vic.edu.au/ack/?gid={@gid}">click here</a> to acknowledge receipt of this notification and {@StudentgivenName}&#39;s attendance at this detention.<br /></p><p>Yours sincerely</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p></body>',42,0,1,0,1,0,N'insert'),
(12,N'Student Free Day Detention',N'Notification of Student Free Day Detention For',N'<p>Dear  Parent/Guardian,</p><p>This email is to inform you that {@StudentpreferredName} is required to attend a Student Free Day Detention as outlined below:</p><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr><td>Detention Date:</td><td>{@concequenceDateStart}</td></tr><tr><td>House 
	Leader:</td><td>{@HOHqualifier} {@HOHpreferedName} {@HOHsurname}</td></tr></table><p>{@StudentpreferredName} is required to report to Reception at 8:30am in{@DressCode}.</p><p>Please <a href="https://ack.whitefriars.vic.edu.au/ack/?gid={@gid}">click here</a> to acknowledge receipt of this notification and {@StudentgivenName}&#39;s attendance at this detention.</p><p><strong><em>Please note that a Student Free Day Detention is regarded by the College as a very serious matter. Failure to attend without a valid reason will result in further severe disciplinary consequences.</em></strong><br /></p><p>I trust that you will discuss with {@StudentpreferredName} the reason for this detention and that there will be no recurrence of such behaviour.</p><p>Yours sincerely<br />&nbsp;</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',43,0,1,0,1,0,N'insert'),
(13,N'Suspension from Buses',N'Notification of Suspension from Buses For',N'<p>Dear  Parent/Guardian,<br /><br />It has come to our attention that {@StudentpreferredName} has engaged in unacceptable behaviour on a College bus.&nbsp; Due to our heavy reliance on the bus company&#39;s buses for the transport of our students to and from school, any breaches of our code of behaviour are taken very seriously.&nbsp; We do not wish to jeopardize our relationship with the bus company or the safety of our students.&nbsp; As a consequence of his actions, {@StudentpreferredName} will not be permitted to catch an afternoon bus from the College grounds from {@concequenceDateStart} until {@concequenceDateEnd}.&nbsp; <br />Please note the details below:<br /></p><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr><td><b>Suspension from Buses Begins:</b></td><td><b>{@concequenceDateStart}</b></td></tr><tr><td><b>Suspension from Buses Ends:</b></td><td><b>{@concequenceDateEnd} </b> </td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>We trust that {@StudentpreferredName} will think twice before again putting himself in a position where he will lose the privilege of catching a bus at the College.<br /><br />Please <a href="https://ack.whitefriars.vic.edu.au/ack/?gid={@gid}">click here</a> to acknowledge receipt of this notification.<br /><br />If you have any queries regarding this matter, please do not hesitate to contact me at the College.</p><p>Yours sincerely, <br /></p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',62,0,1,0,1,0,N'insert'),
(14,N'After School Detention Data Updated',N'Alert: Alteration of After School Detention Details For',N'<p>Dear  Parent/Guardian,</p><p>Please be advised that the details of the After School Detention (as outlined below) have been modified.</p><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr style="font-weight: 700"><td><font color="red">New Detention Date:</font></td><td><font color="red">{@concequenceDateStart}</font></td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr><tr><td>House 
	Leader:</td><td>{@HOHqualifier} {@HOHpreferedName} {@HOHsurname}</td></tr></table><p>Please <a href="https://ack.whitefriars.vic.edu.au/ack/?gid={@gid}">click here</a> to acknowledge receipt of this notification and {@StudentgivenName}&#39;s attendance on the new date.</p><p><strong><em>Please note - failure to attend this After School Detention will result in the issuing of a Saturday Detention.</em></strong><br /></p><table style="border-style: solid; border-width: 2px; padding: 1px 4px"><tr><td style="text-align: center"><strong>After School Detention Procedures</strong></td></tr><tr><td><ul><li>Students must present themselves to the supervising teacher in Room U4 at 3:25pm</li><li>Students are expected to bring a pen and work in silence in the room.</li><li>Work may be set by the supervising teacher or by the teacher issuing the detention</li><li>Students may be required to undertake College service at this time.</li></ul></td></tr></table><p>Yours sincerely<br /></p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',46,0,1,0,1,0,N'update'),
(15,N'Suspension from College',N'Notification of Suspension from College For',N'<div style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">
    <p>Dear Parent/Guardian,</p>
    <p>This email is to confirm {@StudentpreferredName}&#39;s suspension from the College from {@concequenceDateStart} up to and including {@concequenceDateEnd} as a result of {@incidentType}.</p>
    <p>{@StudentpreferredName} has been spoken to regarding his involvement in this incident and why it is regarded as an extremely serious matter by the College. We would appreciate if you could speak with him in an effort to ensure {@StudentpreferredName}
        is aware of how his actions have affected himself and others.</p>
    <p>Should {@StudentpreferredName} need to contact his subject teachers regarding work which he can undertake during this period of suspension, he should do so by either email or phone between 3.15 and 4.00pm on a school day.</p>
    <p>{@StudentpreferredName} is to report to his House Leader immediately upon his return to the College to discuss his return to classes.</p>
    <p>We look forward to your support in this matter and hope {@StudentpreferredName} is able to learn from this experience. Should you have any queries, or require further information, regarding this matter please do not hesitate to contact {@StudentpreferredName}&#39;s
        House Leader at the College.</p>
    <p>Suspension details:</p>
    <table>
        <tr>
            <td>Student:</td>
            <td>{@StudentgivenName} {@Studentsurname}</td>
        </tr>
        <tr>
            <td>Issue:</td>
            <td>{@incidentType}</td>
        </tr>
        <tr>
            <td style="vertical-align:top">Suspension Dates:</td>
            <td>
                <table>
                    <tr>
                        <td>First day</td>
                        <td>{@concequenceDateStart}</td>
                    </tr>
                    <tr>
                        <td>Last day</td>
                        <td>{@concequenceDateEnd}</td>
                    </tr>
                </table>
            </td>
        </tr>
        <tr>
            <td>House Leader:
            </td>
            <td>{@HOHqualifier} {@HOHpreferedName} {@HOHsurname}</td>
        </tr>
        <tr>
            <td>Deputy Principal:</td>
            <td>{@DPqualifier} {@DPpreferedName} {@DPsurname}</td>
        </tr>
    </table>
    <p>Yours faithfully</p>
</div>
<p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',36,0,1,0,1,0,N'insert'),
(17,N'Lunchtime Detention',N'You have to attend a lunchtime detention',N'<font color=red size=4>You have been issued with a lunchtime detention.</font></br></br>
Student:<b>{@Studentsurname},{@StudentgivenName}({@StudentpreferredName})</b></br></br>Date of Detention:<b>{@concequenceDateStart}</b></br></br>Reason for Detention:<b>{@incidentType}</b></br></br>Issuing Teacher:<b>{@Staffqualifier}{@StaffpreferedName}{@Staffsurname}</b></br></br>You are required to report to Student Reception on {@concequenceDateStart} during lunchtime to begin your detention at 1.30 pm (Mon-Fri).</br></br>If you cannot attend this detention for any reason you need to talk with either the teacher who issued this detention or your House Leader.</br></br><font color=red size=4> Failure to attend this lunchtime detention will result in a Friday After-School Detention</font>',70,1,0,1,1,0,N'insert'),
(18,N'Lunchtime Detention',N'Your lunchtime detention has been updated',N'<p><font color=red size=4>Your lunchtime detention has had its date changed!</font><p>Student: <b>{@Studentsurname}, {@StudentgivenName} ({@StudentpreferredName})</b><p>New Date of Detention: <b>{@concequenceDateStart}</b><p>Reason for Detention: <b>{@incidentType}</b><p>Issuing Teacher: <b>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</b><p> <p>You are required to report to Student Reception on {@concequenceDateStart} during lunchtime to begin your detention at 1.30pm (Mon-Fri). If you cannot attend this detention for any reason you need to talk with either the teacher who issued this detention or your House Leader.<p><font color=red size=4>Failure to attend this yard duty will result in a Friday After-School Detention</font>',70,1,0,1,1,0,N'update'),
(19,N'Lunchtime Detention',N'You DO NOT have  to attend your lunchtime detention',N'<p><font color=blue size=4>Your lunch time detention has been deleted. You no longer need to attend the following lunchtime detention.</font><p>Student: <b>{@Studentsurname}, {@StudentgivenName} ({@StudentpreferredName})</b><p>Date of Detention: <b>{@concequenceDateStart}</b><p>Reason for Detention: <b>{@incidentType}</b><p>Issuing Teacher: <b>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</b><p> </p><font color=blue size=4><p>If you have any questions regarding this email please contact your House Leader.</font>',70,1,0,1,1,0,N'delete'),
(20,N'Suspension from Classes',N'Notification of Suspension from Classes For',N'<div style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif"><p>DearParent/Guardian,</p><p>This email is to confirm {@StudentpreferredName}&#39;s suspension from classes at the College from {@concequenceDateStart} up to and including {@concequenceDateEnd} as a result of {@incidentType}. {@StudentpreferredName} is required to attend the College throughout this time however he will be completing work under supervision away from his regular classes.</p><p>{@StudentpreferredName} has been spoken to regarding his involvement in this incident and why it is regarded as an extremely serious matter by the College.  We would appreciate if you could speak with him in an effort to ensure {@StudentpreferredName} is aware of how his actions have affected himself and others.</p><p>We look forward to your support in this matter and hope {@StudentpreferredName} is able to learn from this experience.  Should you have any queries or require further information please do not hesitate to contact {@StudentpreferredName}&#39;s House  at the College.</p><p>Suspension details:</p><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr><td style="vertical-align:top">Class Suspension Dates:</td><td><table><tr><td>First day</td><td>{@concequenceDateStart}</td></tr><tr><td>Last day</td><td>{@concequenceDateEnd}</td></tr></table></td></tr><tr><td>House 
	Leader:</td><td>{@HOHqualifier} {@HOHpreferedName} {@HOHsurname}</td></tr><tr><td>Deputy Principal:</td><td>{@DPqualifier} {@DPpreferedName} {@DPsurname}</td></tr></table><p>Yours faithfully</p></div><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',41,0,1,1,1,0,N'insert'),
(21,N'Email Notification To Parent -HairStyle/Shaving',N'Notification of Uniform Infringements',N'<p> Dear Parent/Guardian,
    <div>
        <p><span>  This email is to inform you that {@StudentpreferredName}’s ’s appearance at school is currently in breach of the College’s published expectations of students regarding their personal presentation - students are required to abide by these at all times. <br />    {@StudentpreferredName} is in breach of expectations regarding his {@incidentType}. (See policy below) .</span></p>
        <p><span>  &nbsp;{@StudentpreferredName} has been spoken to regarding this and is required to rectify the matter by  <b>{@concequenceDateStart}</b>. </span> </p>
        <p><span>  Should {@StudentpreferredName} return to school without tending to this matter by the required date, he is at risk of being sent home from school</span></p>
        <p><span>      We thank you for your support and look forward to {@StudentpreferredName} returning to school with his personal presentation in accordance with College requirements.<br/>  </span></p>
        <p><span> Policy  </span> </p>
        <p><span> <i>Students are expected to be neat, clean and tidy in appearance at all times. Students who are untidily or inappropriately dressed will be expected to remedy this situation without delay. Students’ hair must be clean and neat. It must be short enough to
        be well clear of the collar and the eyes and off the face All haircuts must be no shorter than a No. 2 (clipper blade) cut. Tying hair back is not permitted. Hair must also be their natural colour. Extreme hairstyles are not permitted. These include,
        but are not restricted to tails, mohawks, undercutting and extreme shaved sections.</i></span> </p>
</p>
<p><span>Yours sincerely,</span></p>
</div>
<p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>
</p>',80,1,1,1,1,0,N'insert'),
(22,N'After School Intervantion',N'Notification of After School Intervention For',N'<p>Dear  Parent/Guardian,</p><p>&nbsp; As previously communicated, {@StudentpreferredName} was required to submit an assessment task. He has again failed to meet the due date for this work. </p><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr><td>Detention Date:</td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr><tr><td>   House Leader:</td><td>{@HOHqualifier} {@HOHpreferedName} {@HOHsurname}</td></tr></table><p>Please note, that failure to attend this After School Study Intervention Session will result in the issuing of a Saturday Detention.<br/>Please <a href="https://ack.whitefriars.vic.edu.au/ack/?gid={@gid}">click here</a> to acknowledge receipt of this notification and {@StudentgivenName}&#39;s attendance at this study intervention.</p><table style="border-style: solid; border-width: 2px; padding: 1px 4px"><tr><td style="text-align: center"><strong>After School Study Intervention Procedures</strong></td></tr><tr><td><ul><li>Students must present themselves to the supervising teacher at the Library at 3:25pm.</li><li>Students are expected to bring materials necessary for them to  complete work set by one or more of their subject teachers.</li></ul></td></tr></table><p>Please contact me at the College if you wish to further discuss your son&#39;s learning.</p><p>Yours sincerely</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',81,0,1,1,1,0,N'insert'),
(23,N'After School Detention',N'Notification of After School Detention For',N'Dear  Parent/Guardian,</p><p>This email is to inform you that {@StudentpreferredName} is required to attend an After School Detention as outlined below:</p><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr><td>Detention Date:</td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr><tr><td>   House Leader:</td><td>{@HOHqualifier} {@HOHpreferedName} {@HOHsurname}</td></tr></table><p>Please <a href="https://ack.whitefriars.vic.edu.au/ack/?gid={@gid}">click here</a> to acknowledge receipt of this notification and {@StudentgivenName}&#39;s attendance at this detention.</p><p><strong><em>Please note - failure to attend this After School Detention will result in the issuing of a Saturday Detention. Furthermore, another breach of the {@incidentType} policy this year will result in a parent/guardian having to collect the mobile phone from the College.</em></strong><br /></p><table style="border-style: solid; border-width: 2px; padding: 1px 4px"><tr><td style="text-align: center"><strong>After School Detention Procedures</strong></td></tr><tr><td><ul><li>Students must present themselves to the supervising teacher   at Student Reception at 3:25PM</li><li>Students are expected to bring a pen and work in silence in the room.</li><li>Work may be set by the supervising teacher or by the teacher issuing the detention</li><li>Students may be required to undertake College service at this time.</li></ul></td></tr></table><p>Yours sincerely</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',82,0,1,1,1,0,N'insert'),
(24,N'After School Detention Data Updated',N'Alert: Alteration of After School Detention Details For',N'<p>Dear  Parent/Guardian,</p><p>Please be advised that the details of the After School Detention (as outlined below) have been modified.</p><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr style="font-weight: 700"><td><font color="red">New Detention Date:</font></td><td><font color="red">{@concequenceDateStart}</font></td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr><tr><td>House 
	Leader:</td><td>{@HOHqualifier} {@HOHpreferedName} {@HOHsurname}</td></tr></table><p>Please <a href="https://ack.whitefriars.vic.edu.au/ack/?gid={@gid}">click here</a> to acknowledge receipt of this notification and {@StudentgivenName}&#39;s attendance on the new date.</p><p><strong><em>Please note - failure to attend this After School Detention will result in the issuing of a Saturday Detention.</em></strong><br /></p><table style="border-style: solid; border-width: 2px; padding: 1px 4px"><tr><td style="text-align: center"><strong>After School Detention Procedures</strong></td></tr><tr><td><ul><li>Students must present themselves to the supervising teacher in Room U4 at 3:25pm</li><li>Students are expected to bring a pen and work in silence in the room.</li><li>Work may be set by the supervising teacher or by the teacher issuing the detention</li><li>Students may be required to undertake College service at this time.</li></ul></td></tr></table><p>Yours sincerely<br /></p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',82,0,1,0,1,0,N'update'),
(26,N'Verbal Or Written Apology',N'Level 1 Notification Verbal or Written Apology',N'<p>Dear Staff,<br /><br />This email is to inform you that {@StudentpreferredName} has been issued with {@concequence}. The details are as follows:<br /></P><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr>
	<td style="height: 31px">consequence:</td><td style="height: 31px">{@concequence}</td></tr><tr><td>consequence Date: </td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>Yours sincerely,</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',44,0,0,1,1,0,N'insert'),
(27,N'Supervised yard duty (by issuing teacher) at recess or lunch',N'Level 1 Notification Supervised yard duty (by issuing teacher) at recess or lunch',N'<p>Dear Staff,<br /><br />This email is to inform you that {@StudentpreferredName} has been issued with {@concequence}. The details are as follows:<br /></P><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr>
	<td style="height: 31px">consequence:</td><td style="height: 31px">{@concequence}</td></tr><tr><td>consequence Date: </td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>Yours sincerely,</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',56,0,0,1,1,0,N'insert'),
(28,N'Send Home To Change',N'Level 1 Notification Send Home To Change',N'<p>Dear Staff,<br /><br />This email is to inform you that {@StudentpreferredName} has been issued with {@concequence}. The details are as follows:<br /></P><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr>
	<td style="height: 31px">consequence:</td><td style="height: 31px">{@concequence}</td></tr><tr><td>consequence Date: </td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>Yours sincerely,</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',49,0,0,1,1,0,N'insert'),
(29,N'Verbal Correction Or Reprimand',N'Level 1 Notification Verbal Correction or Reprimand',N'<p>Dear Staff,<br /><br />This email is to inform you that {@StudentpreferredName} has been issued with {@concequence}. The details are as follows:<br /></P><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr>
	<td style="height: 31px">consequence:</td><td style="height: 31px">{@concequence}</td></tr><tr><td>consequence Date: </td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>Yours sincerely,</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',52,0,0,1,1,0,N'insert'),
(30,N'Move Seat Within Classroom',N'Level 1 Notification Move Seat Within Classroom',N'<p>Dear Staff,<br /><br />This email is to inform you that {@StudentpreferredName} has been issued with {@concequence}. The details are as follows:<br /></P><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr>
	<td style="height: 31px">consequence:</td><td style="height: 31px">{@concequence}</td></tr><tr><td>consequence Date: </td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>Yours sincerely,</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',53,0,0,1,1,0,N'insert'),
(31,N'Recess or lunchtime detention  (supervised by issuing teacher)',N'Level 1 Notification Recess or lunchtime detention  (supervised by issuing teacher)',N'<p>Dear Staff,<br /><br />This email is to inform you that {@StudentpreferredName} has been issued with {@concequence}. The details are as follows:<br /></P><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr>
	<td style="height: 31px">consequence:</td><td style="height: 31px">{@concequence}</td></tr><tr><td>consequence Date: </td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>Yours sincerely,</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',57,0,0,1,1,0,N'insert'),
(32,N'Send out of class (5 min max)',N'Level 1 Notification Send out of class (5 min max))',N'<p>Dear Staff,<br /><br />This email is to inform you that {@StudentpreferredName} has been issued with {@concequence}. The details are as follows:<br /></P><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr>
	<td style="height: 31px">consequence:</td><td style="height: 31px">{@concequence}</td></tr><tr><td>consequence Date: </td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>Yours sincerely,</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',58,0,0,1,1,0,N'insert'),
(33,N'Send to another class for rest of period',N'Level 1 Notification Send to another class for rest of period',N'<p>Dear Staff,<br /><br />This email is to inform you that {@StudentpreferredName} has been issued with {@concequence}. The details are as follows:<br /></P><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr>
	<td style="height: 31px">consequence:</td><td style="height: 31px">{@concequence}</td></tr><tr><td>consequence Date: </td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>Yours sincerely,</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',59,0,0,1,1,0,N'insert'),
(34,N'Change Of Bus',N'Level 1 Notification Change Of Bus',N'<p>Dear Staff,<br /><br />This email is to inform you that {@StudentpreferredName} has been issued with {@concequence}. The details are as follows:<br /></P><table><tr><td>Student:</td><td>{@StudentgivenName} {@Studentsurname}</td></tr><tr><td>Issue:</td><td>{@incidentType}</td></tr><tr>
	<td style="height: 31px">consequence:</td><td style="height: 31px">{@concequence}</td></tr><tr><td>consequence Date: </td><td>{@concequenceDateStart}</td></tr><tr><td>Issuing Teacher:</td><td>{@Staffqualifier} {@StaffpreferedName} {@Staffsurname}</td></tr></table><p>Yours sincerely,</p><p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>',61,0,0,1,1,0,N'insert'),
(35,N'Email Notification To Parent SunSmart Infringement',N'Notification of SunSmart Infringement',N'<p> Dear Parent/Guardian,
    <div>
        <p><span>  This email is to inform you that {@StudentpreferredName} has failed to bring his College cap for his Physical Education class which is in breach of the College’s published expectations of students regarding sun protection during Term’s 1 & 4. While the College provides students with the opportunity to apply suncrean during these classes, extra protection is important and in line with SunSmart guidelines. <br />    </span>
        <span>  {@StudentpreferredName} has been spoken to regarding this and is required to ensure he has his College cap for his next Physical Education class.   </span> 
       
 <span>  Should {@StudentpreferredName} not have his College cap again for his Physical Education class this term, sanctions will be applied.
          Caps can be purchased at our uniform supplier, Bob Stewart, or the second-hand uniform shop open at the College on Tuesdays between 12.30pm-2.30pm. </span>
          </p>
      
  
  <p><span>Yours sincerely,</span></p>
</div>
<p><span style="font-size: 12pt;font-family: Arial, Helvetica, sans-serif">{@StaffpreferedName} {@Staffsurname}</span><br /><span style="font-size: 10pt;font-family: Arial, Helvetica, sans-serif">{@Stafftitle}</span></p>
</p>',83,1,1,1,1,0,N'insert')

DECLARE @TemplateFields TABLE (LegacyId INT PRIMARY KEY, TemplateLegacyId INT, FieldName NVARCHAR(255), FieldType NVARCHAR(100), FieldDescription NVARCHAR(MAX));
INSERT INTO @TemplateFields VALUES
(1,2,N'WorkItem',NULL,N'Work Item'),
(2,2,N'Class',NULL,N'Class'),
(3,2,N'SubmissionDate',N'Date',N'Submission Date'),
(4,2,N'NewSubmissionDate',N'Date',N'New Submission Date'),
(5,3,N'WorkItem',NULL,N'Work Item'),
(6,3,N'Class',NULL,N'Class'),
(7,3,N'SubmissionDate',N'Date',N'Submission Date'),
(8,3,N'NewSubmissionDate',N'Date',N'New Submission Date'),
(9,12,N'DressCode',N'String',N'clothing suitable for light work around the College / full academic uniform and will be engaged in academic study')

DECLARE @MigrationRunId BIGINT;
BEGIN TRY
    BEGIN TRANSACTION;
    INSERT INTO wellbeing.LegacyReferenceMigrationLog
    (SourceName,StartedAt,CompletedAt,Outcome,ImportedLocations,ImportedClassifications,ImportedIncidentTypes,ImportedTypeClassifications,ImportedConsequences,ImportedTypeConsequences,ImportedAllowedDays,ImportedAllowedYearLevels,ImportedCommunicationTemplates,Notes)
    VALUES (N'Incident concequnces.txt',@StartedAt,@StartedAt,N'RUNNING',0,0,0,0,0,0,0,0,0,N'Source extract has no active flags; reference rows imported active. Approval and parent-notification configuration remains NULL/unknown. Type/consequence association source is limited to TOP (1000).');
    SET @MigrationRunId=SCOPE_IDENTITY();

    INSERT INTO wellbeing.tblSchoolLocations (LocationCode,LocationName,IsActive,DisplayOrder,LegacyIncidentLocationId)
    SELECT CONCAT(N'DC_LOCATION_',s.LegacyId),s.Name,1,s.DisplayOrder,s.LegacyId
    FROM @Locations s WHERE NOT EXISTS (SELECT 1 FROM wellbeing.tblSchoolLocations t WHERE t.LegacyIncidentLocationId=s.LegacyId);

    INSERT INTO wellbeing.tblIncidentClassifications (ClassificationCode,ClassificationName,RequiresApproval,RequiresParentNotification,IsActive,DisplayOrder,LegacyGeneralClassificationId,LegacyLocationId)
    SELECT CONCAT(N'DC_CLASS_',s.LegacyId),s.Name,NULL,NULL,1,s.DisplayOrder,s.LegacyId,s.LocationLegacyId
    FROM @Classifications s WHERE NOT EXISTS (SELECT 1 FROM wellbeing.tblIncidentClassifications t WHERE t.LegacyGeneralClassificationId=s.LegacyId);

    INSERT INTO wellbeing.tblIncidentTypes (IncidentTypeCode,IncidentTypeName,IsActive,DisplayOrder,LegacyIncidentTypeId,LegacyIncidentLevel)
    SELECT CONCAT(N'DC_TYPE_',s.LegacyId),s.Name,1,s.LegacyId,s.LegacyId,s.LegacyLevel
    FROM @IncidentTypes s WHERE NOT EXISTS (SELECT 1 FROM wellbeing.tblIncidentTypes t WHERE t.LegacyIncidentTypeId=s.LegacyId);

    INSERT INTO wellbeing.tblConsequences (ConsequenceCode,ConsequenceName,ConsequenceDescription,PolicyLevelId,SeverityLevel,RequiresApproval,RequiresParentNotification,ApprovalRoleRequired,EstimatedDurationDays,DisplayOrder,IsActive,LegacyConsequenceId,LegacyAllowsMultiplePerDay,LegacyLength,LegacyProcessorRole,LegacyApprovalStatusKnown)
    SELECT CONCAT(N'DC_CONSEQUENCE_',s.LegacyId),LEFT(s.Name,100),s.Name,NULL,NULL,NULL,NULL,NULL,s.LegacyLength,s.LegacyId,1,s.LegacyId,s.AllowsMultiplePerDay,s.LegacyLength,NULLIF(s.ProcessorRole,N'NULL'),0
    FROM @Consequences s WHERE NOT EXISTS (SELECT 1 FROM wellbeing.tblConsequences t WHERE t.LegacyConsequenceId=s.LegacyId);

    UPDATE target SET LegacyProcessorRole=NULLIF(source.ProcessorRole,N'NULL'),LegacyAllowsMultiplePerDay=source.AllowsMultiplePerDay,LegacyLength=source.LegacyLength
    FROM wellbeing.tblConsequences target JOIN @Consequences source ON target.LegacyConsequenceId=source.LegacyId;

    INSERT INTO wellbeing.IncidentClassificationLocation (ClassificationId,LocationId,LegacyGeneralClassificationId)
    SELECT classification.ClassificationId,location.LocationId,source.LegacyId
    FROM @Classifications source
    JOIN wellbeing.tblIncidentClassifications classification ON classification.LegacyGeneralClassificationId=source.LegacyId
    JOIN wellbeing.tblSchoolLocations location ON location.LegacyIncidentLocationId=source.LocationLegacyId
    WHERE NOT EXISTS (SELECT 1 FROM wellbeing.IncidentClassificationLocation x WHERE x.LegacyGeneralClassificationId=source.LegacyId);

    INSERT INTO wellbeing.IncidentTypeClassification (IncidentTypeId,ClassificationId,LegacyIncidentTypeId,LegacyGeneralClassificationId)
    SELECT type.IncidentTypeId,classification.ClassificationId,source.TypeLegacyId,source.ClassificationLegacyId
    FROM @TypeClassifications source
    JOIN wellbeing.tblIncidentTypes type ON type.LegacyIncidentTypeId=source.TypeLegacyId
    JOIN wellbeing.tblIncidentClassifications classification ON classification.LegacyGeneralClassificationId=source.ClassificationLegacyId
    WHERE NOT EXISTS (SELECT 1 FROM wellbeing.IncidentTypeClassification x WHERE x.IncidentTypeId=type.IncidentTypeId AND x.ClassificationId=classification.ClassificationId);

    INSERT INTO wellbeing.IncidentTypeConsequence (IncidentTypeId,ClassificationId,ConsequenceId)
    SELECT type.IncidentTypeId,classification.ClassificationId,consequence.ConsequenceId
    FROM @TypeConsequences source
    JOIN wellbeing.tblIncidentTypes type ON type.LegacyIncidentTypeId=source.TypeLegacyId
    JOIN wellbeing.tblIncidentClassifications classification ON classification.LegacyGeneralClassificationId=source.ClassificationLegacyId
    JOIN wellbeing.tblConsequences consequence ON consequence.LegacyConsequenceId=source.ConsequenceLegacyId
    WHERE NOT EXISTS (SELECT 1 FROM wellbeing.IncidentTypeConsequence x WHERE x.IncidentTypeId=type.IncidentTypeId AND x.ClassificationId=classification.ClassificationId AND x.ConsequenceId=consequence.ConsequenceId);

    INSERT INTO wellbeing.ConsequenceAllowedDay (LegacyAllowedDayId,ConsequenceId,IsAllowed,IsCycleDay,LegacyDay,LegacyYearLevel)
    SELECT source.LegacyId,target.ConsequenceId,source.IsAllowed,source.IsCycleDay,source.LegacyDay,source.LegacyYearLevel
    FROM @AllowedDays source JOIN wellbeing.tblConsequences target ON target.LegacyConsequenceId=source.ConsequenceLegacyId
    WHERE NOT EXISTS (SELECT 1 FROM wellbeing.ConsequenceAllowedDay existing WHERE existing.LegacyAllowedDayId=source.LegacyId);

    INSERT INTO wellbeing.ConsequenceAllowedYearLevel (LegacyAllowedYearLevelId,ConsequenceId,YearLevel)
    SELECT source.LegacyId,target.ConsequenceId,source.YearLevel
    FROM @AllowedYears source JOIN wellbeing.tblConsequences target ON target.LegacyConsequenceId=source.ConsequenceLegacyId
    WHERE NOT EXISTS (SELECT 1 FROM wellbeing.ConsequenceAllowedYearLevel existing WHERE existing.LegacyAllowedYearLevelId=source.LegacyId);

    INSERT INTO wellbeing.LegacyConsequenceCommunicationTemplate (LegacyCommunicationTemplateId,TemplateDescription,TemplateSubject,TemplateMessage,LegacyConsequenceId,SendToStudent,SendToParent,SendToPastoralCareTeacher,SendToHeadOfHouse,SendToDeputyPrincipal,EventType)
    SELECT source.LegacyId,source.TemplateDescription,source.TemplateSubject,source.TemplateMessage,source.ConsequenceLegacyId,source.SendToStudent,source.SendToParent,source.SendToPCT,source.SendToHOH,source.SendToDP,source.EventType
    FROM @Templates source WHERE NOT EXISTS (SELECT 1 FROM wellbeing.LegacyConsequenceCommunicationTemplate target WHERE target.LegacyCommunicationTemplateId=source.LegacyId);

    INSERT INTO wellbeing.LegacyCommunicationTemplateDataField (LegacyDataFieldId,LegacyCommunicationTemplateId,FieldName,FieldType,FieldDescription)
    SELECT source.LegacyId,source.TemplateLegacyId,source.FieldName,source.FieldType,source.FieldDescription
    FROM @TemplateFields source
    JOIN wellbeing.LegacyConsequenceCommunicationTemplate target ON target.LegacyCommunicationTemplateId=source.TemplateLegacyId
    WHERE NOT EXISTS (SELECT 1 FROM wellbeing.LegacyCommunicationTemplateDataField existing WHERE existing.LegacyDataFieldId=source.LegacyId);

    INSERT INTO wellbeing.LegacyReferenceMigrationException (MigrationRunId,SourceTable,SourceIdentifiers,ExceptionType,Details)
    SELECT @MigrationRunId,N'IncidentTypesForIncidentGeneralClassification',CONCAT(source.TypeLegacyId,N'/',source.ClassificationLegacyId),N'ORPHAN_REFERENCE',N'Type or classification source identifier was not found; mapping not activated.'
    FROM @TypeClassifications source
    WHERE NOT EXISTS (SELECT 1 FROM wellbeing.tblIncidentTypes t WHERE t.LegacyIncidentTypeId=source.TypeLegacyId)
       OR NOT EXISTS (SELECT 1 FROM wellbeing.tblIncidentClassifications c WHERE c.LegacyGeneralClassificationId=source.ClassificationLegacyId);

    INSERT INTO wellbeing.LegacyReferenceMigrationException (MigrationRunId,SourceTable,SourceIdentifiers,ExceptionType,Details)
    SELECT @MigrationRunId,N'ConcequencesForIncidentTypesAndGeneralClassification',CONCAT(source.TypeLegacyId,N'/',source.ClassificationLegacyId,N'/',source.ConsequenceLegacyId),N'ORPHAN_REFERENCE',N'Type, classification, or consequence source identifier was not found; mapping not activated.'
    FROM @TypeConsequences source
    WHERE NOT EXISTS (SELECT 1 FROM wellbeing.tblIncidentTypes t WHERE t.LegacyIncidentTypeId=source.TypeLegacyId)
       OR NOT EXISTS (SELECT 1 FROM wellbeing.tblIncidentClassifications c WHERE c.LegacyGeneralClassificationId=source.ClassificationLegacyId)
       OR NOT EXISTS (SELECT 1 FROM wellbeing.tblConsequences c WHERE c.LegacyConsequenceId=source.ConsequenceLegacyId);

    INSERT INTO wellbeing.LegacyReferenceMigrationException (MigrationRunId,SourceTable,SourceIdentifiers,ExceptionType,Details)
    SELECT @MigrationRunId,N'ConcequencesForIncidentTypesAndGeneralClassification',CONCAT(source.TypeLegacyId,N'/',source.ClassificationLegacyId),N'UNMAPPED_TYPE_CLASSIFICATION',N'Consequence source contains this type/classification pair, but the separate IncidentTypesForIncidentGeneralClassification export does not. Consequence mapping retained; verify source relationship.'
    FROM @TypeConsequences source
    WHERE EXISTS (SELECT 1 FROM wellbeing.tblIncidentTypes t WHERE t.LegacyIncidentTypeId=source.TypeLegacyId)
      AND EXISTS (SELECT 1 FROM wellbeing.tblIncidentClassifications c WHERE c.LegacyGeneralClassificationId=source.ClassificationLegacyId)
      AND EXISTS (SELECT 1 FROM wellbeing.tblConsequences c WHERE c.LegacyConsequenceId=source.ConsequenceLegacyId)
      AND NOT EXISTS (
          SELECT 1
          FROM wellbeing.IncidentTypeClassification relation
          JOIN wellbeing.tblIncidentTypes t ON t.IncidentTypeId=relation.IncidentTypeId
          JOIN wellbeing.tblIncidentClassifications c ON c.ClassificationId=relation.ClassificationId
          WHERE t.LegacyIncidentTypeId=source.TypeLegacyId
            AND c.LegacyGeneralClassificationId=source.ClassificationLegacyId
      );

    INSERT INTO wellbeing.LegacyReferenceMigrationException (MigrationRunId,SourceTable,SourceIdentifiers,ExceptionType,Details)
    SELECT @MigrationRunId,N'ConcequenceAllowedDays',CONVERT(NVARCHAR(50),source.LegacyId),N'ORPHAN_REFERENCE',N'Consequence identifier was not found; allowed-day row not activated.'
    FROM @AllowedDays source WHERE NOT EXISTS (SELECT 1 FROM wellbeing.tblConsequences c WHERE c.LegacyConsequenceId=source.ConsequenceLegacyId);

    INSERT INTO wellbeing.LegacyReferenceMigrationException (MigrationRunId,SourceTable,SourceIdentifiers,ExceptionType,Details)
    SELECT @MigrationRunId,N'ConcequenceAllowedYearLevels',CONVERT(NVARCHAR(50),source.LegacyId),N'ORPHAN_REFERENCE',N'Consequence identifier was not found; year-level row not activated.'
    FROM @AllowedYears source WHERE NOT EXISTS (SELECT 1 FROM wellbeing.tblConsequences c WHERE c.LegacyConsequenceId=source.ConsequenceLegacyId);

    INSERT INTO wellbeing.LegacyReferenceMigrationException (MigrationRunId,SourceTable,SourceIdentifiers,ExceptionType,Details)
    SELECT @MigrationRunId,N'ConcequenceCommunicationTemplate',CONVERT(NVARCHAR(50),source.LegacyId),N'ORPHAN_REFERENCE',N'Consequence identifier was not found; source ID retained without resolved consequence.'
    FROM @Templates source WHERE source.ConsequenceLegacyId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM wellbeing.tblConsequences c WHERE c.LegacyConsequenceId=source.ConsequenceLegacyId);

    INSERT INTO wellbeing.LegacyReferenceMigrationException (MigrationRunId,SourceTable,SourceIdentifiers,ExceptionType,Details)
    SELECT @MigrationRunId,N'ConcequencesForIncidentTypesAndGeneralClassification',N'TOP (1000)',N'SOURCE_ROW_LIMIT',N'The supplied extract was produced with SELECT TOP (1000); source count and completeness beyond these rows cannot be confirmed.'
    WHERE (SELECT COUNT(*) FROM @TypeConsequences)=1000;

    INSERT INTO wellbeing.LegacyReferenceMigrationException (MigrationRunId,SourceTable,SourceIdentifiers,ExceptionType,Details)
    SELECT @MigrationRunId,source.SourceTable,N'No result set in supplied text extract',N'SOURCE_DATA_NOT_PROVIDED',N'The supplied text file contains no source rows for this table; no records were fabricated or migrated.'
    FROM (VALUES
        (N'Incident'),
        (N'IncidentAuditLog'),
        (N'IncidentCommunication'),
        (N'Acknowledgement'),
        (N'ConcequenceCommunicationTemplateSendTo'),
        (N'WorkFlowCommunicationTemplates'),
        (N'IncidentCommunicationTemplateData')
    ) AS source(SourceTable);

    SELECT @LocationCount=COUNT(*) FROM @Locations;
    SELECT @ClassificationCount=COUNT(*) FROM @Classifications;
    SELECT @TypeCount=COUNT(*) FROM @IncidentTypes;
    SELECT @TypeClassificationCount=COUNT(*) FROM @TypeClassifications;
    SELECT @ConsequenceCount=COUNT(*) FROM @Consequences;
    SELECT @TypeConsequenceCount=COUNT(*) FROM @TypeConsequences;
    SELECT @AllowedDayCount=COUNT(*) FROM @AllowedDays;
    SELECT @AllowedYearCount=COUNT(*) FROM @AllowedYears;
    SELECT @TemplateCount=COUNT(*) FROM @Templates;

    UPDATE wellbeing.LegacyReferenceMigrationLog
    SET CompletedAt=SYSUTCDATETIME(),Outcome=N'COMPLETED',ImportedLocations=@LocationCount,ImportedClassifications=@ClassificationCount,
        ImportedIncidentTypes=@TypeCount,ImportedTypeClassifications=@TypeClassificationCount,ImportedConsequences=@ConsequenceCount,
        ImportedTypeConsequences=@TypeConsequenceCount,ImportedAllowedDays=@AllowedDayCount,ImportedAllowedYearLevels=@AllowedYearCount,
        ImportedCommunicationTemplates=@TemplateCount
    WHERE MigrationRunId=@MigrationRunId;
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;

SELECT * FROM wellbeing.LegacyReferenceMigrationLog WHERE MigrationRunId=@MigrationRunId;
SELECT SourceTable,ExceptionType,COUNT(*) AS ExceptionCount FROM wellbeing.LegacyReferenceMigrationException WHERE MigrationRunId=@MigrationRunId GROUP BY SourceTable,ExceptionType ORDER BY SourceTable,ExceptionType;
