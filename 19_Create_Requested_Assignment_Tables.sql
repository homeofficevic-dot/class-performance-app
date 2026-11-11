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

IF OBJECT_ID(N'org.HouseStaffAssignment', N'U') IS NULL
BEGIN
    CREATE TABLE org.HouseStaffAssignment
    (
        HouseStaffAssignmentID BIGINT IDENTITY(1,1) CONSTRAINT PK_org_HouseStaffAssignment PRIMARY KEY,
        HouseKey INT NOT NULL,
        StaffKey INT NOT NULL,
        RoleType NVARCHAR(50) NOT NULL,
        EffectiveFrom DATE NOT NULL,
        EffectiveTo DATE NULL,
        IsPrimary BIT NOT NULL CONSTRAINT DF_org_HouseStaffAssignment_IsPrimary DEFAULT 1,
        IsActive BIT NOT NULL CONSTRAINT DF_org_HouseStaffAssignment_IsActive DEFAULT 1,
        CreatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_org_HouseStaffAssignment_CreatedAt DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(255) NULL,
        UpdatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_org_HouseStaffAssignment_UpdatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedBy NVARCHAR(255) NULL,
        SourceSystem NVARCHAR(100) NULL,
        SourceRecordID NVARCHAR(150) NULL,
        CONSTRAINT CK_org_HouseStaffAssignment_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom),
        CONSTRAINT CK_org_HouseStaffAssignment_Role CHECK (RoleType IN (N'HeadOfHouse',N'DeputyHeadOfHouse',N'HouseSupport')),
        CONSTRAINT FK_org_HouseStaffAssignment_House FOREIGN KEY (HouseKey) REFERENCES org.House(HouseKey),
        CONSTRAINT FK_org_HouseStaffAssignment_Staff FOREIGN KEY (StaffKey) REFERENCES org.Staff(StaffKey)
    );
    CREATE UNIQUE INDEX UX_org_HouseStaffAssignment_Source ON org.HouseStaffAssignment(SourceSystem,SourceRecordID)
        WHERE SourceSystem IS NOT NULL AND SourceRecordID IS NOT NULL;
END;
GO

IF OBJECT_ID(N'org.PastoralGroupStaffAssignment', N'U') IS NULL
BEGIN
    CREATE TABLE org.PastoralGroupStaffAssignment
    (
        PastoralGroupStaffAssignmentID BIGINT IDENTITY(1,1) CONSTRAINT PK_org_PastoralGroupStaffAssignment PRIMARY KEY,
        PastoralGroupKey INT NOT NULL,
        StaffKey INT NOT NULL,
        RoleType NVARCHAR(50) NOT NULL,
        EffectiveFrom DATE NOT NULL,
        EffectiveTo DATE NULL,
        IsPrimary BIT NOT NULL CONSTRAINT DF_org_PastoralGroupStaffAssignment_IsPrimary DEFAULT 1,
        IsActive BIT NOT NULL CONSTRAINT DF_org_PastoralGroupStaffAssignment_IsActive DEFAULT 1,
        IsTemporary BIT NOT NULL CONSTRAINT DF_org_PastoralGroupStaffAssignment_IsTemporary DEFAULT 0,
        CreatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_org_PastoralGroupStaffAssignment_CreatedAt DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(255) NULL,
        UpdatedAt DATETIME2(3) NOT NULL CONSTRAINT DF_org_PastoralGroupStaffAssignment_UpdatedAt DEFAULT SYSUTCDATETIME(),
        UpdatedBy NVARCHAR(255) NULL,
        SourceSystem NVARCHAR(100) NULL,
        SourceRecordID NVARCHAR(150) NULL,
        CONSTRAINT CK_org_PastoralGroupStaffAssignment_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom),
        CONSTRAINT CK_org_PastoralGroupStaffAssignment_Role CHECK (RoleType IN (N'PastoralCareTeacher',N'AssistantPastoralCareTeacher',N'ReliefPastoralCareTeacher')),
        CONSTRAINT FK_org_PastoralGroupStaffAssignment_Group FOREIGN KEY (PastoralGroupKey) REFERENCES org.PastoralGroup(PastoralGroupKey),
        CONSTRAINT FK_org_PastoralGroupStaffAssignment_Staff FOREIGN KEY (StaffKey) REFERENCES org.Staff(StaffKey)
    );
    CREATE UNIQUE INDEX UX_org_PastoralGroupStaffAssignment_Source ON org.PastoralGroupStaffAssignment(SourceSystem,SourceRecordID)
        WHERE SourceSystem IS NOT NULL AND SourceRecordID IS NOT NULL;
