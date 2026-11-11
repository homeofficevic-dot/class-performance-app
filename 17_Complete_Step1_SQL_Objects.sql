-- Step 1 completion objects and compatibility/reporting surfaces.
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

IF SCHEMA_ID(N'wellbeing') IS NULL EXEC(N'CREATE SCHEMA wellbeing');
IF SCHEMA_ID(N'audit') IS NULL EXEC(N'CREATE SCHEMA audit');
GO

IF OBJECT_ID(N'audit.ChangeLog', N'U') IS NULL
BEGIN
    CREATE TABLE audit.ChangeLog
    (
        AuditID BIGINT IDENTITY(1,1) CONSTRAINT PK_audit_ChangeLog PRIMARY KEY,
        EntityName SYSNAME NOT NULL,
        EntityID NVARCHAR(100) NOT NULL,
        Operation NVARCHAR(30) NOT NULL,
        OldValues NVARCHAR(MAX) NULL,
        NewValues NVARCHAR(MAX) NULL,
        ChangedBy NVARCHAR(255) NULL,
        ChangedAt DATETIME2(3) NOT NULL CONSTRAINT DF_audit_ChangeLog_ChangedAt DEFAULT SYSUTCDATETIME(),
        CorrelationID UNIQUEIDENTIFIER NULL
    );
    CREATE INDEX IX_audit_ChangeLog_Entity ON audit.ChangeLog(EntityName, EntityID, ChangedAt);
END;
GO

IF OBJECT_ID(N'wellbeing.StudentPastoralAssignment', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.StudentPastoralAssignment
    (
        StudentPastoralAssignmentID BIGINT IDENTITY(1,1) CONSTRAINT PK_wellbeing_StudentPastoralAssignment PRIMARY KEY,
        StudentKey BIGINT NOT NULL,
        HouseKey INT NULL,
        PastoralGroupKey INT NULL,
        EffectiveFrom DATE NOT NULL,
        EffectiveTo DATE NULL,
        AssignmentStatus NVARCHAR(30) NOT NULL CONSTRAINT DF_wellbeing_StudentPastoralAssignment_Status DEFAULT N'ACTIVE',
        SourceSystem NVARCHAR(100) NULL,
        SourceRecordID NVARCHAR(150) NULL,
        CreatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_wellbeing_StudentPastoralAssignment_CreatedAt DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(255) NULL,
        UpdatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_wellbeing_StudentPastoralAssignment_UpdatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedBy NVARCHAR(255) NULL,
        CONSTRAINT CK_wellbeing_StudentPastoralAssignment_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom),
        CONSTRAINT CK_wellbeing_StudentPastoralAssignment_Status CHECK (AssignmentStatus IN (N'ACTIVE',N'ENDED',N'CANCELLED')),
        CONSTRAINT CK_wellbeing_StudentPastoralAssignment_Target CHECK (HouseKey IS NOT NULL OR PastoralGroupKey IS NOT NULL),
        CONSTRAINT FK_wellbeing_StudentPastoralAssignment_Student FOREIGN KEY (StudentKey) REFERENCES gold.dimStudent(StudentKey),
        CONSTRAINT FK_wellbeing_StudentPastoralAssignment_House FOREIGN KEY (HouseKey) REFERENCES org.House(HouseKey),
        CONSTRAINT FK_wellbeing_StudentPastoralAssignment_Group FOREIGN KEY (PastoralGroupKey) REFERENCES org.PastoralGroup(PastoralGroupKey)
    );
    CREATE UNIQUE INDEX UX_wellbeing_StudentPastoralAssignment_Source
        ON wellbeing.StudentPastoralAssignment(SourceSystem, SourceRecordID)
        WHERE SourceSystem IS NOT NULL AND SourceRecordID IS NOT NULL;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_org_Staff_MasterStaffKey' AND object_id = OBJECT_ID(N'org.Staff'))
    CREATE UNIQUE INDEX UX_org_Staff_MasterStaffKey ON org.Staff(MasterStaffKey) WHERE MasterStaffKey IS NOT NULL;
GO

CREATE OR ALTER VIEW wellbeing.vw_StudentPastoralAssignments
AS
SELECT a.StudentHouseAssignmentKey AS StudentPastoralAssignmentID,
       a.StudentKey, a.HouseKey AS HouseID, NULL AS PastoralGroupID, a.EffectiveFrom, a.EffectiveTo,
       CONVERT(nvarchar(30), CASE WHEN a.EffectiveTo IS NULL OR a.EffectiveTo >= CAST(GETDATE() AS DATE) THEN N'ACTIVE' ELSE N'ENDED' END) AS AssignmentStatus,
       a.SourceSystem, a.SourceAssignmentId AS SourceRecordID, a.CreatedDate AS CreatedAt,
       a.CreatedBy, a.CreatedDate AS UpdatedAt, a.CreatedBy AS UpdatedBy
