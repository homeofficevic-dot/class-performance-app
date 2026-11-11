-- Organisation and pastoral assignment model.
-- SQL Server / SchoolDW. Run after the gold student and staff dimensions exist.
USE SchoolDW;
GO

IF SCHEMA_ID(N'org') IS NULL EXEC(N'CREATE SCHEMA org');
GO

IF OBJECT_ID(N'org.Staff', N'U') IS NULL
BEGIN
    CREATE TABLE org.Staff
    (
        StaffKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_org_Staff PRIMARY KEY,
        MasterStaffKey INT NULL,
        SourceSystem NVARCHAR(100) NOT NULL,
        SourceEmployeeId NVARCHAR(150) NOT NULL,
        DisplayName NVARCHAR(250) NOT NULL,
        EmailAddress NVARCHAR(320) NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_org_Staff_IsActive DEFAULT 1,
        CreatedDate DATETIME2(3) NOT NULL CONSTRAINT DF_org_Staff_CreatedDate DEFAULT SYSUTCDATETIME(),
        ModifiedDate DATETIME2(3) NOT NULL CONSTRAINT DF_org_Staff_ModifiedDate DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_org_Staff_Source UNIQUE (SourceSystem, SourceEmployeeId)
    );
END;
GO

IF OBJECT_ID(N'org.House', N'U') IS NULL
BEGIN
    CREATE TABLE org.House
    (
        HouseKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_org_House PRIMARY KEY,
        HouseCode NVARCHAR(100) NOT NULL,
        HouseName NVARCHAR(200) NOT NULL,
        SourceSystem NVARCHAR(100) NULL,
        SourceHouseId NVARCHAR(150) NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_org_House_IsActive DEFAULT 1,
        EffectiveFrom DATE NOT NULL,
        EffectiveTo DATE NULL,
        CreatedDate DATETIME2(3) NOT NULL CONSTRAINT DF_org_House_CreatedDate DEFAULT SYSUTCDATETIME(),
        ModifiedDate DATETIME2(3) NOT NULL CONSTRAINT DF_org_House_ModifiedDate DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_org_House_Code UNIQUE (HouseCode),
        CONSTRAINT UQ_org_House_Source UNIQUE (SourceSystem, SourceHouseId),
        CONSTRAINT CK_org_House_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
    );
END;
GO

IF OBJECT_ID(N'org.PastoralGroup', N'U') IS NULL
BEGIN
    CREATE TABLE org.PastoralGroup
    (
        PastoralGroupKey INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_org_PastoralGroup PRIMARY KEY,
        GroupCode NVARCHAR(100) NOT NULL,
        GroupName NVARCHAR(200) NOT NULL,
        SourceSystem NVARCHAR(100) NULL,
        SourceGroupId NVARCHAR(150) NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_org_PastoralGroup_IsActive DEFAULT 1,
        EffectiveFrom DATE NOT NULL,
        EffectiveTo DATE NULL,
        CreatedDate DATETIME2(3) NOT NULL CONSTRAINT DF_org_PastoralGroup_CreatedDate DEFAULT SYSUTCDATETIME(),
        ModifiedDate DATETIME2(3) NOT NULL CONSTRAINT DF_org_PastoralGroup_ModifiedDate DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_org_PastoralGroup_Code UNIQUE (GroupCode),
        CONSTRAINT UQ_org_PastoralGroup_Source UNIQUE (SourceSystem, SourceGroupId),
        CONSTRAINT CK_org_PastoralGroup_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
    );
END;
GO

IF OBJECT_ID(N'org.StudentHouseAssignment', N'U') IS NULL
BEGIN
    CREATE TABLE org.StudentHouseAssignment
    (
        StudentHouseAssignmentKey BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_org_StudentHouseAssignment PRIMARY KEY,
        StudentKey BIGINT NOT NULL,
        HouseKey INT NOT NULL,
        EffectiveFrom DATE NOT NULL,
        EffectiveTo DATE NULL,
        IsPrimary BIT NOT NULL CONSTRAINT DF_org_StudentHouse_IsPrimary DEFAULT 1,
        SourceSystem NVARCHAR(100) NULL,
        SourceAssignmentId NVARCHAR(150) NULL,
        CreatedDate DATETIME2(3) NOT NULL CONSTRAINT DF_org_StudentHouse_CreatedDate DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(255) NULL,
        CONSTRAINT CK_org_StudentHouse_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom),
        CONSTRAINT FK_org_StudentHouse_House FOREIGN KEY (HouseKey) REFERENCES org.House(HouseKey)
    );
END;
GO

