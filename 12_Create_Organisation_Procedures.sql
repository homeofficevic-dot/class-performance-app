USE SchoolDW;
GO

CREATE OR ALTER PROCEDURE org.usp_GetStudentPastoralAssignment
    @StudentKey BIGINT,
    @AsAtDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @AsAtDate = COALESCE(@AsAtDate, CAST(GETDATE() AS DATE));

    IF NOT EXISTS (SELECT 1 FROM gold.dimStudent WHERE StudentKey = @StudentKey)
        THROW 51000, 'StudentKey does not exist in gold.dimStudent.', 1;

    ;WITH h AS
    (
        SELECT a.*, COUNT(*) OVER () AS Cnt, COUNT(CASE WHEN IsPrimary = 1 THEN 1 END) OVER () AS PrimaryCnt
        FROM org.StudentHouseAssignment AS a
        WHERE a.StudentKey = @StudentKey AND a.EffectiveFrom <= @AsAtDate
          AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= @AsAtDate)
    ),
    p AS
    (
        SELECT a.*, COUNT(*) OVER () AS Cnt, COUNT(CASE WHEN IsPrimary = 1 THEN 1 END) OVER () AS PrimaryCnt
        FROM org.StudentPastoralGroupAssignment AS a
        WHERE a.StudentKey = @StudentKey AND a.EffectiveFrom <= @AsAtDate
          AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= @AsAtDate)
    )
    SELECT @StudentKey AS StudentKey, @AsAtDate AS AsAtDate,
           CASE WHEN h.Cnt = 1 AND h.PrimaryCnt = 1 THEN h.HouseKey END AS HouseKey,
           CASE WHEN p.Cnt = 1 AND p.PrimaryCnt = 1 THEN p.PastoralGroupKey END AS PastoralGroupKey,
           CASE WHEN h.Cnt = 1 AND h.PrimaryCnt = 1 THEN hoh.StaffKey END AS HeadOfHouseStaffKey,
           CASE WHEN p.Cnt = 1 AND p.PrimaryCnt = 1 THEN pct.StaffKey END AS PastoralCareTeacherStaffKey,
           CONVERT(bit, CASE WHEN ISNULL(h.Cnt, 0) <> 1 OR ISNULL(h.PrimaryCnt, 0) <> 1
                                  OR ISNULL(p.Cnt, 0) <> 1 OR ISNULL(p.PrimaryCnt, 0) <> 1
                                  OR ISNULL(hoh.Cnt, 0) <> 1 OR ISNULL(hoh.PrimaryCnt, 0) <> 1
                                  OR ISNULL(pct.Cnt, 0) <> 1 OR ISNULL(pct.PrimaryCnt, 0) <> 1
                             THEN 1 ELSE 0 END) AS HasConflict,
           CASE WHEN h.Cnt = 1 AND h.PrimaryCnt = 1 THEN house.HouseCode END AS HouseCode,
           CASE WHEN p.Cnt = 1 AND p.PrimaryCnt = 1 THEN pg.GroupCode END AS PastoralGroupCode,
           CASE WHEN h.Cnt = 1 AND h.PrimaryCnt = 1 THEN hoh.DisplayName END AS HeadOfHouse,
           CASE WHEN p.Cnt = 1 AND p.PrimaryCnt = 1 THEN pct.DisplayName END AS PastoralCareTeacher
    FROM (SELECT @StudentKey AS StudentKey) AS base
    LEFT JOIN
    (
        SELECT StudentKey, MAX(HouseKey) AS HouseKey, MAX(Cnt) AS Cnt, MAX(PrimaryCnt) AS PrimaryCnt
        FROM h GROUP BY StudentKey
    ) AS h ON h.StudentKey = base.StudentKey
    LEFT JOIN
    (
        SELECT StudentKey, MAX(PastoralGroupKey) AS PastoralGroupKey, MAX(Cnt) AS Cnt, MAX(PrimaryCnt) AS PrimaryCnt
        FROM p GROUP BY StudentKey
    ) AS p ON p.StudentKey = base.StudentKey
    LEFT JOIN org.House AS house ON house.HouseKey = CASE WHEN h.Cnt = 1 AND h.PrimaryCnt = 1 THEN h.HouseKey END
    LEFT JOIN org.PastoralGroup AS pg ON pg.PastoralGroupKey = CASE WHEN p.Cnt = 1 AND p.PrimaryCnt = 1 THEN p.PastoralGroupKey END
    OUTER APPLY
    (
        SELECT CASE WHEN COUNT(*) = 1 THEN MAX(a.StaffKey) END AS StaffKey,
               CASE WHEN COUNT(*) = 1 THEN MAX(s.DisplayName) END AS DisplayName,
               COUNT(*) AS Cnt, COUNT(*) AS PrimaryCnt
        FROM org.StaffHouseAssignment AS a JOIN org.Staff AS s ON s.StaffKey = a.StaffKey
        WHERE a.HouseKey = h.HouseKey AND a.RoleCode = N'HEAD_OF_HOUSE' AND a.IsPrimary = 1
          AND a.EffectiveFrom <= @AsAtDate AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= @AsAtDate)
    ) AS hoh
    OUTER APPLY
    (
        SELECT CASE WHEN COUNT(*) = 1 THEN MAX(a.StaffKey) END AS StaffKey,
               CASE WHEN COUNT(*) = 1 THEN MAX(s.DisplayName) END AS DisplayName,
               COUNT(*) AS Cnt, COUNT(*) AS PrimaryCnt
        FROM org.StaffPastoralGroupAssignment AS a JOIN org.Staff AS s ON s.StaffKey = a.StaffKey
        WHERE a.PastoralGroupKey = p.PastoralGroupKey AND a.RoleCode = N'PASTORAL_CARE_TEACHER' AND a.IsPrimary = 1
          AND a.EffectiveFrom <= @AsAtDate AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= @AsAtDate)
    ) AS pct;