FROM org.StudentHouseAssignment AS a
UNION ALL
SELECT a.StudentPastoralGroupAssignmentKey, a.StudentKey, NULL, a.PastoralGroupKey,
       a.EffectiveFrom, a.EffectiveTo,
       CONVERT(nvarchar(30), CASE WHEN a.EffectiveTo IS NULL OR a.EffectiveTo >= CAST(GETDATE() AS DATE) THEN N'ACTIVE' ELSE N'ENDED' END),
       a.SourceSystem, a.SourceAssignmentId, a.CreatedDate, a.CreatedBy, a.CreatedDate, a.CreatedBy
FROM org.StudentPastoralGroupAssignment AS a;
GO

CREATE OR ALTER VIEW wellbeing.vw_StudentCurrentPastoralAssignment
AS
SELECT v.StudentKey,
       CONCAT(COALESCE(s.PreferredFirstName, s.FirstName), N' ', COALESCE(s.PreferredLastName, s.LastName)) AS StudentName,
       v.HouseKey AS HouseID, h.HouseName,
       v.PastoralGroupKey AS PastoralGroupID, pg.GroupName AS PastoralGroupName,
       cur.PastoralCareTeacherStaffKey, cur.PastoralCareTeacher AS PastoralCareTeacherName,
       cur.HeadOfHouseStaffKey, cur.HeadOfHouse AS HeadOfHouseName,
       v.EffectiveFrom, v.EffectiveTo,
       cur.HasConflict
FROM
(
    SELECT COALESCE(sh.StudentKey, pg.StudentKey) AS StudentKey, sh.HouseKey, pg.PastoralGroupKey,
           CASE WHEN sh.HasConflict = 0 AND pg.HasConflict = 0 THEN
                (SELECT MIN(EffectiveFrom) FROM org.StudentHouseAssignment x WHERE x.StudentKey = sh.StudentKey
                 AND x.EffectiveFrom <= CAST(GETDATE() AS DATE) AND (x.EffectiveTo IS NULL OR x.EffectiveTo >= CAST(GETDATE() AS DATE)))
           END AS EffectiveFrom,
           CONVERT(date, NULL) AS EffectiveTo
    FROM org.vwCurrentStudentHouse sh
    FULL JOIN org.vwCurrentStudentPastoralGroup pg ON pg.StudentKey = sh.StudentKey
) AS v
JOIN gold.dimStudent s ON s.StudentKey = v.StudentKey
LEFT JOIN org.House h ON h.HouseKey = v.HouseKey
LEFT JOIN org.PastoralGroup pg ON pg.PastoralGroupKey = v.PastoralGroupKey
LEFT JOIN org.vwStudentCurrentPastoralAssignment cur ON cur.StudentKey = v.StudentKey;
GO

CREATE OR ALTER VIEW org.vw_CurrentHouseStaffAssignments
AS
SELECT HouseKey AS HouseID, StaffKey AS StaffID, RoleCode AS RoleType,
       EffectiveFrom, EffectiveTo, IsPrimary, CONVERT(bit, 1) AS IsActive,
       IsTemporary, SourceSystem, SourceAssignmentId AS SourceRecordID
FROM org.StaffHouseAssignment
WHERE EffectiveFrom <= CAST(GETDATE() AS DATE)
  AND (EffectiveTo IS NULL OR EffectiveTo >= CAST(GETDATE() AS DATE));
GO

CREATE OR ALTER VIEW org.vw_CurrentPastoralGroupStaffAssignments
AS
SELECT PastoralGroupKey AS PastoralGroupID, StaffKey AS StaffID, RoleCode AS RoleType,
       EffectiveFrom, EffectiveTo, IsPrimary, CONVERT(bit, 1) AS IsActive,
       IsTemporary, SourceSystem, SourceAssignmentId AS SourceRecordID
FROM org.StaffPastoralGroupAssignment
WHERE EffectiveFrom <= CAST(GETDATE() AS DATE)
  AND (EffectiveTo IS NULL OR EffectiveTo >= CAST(GETDATE() AS DATE));
GO

