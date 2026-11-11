import 'dotenv/config';
import express from 'express';
import sql from 'mssql/msnodesqlv8.js';
import { resolve } from 'node:path';
import { buildAttendanceAnalytics, mergeAttendanceAnalytics } from './attendance-analytics.mjs';
import adminConfigRouter from './backend/routes/admin-config.routes.mjs';

const app = express();
const port = Number(process.env.COMPASS_PROXY_PORT || 4201);
const studentPhotosDirectory = resolve(
  process.env.COMPASS_PHOTOS_DIR?.trim() || 'C:\\Sanits\\CompassPhotos'
);
const sqlAuth = process.env.SQL_AUTH?.trim().toLowerCase() || 'windows';
if (sqlAuth !== 'windows' && sqlAuth !== 'sql') {
  throw new Error('SQL_AUTH must be either "windows" or "sql".');
}
if (sqlAuth === 'sql' && (!process.env.SQL_USER?.trim() || !process.env.SQL_PASSWORD)) {
  throw new Error('SQL_USER and SQL_PASSWORD are required when SQL_AUTH=sql.');
}
const databaseConfig = {
  server: process.env.SQL_SERVER?.trim() || 'localhost',
  database: process.env.SQL_DATABASE?.trim() || 'SchoolDW',
  driver: process.env.SQL_DRIVER?.trim() || 'ODBC Driver 17 for SQL Server',
  requestTimeout: 120000,
  ...(sqlAuth === 'sql' ? {
    user: process.env.SQL_USER.trim(),
    password: process.env.SQL_PASSWORD
  } : {}),
  options: {
    trustedConnection: sqlAuth === 'windows',
    trustServerCertificate: process.env.SQL_TRUST_SERVER_CERTIFICATE === 'true'
  }
};
let poolPromise;
const campusAttendanceCache = new Map();
const campusAnalyticsCache = new Map();
const campusAttendanceCacheTtlMs = 5 * 60 * 1000;

function getDatabasePool() {
  if (!poolPromise) {
    poolPromise = sql.connect(databaseConfig).catch((error) => {
      poolPromise = undefined;
      throw error;
    });
  }
  return poolPromise;
}

app.locals.getDatabasePool = getDatabasePool;
app.locals.sql = sql;

app.disable('x-powered-by');
app.use(express.json({ limit: '2mb' }));
app.use('/api/admin/config', adminConfigRouter);

app.get('/api/compass/health', async (_request, response) => {
  try {
    const pool = await getDatabasePool();
    await pool.request().query('SELECT 1 AS connected;');
    response.json({ configured: true, database: databaseConfig.database });
  } catch (error) {
    console.error('MSSQL health check failed:', error);
    response.status(503).json({ configured: false, error: 'MSSQL database is unavailable.' });
  }
});

app.get(['/api/compass/student-photos/:username', '/api/compass/person-photos/:username'], (request, response) => {
  const { username } = request.params;
  if (!/^[a-z0-9][a-z0-9._'-]{0,199}$/i.test(username)) {
    return response.status(400).json({ error: 'Invalid person username.' });
  }

  response.sendFile(`${username}.png`, {
    root: studentPhotosDirectory,
    dotfiles: 'deny'
  }, (error) => {
    if (!error) return;
    if (error.status === 404 || error.code === 'ENOENT') {
      return response.status(404).json({ error: 'Person photo not found.' });
    }

    console.error('Person photo could not be served:', error);
    if (!response.headersSent) {
      response.status(500).json({ error: 'Unable to serve person photo.' });
    }
  });
});

function normalizeKey(value) {
  return String(value).replace(/[^a-z0-9]/gi, '').toLowerCase();
}

function readString(record, aliases) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) return '';
  const values = new Map(Object.entries(record).map(([key, value]) => [normalizeKey(key), value]));
  for (const alias of aliases) {
    const value = values.get(normalizeKey(alias));
    if (typeof value === 'string' || typeof value === 'number') {
      const normalized = String(value).trim();
      if (normalized) return normalized;
    }
  }
  return '';
}

function parsePayloadRows(rows) {
  return rows.map((row) => {
    try {
      return { ...row, payload: JSON.parse(row.PayloadJson) };
    } catch (error) {
      console.error('Invalid JSON in Compass payload table:', error);
      throw new Error('A Compass payload in MSSQL is not valid JSON.');
    }
  });
}

app.get('/api/compass/class-performance/staff', async (_request, response) => {
  try {
    const pool = await getDatabasePool();
    const classCountsResult = await pool.request().query(`
      SELECT CompassPersonId, COUNT(DISTINCT ClassSourcedId) AS ClassCount
      FROM dbo.CompassTeacherClasses
      WHERE ClassSourcedId IS NOT NULL AND (IsActive = 1 OR IsActive IS NULL)
      GROUP BY CompassPersonId;
    `);
    const classCounts = new Map(
      classCountsResult.recordset.map((row) => [String(row.CompassPersonId), Number(row.ClassCount)])
    );

    const result = await pool.request().query(`
      SELECT d.StaffKey, b.CompassPersonId, b.PayloadJson
      FROM dbo.CompassStaffBasic AS b
      LEFT JOIN gold.dimStaff AS d
        ON CONVERT(NVARCHAR(200), d.CompassPersonId) = CONVERT(NVARCHAR(200), b.CompassPersonId)
      ORDER BY b.CompassPersonId;
    `);
    const staff = parsePayloadRows(result.recordset).map(({ StaffKey, CompassPersonId, payload }) => {
      const firstName = readString(payload, ['preferredFirstName', 'firstName', 'givenName']);
      const lastName = readString(payload, ['preferredLastName', 'lastName', 'familyName', 'surname']);
      const displayName = readString(payload, ['fullName', 'displayName', 'name'])
        || [firstName, lastName].filter(Boolean).join(' ')
        || CompassPersonId;
      const id = String(CompassPersonId);
      return {
        staffKey: StaffKey,
        compassPersonId: id,
        displayName,
        role: readString(payload, ['jobTitle', 'positionTitle', 'staffRole', 'role', 'importBaseRole']) || 'Compass staff',
        roleInSchool: readString(payload, ['roleInSchool']),
        homeCampus: readString(payload, ['homeCampus', 'campusId', 'campusName', 'campus']),
        classCount: classCounts.get(id) || 0
      };
    });
    // Sort staff who have allocated classes to the top, then alphabetically by name
    staff.sort((a, b) => {
      if ((b.classCount > 0) !== (a.classCount > 0)) {
        return (b.classCount > 0 ? 1 : 0) - (a.classCount > 0 ? 1 : 0);
      }
      return a.displayName.localeCompare(b.displayName);
    });
    response.json(staff);
  } catch (error) {
    console.error('MSSQL class-performance staff query failed:', error);
    response.status(503).json({ error: 'Unable to load Compass staff from MSSQL. Confirm dbo.CompassStaffBasic exists and is populated.' });
  }
});

