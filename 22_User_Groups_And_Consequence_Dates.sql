USE SchoolDW;
GO

IF COL_LENGTH(N'wellbeing.tblConsequences', N'RequiresScheduledEndDate') IS NULL
BEGIN
    ALTER TABLE wellbeing.tblConsequences
        ADD RequiresScheduledEndDate BIT NOT NULL
            CONSTRAINT DF_tblConsequences_RequiresScheduledEndDate DEFAULT (0) WITH VALUES;
END;
GO

UPDATE wellbeing.tblConsequences
SET RequiresScheduledEndDate = 1,
    ModifiedDate = SYSUTCDATETIME(),
    ModifiedBy = N'22_User_Groups_And_Consequence_Dates'
WHERE IsActive = 1
  AND ConsequenceName LIKE N'Suspension%'
  AND ConsequenceName <> N'Permanent Exclusion'
  AND RequiresScheduledEndDate = 0;
GO

MERGE wellbeing.IncidentRole AS target
USING (VALUES
    (N'REPORTING_STAFF', N'Staff'),
    (N'HEAD_OF_HOUSE', N'Head of House'),
    (N'PASTORAL_CARE', N'Pastoral Care'),
    (N'ADMINISTRATION', N'Admin'),
    (N'SUPER_USER', N'Super User'),
    (N'DEPUTY_PRINCIPAL', N'Deputy Principal'),
    (N'AUTHORIZED_APPROVER', N'Authorized Approver')
) AS source(RoleCode, RoleName)
ON target.RoleCode = source.RoleCode
WHEN MATCHED THEN UPDATE SET RoleName = source.RoleName, IsActive = 1
WHEN NOT MATCHED THEN INSERT (RoleCode, RoleName) VALUES (source.RoleCode, source.RoleName);
GO

DECLARE @StaffCount INT;
SELECT @StaffCount = COUNT(*)
FROM gold.dimStaff
WHERE LOWER(LTRIM(RTRIM(Username))) = LOWER(N'chamila.pathirana')
  AND IsCurrent = 1
  AND EffectiveFromUtc <= SYSUTCDATETIME()
  AND (EffectiveToUtc IS NULL OR EffectiveToUtc >= SYSUTCDATETIME());

IF @StaffCount <> 1
    THROW 51001, 'Expected exactly one current gold.dimStaff record for chamila.pathirana.', 1;

IF NOT EXISTS
(
    SELECT 1
    FROM wellbeing.IncidentStaffRole AS assignment
    INNER JOIN wellbeing.IncidentRole AS role
        ON role.IncidentRoleId = assignment.IncidentRoleId
    WHERE LOWER(assignment.StaffUsername) = LOWER(N'chamila.pathirana')
      AND role.RoleCode = N'SUPER_USER'
      AND assignment.IsActive = 1
      AND assignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
      AND (assignment.EffectiveTo IS NULL OR assignment.EffectiveTo >= CAST(GETDATE() AS DATE))
)
BEGIN
    INSERT INTO wellbeing.IncidentStaffRole
        (StaffUsername, IncidentRoleId, EffectiveFrom, IsActive, CreatedBy)
    SELECT N'chamila.pathirana', IncidentRoleId, CAST(GETDATE() AS DATE), 1, N'bootstrap'
    FROM wellbeing.IncidentRole
    WHERE RoleCode = N'SUPER_USER'
      AND IsActive = 1;
END;
GO