CREATE OR ALTER TRIGGER org.trg_StudentHouseAssignment_Audit
ON org.StudentHouseAssignment
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT audit.ChangeLog(EntityName, EntityID, Operation, OldValues, NewValues, ChangedBy)
    SELECT N'org.StudentHouseAssignment', CONVERT(nvarchar(100), COALESCE(i.StudentHouseAssignmentKey,d.StudentHouseAssignmentKey)),
           CASE WHEN i.StudentHouseAssignmentKey IS NULL THEN N'DELETE' WHEN d.StudentHouseAssignmentKey IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
           (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           COALESCE(i.CreatedBy,d.CreatedBy)
    FROM inserted i FULL JOIN deleted d ON d.StudentHouseAssignmentKey=i.StudentHouseAssignmentKey;
END;
GO

CREATE OR ALTER TRIGGER org.trg_StudentPastoralGroupAssignment_Audit
ON org.StudentPastoralGroupAssignment
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT audit.ChangeLog(EntityName, EntityID, Operation, OldValues, NewValues, ChangedBy)
    SELECT N'org.StudentPastoralGroupAssignment', CONVERT(nvarchar(100), COALESCE(i.StudentPastoralGroupAssignmentKey,d.StudentPastoralGroupAssignmentKey)),
           CASE WHEN i.StudentPastoralGroupAssignmentKey IS NULL THEN N'DELETE' WHEN d.StudentPastoralGroupAssignmentKey IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
           (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           COALESCE(i.CreatedBy,d.CreatedBy)
    FROM inserted i FULL JOIN deleted d ON d.StudentPastoralGroupAssignmentKey=i.StudentPastoralGroupAssignmentKey;
END;
GO

CREATE OR ALTER TRIGGER org.trg_StaffHouseAssignment_Audit
ON org.StaffHouseAssignment
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT audit.ChangeLog(EntityName, EntityID, Operation, OldValues, NewValues, ChangedBy)
    SELECT N'org.StaffHouseAssignment', CONVERT(nvarchar(100), COALESCE(i.StaffHouseAssignmentKey,d.StaffHouseAssignmentKey)),
           CASE WHEN i.StaffHouseAssignmentKey IS NULL THEN N'DELETE' WHEN d.StaffHouseAssignmentKey IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
           (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           COALESCE(i.CreatedBy,d.CreatedBy)
    FROM inserted i FULL JOIN deleted d ON d.StaffHouseAssignmentKey=i.StaffHouseAssignmentKey;
END;
GO

CREATE OR ALTER TRIGGER org.trg_StaffPastoralGroupAssignment_Audit
ON org.StaffPastoralGroupAssignment
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT audit.ChangeLog(EntityName, EntityID, Operation, OldValues, NewValues, ChangedBy)
    SELECT N'org.StaffPastoralGroupAssignment', CONVERT(nvarchar(100), COALESCE(i.StaffPastoralGroupAssignmentKey,d.StaffPastoralGroupAssignmentKey)),
           CASE WHEN i.StaffPastoralGroupAssignmentKey IS NULL THEN N'DELETE' WHEN d.StaffPastoralGroupAssignmentKey IS NULL THEN N'UPDATE' ELSE N'UPDATE' END,
           (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
           COALESCE(i.CreatedBy,d.CreatedBy)
    FROM inserted i FULL JOIN deleted d ON d.StaffPastoralGroupAssignmentKey=i.StaffPastoralGroupAssignmentKey;
END;
GO

CREATE OR ALTER TRIGGER org.trg_StudentHouseAssignment_NoOverlap
ON org.StudentHouseAssignment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
    (
        SELECT 1 FROM org.StudentHouseAssignment a JOIN org.StudentHouseAssignment b
          ON a.StudentHouseAssignmentKey < b.StudentHouseAssignmentKey AND a.StudentKey=b.StudentKey
         AND a.EffectiveFrom <= ISNULL(b.EffectiveTo,'99991231')
         AND b.EffectiveFrom <= ISNULL(a.EffectiveTo,'99991231')
         AND a.IsPrimary=1 AND b.IsPrimary=1
        JOIN (SELECT DISTINCT StudentKey FROM inserted) i ON i.StudentKey=a.StudentKey
    )
    BEGIN ROLLBACK; THROW 51020, 'Overlapping primary House assignments are not permitted.', 1; END;
END;
GO

CREATE OR ALTER TRIGGER org.trg_StudentPastoralGroupAssignment_NoOverlap
ON org.StudentPastoralGroupAssignment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
    (
        SELECT 1 FROM org.StudentPastoralGroupAssignment a JOIN org.StudentPastoralGroupAssignment b
          ON a.StudentPastoralGroupAssignmentKey < b.StudentPastoralGroupAssignmentKey AND a.StudentKey=b.StudentKey
         AND a.EffectiveFrom <= ISNULL(b.EffectiveTo,'99991231')
         AND b.EffectiveFrom <= ISNULL(a.EffectiveTo,'99991231')
         AND a.IsPrimary=1 AND b.IsPrimary=1
        JOIN (SELECT DISTINCT StudentKey FROM inserted) i ON i.StudentKey=a.StudentKey
    )
    BEGIN ROLLBACK; THROW 51021, 'Overlapping primary pastoral-group assignments are not permitted.', 1; END;
END;
GO