app.get('/api/compass/staff/:compassPersonId/classes', async (request, response) => {
  try {
    const pool = await getDatabasePool();
    const result = await pool.request()
      .input('compassPersonId', sql.NVarChar(100), request.params.compassPersonId)
      .query(`
        SELECT
          tc.ClassSourcedId,
          tc.ClassCode,
          tc.SubjectName,
          tc.RoleDescription,
          tc.IsActive,
          COUNT(DISTINCT sc.CompassPersonId) AS StudentCount
        FROM dbo.CompassTeacherClasses AS tc
        LEFT JOIN dbo.CompassStudentClasses AS sc
          ON (sc.ClassSourcedId = tc.ClassSourcedId OR sc.ClassCode = tc.ClassCode)
          AND (sc.IsActive = 1 OR sc.IsActive IS NULL)
        WHERE tc.CompassPersonId = @compassPersonId
          AND tc.ClassSourcedId IS NOT NULL
          AND (tc.IsActive = 1 OR tc.IsActive IS NULL)
        GROUP BY tc.ClassSourcedId, tc.ClassCode, tc.SubjectName, tc.RoleDescription, tc.IsActive
        ORDER BY tc.ClassCode, tc.ClassSourcedId;
      `);
    response.json(result.recordset.map((row) => ({
      classSourcedId: String(row.ClassSourcedId),
      classCode: row.ClassCode == null ? '' : String(row.ClassCode),
      subjectName: row.SubjectName == null ? '' : String(row.SubjectName),
      roleDescription: row.RoleDescription == null ? '' : String(row.RoleDescription),
      studentCount: row.StudentCount == null ? 0 : Number(row.StudentCount),
      isActive: row.IsActive == null ? true : Boolean(row.IsActive)
    })));
  } catch (error) {
    console.error('MSSQL teacher-class query failed:', error);
    response.status(503).json({
      error: 'Unable to load teacher classes. Confirm dbo.CompassTeacherClasses has ClassSourcedId values; rerun the teacher-class sync if it does not.'
    });
  }
});

app.get('/api/compass/classes/:classSourcedId/students', async (request, response) => {
  try {
    const pool = await getDatabasePool();
    const result = await pool.request()
      .input('classSourcedId', sql.NVarChar(100), request.params.classSourcedId)
      .query(`
        SELECT
          csc.CompassPersonId, csc.SourcedId, csc.StudentCode, csc.ClassCode,
          csc.IsActive, csc.GivenName, csc.FamilyName, csc.Username, csc.Identifier,
          csc.ClassSourcedId, csc.ClassTitle,
          COALESCE(CAST(csc.YearLevel AS NVARCHAR(50)), sb.yearLevel) AS YearLevel,
          sb.homeCampus AS HomeCampus
        FROM dbo.CompassStudentClasses AS csc
        LEFT JOIN dbo.StudentsBasic AS sb
          ON sb.compassPersonId = csc.CompassPersonId OR sb.studentCode = csc.StudentCode
        WHERE (csc.ClassSourcedId = @classSourcedId OR csc.ClassCode = @classSourcedId)
          AND (csc.IsActive = 1 OR csc.IsActive IS NULL)
        ORDER BY csc.FamilyName, csc.GivenName, csc.StudentCode, csc.CompassPersonId;
      `);
    response.json(result.recordset.map((row) => ({
      compassPersonId: row.CompassPersonId == null ? '' : String(row.CompassPersonId),
      sourcedId: row.SourcedId == null ? '' : String(row.SourcedId),
      studentCode: row.StudentCode == null ? '' : String(row.StudentCode),
      classCode: row.ClassCode == null ? '' : String(row.ClassCode),
      givenName: row.GivenName == null ? '' : String(row.GivenName),
      familyName: row.FamilyName == null ? '' : String(row.FamilyName),
      username: row.Username == null ? '' : String(row.Username),
      identifier: row.Identifier == null ? '' : String(row.Identifier),
      classSourcedId: row.ClassSourcedId == null ? '' : String(row.ClassSourcedId),
      classTitle: row.ClassTitle == null ? '' : String(row.ClassTitle),
      yearLevel: row.YearLevel == null ? '' : String(row.YearLevel),
      homeCampus: row.HomeCampus == null ? '' : String(row.HomeCampus)
    })));
  } catch (error) {
    console.error('MSSQL class roster query failed:', error);
    response.status(503).json({
      error: 'Unable to load this class roster. Confirm dbo.CompassStudentClasses contains ClassSourcedId values from the class roster sync.'
    });
  }
});

function getClassIdentityValues(students) {
  return [...new Set(students.flatMap((student) => [
    student.compassPersonId,
    student.sourcedId,
    student.studentCode,
    student.identifier,
    student.username
  ]).map((value) => String(value ?? '').trim()).filter(Boolean))];
}

app.get('/api/compass/classes/:classSourcedId/attendance', async (request, response) => {
  try {
    const pool = await getDatabasePool();
    const result = await pool.request()
      .input('classSourcedId', sql.NVarChar(100), request.params.classSourcedId)
      .query(`
        SELECT attendance.CompassPersonId, attendance.PayloadJson
        FROM dbo.CompassAttendancePeriodLines AS attendance
        WHERE attendance.CompassPersonId IN (
          SELECT CompassPersonId
          FROM dbo.CompassStudentClasses
          WHERE (ClassSourcedId = @classSourcedId OR ClassCode = @classSourcedId)
            AND (IsActive = 1 OR IsActive IS NULL)
        );
      `);
    response.json(parsePayloadRows(result.recordset).map(({ payload }) => payload));
  } catch (error) {
    console.error('MSSQL class attendance query failed:', error);
    response.status(503).json({
      error: 'Unable to load attendance for this class. Confirm dbo.CompassAttendancePeriodLines is populated and contains student identifiers.'
    });
  }
});

app.get('/api/compass/classes/:classSourcedId/attendance-analytics', async (request, response) => {
  const campusId = typeof request.query.campusId === 'string' ? request.query.campusId.trim() : '';
  if (campusId.length > 100) {
    return response.status(400).json({ error: 'campusId must not exceed 100 characters.' });
  }
  const dateRange = readAttendanceDateRange(request, response);
  if (dateRange === undefined) return;

  try {
    const pool = await getDatabasePool();
    const studentsRequest = new sql.Request(pool, { requestTimeout: 120000 })
      .input('classSourcedId', sql.NVarChar(100), request.params.classSourcedId)
      .input('campusId', sql.NVarChar(100), campusId || null);
    const studentsResult = await studentsRequest.query(`
        SELECT
          classStudents.CompassPersonId,
          classStudents.StudentCode,
          classStudents.GivenName,
          classStudents.FamilyName
        FROM dbo.CompassStudentClasses AS classStudents
        WHERE (classStudents.ClassSourcedId = @classSourcedId OR classStudents.ClassCode = @classSourcedId)
          AND (classStudents.IsActive = 1 OR classStudents.IsActive IS NULL)
          AND (
            @campusId IS NULL
            OR EXISTS (
              SELECT 1
              FROM dbo.StudentsBasic AS campusStudents
              WHERE campusStudents.CompassPersonId = classStudents.CompassPersonId
                AND campusStudents.homeCampus = @campusId
            )
          );
      `);

    const students = [...new Map(
      studentsResult.recordset
        .filter((student) => student.CompassPersonId)
        .map((student) => [String(student.CompassPersonId), student])
    ).values()];
    const analyticsBatches = [];
    const batchSize = 500;

    for (let offset = 0; offset < students.length; offset += batchSize) {
      const batch = students.slice(offset, offset + batchSize);
      const attendanceRequest = new sql.Request(pool, { requestTimeout: 120000 });
      const parameters = batch.map((student, index) => {
        const parameterName = `person${index}`;
        attendanceRequest.input(parameterName, sql.NVarChar(100), String(student.CompassPersonId));
        return `@${parameterName}`;
      });
      if (dateRange) {
        attendanceRequest.input('attendanceStart', sql.DateTimeOffset, dateRange.startDate);
        attendanceRequest.input('attendanceEnd', sql.DateTimeOffset, dateRange.endDate);
      }
      const attendanceResult = await attendanceRequest.query(`
        SELECT CompassPersonId, PayloadJson
        FROM dbo.CompassAttendancePeriodLines
          WITH (INDEX(IX_CompassAttendancePeriodLines_CompassPersonId))
        WHERE CompassPersonId IN (${parameters.join(', ')})
        ${dateRange ? `
          AND COALESCE(
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.start'), 127),
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.finish'), 127),
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.updatedTimestamp'), 127)
          ) >= @attendanceStart
          AND COALESCE(
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.start'), 127),
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.finish'), 127),
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.updatedTimestamp'), 127)
          ) < @attendanceEnd
        ` : ''}
      `);
      analyticsBatches.push(buildAttendanceAnalytics(batch, attendanceResult.recordset));
    }

    response.json(mergeAttendanceAnalytics(analyticsBatches));
  } catch (error) {
    console.error('MSSQL class attendance analytics query failed:', error);
    response.status(503).json({ error: 'Unable to calculate attendance analytics for this class.' });
  }
});

