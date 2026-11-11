USE SchoolDW;
GO

-- Student -> class membership (current allocations come from silver.StudentClasses).
CREATE OR ALTER VIEW gold.factStudentClassMembership
AS
SELECT
    s.StudentKey,
    c.ClassKey,
    sc.CompassPersonId,
    c.CompassClassId,
    c.ClassCode,
    MAX(sc.SubjectName) AS SubjectName,
    CAST(MAX(CASE WHEN sc.IsActive = 1 THEN 1 ELSE 0 END) AS bit) AS IsCurrent
FROM silver.StudentClasses AS sc
INNER JOIN gold.dimStudent AS s
    ON s.CompassPersonId = sc.CompassPersonId
INNER JOIN gold.dimClass AS c
    ON c.CompassClassId = sc.ClassSourcedId
   AND c.IsCurrent = 1
GROUP BY s.StudentKey, c.ClassKey, sc.CompassPersonId, c.CompassClassId, c.ClassCode;
GO

-- Teacher -> class allocation (from silver.TeacherClasses).
CREATE OR ALTER VIEW gold.factTeacherClass
AS
SELECT
    st.StaffKey,
    c.ClassKey,
    tc.CompassPersonId,
    c.CompassClassId,
    c.ClassCode,
    MAX(tc.SubjectName) AS SubjectName,
    MAX(tc.RoleDescription) AS RoleDescription,
    CAST(MAX(CASE WHEN tc.IsActive = 1 THEN 1 ELSE 0 END) AS bit) AS IsCurrent
FROM silver.TeacherClasses AS tc
INNER JOIN gold.dimStaff AS st
    ON st.CompassPersonId = tc.CompassPersonId
   AND st.IsCurrent = 1
INNER JOIN gold.dimClass AS c
    ON c.CompassClassId = tc.ClassSourcedId
   AND c.IsCurrent = 1
GROUP BY st.StaffKey, c.ClassKey, tc.CompassPersonId, c.CompassClassId, c.ClassCode;
GO

-- Campus with its Compass GUID (students, staff and attendance reference campuses by GUID).
CREATE OR ALTER VIEW gold.vwCampus
AS
SELECT
    c.CampusKey,
    sc.campus_id AS CampusGuid,
    c.CampusCode,
    c.CampusName
FROM gold.dimCampus AS c
INNER JOIN silver.Campuses AS sc
    ON sc.name = c.CampusName
   AND sc.is_current = 1
WHERE c.IsCurrent = 1;
GO

-- Staff with role and home campus.
CREATE OR ALTER VIEW gold.vwStaffDirectory
AS
SELECT
    st.StaffKey,
    st.CompassPersonId,
    st.Username,
    st.FirstName,
    st.LastName,
    b.RoleInSchool,
    b.HomeCampus
FROM gold.dimStaff AS st
OUTER APPLY (
    SELECT TOP (1) RoleInSchool, HomeCampus
    FROM silver.CompassStaffBasic AS x
    WHERE x.CompassPersonId = st.CompassPersonId
      AND x.IsCurrent = 1
    ORDER BY x.ValidFromUTC DESC
) AS b
WHERE st.IsCurrent = 1;
GO
