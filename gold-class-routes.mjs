import express from 'express';
import sql from 'mssql/msnodesqlv8.js';

const router = express.Router();

function fail(response, label, error) {
  console.error(`${label} failed:`, error);
  response.status(503).json({ error: `Unable to load ${label} from Gold.` });
}

function validId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 100;
}

const displayName = (first, last) => [first, last].filter(Boolean).join(' ');

// Staff who teach at least one current class.
router.get('/class-performance/staff', async (request, response) => {
  try {
    const pool = await request.app.locals.getDatabasePool();
    const result = await pool.request()
      .input('campusId', sql.UniqueIdentifier, request.campusAccess.campusId)
      .input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0)
      .query(`
      SELECT
        st.StaffKey,
        st.CompassPersonId,
        st.FirstName,
        st.LastName,
        st.Username,
        st.RoleInSchool,
        st.HomeCampus,
        COUNT(DISTINCT t.ClassKey) AS ClassCount
      FROM gold.vwStaffDirectory AS st
      INNER JOIN gold.factTeacherClass AS t
        ON t.StaffKey = st.StaffKey
       AND t.IsCurrent = 1
      INNER JOIN gold.factStudentClassMembership AS m
        ON m.ClassKey = t.ClassKey
       AND m.IsCurrent = 1
      INNER JOIN gold.dimStudent AS s
        ON s.StudentKey = m.StudentKey
      INNER JOIN gold.dimCampus AS c
        ON c.CompassCampusId = s.HomeCampus
       AND c.IsCurrent = 1
      WHERE @allCampusAccess = 1 OR s.HomeCampus = @campusId
      GROUP BY st.StaffKey, st.CompassPersonId, st.FirstName, st.LastName, st.Username,
               st.RoleInSchool, st.HomeCampus
      ORDER BY st.LastName, st.FirstName;
    `);

    response.json(result.recordset.map((row) => ({
      staffKey: row.StaffKey,
      compassPersonId: row.CompassPersonId,
      displayName: displayName(row.FirstName, row.LastName) || row.Username || row.CompassPersonId,
      role: row.RoleInSchool || 'Teacher',
      username: row.Username ?? undefined,
      roleInSchool: row.RoleInSchool ?? undefined,
      homeCampus: row.HomeCampus ?? undefined,
      classCount: Number(row.ClassCount)
    })));
  } catch (error) {
    fail(response, 'staff', error);
  }
});

router.get('/staff/:compassPersonId/classes', async (request, response) => {
  const { compassPersonId } = request.params;
  if (!validId(compassPersonId)) {
    return response.status(400).json({ error: 'Invalid Compass staff ID.' });
  }

  try {
    const pool = await request.app.locals.getDatabasePool();
    const result = await pool.request()
      .input('staffId', sql.NVarChar(100), compassPersonId)
      .input('campusId', sql.UniqueIdentifier, request.campusAccess.campusId)
      .input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0)
      .query(`
        SELECT
          t.CompassClassId,
          t.ClassCode,
          t.SubjectName,
          t.RoleDescription,
          t.IsCurrent,
          (
            SELECT COUNT(*)
            FROM gold.factStudentClassMembership AS m
            INNER JOIN gold.dimStudent AS s ON s.StudentKey = m.StudentKey
            WHERE m.ClassKey = t.ClassKey
              AND m.IsCurrent = 1
              AND (@allCampusAccess = 1 OR s.HomeCampus = @campusId)
          ) AS StudentCount
        FROM gold.factTeacherClass AS t
        WHERE t.CompassPersonId = @staffId
          AND t.IsCurrent = 1
          AND
          (
            @allCampusAccess = 1
            OR EXISTS
            (
              SELECT 1
              FROM gold.factStudentClassMembership AS m
              INNER JOIN gold.dimStudent AS s ON s.StudentKey = m.StudentKey
              WHERE m.ClassKey = t.ClassKey
                AND m.IsCurrent = 1
                AND s.HomeCampus = @campusId
            )
          )
        ORDER BY t.ClassCode;
      `);

    response.json(result.recordset.map((row) => ({
      classSourcedId: row.CompassClassId,
      classCode: row.ClassCode,
      subjectName: row.SubjectName ?? '',
      roleDescription: row.RoleDescription ?? '',
      studentCount: Number(row.StudentCount),
      isActive: Boolean(row.IsCurrent)
    })));
  } catch (error) {
    fail(response, 'teacher classes', error);
  }
});

router.get('/classes/:classSourcedId/students', async (request, response) => {
  const { classSourcedId } = request.params;
  if (!validId(classSourcedId)) {
    return response.status(400).json({ error: 'Invalid class identifier.' });
  }

  try {
    const pool = await request.app.locals.getDatabasePool();
    const result = await pool.request()
      .input('classId', sql.NVarChar(100), classSourcedId)
      .input('campusId', sql.UniqueIdentifier, request.campusAccess.campusId)
      .input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0)
      .query(`
        SELECT
          s.CompassPersonId,
          s.Username,
          s.StudentCode,
          COALESCE(NULLIF(s.PreferredFirstName, ''), s.FirstName) AS GivenName,
          COALESCE(NULLIF(s.PreferredLastName, ''), s.LastName) AS FamilyName,
          s.YearLevel,
          s.CampusYearlevel,
          s.HomeCampus,
          m.ClassCode
        FROM gold.factStudentClassMembership AS m
        INNER JOIN gold.dimStudent AS s
          ON s.StudentKey = m.StudentKey
        WHERE m.IsCurrent = 1
          AND (m.CompassClassId = @classId OR m.ClassCode = @classId)
          AND (@allCampusAccess = 1 OR s.HomeCampus = @campusId)
        ORDER BY FamilyName, GivenName;
      `);

    response.json(result.recordset.map((row) => ({
      compassPersonId: row.CompassPersonId,
      username: row.Username,
      studentCode: row.StudentCode,
      givenName: row.GivenName,
      familyName: row.FamilyName,
      yearLevel: row.YearLevel,
      campusYearLevel: row.CampusYearlevel,
      homeCampus: row.HomeCampus,
      classCode: row.ClassCode
    })));
  } catch (error) {
    fail(response, 'class students', error);
  }
});