app.get('/api/compass/classes/:classSourcedId/learning-needs', async (request, response) => {
  try {
    const pool = await getDatabasePool();
    const result = await pool.request()
      .input('classSourcedId', sql.NVarChar(100), request.params.classSourcedId)
      .query(`
        SELECT DISTINCT needs.CompassPersonId, needs.PayloadJson
        FROM dbo.CompassStudentClasses AS roster
        INNER JOIN dbo.CompassStudentLearningNeeds AS needs
          ON needs.CompassPersonId = roster.CompassPersonId
        WHERE roster.ClassSourcedId = @classSourcedId
          AND (roster.IsActive = 1 OR roster.IsActive IS NULL);
      `);
    response.json(parsePayloadRows(result.recordset).map(({ CompassPersonId, payload }) => ({
      compassPersonId: String(CompassPersonId),
      payload
    })));
  } catch (error) {
    console.error('MSSQL class learning-needs query failed:', error);
    response.status(503).json({
      error: 'Unable to load learning-needs details. Confirm dbo.CompassStudentLearningNeeds is populated.'
    });
  }
});

function getPage(request, response) {
  const limit = Number(request.query.limit ?? 100);
  const offset = Number(request.query.offset ?? 0);
  if (!Number.isInteger(limit) || limit < 1 || limit > 500) {
    response.status(400).json({ error: 'limit must be an integer between 1 and 500.' });
    return undefined;
  }
  if (!Number.isInteger(offset) || offset < 0) {
    response.status(400).json({ error: 'offset must be a non-negative integer.' });
    return undefined;
  }
  return { limit, offset };
}

function readAttendanceDateRange(request, response) {
  const startValue = typeof request.query.startDate === 'string' ? request.query.startDate : '';
  const endValue = typeof request.query.endDate === 'string' ? request.query.endDate : '';
  if (!startValue && !endValue) return null;

  const isUtcTimestamp = (value) =>
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$/i.test(value)
    && !Number.isNaN(Date.parse(value));
  if (!isUtcTimestamp(startValue) || !isUtcTimestamp(endValue) || Date.parse(startValue) >= Date.parse(endValue)) {
    response.status(400).json({
      error: 'startDate and endDate must be valid UTC timestamps, with startDate before endDate.'
    });
    return undefined;
  }

  return { startDate: new Date(startValue), endDate: new Date(endValue) };
}

// Restricts an assessment table to students whose home campus matches @campusId.
// Rows are linked by Compass person id, student code, username or name because many
// assessment rows are only loosely matched to Compass.
function campusAssessmentFilter(source) {
  const campusStudents = (expression) =>
    `(SELECT ${expression} COLLATE DATABASE_DEFAULT FROM dbo.StudentsBasic WHERE homeCampus = @campusId)`;
  const codeColumns = source === 'pat'
    ? ['UniqueId', 'StudentSourceId', 'ExternalStudentId', 'Username']
    : ['StudentSourceId', 'ExternalStudentId'];
  const nameColumns = source === 'pat'
    ? ['FamilyName, N\' \', GivenName', 'GivenName, N\' \', FamilyName']
    : ['StudentLastName, N\' \', StudentFirstName', 'StudentFirstName, N\' \', StudentLastName'];
  const usernameColumn = 'CompassUsername';
  return `
    AND (
      @campusId IS NULL
      OR CONVERT(nvarchar(200), CompassPersonId) COLLATE DATABASE_DEFAULT IN ${campusStudents('CONVERT(nvarchar(200), compassPersonId)')}
      OR ${usernameColumn} COLLATE DATABASE_DEFAULT IN ${campusStudents('username')}
      ${codeColumns.map((column) => `
      OR CONVERT(nvarchar(200), ${column}) COLLATE DATABASE_DEFAULT IN ${campusStudents('studentCode')}
      OR CONVERT(nvarchar(200), ${column}) COLLATE DATABASE_DEFAULT IN ${campusStudents('username')}`).join('')}
      ${nameColumns.map((columns) => `
      OR LTRIM(RTRIM(CONCAT(${columns}))) COLLATE DATABASE_DEFAULT IN ${campusStudents('LTRIM(RTRIM(CONCAT(lastName, N\' \', firstName)))')}
      OR LTRIM(RTRIM(CONCAT(${columns}))) COLLATE DATABASE_DEFAULT IN ${campusStudents('LTRIM(RTRIM(CONCAT(preferredLastName, N\' \', preferredFirstName)))')}`).join('')}
    )
  `;
}

function readCampusScope(request, response) {
  const rawCampusId = request.params.campusId ?? request.query.campusId;
  const campusId = typeof rawCampusId === 'string' ? rawCampusId.trim() : '';
  if (campusId.length > 100) {
    response.status(400).json({ error: 'campusId must not exceed 100 characters.' });
    return undefined;
  }
  return campusId;
}

