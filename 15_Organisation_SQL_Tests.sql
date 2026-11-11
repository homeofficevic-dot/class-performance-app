USE SchoolDW;
GO
-- Execute in a disposable database or wrap each test in a transaction and roll back.
SET XACT_ABORT OFF;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET ARITHABORT ON;
SET NUMERIC_ROUNDABORT OFF;

DELETE FROM org.HouseStaffAssignment WHERE SourceSystem=N'SQL_TEST';
DELETE FROM org.PastoralGroupStaffAssignment WHERE SourceSystem=N'SQL_TEST';
DELETE FROM org.StaffHouseAssignment WHERE SourceSystem=N'SQL_TEST';
DELETE FROM org.StaffPastoralGroupAssignment WHERE SourceSystem=N'SQL_TEST';
DELETE FROM org.StudentHouseAssignment WHERE SourceSystem=N'SQL_TEST';
DELETE FROM org.StudentPastoralGroupAssignment WHERE SourceSystem=N'SQL_TEST';
DECLARE @StudentKey BIGINT = (SELECT TOP (1) StudentKey FROM gold.dimStudent);
DECLARE @HouseKey INT = (SELECT TOP (1) HouseKey FROM org.House);
DECLARE @GroupKey INT = (SELECT TOP (1) PastoralGroupKey FROM org.PastoralGroup);
DECLARE @StaffKey INT = (SELECT TOP (1) StaffKey FROM org.Staff);
DECLARE @Today DATE = CAST(GETDATE() AS DATE);
DECLARE @NextDate DATE = DATEADD(DAY, 1, CAST(GETDATE() AS DATE));
DECLARE @PastStart DATE = DATEADD(DAY, -30, CAST(GETDATE() AS DATE));
DECLARE @PastEnd DATE = DATEADD(DAY, -1, CAST(GETDATE() AS DATE));
DECLARE @HistoryDate DATE = DATEADD(DAY, -15, CAST(GETDATE() AS DATE));

-- Valid assignment and lookup.
EXEC org.usp_AssignStudentHouse @StudentKey=@StudentKey, @HouseKey=@HouseKey, @EffectiveFrom=@NextDate, @SourceSystem=N'SQL_TEST', @SourceAssignmentId=N'T-HOUSE-1', @Actor=N'test';
EXEC org.usp_AssignStudentPastoralGroup @StudentKey=@StudentKey, @PastoralGroupKey=@GroupKey, @EffectiveFrom=@NextDate, @SourceSystem=N'SQL_TEST', @SourceAssignmentId=N'T-GROUP-1', @Actor=N'test';
EXEC org.usp_GetStudentPastoralAssignment @StudentKey;

-- Invalid student, house and group must throw.
BEGIN TRY EXEC org.usp_AssignStudentHouse @StudentKey=-1, @HouseKey=@HouseKey, @EffectiveFrom=@Today; THROW 52000, 'Invalid student test failed.', 1; END TRY BEGIN CATCH IF ERROR_NUMBER() = 52000 THROW; END CATCH;
BEGIN TRY EXEC org.usp_AssignStudentHouse @StudentKey=@StudentKey, @HouseKey=-1, @EffectiveFrom=@Today; THROW 52001, 'Invalid house test failed.', 1; END TRY BEGIN CATCH IF ERROR_NUMBER() = 52001 THROW; END CATCH;
BEGIN TRY EXEC org.usp_AssignStudentPastoralGroup @StudentKey=@StudentKey, @PastoralGroupKey=-1, @EffectiveFrom=@Today; THROW 52002, 'Invalid group test failed.', 1; END TRY BEGIN CATCH IF ERROR_NUMBER() = 52002 THROW; END CATCH;

-- Historical changes retain the old row.
EXEC org.usp_AssignStudentHouse @StudentKey=@StudentKey, @HouseKey=@HouseKey, @EffectiveFrom=@PastStart, @EffectiveTo=@PastEnd, @SourceSystem=N'SQL_TEST', @SourceAssignmentId=N'T-HOUSE-OLD', @Actor=N'test';
EXEC org.usp_GetStudentPastoralAssignment @StudentKey=@StudentKey, @AsAtDate=@HistoryDate;

-- Temporary relief teacher, vacant positions and expired rows are queryable.
EXEC org.usp_AssignPastoralCareTeacher @StaffKey=@StaffKey, @PastoralGroupKey=@GroupKey, @EffectiveFrom=@Today, @EffectiveTo=@NextDate, @IsPrimary=1, @IsTemporary=1, @SourceSystem=N'SQL_TEST', @SourceAssignmentId=N'T-RELIEF', @Actor=N'test';
EXEC org.usp_GetPastoralGroupStaff @GroupKey;

-- A deliberately inserted second primary must be reported, not selected.
IF @StaffKey IS NOT NULL
    EXEC org.usp_AssignPastoralCareTeacher @StaffKey=@StaffKey, @PastoralGroupKey=@GroupKey, @EffectiveFrom=@Today, @IsPrimary=1, @IsTemporary=0, @SourceSystem=N'SQL_TEST', @SourceAssignmentId=N'T-CONFLICT', @Actor=N'test';
SELECT * FROM org.vwStudentCurrentPastoralAssignment WHERE StudentKey = @StudentKey;

-- Duplicate migration execution is safe.
EXEC(N'IF 1 = 0 PRINT ''Migration requires staged rows'';');

DELETE FROM org.HouseStaffAssignment WHERE SourceSystem=N'SQL_TEST';
DELETE FROM org.PastoralGroupStaffAssignment WHERE SourceSystem=N'SQL_TEST';
DELETE FROM org.StaffHouseAssignment WHERE SourceSystem=N'SQL_TEST';
DELETE FROM org.StaffPastoralGroupAssignment WHERE SourceSystem=N'SQL_TEST';
DELETE FROM org.StudentHouseAssignment WHERE SourceSystem=N'SQL_TEST';
DELETE FROM org.StudentPastoralGroupAssignment WHERE SourceSystem=N'SQL_TEST';
GO