IF OBJECT_ID(N'org.StudentPastoralGroupAssignment', N'U') IS NULL
BEGIN
    CREATE TABLE org.StudentPastoralGroupAssignment
    (
        StudentPastoralGroupAssignmentKey BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_org_StudentPastoralGroupAssignment PRIMARY KEY,
        StudentKey BIGINT NOT NULL,
        PastoralGroupKey INT NOT NULL,
        EffectiveFrom DATE NOT NULL,
        EffectiveTo DATE NULL,
        IsPrimary BIT NOT NULL CONSTRAINT DF_org_StudentPastoral_IsPrimary DEFAULT 1,
        SourceSystem NVARCHAR(100) NULL,
        SourceAssignmentId NVARCHAR(150) NULL,
        CreatedDate DATETIME2(3) NOT NULL CONSTRAINT DF_org_StudentPastoral_CreatedDate DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(255) NULL,
        CONSTRAINT CK_org_StudentPastoral_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom),
        CONSTRAINT FK_org_StudentPastoral_Group FOREIGN KEY (PastoralGroupKey) REFERENCES org.PastoralGroup(PastoralGroupKey)
    );
END;
GO

IF OBJECT_ID(N'org.StaffHouseAssignment', N'U') IS NULL
BEGIN
    CREATE TABLE org.StaffHouseAssignment
    (
        StaffHouseAssignmentKey BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_org_StaffHouseAssignment PRIMARY KEY,
        StaffKey INT NOT NULL,
        HouseKey INT NOT NULL,
        RoleCode NVARCHAR(50) NOT NULL,
        EffectiveFrom DATE NOT NULL,
        EffectiveTo DATE NULL,
        IsPrimary BIT NOT NULL CONSTRAINT DF_org_StaffHouse_IsPrimary DEFAULT 1,
        IsTemporary BIT NOT NULL CONSTRAINT DF_org_StaffHouse_IsTemporary DEFAULT 0,
        SourceSystem NVARCHAR(100) NULL,
        SourceAssignmentId NVARCHAR(150) NULL,
        CreatedDate DATETIME2(3) NOT NULL CONSTRAINT DF_org_StaffHouse_CreatedDate DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(255) NULL,
        CONSTRAINT CK_org_StaffHouse_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom),
        CONSTRAINT FK_org_StaffHouse_Staff FOREIGN KEY (StaffKey) REFERENCES org.Staff(StaffKey),
        CONSTRAINT FK_org_StaffHouse_House FOREIGN KEY (HouseKey) REFERENCES org.House(HouseKey)
    );
END;
GO

IF OBJECT_ID(N'org.StaffPastoralGroupAssignment', N'U') IS NULL
BEGIN
    CREATE TABLE org.StaffPastoralGroupAssignment
    (
        StaffPastoralGroupAssignmentKey BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_org_StaffPastoralGroupAssignment PRIMARY KEY,
        StaffKey INT NOT NULL,
        PastoralGroupKey INT NOT NULL,
        RoleCode NVARCHAR(50) NOT NULL,
        EffectiveFrom DATE NOT NULL,
        EffectiveTo DATE NULL,
        IsPrimary BIT NOT NULL CONSTRAINT DF_org_StaffPastoral_IsPrimary DEFAULT 1,
        IsTemporary BIT NOT NULL CONSTRAINT DF_org_StaffPastoral_IsTemporary DEFAULT 0,
        SourceSystem NVARCHAR(100) NULL,
        SourceAssignmentId NVARCHAR(150) NULL,
        CreatedDate DATETIME2(3) NOT NULL CONSTRAINT DF_org_StaffPastoral_CreatedDate DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(255) NULL,
        CONSTRAINT CK_org_StaffPastoral_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom),
        CONSTRAINT FK_org_StaffPastoral_Staff FOREIGN KEY (StaffKey) REFERENCES org.Staff(StaffKey),
        CONSTRAINT FK_org_StaffPastoral_Group FOREIGN KEY (PastoralGroupKey) REFERENCES org.PastoralGroup(PastoralGroupKey)
    );
END;
GO

IF OBJECT_ID(N'org.AssignmentAudit', N'U') IS NULL
BEGIN
    CREATE TABLE org.AssignmentAudit
    (
        AssignmentAuditKey BIGINT IDENTITY(1,1) CONSTRAINT PK_org_AssignmentAudit PRIMARY KEY,
        EntityName SYSNAME NOT NULL,
        EntityKey BIGINT NULL,
        ActionCode NVARCHAR(30) NOT NULL,
        Details NVARCHAR(MAX) NULL,
        Actor NVARCHAR(255) NULL,
        AuditDate DATETIME2(3) NOT NULL CONSTRAINT DF_org_AssignmentAudit_AuditDate DEFAULT SYSUTCDATETIME()
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_org_Staff_MasterStaff')
    ALTER TABLE org.Staff WITH CHECK ADD CONSTRAINT FK_org_Staff_MasterStaff
        FOREIGN KEY (MasterStaffKey) REFERENCES gold.dimStaff(StaffKey);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_org_StudentHouse_Student')
    ALTER TABLE org.StudentHouseAssignment WITH CHECK ADD CONSTRAINT FK_org_StudentHouse_Student
        FOREIGN KEY (StudentKey) REFERENCES gold.dimStudent(StudentKey);
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_org_StudentPastoral_Student')
    ALTER TABLE org.StudentPastoralGroupAssignment WITH CHECK ADD CONSTRAINT FK_org_StudentPastoral_Student
        FOREIGN KEY (StudentKey) REFERENCES gold.dimStudent(StudentKey);
GO