async function handlePatResults(request, response) {
  const campusId = readCampusScope(request, response);
  if (campusId === undefined) return;
  const limit = Number(request.query.limit ?? 1000);
  const offset = Number(request.query.offset ?? 0);
  if (!Number.isInteger(limit) || limit < 1 || limit > 1000) {
    return response.status(400).json({ error: 'limit must be an integer between 1 and 1000.' });
  }
  if (!Number.isInteger(offset) || offset < 0) {
    return response.status(400).json({ error: 'offset must be a non-negative integer.' });
  }

  const search = typeof request.query.search === 'string' ? request.query.search.trim() : '';
  if (search.length > 100) {
    return response.status(400).json({ error: 'search must be 100 characters or fewer.' });
  }
  const studentCode = typeof request.query.studentCode === 'string'
    ? request.query.studentCode.trim()
    : '';
  if (studentCode.length > 200) {
    return response.status(400).json({ error: 'studentCode must be 200 characters or fewer.' });
  }
  let studentCodes = [];
  if (typeof request.query.studentCodes === 'string' && request.query.studentCodes.trim()) {
    try {
      const parsedStudentCodes = JSON.parse(request.query.studentCodes);
      if (!Array.isArray(parsedStudentCodes) || parsedStudentCodes.length > 500
        || parsedStudentCodes.some((value) => typeof value !== 'string' || value.trim().length > 200)) {
        return response.status(400).json({ error: 'studentCodes must be a JSON array of up to 500 strings, each 200 characters or fewer.' });
      }
      studentCodes = [...new Set(parsedStudentCodes.map((value) => value.trim()).filter(Boolean))];
    } catch {
      return response.status(400).json({ error: 'studentCodes must be a valid JSON array.' });
    }
  }
  let studentNames = [];
  if (typeof request.query.studentNames === 'string' && request.query.studentNames.trim()) {
    try {
      const parsedStudentNames = JSON.parse(request.query.studentNames);
      if (!Array.isArray(parsedStudentNames) || parsedStudentNames.length > 500
        || parsedStudentNames.some((value) => typeof value !== 'string' || value.trim().length > 200)) {
        return response.status(400).json({ error: 'studentNames must be a JSON array of up to 500 names, each 200 characters or fewer.' });
      }
      studentNames = [...new Set(parsedStudentNames.map((value) => value.trim()).filter(Boolean))];
    } catch {
      return response.status(400).json({ error: 'studentNames must be a valid JSON array.' });
    }
  }
  const classCode = typeof request.query.classCode === 'string'
    ? request.query.classCode.trim()
    : '';
  if (classCode.length > 200) {
    return response.status(400).json({ error: 'classCode must be 200 characters or fewer.' });
  }

  const requestedTestType = typeof request.query.testType === 'string'
    ? request.query.testType.trim().toUpperCase()
    : '';
  if (requestedTestType && !['PATM', 'PATR'].includes(requestedTestType)) {
    return response.status(400).json({ error: 'testType must be PATM or PATR.' });
  }

  try {
    const pool = await getDatabasePool();
    const filter = `
      WHERE (@testType IS NULL OR TestType = @testType)
        AND (
          (@studentCode IS NULL AND @studentCodesJson IS NULL AND @studentNamesJson IS NULL)
          OR CONVERT(nvarchar(200), UniqueId) = @studentCode
          OR CONVERT(nvarchar(200), StudentSourceId) = @studentCode
          OR CONVERT(nvarchar(200), ExternalStudentId) = @studentCode
          OR CONVERT(nvarchar(200), CompassPersonId) = @studentCode
          OR Username = @studentCode
          OR CompassUsername = @studentCode
          OR EXISTS (
            SELECT 1
            FROM OPENJSON(@studentCodesJson) AS studentCodeValue
            WHERE CONVERT(nvarchar(200), UniqueId) = studentCodeValue.[value]
              OR CONVERT(nvarchar(200), StudentSourceId) = studentCodeValue.[value]
              OR CONVERT(nvarchar(200), ExternalStudentId) = studentCodeValue.[value]
              OR CONVERT(nvarchar(200), CompassPersonId) = studentCodeValue.[value]
              OR Username = studentCodeValue.[value]
              OR CompassUsername = studentCodeValue.[value]
          )
          OR EXISTS (
            SELECT 1
            FROM OPENJSON(@studentNamesJson) AS studentNameValue
            WHERE LTRIM(RTRIM(StudentName)) = studentNameValue.[value]
              OR LTRIM(RTRIM(CONCAT(GivenName, N' ', FamilyName))) = studentNameValue.[value]
              OR LTRIM(RTRIM(CONCAT(FamilyName, N' ', GivenName))) = studentNameValue.[value]
          )
        )
        AND (
          @classCode IS NULL
          OR @studentCodesJson IS NOT NULL
          OR @studentNamesJson IS NOT NULL
          OR CONVERT(nvarchar(200), ClassName) = @classCode
        )
        AND (
          @search IS NULL
          OR StudentName LIKE N'%' + @search + N'%'
          OR UniqueId LIKE N'%' + @search + N'%'
          OR Username LIKE N'%' + @search + N'%'
          OR TestName LIKE N'%' + @search + N'%'
          OR Strand LIKE N'%' + @search + N'%'
        )
        ${campusAssessmentFilter('pat')}
    `;
    const createRequest = () => pool.request()
      .input('testType', sql.NVarChar(10), requestedTestType || null)
      .input('campusId', sql.NVarChar(100), campusId || null)
      .input('studentCode', sql.NVarChar(200), studentCode || null)
      .input('studentCodesJson', sql.NVarChar(sql.MAX), studentCodes.length ? JSON.stringify(studentCodes) : null)
      .input('studentNamesJson', sql.NVarChar(sql.MAX), studentNames.length ? JSON.stringify(studentNames) : null)
      .input('classCode', sql.NVarChar(200), classCode || null)
      .input('search', sql.NVarChar(100), search || null);
    const countResult = await createRequest().query(`
      SELECT COUNT_BIG(*) AS total
      FROM [SchoolDW].[silver].[PAT]
      ${filter};
    `);
    const result = await createRequest()
      .input('offset', sql.Int, offset)
      .input('limit', sql.Int, limit)
      .query(`
        SELECT
          SilverBusinessKey, SourceKey, SourceSystem, SourceFileName, SourceRowNumber,
          StudentSourceId, StudentName, StudentFirstName, StudentLastName, ExternalStudentId,
          AssessmentType, AssessmentDate, TestName, YearLevel, ClassName, ScaleScore, Band,
          Strand, FocusArea, AssessmentRange, AssessmentPercentage, AchievementLevel,
          AssessmentINLP, StrandAverageAchievementLevel, Growth, CompassPersonId,
          CompassUsername, MatchMethod, MatchScore, MatchStatus, DataQualityNotes,
          SourceDataJson, LoadedAtUtc, FamilyName, GivenName, MiddleNames, UniqueId,
          Username, DateOfBirth, Gender, ReportingWindow, ExportedDate, TestDate, TestType
        FROM [SchoolDW].[silver].[PAT]
        ${filter}
        ORDER BY AssessmentDate DESC, FamilyName, GivenName, SilverBusinessKey
        OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;
      `);
    const total = Number(countResult.recordset[0].total);
    response.json({
      data: result.recordset,
      page: {
        limit,
        offset,
        total,
        hasMore: offset + result.recordset.length < total
      }
    });
  } catch (error) {
    console.error('MSSQL PAT results query failed:', error);
    response.status(503).json({
      error: 'Unable to load PAT results from SchoolDW.silver.PAT. Confirm the table exists and the API account has SELECT permission.'
    });
  }
}

app.get([
  '/api/compass/pat-results',
  '/api/compass/campuses/pat-results',
  '/api/compass/campuses/:campusId/pat-results'
], handlePatResults);