END;
GO

INSERT org.HouseStaffAssignment
    (HouseKey,StaffKey,RoleType,EffectiveFrom,EffectiveTo,IsPrimary,IsActive,CreatedBy,SourceSystem,SourceRecordID)
SELECT a.HouseKey,a.StaffKey,
       CASE a.RoleCode WHEN N'HEAD_OF_HOUSE' THEN N'HeadOfHouse'
                       WHEN N'DEPUTY_HEAD_OF_HOUSE' THEN N'DeputyHeadOfHouse'
                       ELSE N'HouseSupport' END,
       a.EffectiveFrom,a.EffectiveTo,a.IsPrimary,1,a.CreatedBy,a.SourceSystem,a.SourceAssignmentId
FROM org.StaffHouseAssignment a
WHERE NOT EXISTS
(
    SELECT 1 FROM org.HouseStaffAssignment x
    WHERE x.SourceSystem=a.SourceSystem AND x.SourceRecordID=a.SourceAssignmentId
      AND a.SourceSystem IS NOT NULL AND a.SourceAssignmentId IS NOT NULL
);

INSERT org.PastoralGroupStaffAssignment
    (PastoralGroupKey,StaffKey,RoleType,EffectiveFrom,EffectiveTo,IsPrimary,IsActive,IsTemporary,CreatedBy,SourceSystem,SourceRecordID)
SELECT a.PastoralGroupKey,a.StaffKey,
       CASE WHEN a.IsTemporary=1 THEN N'ReliefPastoralCareTeacher' ELSE N'PastoralCareTeacher' END,
       a.EffectiveFrom,a.EffectiveTo,a.IsPrimary,1,a.IsTemporary,a.CreatedBy,a.SourceSystem,a.SourceAssignmentId
FROM org.StaffPastoralGroupAssignment a
WHERE NOT EXISTS
(
    SELECT 1 FROM org.PastoralGroupStaffAssignment x
    WHERE x.SourceSystem=a.SourceSystem AND x.SourceRecordID=a.SourceAssignmentId
      AND a.SourceSystem IS NOT NULL AND a.SourceAssignmentId IS NOT NULL
);
GO

CREATE OR ALTER TRIGGER org.trg_StaffHouseAssignment_SyncRequestedTable
ON org.StaffHouseAssignment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT org.HouseStaffAssignment
        (HouseKey,StaffKey,RoleType,EffectiveFrom,EffectiveTo,IsPrimary,IsActive,CreatedBy,SourceSystem,SourceRecordID)
    SELECT i.HouseKey,i.StaffKey,
           CASE i.RoleCode WHEN N'HEAD_OF_HOUSE' THEN N'HeadOfHouse'
                           WHEN N'DEPUTY_HEAD_OF_HOUSE' THEN N'DeputyHeadOfHouse'
                           ELSE N'HouseSupport' END,
           i.EffectiveFrom,i.EffectiveTo,i.IsPrimary,1,i.CreatedBy,i.SourceSystem,i.SourceAssignmentId
    FROM inserted i
    WHERE i.SourceSystem IS NOT NULL AND i.SourceAssignmentId IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM org.HouseStaffAssignment x WHERE x.SourceSystem=i.SourceSystem AND x.SourceRecordID=i.SourceAssignmentId);
END;
GO

CREATE OR ALTER TRIGGER org.trg_StaffPastoralGroupAssignment_SyncRequestedTable
ON org.StaffPastoralGroupAssignment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT org.PastoralGroupStaffAssignment
        (PastoralGroupKey,StaffKey,RoleType,EffectiveFrom,EffectiveTo,IsPrimary,IsActive,IsTemporary,CreatedBy,SourceSystem,SourceRecordID)
    SELECT i.PastoralGroupKey,i.StaffKey,
           CASE WHEN i.IsTemporary=1 THEN N'ReliefPastoralCareTeacher' ELSE N'PastoralCareTeacher' END,
           i.EffectiveFrom,i.EffectiveTo,i.IsPrimary,1,i.IsTemporary,i.CreatedBy,i.SourceSystem,i.SourceAssignmentId
    FROM inserted i
    WHERE i.SourceSystem IS NOT NULL AND i.SourceAssignmentId IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM org.PastoralGroupStaffAssignment x WHERE x.SourceSystem=i.SourceSystem AND x.SourceRecordID=i.SourceAssignmentId);
END;
GO
