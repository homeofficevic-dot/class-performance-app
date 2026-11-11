-- Controlled, idempotent migration.
-- Load only verified rows into the staging tables from the named legacy sources.
-- The staging contract is deliberately explicit so missing/ambiguous source data
-- cannot create guessed relationships.
USE SchoolDW;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF OBJECT_ID(N'org.MigrationEmployee', N'U') IS NULL
CREATE TABLE org.MigrationEmployee
(
    SourceSystem NVARCHAR(100) NOT NULL, SourceEmployeeId NVARCHAR(150) NOT NULL,
    MasterStaffKey INT NULL, DisplayName NVARCHAR(250) NOT NULL, EmailAddress NVARCHAR(320) NULL,
    IsVerified BIT NOT NULL, LoadBatchId UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT PK_org_MigrationEmployee PRIMARY KEY (SourceSystem, SourceEmployeeId)
);
IF OBJECT_ID(N'org.MigrationHouse', N'U') IS NULL
CREATE TABLE org.MigrationHouse
(
    SourceSystem NVARCHAR(100) NOT NULL, SourceHouseId NVARCHAR(150) NOT NULL,
    HouseCode NVARCHAR(100) NOT NULL, HouseName NVARCHAR(200) NOT NULL, IsVerified BIT NOT NULL,
    EffectiveFrom DATE NOT NULL, EffectiveTo DATE NULL, LoadBatchId UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT PK_org_MigrationHouse PRIMARY KEY (SourceSystem, SourceHouseId)
);
IF OBJECT_ID(N'org.MigrationPastoralGroup', N'U') IS NULL
CREATE TABLE org.MigrationPastoralGroup
(
    SourceSystem NVARCHAR(100) NOT NULL, SourceGroupId NVARCHAR(150) NOT NULL,
    GroupCode NVARCHAR(100) NOT NULL, GroupName NVARCHAR(200) NOT NULL, IsVerified BIT NOT NULL,
    EffectiveFrom DATE NOT NULL, EffectiveTo DATE NULL, LoadBatchId UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT PK_org_MigrationPastoralGroup PRIMARY KEY (SourceSystem, SourceGroupId)
);
IF OBJECT_ID(N'org.MigrationStaffResponsibility', N'U') IS NULL
CREATE TABLE org.MigrationStaffResponsibility
(
    SourceSystem NVARCHAR(100) NOT NULL, SourceAssignmentId NVARCHAR(150) NOT NULL,
    SourceEmployeeId NVARCHAR(150) NOT NULL, HouseSourceId NVARCHAR(150) NULL,
    GroupSourceId NVARCHAR(150) NULL, RoleCode NVARCHAR(50) NOT NULL,
    EffectiveFrom DATE NOT NULL, EffectiveTo DATE NULL, IsPrimary BIT NOT NULL,
    IsTemporary BIT NOT NULL, IsVerified BIT NOT NULL, LoadBatchId UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT PK_org_MigrationStaffResponsibility PRIMARY KEY (SourceSystem, SourceAssignmentId)
);
IF OBJECT_ID(N'org.MigrationStudentAssignment', N'U') IS NULL
CREATE TABLE org.MigrationStudentAssignment
(
    SourceSystem NVARCHAR(100) NOT NULL, SourceAssignmentId NVARCHAR(150) NOT NULL,
    StudentKey BIGINT NOT NULL, HouseSourceId NVARCHAR(150) NULL, GroupSourceId NVARCHAR(150) NULL,
    EffectiveFrom DATE NOT NULL, EffectiveTo DATE NULL, IsPrimary BIT NOT NULL,
    IsVerified BIT NOT NULL, LoadBatchId UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT PK_org_MigrationStudentAssignment PRIMARY KEY (SourceSystem, SourceAssignmentId)
);
GO

-- Source adapters: populate the staging tables after verifying the actual legacy
-- column mappings in DC_College_Organisation, DC_StudentManagement_Organisation,
-- DC_House_Heads and DC_Level_CoOrdinators. Do not insert unverified rows.
-- Existing employee/student master keys must be resolved before staging.

SET XACT_ABORT ON;
BEGIN TRAN;

MERGE org.Staff AS target
USING (SELECT * FROM org.MigrationEmployee WHERE IsVerified = 1) AS source
ON target.SourceSystem = source.SourceSystem AND target.SourceEmployeeId = source.SourceEmployeeId
WHEN MATCHED THEN UPDATE SET MasterStaffKey = source.MasterStaffKey, DisplayName = source.DisplayName,
    EmailAddress = source.EmailAddress, ModifiedDate = SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT (MasterStaffKey, SourceSystem, SourceEmployeeId, DisplayName, EmailAddress)
    VALUES (source.MasterStaffKey, source.SourceSystem, source.SourceEmployeeId, source.DisplayName, source.EmailAddress);