async function handleEssentialAssessmentResults(request, response) {
  const campusId = readCampusScope(request, response);
  if (campusId === undefined) return;
  const isCampusRoute = request.path.startsWith('/api/compass/campuses/');
  const limit = Number(request.query.limit ?? 50);
  const offset = Number(request.query.offset ?? 0);
  if (!Number.isInteger(limit) || limit < 1 || limit > 1000) {
    return response.status(400).json({ error: 'limit must be an integer between 1 and 1000.' });
  }
  if (!Number.isInteger(offset) || offset < 0) {
    return response.status(400).json({ error: 'offset must be a non-negative integer.' });
  }

  let requestedStudentCodes = request.body?.studentCodes ?? [];
  let requestedStudentNames = request.body?.studentNames ?? [];
  let requestedClassCode = request.body?.classCode;
  if (request.method === 'GET') {
    requestedClassCode = request.query.classCode;
    requestedStudentCodes = [];
    requestedStudentNames = [];
    if (typeof request.query.studentCodes === 'string' && request.query.studentCodes.trim()) {
      try {
        requestedStudentCodes = JSON.parse(request.query.studentCodes);
      } catch {
        return response.status(400).json({ error: 'studentCodes must be a valid JSON array.' });
      }
    }
    if (Array.isArray(requestedStudentCodes)
      && typeof request.query.studentCode === 'string' && request.query.studentCode.trim()) {
      requestedStudentCodes.push(request.query.studentCode.trim());
    }
    if (typeof request.query.studentNames === 'string' && request.query.studentNames.trim()) {
      try {
        requestedStudentNames = JSON.parse(request.query.studentNames);
      } catch {
        return response.status(400).json({ error: 'studentNames must be a valid JSON array.' });
      }
    }
  }

  const classCode = typeof requestedClassCode === 'string' ? requestedClassCode.trim() : '';
  if (classCode.length > 200) {
    return response.status(400).json({ error: 'classCode must be 200 characters or fewer.' });
  }

  if (!Array.isArray(requestedStudentCodes) || requestedStudentCodes.length > 5000
    || requestedStudentCodes.some((value) => typeof value !== 'string' || value.trim().length > 200)) {
    return response.status(400).json({
      error: 'studentCodes must be an array of up to 5000 identifiers, each 200 characters or fewer.'
    });
  }
  const studentCodes = [...new Set(requestedStudentCodes.map((value) => value.trim()).filter(Boolean))];
  if (!Array.isArray(requestedStudentNames) || requestedStudentNames.length > 5000
    || requestedStudentNames.some((value) => typeof value !== 'string' || value.trim().length > 200)) {
    return response.status(400).json({
      error: 'studentNames must be an array of up to 5000 names, each 200 characters or fewer.'
    });
  }
  const studentNames = [...new Set(requestedStudentNames.map((value) => value.trim()).filter(Boolean))];
  if (!studentCodes.length && !studentNames.length && !classCode && !campusId && !isCampusRoute) {
    return response.status(400).json({ error: 'Provide studentCodes, studentNames, classCode or campusId to scope assessment results.' });
  }

  try {
    const pool = await getDatabasePool();
    const filter = `
      WHERE (
        (@studentCodesJson IS NULL AND @studentNamesJson IS NULL)
        OR EXISTS (
          SELECT 1
          FROM OPENJSON(@studentCodesJson) AS studentCodeValue
          WHERE CONVERT(nvarchar(200), StudentSourceId) = studentCodeValue.[value]
            OR CONVERT(nvarchar(200), ExternalStudentId) = studentCodeValue.[value]
            OR CONVERT(nvarchar(200), CompassPersonId) = studentCodeValue.[value]
            OR CompassUsername = studentCodeValue.[value]
        )
        OR EXISTS (
          SELECT 1
          FROM OPENJSON(@studentNamesJson) AS studentNameValue
          WHERE LTRIM(RTRIM(StudentName)) = studentNameValue.[value]
            OR LTRIM(RTRIM(CONCAT(StudentFirstName, N' ', StudentLastName))) = studentNameValue.[value]
            OR LTRIM(RTRIM(CONCAT(StudentLastName, N' ', StudentFirstName))) = studentNameValue.[value]
        )
      )
      AND (
        @classCode IS NULL
        OR CONVERT(nvarchar(200), ClassName) = @classCode
        OR @studentCodesJson IS NOT NULL
        OR @studentNamesJson IS NOT NULL
      )
      ${campusAssessmentFilter('essential')}
    `;
    const createRequest = () => pool.request()
      .input('campusId', sql.NVarChar(100), campusId || null)
      .input('studentCodesJson', sql.NVarChar(sql.MAX), studentCodes.length ? JSON.stringify(studentCodes) : null)
      .input('studentNamesJson', sql.NVarChar(sql.MAX), studentNames.length ? JSON.stringify(studentNames) : null)
      .input('classCode', sql.NVarChar(200), classCode || null);
    const countResult = await createRequest().query(`
      SELECT COUNT_BIG(*) AS total
      FROM [SchoolDW].[silver].[EssentialAssessment]
      ${filter};
    `);
    const result = await createRequest()
      .input('offset', sql.Int, offset)
      .input('limit', sql.Int, limit)
      .query(`
        SELECT
          SilverBusinessKey, StudentSourceId, StudentName, StudentFirstName, StudentLastName,
          ExternalStudentId, AssessmentType, AssessmentDate, TestName, YearLevel, ClassName,
          ScaleScore, Band, Strand, FocusArea, AssessmentRange, AssessmentPercentage,
          AchievementLevel, AssessmentINLP, StrandAverageAchievementLevel, Growth,
          CompassPersonId, CompassUsername, MatchStatus, DataQualityNotes
        FROM [SchoolDW].[silver].[EssentialAssessment]
        ${filter}
        ORDER BY AssessmentDate DESC, StudentName, SilverBusinessKey
        OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;
      `);
    const total = Number(countResult.recordset[0].total);
    response.json({
      data: result.recordset,
      page: {
        limit,
        offset,
        total,
        hasMore: offset + result.recordset.length < total
      }
    });
  } catch (error) {
    console.error('MSSQL Essential Assessment results query failed:', error);
    response.status(503).json({
      error: 'Unable to load Essential Assessment results from SchoolDW.silver.EssentialAssessment. Confirm the table exists and the API account has SELECT permission.'
    });
  }
}

app.route([
  '/api/compass/essential-assessment-results',
  '/api/compass/campuses/essential-assessment-results',
  '/api/compass/campuses/:campusId/essential-assessment-results'
])
  .get(handleEssentialAssessmentResults)
  .post(handleEssentialAssessmentResults);

let studentsListCache = null;
let studentsListPending = null;

app.get('/api/compass/students', async (request, response) => {
  try {
    if (request.query.refresh !== '1' && studentsListCache?.expiresAt > Date.now()) {
      return response.json(studentsListCache.rows);
    }
    studentsListPending ??= (async () => {
    const pool = await getDatabasePool();
    const result = await new sql.Request(pool, { requestTimeout: 120000 }).query(`
      SELECT
  s.compassPersonId,
  s.studentCode,
  s.firstName,
  s.preferredFirstName,
  s.lastName,
  s.preferredLastName,
  s.username,
  s.yearLevel,
  s.homeCampus,
  c.Name AS homeCampusName,
  c.Code AS homeCampusCode,
  s.gender,
  s.dateOfBirth,
  s.nationality,
  s.userStatus
FROM dbo.StudentsBasic AS s
LEFT JOIN dbo.CompassCampuses AS c
  ON c.CampusId = s.homeCampus
ORDER BY s.lastName, s.firstName, s.compassPersonId;
    `);
    studentsListCache = { rows: result.recordset, expiresAt: Date.now() + 5 * 60 * 1000 };
    return result.recordset;
    })().finally(() => { studentsListPending = null; });
    response.json(await studentsListPending);
  } catch (error) {
    console.error('MSSQL student query failed:', error);
    response.status(503).json({ error: 'Unable to load students from MSSQL.' });
  }
});


app.get('/api/compass/students/by-username/:username', async (request, response) => {
  const username = request.params.username.trim();
  if (!username || username.length > 200) {
    return response.status(400).json({ error: 'Username must contain 1 to 200 characters.' });
  }

  try {
    const pool = await getDatabasePool();
    const result = await pool.request()
      .input('username', sql.NVarChar(200), username)
      .query(`
        SELECT
          s.compassPersonId,
          s.studentCode,
          s.firstName,
          s.preferredFirstName,
          s.lastName,
          s.preferredLastName,
          s.username,
          s.yearLevel,
          s.homeCampus,
          c.Name AS homeCampusName,
          c.Code AS homeCampusCode,
          s.gender,
          s.dateOfBirth,
          s.nationality,
          s.userStatus
        FROM dbo.StudentsBasic AS s
        LEFT JOIN dbo.CompassCampuses AS c
          ON c.CampusId = s.homeCampus
        WHERE s.username = @username;
      `);

    if (result.recordset.length === 0) {
      return response.status(404).json({ error: 'Student not found for this username.' });
    }
    if (result.recordset.length > 1) {
      return response.status(409).json({ error: 'More than one student matches this username.' });
    }
    response.json(result.recordset[0]);
  } catch (error) {
    console.error('MSSQL student username query failed:', error);
    response.status(503).json({ error: 'Unable to load the student from MSSQL.' });
  }
});
app.get('/api/compass/students/by-student-code/:studentCode', async (request, response) => {
  const studentCode = request.params.studentCode.trim();
  if (!studentCode || studentCode.length > 200) {
    return response.status(400).json({ error: 'studentCode must contain 1 to 200 characters.' });
  }

  try {
    const pool = await getDatabasePool();
    const result = await pool.request()
      .input('studentCode', sql.NVarChar(200), studentCode)
      .query(`
        SELECT
          s.compassPersonId,
          s.studentCode,
          s.firstName,
          s.preferredFirstName,
          s.lastName,
          s.preferredLastName,
          s.username,
          s.yearLevel,
          s.homeCampus,
          c.Name AS homeCampusName,
          c.Code AS homeCampusCode,
          s.gender,
          s.dateOfBirth,
          s.nationality,
          s.userStatus
        FROM dbo.StudentsBasic AS s
        LEFT JOIN dbo.CompassCampuses AS c
          ON c.CampusId = s.homeCampus
        WHERE s.studentCode = @studentCode;
      `);

    if (result.recordset.length === 0) {
      return response.status(404).json({ error: 'Student not found for this studentCode.' });
    }
    if (result.recordset.length > 1) {
      return response.status(409).json({ error: 'More than one student matches this studentCode.' });
    }
    response.json(result.recordset[0]);
  } catch (error) {
    console.error('MSSQL student studentCode query failed:', error);
    response.status(503).json({ error: 'Unable to load the student from MSSQL.' });
  }
});

