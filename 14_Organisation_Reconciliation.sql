USE SchoolDW;
GO

-- Each result set is a reconciliation report. Zero rows is the acceptance target.
SELECT SourceSystem, SourceEmployeeId, COUNT(*) AS DuplicateRows
FROM org.MigrationEmployee GROUP BY SourceSystem, SourceEmployeeId HAVING COUNT(*) > 1;
SELECT MasterStaffKey, COUNT(*) AS EmployeeMappings
FROM org.Staff WHERE MasterStaffKey IS NOT NULL GROUP BY MasterStaffKey HAVING COUNT(*) > 1;

SELECT h.HouseKey, h.HouseCode FROM org.House h
LEFT JOIN org.StaffHouseAssignment a ON a.HouseKey = h.HouseKey AND a.RoleCode = N'HEAD_OF_HOUSE'
 AND a.IsPrimary = 1 AND a.EffectiveFrom <= CAST(GETDATE() AS DATE)
 AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= CAST(GETDATE() AS DATE))
WHERE a.StaffHouseAssignmentKey IS NULL;

SELECT g.PastoralGroupKey, g.GroupCode FROM org.PastoralGroup g
LEFT JOIN org.StaffPastoralGroupAssignment a ON a.PastoralGroupKey = g.PastoralGroupKey
 AND a.RoleCode = N'PASTORAL_CARE_TEACHER' AND a.IsPrimary = 1
 AND a.EffectiveFrom <= CAST(GETDATE() AS DATE)
 AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= CAST(GETDATE() AS DATE))
WHERE a.StaffPastoralGroupAssignmentKey IS NULL;

SELECT s.StudentKey FROM gold.dimStudent s
LEFT JOIN org.vwCurrentStudentHouse h ON h.StudentKey = s.StudentKey
WHERE h.StudentKey IS NULL;
SELECT s.StudentKey FROM gold.dimStudent s
LEFT JOIN org.vwCurrentStudentPastoralGroup g ON g.StudentKey = s.StudentKey
WHERE g.StudentKey IS NULL;

SELECT HouseKey, COUNT(*) AS PrimaryHeadCount FROM org.StaffHouseAssignment
WHERE RoleCode = N'HEAD_OF_HOUSE' AND IsPrimary = 1 AND EffectiveFrom <= CAST(GETDATE() AS DATE)
  AND (EffectiveTo IS NULL OR EffectiveTo >= CAST(GETDATE() AS DATE))
GROUP BY HouseKey HAVING COUNT(*) > 1;
SELECT PastoralGroupKey, COUNT(*) AS PrimaryTeacherCount FROM org.StaffPastoralGroupAssignment
WHERE RoleCode = N'PASTORAL_CARE_TEACHER' AND IsPrimary = 1 AND EffectiveFrom <= CAST(GETDATE() AS DATE)
  AND (EffectiveTo IS NULL OR EffectiveTo >= CAST(GETDATE() AS DATE))
GROUP BY PastoralGroupKey HAVING COUNT(*) > 1;

SELECT StudentKey, N'House' AS AssignmentType, COUNT(*) AS CurrentRows
FROM org.StudentHouseAssignment WHERE EffectiveFrom <= CAST(GETDATE() AS DATE)
  AND (EffectiveTo IS NULL OR EffectiveTo >= CAST(GETDATE() AS DATE)) GROUP BY StudentKey HAVING COUNT(*) > 1
UNION ALL
SELECT StudentKey, N'PastoralGroup', COUNT(*) FROM org.StudentPastoralGroupAssignment
WHERE EffectiveFrom <= CAST(GETDATE() AS DATE) AND (EffectiveTo IS NULL OR EffectiveTo >= CAST(GETDATE() AS DATE))
GROUP BY StudentKey HAVING COUNT(*) > 1;
GO
