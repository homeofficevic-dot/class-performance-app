-- Full student profile; this can include personal information.
SELECT  YearLevel,CampusYearlevel
FROM gold.dimStudent
WHERE StudentKey = 1155;

-- Incident and the student's saved snapshot.
SELECT
    i.IncidentId,
    i.IncidentNumber,
    i.IncidentDate,
    i.IncidentSummary,
    s.StudentKey,
    s.StudentCode,
    s.YearLevel AS StandardYearLevel,
    s.CampusYearlevel,
    link.StudentYearLevelAtIncident,
    link.StudentYearLevelIdAtIncident,
    link.StudentClassAtIncident,
    link.YearLevelResolutionStatus
FROM wellbeing.factBehaviourIncident AS i
JOIN wellbeing.IncidentStudent AS link
    ON link.IncidentId = i.IncidentId
JOIN gold.dimStudent AS s
    ON s.StudentKey = link.StudentKey
WHERE i.IncidentNumber = N'INC-0009-190432'
  AND s.StudentKey = 1155;

-- Allowed weekday rules for consequence 65 (0 = Sunday, 5 = Friday).
SELECT
    c.ConsequenceId,
    c.ConsequenceName,
    d.LegacyYearLevel,
    d.LegacyDay,
    d.IsAllowed,
    d.IsCycleDay
FROM wellbeing.tblConsequences AS c
LEFT JOIN wellbeing.ConsequenceAllowedDay AS d
    ON d.ConsequenceId = c.ConsequenceId
WHERE c.ConsequenceId = 65;

-- Confirm whether an assignment was saved.
SELECT a.*
FROM wellbeing.factConsequenceAssignment AS a
WHERE a.IncidentId = 22
  AND a.StudentKey = 1155;