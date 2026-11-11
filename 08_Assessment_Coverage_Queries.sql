USE SchoolDW;
GO

/*
  Student resolution for assessment facts.
  StudentKey is NULL on most assessment rows today, so rows are linked to
  gold.dimStudent by StudentKey first, then by source ID = StudentCode or Username.
  Only links that resolve to exactly one student are kept.
*/
CREATE OR ALTER VIEW gold.vwAssessmentStudent
AS
WITH Keys AS
(
    SELECT N'PAT' AS Assessment, f.SilverBusinessKey, f.StudentKey, f.AssessmentDate,
           f.StudentSourceId AS Code1, f.UniqueId AS Code2, f.Username AS Code3, f.CompassUsername AS Code4
    FROM gold.factPAT AS f
    UNION ALL
    SELECT N'EA', f.SilverBusinessKey, f.StudentKey, f.AssessmentDate,
           f.StudentSourceId, f.ExternalStudentId, NULL, f.CompassUsername
    FROM gold.factEssentialAssessment AS f
),
Candidates AS
(
    SELECT k.Assessment, k.SilverBusinessKey, k.AssessmentDate, s.StudentKey
    FROM Keys AS k
    INNER JOIN gold.dimStudent AS s
        ON s.StudentKey = k.StudentKey
        OR s.StudentCode IN (k.Code1, k.Code2)
        OR s.Username IN (k.Code1, k.Code2, k.Code3, k.Code4)
    GROUP BY k.Assessment, k.SilverBusinessKey, k.AssessmentDate, s.StudentKey
)
SELECT Assessment, SilverBusinessKey, AssessmentDate, MIN(StudentKey) AS StudentKey
FROM Candidates
GROUP BY Assessment, SilverBusinessKey, AssessmentDate
HAVING COUNT(*) = 1;
GO

/* 1. Students with both PAT and EA results, with their marks. */
WITH PatStudent AS
(
    SELECT a.StudentKey,
           COUNT(*) AS PatResults,
           MAX(a.AssessmentDate) AS LastPatDate,
           MAX(CASE WHEN p.TestType = N'PATR' THEN p.ScaleScore END) AS PatReadScaleScore,
           MAX(CASE WHEN p.TestType = N'PATM' THEN p.ScaleScore END) AS PatMathScaleScore
    FROM gold.vwAssessmentStudent AS a
    INNER JOIN gold.factPAT AS p ON p.SilverBusinessKey = a.SilverBusinessKey
    WHERE a.Assessment = N'PAT'
    GROUP BY a.StudentKey
),
EaStudent AS
(
    SELECT a.StudentKey,
           COUNT(*) AS EaFocusAreaResults,
           MAX(a.AssessmentDate) AS LastEaDate,
           CONVERT(decimal(6,2), AVG(e.AssessmentPercentage)) AS EaAvgPercentage
    FROM gold.vwAssessmentStudent AS a
    INNER JOIN gold.factEssentialAssessment AS e ON e.SilverBusinessKey = a.SilverBusinessKey
    WHERE a.Assessment = N'EA'
    GROUP BY a.StudentKey
)
SELECT s.StudentKey, s.CompassPersonId, s.StudentCode, s.Username, s.FirstName, s.LastName, s.YearLevel,
       p.PatResults, p.PatReadScaleScore, p.PatMathScaleScore, p.LastPatDate,
       e.EaFocusAreaResults, e.EaAvgPercentage, e.LastEaDate
FROM PatStudent AS p
INNER JOIN EaStudent AS e ON e.StudentKey = p.StudentKey
INNER JOIN gold.dimStudent AS s ON s.StudentKey = p.StudentKey
ORDER BY s.LastName, s.FirstName;
GO

/* 2. Campus with the most students who completed BOTH PAT and EA. */
WITH Both_ AS
(
    SELECT a.StudentKey
    FROM gold.vwAssessmentStudent AS a
    GROUP BY a.StudentKey
    HAVING COUNT(DISTINCT a.Assessment) = 2
)
SELECT TOP (50)
       COALESCE(c.CampusName, CONVERT(nvarchar(50), s.HomeCampus)) AS Campus,
       COUNT(*) AS StudentsWithPatAndEa
FROM Both_ AS b
INNER JOIN gold.dimStudent AS s ON s.StudentKey = b.StudentKey
LEFT JOIN gold.vwCampus AS c ON c.CampusGuid = s.HomeCampus
GROUP BY COALESCE(c.CampusName, CONVERT(nvarchar(50), s.HomeCampus))
ORDER BY StudentsWithPatAndEa DESC;
GO

/* 3. Classes (current roster) ranked by students with PAT and EA, plus completion %. */
WITH Both_ AS
(
    SELECT a.StudentKey
    FROM gold.vwAssessmentStudent AS a
    GROUP BY a.StudentKey
    HAVING COUNT(DISTINCT a.Assessment) = 2
),
Anyone AS
(
    SELECT DISTINCT StudentKey FROM gold.vwAssessmentStudent
)
SELECT TOP (50)
       m.ClassCode, m.SubjectName,
       COUNT(DISTINCT m.StudentKey) AS StudentsInClass,
       COUNT(DISTINCT CASE WHEN a.StudentKey IS NOT NULL THEN m.StudentKey END) AS WithAnyAssessment,
       COUNT(DISTINCT b.StudentKey) AS WithPatAndEa,
       CONVERT(decimal(5,1), 100.0 * COUNT(DISTINCT b.StudentKey) / NULLIF(COUNT(DISTINCT m.StudentKey), 0)) AS PatAndEaPct
FROM gold.factStudentClassMembership AS m
LEFT JOIN Anyone AS a ON a.StudentKey = m.StudentKey
LEFT JOIN Both_ AS b ON b.StudentKey = m.StudentKey
WHERE m.IsCurrent = 1
GROUP BY m.ClassCode, m.SubjectName
ORDER BY WithPatAndEa DESC, StudentsInClass DESC;
GO

/* 4. Teachers ranked by students (across their current classes) with PAT and EA. */
WITH Both_ AS
(
    SELECT a.StudentKey
    FROM gold.vwAssessmentStudent AS a
    GROUP BY a.StudentKey
    HAVING COUNT(DISTINCT a.Assessment) = 2
)
SELECT TOP (50)
       st.CompassPersonId, st.FirstName, st.LastName,
       COUNT(DISTINCT t.ClassKey) AS Classes,
       COUNT(DISTINCT m.StudentKey) AS StudentsTaught,
       COUNT(DISTINCT b.StudentKey) AS StudentsWithPatAndEa
FROM gold.factTeacherClass AS t
INNER JOIN gold.dimStaff AS st ON st.StaffKey = t.StaffKey
INNER JOIN gold.factStudentClassMembership AS m ON m.ClassKey = t.ClassKey AND m.IsCurrent = 1
LEFT JOIN Both_ AS b ON b.StudentKey = m.StudentKey
WHERE t.IsCurrent = 1
GROUP BY st.CompassPersonId, st.FirstName, st.LastName
ORDER BY StudentsWithPatAndEa DESC, StudentsTaught DESC;
GO
