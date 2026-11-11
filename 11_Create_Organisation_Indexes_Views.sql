USE SchoolDW;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_org_Staff_MasterStaffKey' AND object_id = OBJECT_ID(N'org.Staff'))
    CREATE INDEX IX_org_Staff_MasterStaffKey ON org.Staff(MasterStaffKey);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_org_StudentHouse_Current' AND object_id = OBJECT_ID(N'org.StudentHouseAssignment'))
    CREATE INDEX IX_org_StudentHouse_Current ON org.StudentHouseAssignment(StudentKey, EffectiveFrom, EffectiveTo) INCLUDE (HouseKey, IsPrimary);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_org_StudentPastoral_Current' AND object_id = OBJECT_ID(N'org.StudentPastoralGroupAssignment'))
    CREATE INDEX IX_org_StudentPastoral_Current ON org.StudentPastoralGroupAssignment(StudentKey, EffectiveFrom, EffectiveTo) INCLUDE (PastoralGroupKey, IsPrimary);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_org_StaffHouse_Current' AND object_id = OBJECT_ID(N'org.StaffHouseAssignment'))
    CREATE INDEX IX_org_StaffHouse_Current ON org.StaffHouseAssignment(HouseKey, EffectiveFrom, EffectiveTo) INCLUDE (StaffKey, RoleCode, IsPrimary);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_org_StaffPastoral_Current' AND object_id = OBJECT_ID(N'org.StaffPastoralGroupAssignment'))
    CREATE INDEX IX_org_StaffPastoral_Current ON org.StaffPastoralGroupAssignment(PastoralGroupKey, EffectiveFrom, EffectiveTo) INCLUDE (StaffKey, RoleCode, IsPrimary);
GO

CREATE OR ALTER VIEW org.vwCurrentStudentHouse
AS
WITH x AS
(
    SELECT a.StudentKey, a.HouseKey,
           COUNT(*) OVER (PARTITION BY a.StudentKey) AS AssignmentCount,
           COUNT(CASE WHEN a.IsPrimary = 1 THEN 1 END) OVER (PARTITION BY a.StudentKey) AS PrimaryCount
    FROM org.StudentHouseAssignment AS a
    WHERE a.EffectiveFrom <= CAST(GETDATE() AS DATE)
      AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= CAST(GETDATE() AS DATE))
)
SELECT StudentKey,
       CASE WHEN AssignmentCount = 1 AND PrimaryCount = 1 THEN HouseKey END AS HouseKey,
       CONVERT(bit, CASE WHEN AssignmentCount <> 1 OR PrimaryCount <> 1 THEN 1 ELSE 0 END) AS HasConflict
FROM x;
GO

CREATE OR ALTER VIEW org.vwCurrentStudentPastoralGroup
AS
WITH x AS
(
    SELECT a.StudentKey, a.PastoralGroupKey,
           COUNT(*) OVER (PARTITION BY a.StudentKey) AS AssignmentCount,
           COUNT(CASE WHEN a.IsPrimary = 1 THEN 1 END) OVER (PARTITION BY a.StudentKey) AS PrimaryCount
    FROM org.StudentPastoralGroupAssignment AS a
    WHERE a.EffectiveFrom <= CAST(GETDATE() AS DATE)
      AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= CAST(GETDATE() AS DATE))
)
SELECT StudentKey,
       CASE WHEN AssignmentCount = 1 AND PrimaryCount = 1 THEN PastoralGroupKey END AS PastoralGroupKey,
       CONVERT(bit, CASE WHEN AssignmentCount <> 1 OR PrimaryCount <> 1 THEN 1 ELSE 0 END) AS HasConflict
FROM x;
GO

CREATE OR ALTER VIEW org.vwCurrentHouseStaff
AS
SELECT h.HouseKey, h.HouseCode, h.HouseName, a.StaffKey, s.DisplayName, a.RoleCode,
       a.IsPrimary, a.IsTemporary, a.EffectiveFrom, a.EffectiveTo
