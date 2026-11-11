USE SchoolDW;
GO

SET NOCOUNT ON;

DECLARE @Expected TABLE (EntityName NVARCHAR(100), ExpectedCount INT);
INSERT INTO @Expected (EntityName, ExpectedCount)
VALUES
    (N'Locations', 6),
    (N'Classifications', 26),
    (N'Incident types', 119),
    (N'Type/classification mappings', 275),
    (N'Consequences', 39),
    (N'Type/consequence mappings', 1000),
    (N'Allowed days', 13),
    (N'Allowed year levels', 6),
    (N'Communication templates', 28);

DECLARE @Actual TABLE (EntityName NVARCHAR(100), ActualCount INT);
INSERT INTO @Actual (EntityName, ActualCount)
VALUES
    (N'Locations', (SELECT COUNT(*) FROM wellbeing.tblSchoolLocations WHERE LegacyIncidentLocationId IS NOT NULL)),
    (N'Classifications', (SELECT COUNT(*) FROM wellbeing.tblIncidentClassifications WHERE LegacyGeneralClassificationId IS NOT NULL)),
    (N'Incident types', (SELECT COUNT(*) FROM wellbeing.tblIncidentTypes WHERE LegacyIncidentTypeId IS NOT NULL)),
    (N'Type/classification mappings', (SELECT COUNT(*) FROM wellbeing.IncidentTypeClassification)),
    (N'Consequences', (SELECT COUNT(*) FROM wellbeing.tblConsequences WHERE LegacyConsequenceId IS NOT NULL)),
    (N'Type/consequence mappings', (SELECT COUNT(*) FROM wellbeing.IncidentTypeConsequence)),
    (N'Allowed days', (SELECT COUNT(*) FROM wellbeing.ConsequenceAllowedDay)),
    (N'Allowed year levels', (SELECT COUNT(*) FROM wellbeing.ConsequenceAllowedYearLevel)),
    (N'Communication templates', (SELECT COUNT(*) FROM wellbeing.LegacyConsequenceCommunicationTemplate));

IF EXISTS (
    SELECT 1
    FROM @Expected AS expected
    LEFT JOIN @Actual AS actual ON actual.EntityName = expected.EntityName
    WHERE actual.ActualCount IS NULL OR actual.ActualCount <> expected.ExpectedCount
)
BEGIN
    SELECT expected.EntityName, expected.ExpectedCount, actual.ActualCount
    FROM @Expected AS expected
    LEFT JOIN @Actual AS actual ON actual.EntityName = expected.EntityName
    WHERE actual.ActualCount IS NULL OR actual.ActualCount <> expected.ExpectedCount;
    THROW 51000, 'Legacy reference migration count reconciliation failed.', 1;
END;

IF NOT EXISTS (
    SELECT 1
    FROM wellbeing.LegacyReferenceMigrationLog
    WHERE Outcome = N'COMPLETED'
      AND ImportedLocations = 6
      AND ImportedClassifications = 26
      AND ImportedIncidentTypes = 119
      AND ImportedTypeClassifications = 275
      AND ImportedConsequences = 39
      AND ImportedTypeConsequences = 1000
      AND ImportedAllowedDays = 13
      AND ImportedAllowedYearLevels = 6
      AND ImportedCommunicationTemplates = 28
)
    THROW 51001, 'No completed migration run matches the verified source counts.', 1;

IF EXISTS (
    SELECT LegacyIncidentLocationId
    FROM wellbeing.tblSchoolLocations
    WHERE LegacyIncidentLocationId IS NOT NULL
    GROUP BY LegacyIncidentLocationId
    HAVING COUNT(*) > 1
)
    THROW 51002, 'Duplicate legacy location identifiers were found.', 1;

IF EXISTS (
    SELECT LegacyGeneralClassificationId
    FROM wellbeing.tblIncidentClassifications
    WHERE LegacyGeneralClassificationId IS NOT NULL
    GROUP BY LegacyGeneralClassificationId
    HAVING COUNT(*) > 1
)
    THROW 51003, 'Duplicate legacy classification identifiers were found.', 1;

IF EXISTS (
    SELECT LegacyIncidentTypeId
    FROM wellbeing.tblIncidentTypes
    WHERE LegacyIncidentTypeId IS NOT NULL
    GROUP BY LegacyIncidentTypeId
    HAVING COUNT(*) > 1
)
    THROW 51004, 'Duplicate legacy incident type identifiers were found.', 1;

IF EXISTS (
    SELECT LegacyConsequenceId
    FROM wellbeing.tblConsequences
    WHERE LegacyConsequenceId IS NOT NULL
    GROUP BY LegacyConsequenceId
    HAVING COUNT(*) > 1
)
    THROW 51005, 'Duplicate legacy consequence identifiers were found.', 1;

IF EXISTS (
    SELECT 1
    FROM sys.foreign_keys
    WHERE parent_object_id IN (
        OBJECT_ID(N'wellbeing.IncidentClassificationLocation'),
        OBJECT_ID(N'wellbeing.IncidentTypeClassification'),
        OBJECT_ID(N'wellbeing.IncidentTypeConsequence'),
        OBJECT_ID(N'wellbeing.ConsequenceAllowedDay'),
        OBJECT_ID(N'wellbeing.ConsequenceAllowedYearLevel')
    )
      AND (is_disabled = 1 OR is_not_trusted = 1)
)
    THROW 51006, 'A migration foreign key is disabled or untrusted.', 1;

SELECT expected.EntityName, expected.ExpectedCount, actual.ActualCount
FROM @Expected AS expected
INNER JOIN @Actual AS actual ON actual.EntityName = expected.EntityName;

PRINT 'Legacy reference migration reconciliation passed.';
