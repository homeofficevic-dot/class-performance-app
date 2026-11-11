IF NOT EXISTS (
  SELECT 1
  FROM sys.indexes
  WHERE name = N'IX_CompassAttendancePeriodLines_CompassPersonId'
    AND object_id = OBJECT_ID(N'dbo.CompassAttendancePeriodLines')
)
BEGIN
  CREATE NONCLUSTERED INDEX IX_CompassAttendancePeriodLines_CompassPersonId
    ON dbo.CompassAttendancePeriodLines (CompassPersonId);
END;

IF NOT EXISTS (
  SELECT 1
  FROM sys.indexes
  WHERE name = N'IX_StudentsBasic_HomeCampus_CompassPersonId'
    AND object_id = OBJECT_ID(N'dbo.StudentsBasic')
)
BEGIN
  CREATE NONCLUSTERED INDEX IX_StudentsBasic_HomeCampus_CompassPersonId
    ON dbo.StudentsBasic (homeCampus)
    INCLUDE (compassPersonId);
END;