app.get('/api/compass/students/:compassPersonId/classes', async (request, response) => {
  const studentId = request.params.compassPersonId;
  if (studentId.length > 100) {
    return response.status(400).json({ error: 'Student ID must not exceed 100 characters.' });
  }

  try {
    const pool = await getDatabasePool();
    const result = await pool.request()
      .input('compassPersonId', sql.NVarChar(100), studentId)
      .query(`
        SELECT DISTINCT
          csc.ClassSourcedId,
          csc.ClassCode,
          COALESCE(NULLIF(csc.SubjectName, ''), NULLIF(tc.SubjectName, ''), csc.ClassTitle, '') AS SubjectName,
          COALESCE(tc.RoleDescription, '') AS RoleDescription,
          tc.CompassPersonId AS TeacherPersonId,
          COALESCE(
            NULLIF(JSON_VALUE(staff.PayloadJson, '$.fullName'), ''),
            NULLIF(JSON_VALUE(staff.PayloadJson, '$.displayName'), ''),
            NULLIF(CONCAT(
              COALESCE(
                NULLIF(JSON_VALUE(staff.PayloadJson, '$.preferredFirstName'), ''),
                NULLIF(JSON_VALUE(staff.PayloadJson, '$.firstName'), ''),
                ''
              ),
              ' ',
              COALESCE(
                NULLIF(JSON_VALUE(staff.PayloadJson, '$.preferredLastName'), ''),
                NULLIF(JSON_VALUE(staff.PayloadJson, '$.lastName'), ''),
                ''
              )
            ), ' '),
            tc.CompassPersonId
          ) AS TeacherName,
          COALESCE(
            NULLIF(JSON_VALUE(staff.PayloadJson, '$.jobTitle'), ''),
            NULLIF(JSON_VALUE(staff.PayloadJson, '$.positionTitle'), ''),
            NULLIF(JSON_VALUE(staff.PayloadJson, '$.staffRole'), ''),
            NULLIF(JSON_VALUE(staff.PayloadJson, '$.role'), ''),
            'Compass staff'
          ) AS TeacherRole,
          JSON_VALUE(staff.PayloadJson, '$.roleInSchool') AS TeacherRoleInSchool,
          JSON_VALUE(staff.PayloadJson, '$.username') AS TeacherUsername,
          (
            SELECT COUNT(DISTINCT enrolled.CompassPersonId)
            FROM dbo.CompassStudentClasses AS enrolled
            WHERE (enrolled.ClassSourcedId = csc.ClassSourcedId
              OR (enrolled.ClassSourcedId IS NULL AND enrolled.ClassCode = csc.ClassCode))
              AND (enrolled.IsActive = 1 OR enrolled.IsActive IS NULL)
          ) AS StudentCount
        FROM dbo.CompassStudentClasses AS csc
        LEFT JOIN dbo.CompassTeacherClasses AS tc
          ON tc.ClassSourcedId = csc.ClassSourcedId
          AND tc.StudentSourcedId = csc.CompassPersonId
          AND (tc.IsActive = 1 OR tc.IsActive IS NULL)
        LEFT JOIN dbo.CompassStaffBasic AS staff
          ON staff.CompassPersonId = tc.CompassPersonId
        WHERE csc.CompassPersonId = @compassPersonId
          AND (csc.IsActive = 1 OR csc.IsActive IS NULL)
        ORDER BY csc.ClassCode, csc.ClassSourcedId, TeacherName;
      `);

    const classes = new Map();
    for (const row of result.recordset) {
      const classSourcedId = String(row.ClassSourcedId ?? '');
      const classCode = String(row.ClassCode ?? '');
      const key = classSourcedId || classCode;
      if (!key) continue;

      if (!classes.has(key)) {
        classes.set(key, {
          classSourcedId,
          classCode,
          subjectName: String(row.SubjectName ?? ''),
          roleDescription: String(row.RoleDescription ?? ''),
          studentCount: Number(row.StudentCount ?? 0),
          teachers: []
        });
      }

      const teacherId = String(row.TeacherPersonId ?? '');
      if (teacherId) {
        const allocation = classes.get(key);
        if (!allocation.teachers.some((teacher) => teacher.compassPersonId === teacherId)) {
          allocation.teachers.push({
            compassPersonId: teacherId,
            displayName: String(row.TeacherName ?? teacherId),
            role: String(row.TeacherRole ?? 'Compass staff'),
            roleInSchool: String(row.TeacherRoleInSchool ?? ''),
            username: String(row.TeacherUsername ?? ''),
            photoUrl: row.TeacherUsername
              ? `/api/compass/person-photos/${encodeURIComponent(String(row.TeacherUsername))}`
              : undefined
          });
        }
      }
    }
    response.json([...classes.values()]);
  } catch (error) {
    console.error('MSSQL student class allocation query failed:', error);
    response.status(503).json({ error: 'Unable to load this student’s class allocations from MSSQL.' });
  }
});

app.get('/api/compass/students/:compassPersonId/attendance-analytics', async (request, response) => {
  const studentId = request.params.compassPersonId;
  if (studentId.length > 100) {
    return response.status(400).json({ error: 'Student ID must not exceed 100 characters.' });
  }
  const dateRange = readAttendanceDateRange(request, response);
  if (dateRange === undefined) return;

  try {
    const pool = await getDatabasePool();
    const analyticsRequest = new sql.Request(pool, { requestTimeout: 120000 })
      .input('compassPersonId', sql.NVarChar(100), studentId);
    if (dateRange) {
      analyticsRequest.input('attendanceStart', sql.DateTimeOffset, dateRange.startDate);
      analyticsRequest.input('attendanceEnd', sql.DateTimeOffset, dateRange.endDate);
    }
    const result = await analyticsRequest.query(`
        SELECT CompassPersonId, PayloadJson
        FROM dbo.CompassAttendancePeriodLines
          WITH (INDEX(IX_CompassAttendancePeriodLines_CompassPersonId))
        WHERE CompassPersonId = @compassPersonId
        ${dateRange ? `
          AND COALESCE(
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.start'), 127),
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.finish'), 127),
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.updatedTimestamp'), 127)
          ) >= @attendanceStart
          AND COALESCE(
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.start'), 127),
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.finish'), 127),
            TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.updatedTimestamp'), 127)
          ) < @attendanceEnd
        ` : ''}
        ORDER BY COALESCE(
          TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.start'), 127),
          TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.finish'), 127),
          TRY_CONVERT(datetimeoffset, JSON_VALUE(PayloadJson, '$.updatedTimestamp'), 127)
        ) DESC;
      `);
    response.json(buildAttendanceAnalytics([{ CompassPersonId: studentId }], result.recordset));
  } catch (error) {
    console.error('MSSQL student attendance analytics query failed:', error);
    response.status(503).json({ error: 'Unable to load student attendance analytics from MSSQL.' });
  }
});

