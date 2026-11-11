USE SchoolDW;
GO

IF COL_LENGTH(N'gold.dimStudent', N'CampusYearlevel') IS NULL
    ALTER TABLE gold.dimStudent ADD CampusYearlevel varchar(10) NULL;
IF COL_LENGTH(N'gold.DimStudentCore', N'CampusYearlevel') IS NULL
    ALTER TABLE gold.DimStudentCore ADD CampusYearlevel varchar(10) NULL;
GO

CREATE OR ALTER PROCEDURE gold.usp_LoadDimStudent
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @StartedUtc datetime2(7) = SYSUTCDATETIME();

    BEGIN TRY
        BEGIN TRANSACTION;

        IF EXISTS
        (
            SELECT compass_person_id
            FROM silver.Students
            WHERE is_current = 1
              AND compass_person_id IS NOT NULL
            GROUP BY compass_person_id
            HAVING COUNT(*) > 1
        )
            THROW 51001,
                'Duplicate current CompassPersonId values exist in silver.Students. Resolve Silver duplicates before loading Gold.',
                1;

        IF EXISTS
        (
            SELECT compass_person_id
            FROM silver.StudentsBasic
            WHERE is_current = 1
              AND compass_person_id IS NOT NULL
            GROUP BY compass_person_id
            HAVING COUNT(*) > 1
        )
            THROW 51003,
                'Duplicate current CompassPersonId values exist in silver.StudentsBasic. Resolve Silver duplicates before loading Gold.',
                1;

        IF EXISTS
        (
            SELECT 1
            FROM silver.StudentsBasic
            WHERE is_current = 1
              AND compass_person_id IS NOT NULL
              AND year_level IS NOT NULL
              AND LEN(LTRIM(RTRIM(year_level))) > 10
        )
            THROW 51005,
                'A current silver.StudentsBasic.year_level exceeds gold.dimStudent.CampusYearlevel capacity (varchar(10)). Resolve the source value before loading Gold.',
                1;

        SELECT
            s.compass_person_id AS CompassPersonId,
            s.username AS Username,
            s.first_name AS FirstName,
            s.last_name AS LastName,
            s.preferred_first_name AS PreferredFirstName,
            s.preferred_last_name AS PreferredLastName,
            s.middle_name AS MiddleName,
            s.title AS Title,
            s.gender AS Gender,
            s.date_of_birth AS DateOfBirth,
            s.birth_country AS BirthCountry,
            s.residency_status AS ResidencyStatus,
            s.nationality AS Nationality,
            s.email_address AS EmailAddress,
            s.mobile_number AS MobileNumber,
            s.home_phone_number AS HomePhoneNumber,
            s.home_town AS HomeTown,
            s.publish_photo_to_internal AS PublishPhotoToInternal,
            s.publish_photo_to_media AS PublishPhotoToMedia,
            s.row_hash AS SourceRowHash,
            CAST(CASE WHEN b.compass_person_id IS NULL THEN 0 ELSE 1 END AS bit) AS HasCurrentStudentsBasic,
            CONVERT(nvarchar(50), parsed.StandardYearLevel) AS YearLevel,
            CONVERT(varchar(10), b.year_level) AS CampusYearlevel
        INTO #StudentSource
        FROM silver.Students AS s
        LEFT JOIN silver.StudentsBasic AS b
            ON b.compass_person_id = s.compass_person_id
           AND b.is_current = 1
        OUTER APPLY
        (
            SELECT TRY_CONVERT
            (
                int,
                NULLIF
                (
                    RIGHT
                    (
                        LTRIM(RTRIM(b.year_level)),
                        PATINDEX
                        (
                            N'%[^0-9]%',
                            REVERSE(LTRIM(RTRIM(b.year_level))) + N'X'
                        ) - 1
                    ),
                    N''
                )
            ) AS StandardYearLevel
        ) AS parsed
        WHERE s.is_current = 1
          AND s.compass_person_id IS NOT NULL;

        IF EXISTS
        (
            SELECT CompassPersonId
            FROM #StudentSource
            GROUP BY CompassPersonId
            HAVING COUNT_BIG(*) > 1
        )
            THROW 51004,
                'The current student source join produced duplicate CompassPersonId values. Resolve source duplicates before loading Gold.',
                1;

        UPDATE g
        SET
            g.Username = s.Username,
            g.FirstName = s.FirstName,
            g.LastName = s.LastName,
            g.PreferredFirstName = s.PreferredFirstName,
            g.PreferredLastName = s.PreferredLastName,
            g.MiddleName = s.MiddleName,
            g.Title = s.Title,
            g.Gender = s.Gender,
            g.DateOfBirth = s.DateOfBirth,
            g.BirthCountry = s.BirthCountry,
            g.ResidencyStatus = s.ResidencyStatus,
            g.Nationality = s.Nationality,
            g.EmailAddress = s.EmailAddress,
            g.MobileNumber = s.MobileNumber,
            g.HomePhoneNumber = s.HomePhoneNumber,
            g.HomeTown = s.HomeTown,
            g.PublishPhotoToInternal = s.PublishPhotoToInternal,
            g.PublishPhotoToMedia = s.PublishPhotoToMedia,
            g.CampusYearlevel = CASE
                WHEN s.HasCurrentStudentsBasic = 1 THEN s.CampusYearlevel
                ELSE g.CampusYearlevel
            END,
            g.YearLevel = CASE
                WHEN s.HasCurrentStudentsBasic = 1 THEN s.YearLevel
                ELSE g.YearLevel
            END,
            g.SourceStudentsBasic = s.HasCurrentStudentsBasic,
            g.SourceRowHash = s.SourceRowHash,
            g.GoldUpdatedUTC = SYSUTCDATETIME()
        FROM gold.dimStudent AS g
        INNER JOIN #StudentSource AS s
            ON s.CompassPersonId = g.CompassPersonId
        WHERE g.SourceRowHash IS NULL
           OR g.SourceRowHash <> s.SourceRowHash
           OR ISNULL(g.SourceStudentsBasic, 0) <> s.HasCurrentStudentsBasic
           OR
           (
               s.HasCurrentStudentsBasic = 1
               AND
               (
                   g.YearLevel <> s.YearLevel
                   OR (g.YearLevel IS NULL AND s.YearLevel IS NOT NULL)
                   OR (g.YearLevel IS NOT NULL AND s.YearLevel IS NULL)
                   OR ISNULL(g.CampusYearlevel, '') <> ISNULL(s.CampusYearlevel, '')
               )
           );

        INSERT INTO gold.dimStudent
        (
            CompassPersonId,
            Username,
            FirstName,
            LastName,
            PreferredFirstName,
            PreferredLastName,
            MiddleName,
            Title,
            Gender,
            DateOfBirth,
            BirthCountry,
            ResidencyStatus,
            Nationality,
            EmailAddress,
            MobileNumber,
            HomePhoneNumber,
            HomeTown,
            YearLevel,
            CampusYearlevel,
            PublishPhotoToInternal,
            PublishPhotoToMedia,
            SourceRowHash,
            SourceGetStudents,
            SourceStudentsBasic,
            GoldCreatedUTC,
            GoldUpdatedUTC
        )
        SELECT
            s.CompassPersonId,
            s.Username,
            s.FirstName,
            s.LastName,
            s.PreferredFirstName,
            s.PreferredLastName,
            s.MiddleName,
            s.Title,
            s.Gender,
            s.DateOfBirth,
            s.BirthCountry,
            s.ResidencyStatus,
            s.Nationality,
            s.EmailAddress,
            s.MobileNumber,
            s.HomePhoneNumber,
            s.HomeTown,
            CASE WHEN s.HasCurrentStudentsBasic = 1 THEN s.YearLevel END,
            CASE WHEN s.HasCurrentStudentsBasic = 1 THEN s.CampusYearlevel END,
            s.PublishPhotoToInternal,
            s.PublishPhotoToMedia,
            s.SourceRowHash,
            CAST(0 AS bit),
            s.HasCurrentStudentsBasic,
            SYSUTCDATETIME(),
            SYSUTCDATETIME()
        FROM #StudentSource AS s
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM gold.dimStudent AS g WITH (UPDLOCK, HOLDLOCK)
            WHERE g.CompassPersonId = s.CompassPersonId
        );

        UPDATE g
        SET
            g.YearLevel = CONVERT(nvarchar(50), parsed.StandardYearLevel),
            g.CampusYearlevel = CONVERT(varchar(10), b.year_level),
            g.SourceStudentsBasic = 1,
            g.GoldUpdatedUTC = SYSUTCDATETIME()
        FROM gold.dimStudent AS g
        INNER JOIN silver.StudentsBasic AS b
            ON b.compass_person_id = g.CompassPersonId
           AND b.is_current = 1
        OUTER APPLY
        (
            SELECT TRY_CONVERT
            (
                int,
                NULLIF
                (
                    RIGHT
                    (
                        LTRIM(RTRIM(b.year_level)),
                        PATINDEX
                        (
                            N'%[^0-9]%',
                            REVERSE(LTRIM(RTRIM(b.year_level))) + N'X'
                        ) - 1
                    ),
                    N''
                )
            ) AS StandardYearLevel
        ) AS parsed
        WHERE ISNULL(g.YearLevel, N'') <> ISNULL(CONVERT(nvarchar(50), parsed.StandardYearLevel), N'')
           OR ISNULL(g.CampusYearlevel, '') <> ISNULL(CONVERT(varchar(10), b.year_level), '')
           OR ISNULL(g.SourceStudentsBasic, 0) <> 1;

        COMMIT TRANSACTION;

        SELECT
            @StartedUtc AS LoadStartedUtc,
            SYSUTCDATETIME() AS LoadCompletedUtc,
            (SELECT COUNT_BIG(*) FROM #StudentSource) AS CurrentSilverStudents,
            (SELECT COUNT_BIG(*) FROM #StudentSource WHERE HasCurrentStudentsBasic = 1) AS StudentsWithCurrentYearLevelSource,
            (SELECT COUNT_BIG(*) FROM gold.dimStudent) AS GoldStudents;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER PROCEDURE gold.usp_LoadDimStudentCore
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS
    (
        SELECT 1
        FROM silver.GetStudents
        WHERE IsCurrent = 1
          AND TRY_CONVERT(uniqueidentifier, compassPersonId) IS NULL
    )
        THROW 50101, 'Load cancelled: invalid CompassPersonId in current GetStudents.', 1;

    IF EXISTS
    (
        SELECT TRY_CONVERT(uniqueidentifier, compassPersonId)
        FROM silver.GetStudents
        WHERE IsCurrent = 1
        GROUP BY TRY_CONVERT(uniqueidentifier, compassPersonId)
        HAVING COUNT_BIG(*) > 1
    )
        THROW 50102, 'Load cancelled: duplicate current student IDs in GetStudents.', 1;

    IF EXISTS
    (
        SELECT compass_person_id
        FROM silver.StudentsBasic
        WHERE is_current = 1
          AND compass_person_id IS NOT NULL
        GROUP BY compass_person_id
        HAVING COUNT_BIG(*) > 1
    )
        THROW 50103, 'Load cancelled: duplicate current student IDs in StudentsBasic.', 1;

    IF EXISTS
    (
        SELECT compass_person_id
        FROM silver.Students
        WHERE is_current = 1
          AND compass_person_id IS NOT NULL
        GROUP BY compass_person_id
        HAVING COUNT_BIG(*) > 1
    )
        THROW 50104, 'Load cancelled: duplicate current student IDs in Students.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM silver.StudentsBasic
        WHERE is_current = 1
          AND compass_person_id IS NOT NULL
          AND year_level IS NOT NULL
          AND LEN(LTRIM(RTRIM(year_level))) > 10
    )
        THROW 50106, 'Load cancelled: current campus year level exceeds gold.DimStudentCore.CampusYearlevel capacity (varchar(10)).', 1;

    SELECT
        CONVERT(varchar(36), TRY_CONVERT(uniqueidentifier, g.compassPersonId)) AS CompassPersonId,
        COALESCE(g.username, b.username, s.username) AS Username,
        COALESCE(g.firstName, b.first_name, s.first_name) AS FirstName,
        COALESCE(g.lastName, b.last_name, s.last_name) AS LastName,
        COALESCE(g.preferredFirstName, b.preferred_first_name, s.preferred_first_name) AS PreferredFirstName,
        COALESCE(g.preferredLastName, b.preferred_last_name, s.preferred_last_name) AS PreferredLastName,
        COALESCE(b.middle_name, s.middle_name) AS MiddleName,
        COALESCE(b.title, s.title) AS Title,
        COALESCE(g.gender, b.gender, s.gender) AS Gender,
        COALESCE(g.dateOfBirth, b.date_of_birth, s.date_of_birth) AS DateOfBirth,
        COALESCE(g.birthCountry, s.birth_country) AS BirthCountry,
        COALESCE(g.residencyStatus, s.residency_status) AS ResidencyStatus,
        COALESCE(b.nationality, s.nationality) AS Nationality,
        COALESCE(g.emailAddress, s.email_address) AS EmailAddress,
        b.school_email AS SchoolEmail,
        COALESCE(g.mobileNumber, b.mobile_number, s.mobile_number) AS MobileNumber,
        COALESCE(b.home_phone_number, s.home_phone_number) AS HomePhoneNumber,
        COALESCE(g.homeTown, s.home_town) AS HomeTown,
        b.student_code AS StudentCode,
        CONVERT(nvarchar(100), parsed.StandardYearLevel) AS YearLevel,
        CONVERT(varchar(10), b.year_level) AS CampusYearlevel,
        b.organisation_name AS OrganisationName,
        CONVERT(nvarchar(36), b.home_campus) AS HomeCampus,
        b.boarder_type AS BoarderType,
        CONVERT(nvarchar(100), b.student_type) AS StudentType,
        CONVERT(nvarchar(100), b.user_status) AS UserStatus,
        COALESCE(b.publish_photo_to_internal, s.publish_photo_to_internal) AS PublishPhotoToInternal,
        COALESCE(b.publish_photo_to_media, s.publish_photo_to_media) AS PublishPhotoToMedia,
        b.photo_upload_date AS PhotoUploadDate,
        g.RowHash AS SourceRowHash,
        CONVERT(bit, 1) AS SourceGetStudents,
        CONVERT(bit, CASE WHEN b.compass_person_id IS NOT NULL THEN 1 ELSE 0 END) AS SourceStudentsBasic
    INTO #StudentSource
    FROM silver.GetStudents AS g
    LEFT JOIN silver.StudentsBasic AS b
        ON b.compass_person_id = TRY_CONVERT(uniqueidentifier, g.compassPersonId)
       AND b.is_current = 1
    LEFT JOIN silver.Students AS s
        ON s.compass_person_id = TRY_CONVERT(uniqueidentifier, g.compassPersonId)
       AND s.is_current = 1
    OUTER APPLY
    (
        SELECT TRY_CONVERT
        (
            int,
            NULLIF
            (
                RIGHT
                (
                    LTRIM(RTRIM(b.year_level)),
                    PATINDEX(N'%[^0-9]%', REVERSE(LTRIM(RTRIM(b.year_level))) + N'X') - 1
                ),
                N''
            )
        ) AS StandardYearLevel
    ) AS parsed
    WHERE g.IsCurrent = 1;

    IF EXISTS
    (
        SELECT CompassPersonId
        FROM #StudentSource
        GROUP BY CompassPersonId
        HAVING COUNT_BIG(*) > 1
    )
        THROW 50105, 'Load cancelled: source join generated duplicate student rows.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE tgt
        SET
            tgt.Username = src.Username,
            tgt.FirstName = src.FirstName,
            tgt.LastName = src.LastName,
            tgt.PreferredFirstName = src.PreferredFirstName,
            tgt.PreferredLastName = src.PreferredLastName,
            tgt.MiddleName = src.MiddleName,
            tgt.Title = src.Title,
            tgt.Gender = src.Gender,
            tgt.DateOfBirth = src.DateOfBirth,
            tgt.BirthCountry = src.BirthCountry,
            tgt.ResidencyStatus = src.ResidencyStatus,
            tgt.Nationality = src.Nationality,
            tgt.EmailAddress = src.EmailAddress,
            tgt.SchoolEmail = src.SchoolEmail,
            tgt.MobileNumber = src.MobileNumber,
            tgt.HomePhoneNumber = src.HomePhoneNumber,
            tgt.HomeTown = src.HomeTown,
            tgt.StudentCode = src.StudentCode,
            tgt.YearLevel = CASE WHEN src.SourceStudentsBasic = 1 THEN src.YearLevel ELSE tgt.YearLevel END,
            tgt.CampusYearlevel = CASE WHEN src.SourceStudentsBasic = 1 THEN src.CampusYearlevel ELSE tgt.CampusYearlevel END,
            tgt.OrganisationName = src.OrganisationName,
            tgt.HomeCampus = src.HomeCampus,
            tgt.BoarderType = src.BoarderType,
            tgt.StudentType = src.StudentType,
            tgt.UserStatus = src.UserStatus,
            tgt.PublishPhotoToInternal = src.PublishPhotoToInternal,
            tgt.PublishPhotoToMedia = src.PublishPhotoToMedia,
            tgt.PhotoUploadDate = src.PhotoUploadDate,
            tgt.SourceRowHash = src.SourceRowHash,
            tgt.SourceGetStudents = src.SourceGetStudents,
            tgt.SourceStudentsBasic = src.SourceStudentsBasic,
            tgt.GoldUpdatedUTC = SYSUTCDATETIME()
        FROM gold.DimStudentCore AS tgt
        INNER JOIN #StudentSource AS src
            ON src.CompassPersonId = tgt.CompassPersonId
        WHERE ISNULL(tgt.SourceRowHash, '') <> ISNULL(src.SourceRowHash, '')
           OR ISNULL(tgt.SourceStudentsBasic, 0) <> src.SourceStudentsBasic
           OR
           (
               src.SourceStudentsBasic = 1
               AND
               (
                   ISNULL(tgt.YearLevel, '') <> ISNULL(src.YearLevel, '')
                   OR ISNULL(tgt.CampusYearlevel, '') <> ISNULL(src.CampusYearlevel, '')
               )
           );

        INSERT INTO gold.DimStudentCore
        (
            CompassPersonId, Username, FirstName, LastName,
            PreferredFirstName, PreferredLastName, MiddleName, Title,
            Gender, DateOfBirth, BirthCountry, ResidencyStatus,
            Nationality, EmailAddress, SchoolEmail, MobileNumber,
            HomePhoneNumber, HomeTown, StudentCode, YearLevel, CampusYearlevel,
            OrganisationName, HomeCampus, BoarderType, StudentType,
            UserStatus, PublishPhotoToInternal, PublishPhotoToMedia,
            PhotoUploadDate, SourceRowHash, SourceGetStudents, SourceStudentsBasic
        )
        SELECT
            src.CompassPersonId, src.Username, src.FirstName, src.LastName,
            src.PreferredFirstName, src.PreferredLastName, src.MiddleName, src.Title,
            src.Gender, src.DateOfBirth, src.BirthCountry, src.ResidencyStatus,
            src.Nationality, src.EmailAddress, src.SchoolEmail, src.MobileNumber,
            src.HomePhoneNumber, src.HomeTown, src.StudentCode, src.YearLevel, src.CampusYearlevel,
            src.OrganisationName, src.HomeCampus, src.BoarderType, src.StudentType,
            src.UserStatus, src.PublishPhotoToInternal, src.PublishPhotoToMedia,
            src.PhotoUploadDate, src.SourceRowHash, src.SourceGetStudents, src.SourceStudentsBasic
        FROM #StudentSource AS src
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM gold.DimStudentCore AS tgt WITH (UPDLOCK, HOLDLOCK)
            WHERE tgt.CompassPersonId = src.CompassPersonId
        );

        COMMIT TRANSACTION;

        SELECT
            (SELECT COUNT_BIG(*) FROM #StudentSource) AS SourceCurrentRows,
            (SELECT COUNT_BIG(*) FROM gold.DimStudentCore) AS GoldTotalRows,
            (SELECT COUNT_BIG(*)
             FROM #StudentSource AS src
             INNER JOIN gold.DimStudentCore AS tgt
                 ON tgt.CompassPersonId = src.CompassPersonId) AS SourceRowsMatchedInGold;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

CREATE OR ALTER VIEW wellbeing.vwStudentDirectory
AS
    SELECT
        s.StudentKey,
        s.CompassPersonId,
        s.StudentCode,
        s.Username,
        COALESCE(NULLIF(s.PreferredFirstName, N''), s.FirstName) AS StudentFirstName,
        COALESCE(NULLIF(s.PreferredLastName, N''), s.LastName) AS StudentLastName,
        CONCAT
        (
            COALESCE(NULLIF(s.PreferredFirstName, N''), s.FirstName),
            CASE
                WHEN COALESCE(NULLIF(s.PreferredFirstName, N''), s.FirstName) IS NULL
                  OR COALESCE(NULLIF(s.PreferredLastName, N''), s.LastName) IS NULL
                    THEN N''
                ELSE N' '
            END,
            COALESCE(NULLIF(s.PreferredLastName, N''), s.LastName)
        ) AS StudentName,
        s.YearLevel,
        s.CampusYearlevel,
        s.EmailAddress,
        s.SchoolEmail,
        c.CampusKey,
        c.CampusCode,
        c.CampusName,
        c.CompassCampusId
    FROM gold.dimStudent AS s
    LEFT JOIN gold.dimCampus AS c
        ON c.CompassCampusId = s.HomeCampus
       AND c.IsCurrent = 1;
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @Changed TABLE
    (
        IncidentId nvarchar(50) NOT NULL,
        StudentKey nvarchar(50) NOT NULL,
        PreviousYearLevel nvarchar(100) NULL,
        PreviousResolutionStatus nvarchar(80) NULL,
        NewYearLevel nvarchar(100) NOT NULL,
        NewResolutionStatus nvarchar(80) NOT NULL
    );

    ;WITH HistoricalCandidates AS
    (
        SELECT
            l.IncidentId,
            l.StudentKey,
            TRY_CONVERT
            (
                int,
                RIGHT
                (
                    LTRIM(RTRIM(b.year_level)),
                    PATINDEX
                    (
                        N'%[^0-9]%',
                        REVERSE(LTRIM(RTRIM(b.year_level))) + N'X'
                    ) - 1
                )
            ) AS StandardYearLevel,
            COUNT_BIG(*) OVER (PARTITION BY l.IncidentId, l.StudentKey) AS SourceRows
        FROM wellbeing.IncidentStudent AS l
        INNER JOIN wellbeing.factBehaviourIncident AS i
            ON i.IncidentId = l.IncidentId
        INNER JOIN gold.dimStudent AS d
            ON d.StudentKey = l.StudentKey
        INNER JOIN silver.StudentsBasic AS b
            ON b.compass_person_id = d.CompassPersonId
           AND b.valid_from_utc < DATEADD(day, 1, CONVERT(date, i.IncidentDate))
           AND (b.valid_to_utc IS NULL OR b.valid_to_utc >= CONVERT(date, i.IncidentDate))
        WHERE l.StudentYearLevelAtIncident IS NULL
           OR l.YearLevelResolutionStatus <> N'Verified'
    )
    UPDATE l
    SET
        l.StudentYearLevelAtIncident = CONVERT(nvarchar(50), c.StandardYearLevel),
        l.YearLevelResolutionStatus = N'VERIFIED'
    OUTPUT
        CONVERT(nvarchar(50), inserted.IncidentId),
        CONVERT(nvarchar(50), inserted.StudentKey),
        deleted.StudentYearLevelAtIncident,
        deleted.YearLevelResolutionStatus,
        inserted.StudentYearLevelAtIncident,
        inserted.YearLevelResolutionStatus
    INTO @Changed
    FROM wellbeing.IncidentStudent AS l
    INNER JOIN HistoricalCandidates AS c
        ON c.IncidentId = l.IncidentId
       AND c.StudentKey = l.StudentKey
    WHERE c.SourceRows = 1
      AND c.StandardYearLevel IS NOT NULL;

    INSERT INTO wellbeing.AuditEvent
    (
        EventDate,
        Actor,
        Action,
        EntityName,
        EntityId,
        BeforeJson,
        AfterJson
    )
    SELECT
        SYSUTCDATETIME(),
        N'Historical year-level backfill',
        N'HISTORICAL_YEAR_LEVEL_BACKFILL',
        N'IncidentStudent',
        CONCAT(IncidentId, N':', StudentKey),
        (SELECT PreviousYearLevel AS StudentYearLevelAtIncident, PreviousResolutionStatus AS YearLevelResolutionStatus
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT NewYearLevel AS StudentYearLevelAtIncident, NewResolutionStatus AS YearLevelResolutionStatus
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM @Changed;

    COMMIT TRANSACTION;

    SELECT
        (SELECT COUNT(*) FROM @Changed) AS BackfilledIncidentSnapshots,
        (SELECT COUNT(*) FROM @Changed) AS AuditEventsWritten;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @Normalized TABLE
    (
        IncidentId int NOT NULL,
        StudentKey int NOT NULL,
        PreviousYearLevel nvarchar(50) NULL,
        NewYearLevel nvarchar(50) NOT NULL
    );

    ;WITH HistoricalCandidates AS
    (
        SELECT
            l.IncidentId,
            l.StudentKey,
            TRY_CONVERT
            (
                int,
                RIGHT
                (
                    LTRIM(RTRIM(b.year_level)),
                    PATINDEX
                    (
                        N'%[^0-9]%',
                        REVERSE(LTRIM(RTRIM(b.year_level))) + N'X'
                    ) - 1
                )
            ) AS StandardYearLevel,
            COUNT_BIG(*) OVER (PARTITION BY l.IncidentId, l.StudentKey) AS SourceRows
        FROM wellbeing.IncidentStudent AS l
        INNER JOIN wellbeing.factBehaviourIncident AS i
            ON i.IncidentId = l.IncidentId
        INNER JOIN gold.dimStudent AS d
            ON d.StudentKey = l.StudentKey
        INNER JOIN silver.StudentsBasic AS b
            ON b.compass_person_id = d.CompassPersonId
           AND b.valid_from_utc < DATEADD(day, 1, CONVERT(date, i.IncidentDate))
           AND (b.valid_to_utc IS NULL OR b.valid_to_utc >= CONVERT(date, i.IncidentDate))
        WHERE EXISTS
        (
            SELECT 1
            FROM wellbeing.AuditEvent AS audit
            WHERE audit.Action = N'HISTORICAL_YEAR_LEVEL_BACKFILL'
              AND audit.EntityName = N'IncidentStudent'
              AND audit.EntityId = CONCAT(l.IncidentId, N':', l.StudentKey)
        )
    )
    UPDATE l
    SET
        l.StudentYearLevelAtIncident = CONVERT(nvarchar(50), c.StandardYearLevel),
        l.YearLevelResolutionStatus = N'VERIFIED'
    OUTPUT
        inserted.IncidentId,
        inserted.StudentKey,
        deleted.StudentYearLevelAtIncident,
        inserted.StudentYearLevelAtIncident
    INTO @Normalized
    FROM wellbeing.IncidentStudent AS l
    INNER JOIN HistoricalCandidates AS c
        ON c.IncidentId = l.IncidentId
       AND c.StudentKey = l.StudentKey
    WHERE c.SourceRows = 1
      AND c.StandardYearLevel IS NOT NULL
      AND
      (
          TRY_CONVERT(int, l.StudentYearLevelAtIncident) IS NULL
          OR TRY_CONVERT(int, l.StudentYearLevelAtIncident) <> c.StandardYearLevel
      );

    INSERT INTO wellbeing.AuditEvent
    (
        EventDate,
        Actor,
        Action,
        EntityName,
        EntityId,
        BeforeJson,
        AfterJson
    )
    SELECT
        SYSUTCDATETIME(),
        N'Historical year-level normalization',
        N'NORMALIZE_HISTORICAL_YEAR_LEVEL_BACKFILL',
        N'IncidentStudent',
        CONCAT(IncidentId, N':', StudentKey),
        (SELECT PreviousYearLevel AS StudentYearLevelAtIncident
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
        (SELECT NewYearLevel AS StudentYearLevelAtIncident,
                N'VERIFIED' AS YearLevelResolutionStatus
         FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
    FROM @Normalized;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

SELECT
    StudentKey,
    CompassPersonId,
    YearLevel,
    CampusYearlevel,
    FirstName,
    LastName
FROM gold.dimStudent
WHERE StudentKey = 1155;
GO

SELECT
    YearLevel,
    CampusYearlevel,
    TRY_CONVERT(int, YearLevel) AS X,
    TRY_CONVERT(int, NULLIF(
        RIGHT(
            LTRIM(RTRIM(CampusYearlevel)),
            PATINDEX(
                N'%[^0-9]%',
                REVERSE(LTRIM(RTRIM(CampusYearlevel))) + N'X'
            ) - 1
        ),
        N''
    )) AS ParsedCampusYearLevel
FROM gold.dimStudent;
GO

SELECT
    i.IncidentNumber,
    i.IncidentDate,
    l.StudentKey,
    l.StudentYearLevelAtIncident,
    l.YearLevelResolutionStatus,
    l.StudentYearLevelIdAtIncident,
    l.StudentClassAtIncident
FROM wellbeing.factBehaviourIncident AS i
INNER JOIN wellbeing.IncidentStudent AS l
    ON l.IncidentId = i.IncidentId
WHERE i.IncidentNumber = N'INC-0009-190432';
GO
