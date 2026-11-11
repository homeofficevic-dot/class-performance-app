-- Optional local/demo seed only. Every row is explicitly tagged DEMO.
USE SchoolDW;
GO
SET XACT_ABORT ON;
BEGIN TRAN;

;WITH students AS
(
    SELECT StudentKey, ROW_NUMBER() OVER (ORDER BY StudentKey) AS rn
    FROM gold.dimStudent
),
houses AS
(
    SELECT HouseKey, ROW_NUMBER() OVER (ORDER BY HouseKey) AS rn
    FROM org.House WHERE SourceSystem = N'DEMO'
)
INSERT org.StudentHouseAssignment(StudentKey, HouseKey, EffectiveFrom, IsPrimary, SourceSystem, SourceAssignmentId)
SELECT s.StudentKey, h.HouseKey, CAST(GETDATE() AS DATE), 1, N'DEMO',
       CONCAT(N'DEMO-STUDENT-HOUSE-', s.rn)
FROM students s JOIN houses h ON h.rn = ((s.rn - 1) % 4) + 1
WHERE NOT EXISTS
(
    SELECT 1 FROM org.StudentHouseAssignment x
    WHERE x.SourceSystem = N'DEMO'
      AND x.SourceAssignmentId = CONCAT(N'DEMO-STUDENT-HOUSE-', s.rn)
);

;WITH students AS
(
    SELECT StudentKey, ROW_NUMBER() OVER (ORDER BY StudentKey) AS rn
    FROM gold.dimStudent
),
groups AS
(
    SELECT PastoralGroupKey, ROW_NUMBER() OVER (ORDER BY PastoralGroupKey) AS rn
    FROM org.PastoralGroup WHERE SourceSystem = N'DEMO'
)
INSERT org.StudentPastoralGroupAssignment(StudentKey, PastoralGroupKey, EffectiveFrom, IsPrimary, SourceSystem, SourceAssignmentId)
SELECT s.StudentKey, g.PastoralGroupKey, CAST(GETDATE() AS DATE), 1, N'DEMO',
       CONCAT(N'DEMO-STUDENT-GROUP-', s.rn)
FROM students s JOIN groups g ON g.rn = ((s.rn - 1) % 8) + 1
WHERE NOT EXISTS
(
    SELECT 1 FROM org.StudentPastoralGroupAssignment x
    WHERE x.SourceSystem = N'DEMO'
      AND x.SourceAssignmentId = CONCAT(N'DEMO-STUDENT-GROUP-', s.rn)
);

INSERT wellbeing.StudentPastoralAssignment
    (StudentKey, HouseKey, EffectiveFrom, AssignmentStatus, SourceSystem, SourceRecordID, CreatedBy, UpdatedBy)
SELECT a.StudentKey, a.HouseKey, a.EffectiveFrom,
       CASE WHEN a.EffectiveTo IS NULL THEN N'ACTIVE' ELSE N'ENDED' END,
       a.SourceSystem, a.SourceAssignmentId, N'demo-seed', N'demo-seed'
FROM org.StudentHouseAssignment a
WHERE a.SourceSystem = N'DEMO'
  AND NOT EXISTS
  (
      SELECT 1 FROM wellbeing.StudentPastoralAssignment x
      WHERE x.SourceSystem = a.SourceSystem AND x.SourceRecordID = a.SourceAssignmentId
  );

INSERT wellbeing.StudentPastoralAssignment
    (StudentKey, PastoralGroupKey, EffectiveFrom, AssignmentStatus, SourceSystem, SourceRecordID, CreatedBy, UpdatedBy)
SELECT a.StudentKey, a.PastoralGroupKey, a.EffectiveFrom,
       CASE WHEN a.EffectiveTo IS NULL THEN N'ACTIVE' ELSE N'ENDED' END,
       a.SourceSystem, a.SourceAssignmentId, N'demo-seed', N'demo-seed'
FROM org.StudentPastoralGroupAssignment a
WHERE a.SourceSystem = N'DEMO'
  AND NOT EXISTS
  (
      SELECT 1 FROM wellbeing.StudentPastoralAssignment x
      WHERE x.SourceSystem = a.SourceSystem AND x.SourceRecordID = a.SourceAssignmentId
  );

COMMIT;
GO