app.get('/api/compass/students/:compassPersonId/attendance', async (request, response) => {
  const page = getPage(request, response);
  if (!page) return;

  const studentId = request.params.compassPersonId;
  if (studentId.length > 100) {
    return response.status(400).json({ error: 'Student ID must not exceed 100 characters.' });
  }
  const dateRange = readAttendanceDateRange(request, response);
  if (dateRange === undefined) return;

  const allowedSortFields = new Set(['year', 'term', 'week', 'date', 'student', 'attendance', 'attendanceCode']);
  const sortBy = typeof request.query.sortBy === 'string' ? request.query.sortBy : 'date';
  const sortDirection = typeof request.query.sortDirection === 'string'
    ? request.query.sortDirection.toLowerCase()
    : 'desc';
  if (!allowedSortFields.has(sortBy) || !['asc', 'desc'].includes(sortDirection)) {
    return response.status(400).json({ error: 'Invalid attendance sort field or direction.' });
  }

  const recordDateExpression = `COALESCE(
    TRY_CONVERT(datetimeoffset, JSON_VALUE(attendance.PayloadJson, '$.start'), 127),
    TRY_CONVERT(datetimeoffset, JSON_VALUE(attendance.PayloadJson, '$.finish'), 127),
    TRY_CONVERT(datetimeoffset, JSON_VALUE(attendance.PayloadJson, '$.updatedTimestamp'), 127)
  )`;
  const termPeriods = [
    { term: 1, start: '2026-01-27', endExclusive: '2026-04-03', weekStart: '2026-01-26' },
    { term: 2, start: '2026-04-20', endExclusive: '2026-06-27', weekStart: '2026-04-20' },
    { term: 3, start: '2026-07-13', endExclusive: '2026-09-19', weekStart: '2026-07-13' },
    { term: 4, start: '2026-10-05', endExclusive: '2026-12-19', weekStart: '2026-10-05' }
  ];
  const attendanceTermSortExpression = `CASE
    ${termPeriods.map(({ term, start, endExclusive }) => `
      WHEN ${recordDateExpression} >= '${start}' AND ${recordDateExpression} < '${endExclusive}' THEN ${term}
    `).join('')}
    ELSE NULL
  END`;
  const attendanceWeekSortExpression = `CASE
    ${termPeriods.map(({ start, endExclusive, weekStart }) => `
      WHEN ${recordDateExpression} >= '${start}' AND ${recordDateExpression} < '${endExclusive}'
        THEN DATEDIFF(day, '${weekStart}', CONVERT(date, ${recordDateExpression})) / 7 + 1
    `).join('')}
    ELSE NULL
  END`;
  const sortExpression = {
    year: `YEAR(${recordDateExpression})`,
    term: attendanceTermSortExpression,
    week: attendanceWeekSortExpression,
    date: recordDateExpression,
    student: `''`,
    attendance: `LOWER(JSON_VALUE(attendance.PayloadJson, '$.description'))`,
    attendanceCode: `LOWER(JSON_VALUE(attendance.PayloadJson, '$.description'))`
  }[sortBy];
  const primarySortExpression = sortBy === 'student' ? recordDateExpression : sortExpression;
  const secondarySortExpression = sortBy === 'date' || sortBy === 'student'
    ? ''
    : `, ${recordDateExpression} ${sortDirection}`;

  try {
    const pool = await getDatabasePool();
    const countRequest = new sql.Request(pool, { requestTimeout: 120000 })
      .input('compassPersonId', sql.NVarChar(100), studentId);
    if (dateRange) {
      countRequest.input('attendanceStart', sql.DateTimeOffset, dateRange.startDate);
      countRequest.input('attendanceEnd', sql.DateTimeOffset, dateRange.endDate);
    }
    const countResult = await countRequest.query(`
      SELECT COUNT_BIG(*) AS total
      FROM dbo.CompassAttendancePeriodLines AS attendance
      WHERE attendance.CompassPersonId = @compassPersonId
      ${dateRange ? `
        AND ${recordDateExpression} >= @attendanceStart
        AND ${recordDateExpression} < @attendanceEnd
      ` : ''}
    `);

    const recordsRequest = new sql.Request(pool, { requestTimeout: 120000 })
      .input('compassPersonId', sql.NVarChar(100), studentId)
      .input('offset', sql.Int, page.offset)
      .input('limit', sql.Int, page.limit);
    if (dateRange) {
      recordsRequest.input('attendanceStart', sql.DateTimeOffset, dateRange.startDate);
      recordsRequest.input('attendanceEnd', sql.DateTimeOffset, dateRange.endDate);
    }
    const result = await recordsRequest.query(`
      SELECT attendance.RowKey, attendance.PayloadJson
      FROM dbo.CompassAttendancePeriodLines AS attendance
      WHERE attendance.CompassPersonId = @compassPersonId
      ${dateRange ? `
        AND ${recordDateExpression} >= @attendanceStart
        AND ${recordDateExpression} < @attendanceEnd
      ` : ''}
      ORDER BY ${primarySortExpression} ${sortDirection}
        ${secondarySortExpression},
        attendance.RowKey
      OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;
    `);

    const data = result.recordset.map((row) => {
      const payload = JSON.parse(row.PayloadJson);
      const description = typeof payload.description === 'string' ? payload.description.trim() : '';
      const statusId = String(payload.prevalentOverallStatusId ?? '').toLowerCase();
      const firstLine = description.split(/\r?\n/, 1)[0].trim();
      let status = firstLine || 'Absent';
      if (statusId === '21625425-4deb-4957-81be-897914dcff18' || firstLine.toLowerCase() === 'not marked') {
        status = 'Not Marked';
      } else if (statusId === 'fdec4cbf-dce9-4421-90de-29a0f4891461' || firstLine.toLowerCase().includes('present')) {
        status = 'Present';
      }
      return {
        id: String(row.RowKey),
        date: String(payload.start ?? payload.finish ?? payload.updatedTimestamp ?? ''),
        period: String(payload.periodCode ?? payload.periodName ?? payload.period ?? ''),
        status,
        attendanceCode: String(payload.prevalentOverallStatusId ?? ''),
        attendanceReason: firstLine || status,
        details: description
      };
    });
    const total = Number(countResult.recordset[0].total);
    response.json({
      data,
      page: {
        limit: page.limit,
        offset: page.offset,
        total,
        hasMore: page.offset + data.length < total
      }
    });
  } catch (error) {
    console.error('MSSQL student attendance detail query failed:', error);
    response.status(503).json({ error: 'Unable to load this student’s attendance details.' });
  }
});

async function getAttendanceStatsForStudents(pool, studentIds) {
  const summaries = {};
  for (let offset = 0; offset < studentIds.length; offset += 500) {
    const batch = studentIds.slice(offset, offset + 500);
    const attendanceRequest = new sql.Request(pool, { requestTimeout: 120000 });
    const parameters = batch.map((studentId, index) => {
      const parameterName = `studentId${index}`;
      attendanceRequest.input(parameterName, sql.NVarChar(100), studentId);
      return `@${parameterName}`;
    });
    const result = await attendanceRequest.query(`
      WITH AttendanceRecords AS (
        SELECT
          CompassPersonId,
          LOWER(COALESCE(JSON_VALUE(PayloadJson, '$.prevalentOverallStatusId'), '')) AS StatusId,
          LOWER(LTRIM(RTRIM(LEFT(
            COALESCE(JSON_VALUE(PayloadJson, '$.description'), ''),
            CHARINDEX(CHAR(10), COALESCE(JSON_VALUE(PayloadJson, '$.description'), '') + CHAR(10)) - 1
          )))) AS FirstLineDescription
        FROM dbo.CompassAttendancePeriodLines
          WITH (INDEX(IX_CompassAttendancePeriodLines_CompassPersonId))
        WHERE CompassPersonId IN (${parameters.join(',')})
      )
      SELECT
        CompassPersonId,
        COUNT_BIG(*) AS TotalPeriods,
        SUM(CASE
          WHEN StatusId = '21625425-4deb-4957-81be-897914dcff18'
            OR FirstLineDescription = 'not marked'
          THEN 1 ELSE 0
        END) AS NotMarked,
        SUM(CASE
          WHEN StatusId = '21625425-4deb-4957-81be-897914dcff18'
            OR FirstLineDescription = 'not marked'
          THEN 0
          WHEN StatusId = 'fdec4cbf-dce9-4421-90de-29a0f4891461'
            OR FirstLineDescription LIKE '%present%'
          THEN 1 ELSE 0
        END) AS PresentCount,
        SUM(CASE
          WHEN StatusId = '21625425-4deb-4957-81be-897914dcff18'
            OR FirstLineDescription = 'not marked'
          THEN 0 ELSE 1
        END) AS AbsentCount,
        SUM(CASE
          WHEN StatusId <> '21625425-4deb-4957-81be-897914dcff18'
            AND FirstLineDescription <> 'not marked'
            AND (
              FirstLineDescription LIKE '%refusal%'
              OR FirstLineDescription LIKE '%can''t%'
            )
          THEN 1 ELSE 0
        END) AS SchoolRefusal
      FROM AttendanceRecords
      GROUP BY CompassPersonId
      OPTION (RECOMPILE, MAXDOP 1);
    `);

    for (const row of result.recordset) {
      const studentId = String(row.CompassPersonId ?? '');
      if (!studentId) continue;
      const present = Number(row.PresentCount) || 0;
      const absent = Number(row.AbsentCount) || 0;
      const marked = present + absent;
      summaries[studentId] = {
        totalPeriods: Number(row.TotalPeriods) || 0,
        notMarked: Number(row.NotMarked) || 0,
        present,
        absent,
        schoolRefusal: Number(row.SchoolRefusal) || 0,
        rate: marked > 0 ? Number(((present / marked) * 100).toFixed(1)) : 0
      };
    }
  }
  return summaries;
}