MERGE org.House AS target
USING (SELECT * FROM org.MigrationHouse WHERE IsVerified = 1) AS source
ON target.SourceSystem = source.SourceSystem AND target.SourceHouseId = source.SourceHouseId
WHEN MATCHED THEN UPDATE SET HouseCode = source.HouseCode, HouseName = source.HouseName,
    EffectiveFrom = source.EffectiveFrom, EffectiveTo = source.EffectiveTo, ModifiedDate = SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT (HouseCode, HouseName, SourceSystem, SourceHouseId, EffectiveFrom, EffectiveTo)
    VALUES (source.HouseCode, source.HouseName, source.SourceSystem, source.SourceHouseId, source.EffectiveFrom, source.EffectiveTo);

MERGE org.PastoralGroup AS target
USING (SELECT * FROM org.MigrationPastoralGroup WHERE IsVerified = 1) AS source
ON target.SourceSystem = source.SourceSystem AND target.SourceGroupId = source.SourceGroupId
WHEN MATCHED THEN UPDATE SET GroupCode = source.GroupCode, GroupName = source.GroupName,
    EffectiveFrom = source.EffectiveFrom, EffectiveTo = source.EffectiveTo, ModifiedDate = SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT (GroupCode, GroupName, SourceSystem, SourceGroupId, EffectiveFrom, EffectiveTo)
    VALUES (source.GroupCode, source.GroupName, source.SourceSystem, source.SourceGroupId, source.EffectiveFrom, source.EffectiveTo);

INSERT org.StaffHouseAssignment(StaffKey, HouseKey, RoleCode, EffectiveFrom, EffectiveTo, IsPrimary, SourceSystem, SourceAssignmentId, IsTemporary)
SELECT st.StaffKey, h.HouseKey, r.RoleCode, r.EffectiveFrom, r.EffectiveTo, r.IsPrimary, r.SourceSystem, r.SourceAssignmentId, r.IsTemporary
FROM org.MigrationStaffResponsibility r JOIN org.Staff st ON st.SourceSystem = r.SourceSystem AND st.SourceEmployeeId = r.SourceEmployeeId
JOIN org.House h ON h.SourceSystem = r.SourceSystem AND h.SourceHouseId = r.HouseSourceId
WHERE r.IsVerified = 1 AND r.HouseSourceId IS NOT NULL AND r.RoleCode = N'HEAD_OF_HOUSE'
  AND NOT EXISTS (SELECT 1 FROM org.StaffHouseAssignment x WHERE x.SourceSystem = r.SourceSystem AND x.SourceAssignmentId = r.SourceAssignmentId);

INSERT org.StaffPastoralGroupAssignment(StaffKey, PastoralGroupKey, RoleCode, EffectiveFrom, EffectiveTo, IsPrimary, IsTemporary, SourceSystem, SourceAssignmentId)
SELECT st.StaffKey, g.PastoralGroupKey, r.RoleCode, r.EffectiveFrom, r.EffectiveTo, r.IsPrimary, r.IsTemporary, r.SourceSystem, r.SourceAssignmentId
FROM org.MigrationStaffResponsibility r JOIN org.Staff st ON st.SourceSystem = r.SourceSystem AND st.SourceEmployeeId = r.SourceEmployeeId
JOIN org.PastoralGroup g ON g.SourceSystem = r.SourceSystem AND g.SourceGroupId = r.GroupSourceId
WHERE r.IsVerified = 1 AND r.GroupSourceId IS NOT NULL AND r.RoleCode = N'PASTORAL_CARE_TEACHER'
  AND NOT EXISTS (SELECT 1 FROM org.StaffPastoralGroupAssignment x WHERE x.SourceSystem = r.SourceSystem AND x.SourceAssignmentId = r.SourceAssignmentId);

INSERT org.StudentHouseAssignment(StudentKey, HouseKey, EffectiveFrom, EffectiveTo, IsPrimary, SourceSystem, SourceAssignmentId)
SELECT a.StudentKey, h.HouseKey, a.EffectiveFrom, a.EffectiveTo, a.IsPrimary, a.SourceSystem, a.SourceAssignmentId
FROM org.MigrationStudentAssignment a JOIN org.House h ON h.SourceSystem = a.SourceSystem AND h.SourceHouseId = a.HouseSourceId
WHERE a.IsVerified = 1 AND a.HouseSourceId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM org.StudentHouseAssignment x WHERE x.SourceSystem = a.SourceSystem AND x.SourceAssignmentId = a.SourceAssignmentId);

INSERT org.StudentPastoralGroupAssignment(StudentKey, PastoralGroupKey, EffectiveFrom, EffectiveTo, IsPrimary, SourceSystem, SourceAssignmentId)
SELECT a.StudentKey, g.PastoralGroupKey, a.EffectiveFrom, a.EffectiveTo, a.IsPrimary, a.SourceSystem, a.SourceAssignmentId
FROM org.MigrationStudentAssignment a JOIN org.PastoralGroup g ON g.SourceSystem = a.SourceSystem AND g.SourceGroupId = a.GroupSourceId
WHERE a.IsVerified = 1 AND a.GroupSourceId IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM org.StudentPastoralGroupAssignment x WHERE x.SourceSystem = a.SourceSystem AND x.SourceAssignmentId = a.SourceAssignmentId);

COMMIT;
GO