router.get('/students/:compassPersonId/classes', async (request, response) => {
  const { compassPersonId } = request.params;
  if (!validId(compassPersonId)) {
    return response.status(400).json({ error: 'Invalid Compass student ID.' });
  }

  try {
    const pool = await request.app.locals.getDatabasePool();
    const classes = await pool.request()
      .input('studentId', sql.NVarChar(100), compassPersonId)
      .input('campusId', sql.UniqueIdentifier, request.campusAccess.campusId)
      .input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0)
      .query(`
        SELECT
          m.ClassKey,
          m.CompassClassId,
          m.ClassCode,
          m.SubjectName,
          (
            SELECT COUNT(*)
            FROM gold.factStudentClassMembership AS x
            INNER JOIN gold.dimStudent AS s ON s.StudentKey = x.StudentKey
            WHERE x.ClassKey = m.ClassKey
              AND x.IsCurrent = 1
              AND (@allCampusAccess = 1 OR s.HomeCampus = @campusId)
          ) AS StudentCount
        FROM gold.factStudentClassMembership AS m
        WHERE m.CompassPersonId = @studentId
          AND m.IsCurrent = 1
          AND EXISTS
          (
            SELECT 1
            FROM gold.dimStudent AS s
            WHERE s.CompassPersonId = m.CompassPersonId
              AND (@allCampusAccess = 1 OR s.HomeCampus = @campusId)
          )
        ORDER BY m.ClassCode;
      `);

    const teachers = await pool.request()
      .input('studentId', sql.NVarChar(100), compassPersonId)
      .input('campusId', sql.UniqueIdentifier, request.campusAccess.campusId)
      .input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0)
      .query(`
        SELECT
          t.ClassKey,
          st.CompassPersonId,
          st.FirstName,
          st.LastName,
          st.Username,
          t.RoleDescription
        FROM gold.factStudentClassMembership AS m
        INNER JOIN gold.factTeacherClass AS t
          ON t.ClassKey = m.ClassKey AND t.IsCurrent = 1
        INNER JOIN gold.dimStaff AS st
          ON st.StaffKey = t.StaffKey
        WHERE m.CompassPersonId = @studentId
          AND m.IsCurrent = 1
          AND EXISTS
          (
            SELECT 1
            FROM gold.dimStudent AS s
            WHERE s.CompassPersonId = m.CompassPersonId
              AND (@allCampusAccess = 1 OR s.HomeCampus = @campusId)
          )
        ORDER BY st.LastName, st.FirstName;
      `);

    const teachersByClass = new Map();
    for (const row of teachers.recordset) {
      const list = teachersByClass.get(row.ClassKey) ?? [];
      list.push({
        compassPersonId: row.CompassPersonId,
        displayName: displayName(row.FirstName, row.LastName) || row.Username,
        role: row.RoleDescription ?? 'Teacher',
        username: row.Username,
        photoUrl: row.Username
          ? `/api/compass/person-photos/${encodeURIComponent(row.Username)}`
          : undefined
      });
      teachersByClass.set(row.ClassKey, list);
    }

    response.json(classes.recordset.map((row) => ({
      classSourcedId: row.CompassClassId,
      classCode: row.ClassCode,
      subjectName: row.SubjectName ?? '',
      roleDescription: 'Student',
      studentCount: Number(row.StudentCount),
      teachers: teachersByClass.get(row.ClassKey) ?? []
    })));
  } catch (error) {
    fail(response, 'student classes', error);
  }
});

router.get('/students/by-student-code/:studentCode', async (request, response) => {
  const { studentCode } = request.params;
  if (!validId(studentCode)) {
    return response.status(400).json({ error: 'Student code is required.' });
  }

  try {
    const pool = await request.app.locals.getDatabasePool();
    const result = await pool.request()
      .input('code', sql.NVarChar(100), studentCode.trim())
      .input('campusId', sql.UniqueIdentifier, request.campusAccess.campusId)
      .input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0)
      .query(`
        SELECT TOP (1)
          StudentKey, CompassPersonId, Username, StudentCode, FirstName, LastName,
          PreferredFirstName, PreferredLastName, YearLevel, CampusYearlevel, HomeCampus
        FROM gold.dimStudent
        WHERE UPPER(LTRIM(RTRIM(StudentCode))) = UPPER(@code)
          AND (@allCampusAccess = 1 OR HomeCampus = @campusId)
        ORDER BY StudentKey;
      `);

    const student = result.recordset[0];
    if (!student) {
      return response.status(404).json({ error: 'Student not found in Gold layer.', studentCode });
    }

    response.json({
      studentKey: student.StudentKey,
      compassPersonId: student.CompassPersonId,
      username: student.Username,
      studentCode: student.StudentCode,
      firstName: student.FirstName,
      lastName: student.LastName,
      preferredFirstName: student.PreferredFirstName,
      preferredLastName: student.PreferredLastName,
      yearLevel: student.YearLevel,
      campusYearLevel: student.CampusYearlevel,
      homeCampus: student.HomeCampus
    });
  } catch (error) {
    fail(response, 'student', error);
  }
});

export default router;