app.get('/api/compass/students/attendance-analytics', async (request, response) => {
  const campusId = typeof request.query.campusId === 'string' ? request.query.campusId.trim() : '';
  if (campusId.length > 100) {
    return response.status(400).json({ error: 'campusId must not exceed 100 characters.' });
  }

  const cacheKey = campusId || '*';
  const cached = campusAttendanceCache.get(cacheKey);
  if (request.query.refresh !== '1' && cached?.expiresAt > Date.now()) {
    return response.json({ studentStats: cached.studentStats });
  }

  try {
    const pool = await getDatabasePool();
    const studentRequest = new sql.Request(pool, { requestTimeout: 120000 });
    if (campusId) studentRequest.input('campusId', sql.NVarChar(100), campusId);
    const studentResult = await studentRequest.query(`
      SELECT compassPersonId
      FROM dbo.StudentsBasic
      ${campusId ? 'WHERE homeCampus = @campusId' : ''}
      ${campusId ? '' : 'ORDER BY compassPersonId;'}
    `);
    const studentIds = studentResult.recordset
      .map((row) => String(row.compassPersonId ?? ''))
      .filter(Boolean);
    const studentStats = await getAttendanceStatsForStudents(pool, studentIds);

    campusAttendanceCache.set(cacheKey, {
      studentStats,
      expiresAt: Date.now() + campusAttendanceCacheTtlMs
    });
    response.json({ studentStats });
  } catch (error) {
    console.error('MSSQL campus student attendance query failed:', error);
    response.status(503).json({
      error: 'Unable to calculate campus student attendance. Confirm dbo.CompassAttendancePeriodLines and dbo.StudentsBasic are populated and share Compass person IDs.'
    });
  }
});

async function calculateCampusAttendanceAnalytics(pool, campusId) {
  const studentRequest = new sql.Request(pool, { requestTimeout: 120000 });
  if (campusId) studentRequest.input('campusId', sql.NVarChar(100), campusId);
  const studentResult = await studentRequest.query(`
    SELECT
      CompassPersonId,
      StudentCode,
      preferredFirstName AS GivenName,
      preferredLastName AS FamilyName
    FROM dbo.StudentsBasic
    ${campusId ? 'WHERE homeCampus = @campusId' : ''}
    ORDER BY CompassPersonId;
  `);
  const students = studentResult.recordset.filter((student) => student.CompassPersonId);
  const analyticsBatches = [];
  const batchSize = 500;

  for (let offset = 0; offset < students.length; offset += batchSize) {
    const batch = students.slice(offset, offset + batchSize);
    const attendanceRequest = new sql.Request(pool, { requestTimeout: 120000 });
    const parameters = batch.map((student, index) => {
      const parameterName = `person${index}`;
      attendanceRequest.input(parameterName, sql.NVarChar(100), String(student.CompassPersonId));
      return `@${parameterName}`;
    });
    const attendanceResult = await attendanceRequest.query(`
      SELECT CompassPersonId, PayloadJson
      FROM dbo.CompassAttendancePeriodLines
      WHERE CompassPersonId IN (${parameters.join(', ')});
    `);
    analyticsBatches.push(buildAttendanceAnalytics(batch, attendanceResult.recordset));
  }

  return mergeAttendanceAnalytics(analyticsBatches);
}

app.get('/api/compass/campuses/attendance-analytics', async (request, response) => {
  const cacheKey = '*';
  const cached = campusAnalyticsCache.get(cacheKey);
  if (request.query.refresh !== '1' && cached?.expiresAt > Date.now()) {
    return response.json(cached.analytics);
  }

  try {
    const analytics = await calculateCampusAttendanceAnalytics(await getDatabasePool());
    campusAnalyticsCache.set(cacheKey, {
      analytics,
      expiresAt: Date.now() + campusAttendanceCacheTtlMs
    });
    response.json(analytics);
  } catch (error) {
    console.error('MSSQL all-campus attendance analytics query failed:', error);
    response.status(503).json({
      error: 'Unable to calculate all-campus attendance analytics. Confirm student and attendance records are available.'
    });
  }
});

app.get('/api/compass/campuses/:campusId/attendance-analytics', async (request, response) => {
  const campusId = String(request.params.campusId || '').trim();
  if (!campusId || campusId.length > 100) {
    return response.status(400).json({ error: 'A valid campusId is required.' });
  }

  const cached = campusAnalyticsCache.get(campusId);
  if (request.query.refresh !== '1' && cached?.expiresAt > Date.now()) {
    return response.json(cached.analytics);
  }

  try {
    const analytics = await calculateCampusAttendanceAnalytics(await getDatabasePool(), campusId);
    campusAnalyticsCache.set(campusId, {
      analytics,
      expiresAt: Date.now() + campusAttendanceCacheTtlMs
    });
    response.json(analytics);
  } catch (error) {
    console.error('MSSQL campus attendance analytics query failed:', error);
    response.status(503).json({
      error: 'Unable to calculate campus attendance analytics. Confirm the campus students and attendance records are available.'
    });
  }
});

function registerPayloadEndpoint(path, tableName, errorLabel, keyColumn = 'RowKey') {
  app.get(path, async (request, response) => {
    const page = getPage(request, response);
    if (!page) return;

    try {
      const pool = await getDatabasePool();
      const countResult = await pool.request().query(`
        SELECT COUNT_BIG(*) AS total
        FROM ${tableName};
      `);
      const result = await pool.request()
        .input('offset', sql.Int, page.offset)
        .input('limit', sql.Int, page.limit)
        .query(`
          SELECT ${keyColumn}, PayloadJson, SyncedAt
          FROM ${tableName}
          ORDER BY ${keyColumn}
          OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;
        `);
      const data = result.recordset.map((row) => JSON.parse(row.PayloadJson));
      const total = Number(countResult.recordset[0].total);
      response.json({
        data,
        page: {
          limit: page.limit,
          offset: page.offset,
          total,
          hasMore: page.offset + data.length < total
        }
      });
    } catch (error) {
      console.error(`MSSQL ${errorLabel} query failed:`, error);
      response.status(503).json({ error: `Unable to load ${errorLabel} from MSSQL.` });
    }
  });
}

registerPayloadEndpoint('/api/compass/staff', 'dbo.CompassStaffBasic', 'staff');
registerPayloadEndpoint('/api/compass/attendance', 'dbo.CompassAttendancePeriodLines', 'attendance');
registerPayloadEndpoint('/api/compass/learning-needs', 'dbo.CompassStudentLearningNeeds', 'student learning-needs');
registerPayloadEndpoint('/api/compass/campuses', 'dbo.CompassCampuses', 'campuses', 'CampusId');

app.listen(port, '127.0.0.1', () => {
  console.log(`MSSQL REST API listening on http://127.0.0.1:${port}`);
});