END;
GO

CREATE OR ALTER PROCEDURE org.usp_AssignStudentHouse
    @StudentKey BIGINT, @HouseKey INT, @EffectiveFrom DATE, @EffectiveTo DATE = NULL,
    @SourceSystem NVARCHAR(100) = NULL, @SourceAssignmentId NVARCHAR(150) = NULL,
    @Actor NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM gold.dimStudent WHERE StudentKey = @StudentKey) THROW 51001, 'Invalid StudentKey.', 1;
        IF NOT EXISTS (SELECT 1 FROM org.House WHERE HouseKey = @HouseKey AND IsActive = 1) THROW 51002, 'Invalid or inactive HouseKey.', 1;
        IF @EffectiveTo IS NOT NULL AND @EffectiveTo < @EffectiveFrom THROW 51003, 'Invalid assignment date range.', 1;
        UPDATE org.StudentHouseAssignment SET EffectiveTo = DATEADD(DAY, -1, @EffectiveFrom)
        WHERE StudentKey = @StudentKey AND IsPrimary = 1 AND EffectiveFrom < @EffectiveFrom
          AND (EffectiveTo IS NULL OR EffectiveTo >= @EffectiveFrom);
        INSERT org.StudentHouseAssignment(StudentKey, HouseKey, EffectiveFrom, EffectiveTo, SourceSystem, SourceAssignmentId, CreatedBy)
        VALUES (@StudentKey, @HouseKey, @EffectiveFrom, @EffectiveTo, @SourceSystem, @SourceAssignmentId, @Actor);
        INSERT org.AssignmentAudit(EntityName, EntityKey, ActionCode, Details, Actor)
        VALUES (N'StudentHouseAssignment', SCOPE_IDENTITY(), N'ASSIGN', CONCAT(N'HouseKey=', @HouseKey), @Actor);
        COMMIT;
    END TRY
    BEGIN CATCH IF XACT_STATE() <> 0 ROLLBACK; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE org.usp_AssignHeadOfHouse
    @StaffKey INT, @HouseKey INT, @EffectiveFrom DATE, @EffectiveTo DATE = NULL,
    @IsPrimary BIT = 1, @SourceSystem NVARCHAR(100) = NULL, @SourceAssignmentId NVARCHAR(150) = NULL,
    @Actor NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM org.Staff WHERE StaffKey = @StaffKey AND IsActive = 1) THROW 51007, 'Invalid or inactive StaffKey.', 1;
        IF NOT EXISTS (SELECT 1 FROM org.House WHERE HouseKey = @HouseKey AND IsActive = 1) THROW 51008, 'Invalid or inactive HouseKey.', 1;
        IF @EffectiveTo IS NOT NULL AND @EffectiveTo < @EffectiveFrom THROW 51009, 'Invalid assignment date range.', 1;
        INSERT org.StaffHouseAssignment(StaffKey, HouseKey, RoleCode, EffectiveFrom, EffectiveTo, IsPrimary, SourceSystem, SourceAssignmentId, CreatedBy)
        VALUES (@StaffKey, @HouseKey, N'HEAD_OF_HOUSE', @EffectiveFrom, @EffectiveTo, @IsPrimary, @SourceSystem, @SourceAssignmentId, @Actor);
        COMMIT;
    END TRY
    BEGIN CATCH IF XACT_STATE() <> 0 ROLLBACK; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE org.usp_AssignPastoralCareTeacher
    @StaffKey INT, @PastoralGroupKey INT, @EffectiveFrom DATE, @EffectiveTo DATE = NULL,
    @IsPrimary BIT = 1, @IsTemporary BIT = 0, @SourceSystem NVARCHAR(100) = NULL,
    @SourceAssignmentId NVARCHAR(150) = NULL, @Actor NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM org.Staff WHERE StaffKey = @StaffKey AND IsActive = 1) THROW 51010, 'Invalid or inactive StaffKey.', 1;
        IF NOT EXISTS (SELECT 1 FROM org.PastoralGroup WHERE PastoralGroupKey = @PastoralGroupKey AND IsActive = 1) THROW 51011, 'Invalid or inactive PastoralGroupKey.', 1;
        IF @EffectiveTo IS NOT NULL AND @EffectiveTo < @EffectiveFrom THROW 51012, 'Invalid assignment date range.', 1;
        INSERT org.StaffPastoralGroupAssignment(StaffKey, PastoralGroupKey, RoleCode, EffectiveFrom, EffectiveTo, IsPrimary, IsTemporary, SourceSystem, SourceAssignmentId, CreatedBy)
        VALUES (@StaffKey, @PastoralGroupKey, N'PASTORAL_CARE_TEACHER', @EffectiveFrom, @EffectiveTo, @IsPrimary, @IsTemporary, @SourceSystem, @SourceAssignmentId, @Actor);
        COMMIT;
    END TRY
    BEGIN CATCH IF XACT_STATE() <> 0 ROLLBACK; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE org.usp_AssignStudentPastoralGroup
    @StudentKey BIGINT, @PastoralGroupKey INT, @EffectiveFrom DATE, @EffectiveTo DATE = NULL,
    @SourceSystem NVARCHAR(100) = NULL, @SourceAssignmentId NVARCHAR(150) = NULL,
    @Actor NVARCHAR(255) = NULL
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRY
        BEGIN TRAN;
        IF NOT EXISTS (SELECT 1 FROM gold.dimStudent WHERE StudentKey = @StudentKey) THROW 51013, 'Invalid StudentKey.', 1;
        IF NOT EXISTS (SELECT 1 FROM org.PastoralGroup WHERE PastoralGroupKey = @PastoralGroupKey AND IsActive = 1) THROW 51014, 'Invalid or inactive PastoralGroupKey.', 1;
        IF @EffectiveTo IS NOT NULL AND @EffectiveTo < @EffectiveFrom THROW 51015, 'Invalid assignment date range.', 1;
        UPDATE org.StudentPastoralGroupAssignment SET EffectiveTo = DATEADD(DAY, -1, @EffectiveFrom)
        WHERE StudentKey = @StudentKey AND IsPrimary = 1 AND EffectiveFrom < @EffectiveFrom
          AND (EffectiveTo IS NULL OR EffectiveTo >= @EffectiveFrom);
        INSERT org.StudentPastoralGroupAssignment(StudentKey, PastoralGroupKey, EffectiveFrom, EffectiveTo, SourceSystem, SourceAssignmentId, CreatedBy)
        VALUES (@StudentKey, @PastoralGroupKey, @EffectiveFrom, @EffectiveTo, @SourceSystem, @SourceAssignmentId, @Actor);
        COMMIT;
    END TRY
    BEGIN CATCH IF XACT_STATE() <> 0 ROLLBACK; THROW; END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE org.usp_GetHouseStaff
    @HouseKey INT, @AsAtDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON; SET @AsAtDate = COALESCE(@AsAtDate, CAST(GETDATE() AS DATE));
    IF NOT EXISTS (SELECT 1 FROM org.House WHERE HouseKey = @HouseKey) THROW 51016, 'Invalid HouseKey.', 1;
    SELECT a.*, s.DisplayName FROM org.StaffHouseAssignment AS a JOIN org.Staff AS s ON s.StaffKey = a.StaffKey
    WHERE a.HouseKey = @HouseKey AND a.EffectiveFrom <= @AsAtDate AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= @AsAtDate);
END;
GO

CREATE OR ALTER PROCEDURE org.usp_GetPastoralGroupStaff
    @PastoralGroupKey INT, @AsAtDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON; SET @AsAtDate = COALESCE(@AsAtDate, CAST(GETDATE() AS DATE));
    IF NOT EXISTS (SELECT 1 FROM org.PastoralGroup WHERE PastoralGroupKey = @PastoralGroupKey) THROW 51017, 'Invalid PastoralGroupKey.', 1;
    SELECT a.*, s.DisplayName FROM org.StaffPastoralGroupAssignment AS a JOIN org.Staff AS s ON s.StaffKey = a.StaffKey
    WHERE a.PastoralGroupKey = @PastoralGroupKey AND a.EffectiveFrom <= @AsAtDate AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= @AsAtDate);
END;
GO
