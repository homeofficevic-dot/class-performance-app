USE SchoolDW;
GO

IF OBJECT_ID(N'wellbeing.IncidentRole', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.IncidentRole
    (
        IncidentRoleId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_IncidentRole PRIMARY KEY,
        RoleCode NVARCHAR(50) NOT NULL CONSTRAINT UQ_IncidentRole_RoleCode UNIQUE,
        RoleName NVARCHAR(100) NOT NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_IncidentRole_IsActive DEFAULT 1
    );
END;
GO

IF OBJECT_ID(N'wellbeing.IncidentStaffRole', N'U') IS NULL
BEGIN
    CREATE TABLE wellbeing.IncidentStaffRole
    (
        IncidentStaffRoleId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_IncidentStaffRole PRIMARY KEY,
        StaffUsername NVARCHAR(200) NOT NULL,
        IncidentRoleId INT NOT NULL,
        EffectiveFrom DATE NOT NULL CONSTRAINT DF_IncidentStaffRole_EffectiveFrom DEFAULT CAST(GETDATE() AS DATE),
        EffectiveTo DATE NULL,
        IsActive BIT NOT NULL CONSTRAINT DF_IncidentStaffRole_IsActive DEFAULT 1,
        CreatedDate DATETIME2 NOT NULL CONSTRAINT DF_IncidentStaffRole_CreatedDate DEFAULT SYSUTCDATETIME(),
        CreatedBy NVARCHAR(200) NOT NULL,
        CONSTRAINT FK_IncidentStaffRole_Role FOREIGN KEY (IncidentRoleId)
            REFERENCES wellbeing.IncidentRole(IncidentRoleId),
        CONSTRAINT CK_IncidentStaffRole_Dates CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
    );
    CREATE UNIQUE INDEX UX_IncidentStaffRole_ActiveAssignment
        ON wellbeing.IncidentStaffRole(StaffUsername, IncidentRoleId)
        WHERE IsActive = 1 AND EffectiveTo IS NULL;
END;
GO

MERGE wellbeing.IncidentRole AS target
USING (VALUES
    (N'REPORTING_STAFF', N'Staff'),
    (N'HEAD_OF_HOUSE', N'Head of House'),
    (N'PASTORAL_CARE', N'Pastoral Care'),
    (N'DEPUTY_PRINCIPAL', N'Deputy Principal'),
    (N'ADMINISTRATION', N'Administration'),
    (N'AUTHORIZED_APPROVER', N'Authorized Approver'),
    (N'SUPER_USER', N'Super User')
) AS source(RoleCode, RoleName)
ON target.RoleCode = source.RoleCode
WHEN MATCHED THEN UPDATE SET RoleName = source.RoleName, IsActive = 1
WHEN NOT MATCHED THEN INSERT (RoleCode, RoleName) VALUES (source.RoleCode, source.RoleName);
GO