FROM org.StaffHouseAssignment AS a
JOIN org.House AS h ON h.HouseKey = a.HouseKey
JOIN org.Staff AS s ON s.StaffKey = a.StaffKey
WHERE a.EffectiveFrom <= CAST(GETDATE() AS DATE)
  AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= CAST(GETDATE() AS DATE));
GO

CREATE OR ALTER VIEW org.vwCurrentPastoralGroupStaff
AS
SELECT g.PastoralGroupKey, g.GroupCode, g.GroupName, a.StaffKey, s.DisplayName, a.RoleCode,
       a.IsPrimary, a.IsTemporary, a.EffectiveFrom, a.EffectiveTo
FROM org.StaffPastoralGroupAssignment AS a
JOIN org.PastoralGroup AS g ON g.PastoralGroupKey = a.PastoralGroupKey
JOIN org.Staff AS s ON s.StaffKey = a.StaffKey
WHERE a.EffectiveFrom <= CAST(GETDATE() AS DATE)
  AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= CAST(GETDATE() AS DATE));
GO

CREATE OR ALTER VIEW org.vwStudentCurrentPastoralAssignment
AS
SELECT s.StudentKey, h.HouseKey, h.HouseCode, h.HouseName,
       g.PastoralGroupKey, g.GroupCode, g.GroupName,
       CASE WHEN pt.PrimaryCount = 1 THEN pt.StaffKey END AS PastoralCareTeacherStaffKey,
       CASE WHEN pt.PrimaryCount = 1 THEN pt.DisplayName END AS PastoralCareTeacher,
       CASE WHEN hoh.PrimaryCount = 1 THEN hoh.StaffKey END AS HeadOfHouseStaffKey,
       CASE WHEN hoh.PrimaryCount = 1 THEN hoh.DisplayName END AS HeadOfHouse,
       CONVERT(bit, CASE WHEN sh.HasConflict = 1 OR pg.HasConflict = 1
                              OR ISNULL(pt.PrimaryCount, 0) <> 1
                              OR ISNULL(hoh.PrimaryCount, 0) <> 1 THEN 1 ELSE 0 END) AS HasConflict
FROM (SELECT DISTINCT StudentKey FROM org.StudentHouseAssignment
      UNION SELECT DISTINCT StudentKey FROM org.StudentPastoralGroupAssignment) AS s
LEFT JOIN org.vwCurrentStudentHouse AS sh ON sh.StudentKey = s.StudentKey
LEFT JOIN org.House AS h ON h.HouseKey = sh.HouseKey
LEFT JOIN org.vwCurrentStudentPastoralGroup AS pg ON pg.StudentKey = s.StudentKey
LEFT JOIN org.PastoralGroup AS g ON g.PastoralGroupKey = pg.PastoralGroupKey
OUTER APPLY
(
    SELECT CASE WHEN COUNT(*) = 1 THEN MAX(a.StaffKey) END AS StaffKey,
           CASE WHEN COUNT(*) = 1 THEN MAX(st.DisplayName) END AS DisplayName,
           COUNT(*) AS PrimaryCount
    FROM org.StaffPastoralGroupAssignment AS a
    JOIN org.Staff AS st ON st.StaffKey = a.StaffKey
    WHERE a.PastoralGroupKey = pg.PastoralGroupKey AND a.RoleCode = N'PASTORAL_CARE_TEACHER'
      AND a.IsPrimary = 1 AND a.EffectiveFrom <= CAST(GETDATE() AS DATE)
      AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= CAST(GETDATE() AS DATE))
) AS pt
OUTER APPLY
(
    SELECT CASE WHEN COUNT(*) = 1 THEN MAX(a.StaffKey) END AS StaffKey,
           CASE WHEN COUNT(*) = 1 THEN MAX(st.DisplayName) END AS DisplayName,
           COUNT(*) AS PrimaryCount
    FROM org.StaffHouseAssignment AS a
    JOIN org.Staff AS st ON st.StaffKey = a.StaffKey
    WHERE a.HouseKey = sh.HouseKey AND a.RoleCode = N'HEAD_OF_HOUSE'
      AND a.IsPrimary = 1 AND a.EffectiveFrom <= CAST(GETDATE() AS DATE)
      AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= CAST(GETDATE() AS DATE))
) AS hoh;
GO
