
import express from 'express';
import sql from 'mssql/msnodesqlv8.js';
import {
  buildAttendanceAnalytics,
  mergeAttendanceAnalytics
} from './attendance-analytics.mjs';
import { decodeAttendanceJson } from './attendance-json.mjs';

const router = express.Router();

const NOT_MARKED_STATUS_ID = '21625425-4deb-4957-81be-897914dcff18';

const PRESENT_STATUS_ID = 'fdec4cbf-dce9-4421-90de-29a0f4891461';

const cache = new Map();
const CACHE_TTL = 5 * 60 * 1000;

function getCampusScope(request, requestedCampusId) {
  if (request.campusAccess?.allCampusAccess) {
    return requestedCampusId || null;
  }
  return request.campusAccess?.campusId || requestedCampusId || null;
}

function getDateFilter(request, response) {
  const year = request.query.year == null ? '' : String(request.query.year);
  const startDate = request.query.startDate;
  const endDate = request.query.endDate;

  if (year && !/^\d{4}$/.test(year)) {
    response.status(400).json({ error: 'year must be a four-digit year.' });
    return undefined;
  }

  if (Boolean(startDate) !== Boolean(endDate)) {
    response.status(400).json({
      error: 'Both startDate and endDate must be supplied.'
    });
    return undefined;
  }

  let start;
  let end;

  if (startDate && endDate) {
    start = new Date(startDate);
    end = new Date(endDate);

    if (
      Number.isNaN(start.getTime()) ||
      Number.isNaN(end.getTime()) ||
      start >= end
    ) {
      response.status(400).json({
        error: 'Invalid date range. startDate must be before endDate.'
      });
      return undefined;
    }
  }

  return {
    year: year ? Number(year) : null,
    start,
    end
  };
}

function applyDateFilter() {
  return `
    AND (@year IS NULL OR d.CalendarYear = @year)
    AND (@startDate IS NULL OR p.AttendanceDate >= CAST(@startDate AS date))
    AND (@endDate IS NULL OR p.AttendanceDate < CAST(@endDate AS date))
  `;
}

function bindDateParameters(request, filters) {
  request.input('year', sql.SmallInt, filters.year);
  request.input('startDate', sql.DateTime2, filters.start || null);
  request.input('endDate', sql.DateTime2, filters.end || null);
}

function getPaging(request, response) {
  const limit = Number(request.query.limit ?? 100);
  const offset = Number(request.query.offset ?? 0);

  if (!Number.isInteger(limit) || limit < 1 || limit > 500) {
    response.status(400).json({
      error: 'limit must be between 1 and 500.'
    });
    return null;
  }

  if (!Number.isInteger(offset) || offset < 0) {
    response.status(400).json({
      error: 'offset must be a non-negative integer.'
    });
    return null;
  }

  return { limit, offset };
}

function cacheGet(key) {
  const item = cache.get(key);

  if (item && item.expiresAt > Date.now()) {
    return item.value;
  }

  cache.delete(key);
  return null;
}

function cacheSet(key, value) {
  cache.set(key, {
    value,
    expiresAt: Date.now() + CACHE_TTL
  });
}

async function getStudents(pool, filters = {}) {
  const request = pool.request();

  request.input('studentId', sql.NVarChar(100), filters.studentId ?? null);
  request.input('campusId', sql.UniqueIdentifier, filters.campusId ?? null);

  if (filters.classSourcedId) {
    request.input('classSourcedId', sql.NVarChar(100), filters.classSourcedId);
  }

  let membershipJoin = '';
  let membershipFilter = '';

  if (filters.classSourcedId) {
    membershipJoin = `
      INNER JOIN gold.factStudentClassMembership AS m
        ON m.StudentKey = s.StudentKey
       AND m.IsCurrent = 1
      INNER JOIN gold.dimClass AS c
        ON c.ClassKey = m.ClassKey
    `;

    membershipFilter = `
      AND (
        c.CompassClassId = @classSourcedId
        OR c.ClassCode = @classSourcedId
      )
    `;
  }

  const result = await request.query(`
    SELECT DISTINCT
      s.CompassPersonId,
      s.StudentCode,
      COALESCE(s.PreferredFirstName, s.FirstName) AS GivenName,
      COALESCE(s.PreferredLastName, s.LastName) AS FamilyName
    FROM gold.dimStudent AS s
    ${membershipJoin}
    WHERE
      (@studentId IS NULL OR s.CompassPersonId = @studentId)
      AND (@campusId IS NULL OR s.HomeCampus = @campusId)
      ${membershipFilter}
    ORDER BY s.CompassPersonId;
  `);

  return result.recordset;
}

async function getPeriodRecords(pool, filters) {
  const request = pool.request();

  bindDateParameters(request, filters);

  if (filters.studentId) {
    request.input('studentId', sql.NVarChar(100), filters.studentId);
  }

  if (filters.campusId) {
    request.input('campusId', sql.UniqueIdentifier, filters.campusId);
  }

  if (filters.studentIds) {
    // This helper is not used for large ID arrays.
    // Campus and class queries use their relational joins instead.
  }

  const studentCondition = filters.studentId
    ? 'AND p.CompassPersonId = @studentId'
    : '';

  const campusCondition = filters.campusId
    ? 'AND p.CampusGuid = @campusId'
    : '';

  const result = await request.query(`
    SELECT
      p.CompassPersonId,
      p.AttendanceDate,
      p.PeriodStart,
      p.PeriodFinish,
      p.ExpectedMinutes,
      p.PrevalentOverallStatusId,
      p.Description,
      p.PeriodCode,
      p.CampusGuid,
      p.SourceUpdatedTimestamp
    FROM gold.fact_attendance_period AS p
    INNER JOIN gold.dimDate AS d
      ON d.Date = p.AttendanceDate
    WHERE 1 = 1
      ${studentCondition}
      ${campusCondition}
      ${applyDateFilter(request, filters)}
    ORDER BY p.PeriodStart DESC;
  `);

  return result.recordset;
}

async function getAnalytics(pool, scope, refresh = false) {
  const cacheKey = JSON.stringify(scope);
  const cached = cacheGet(cacheKey);

  if (cached && !refresh) return cached;

  const students = await getStudents(pool, scope);
  if (!students.length) return buildAttendanceAnalytics([], []);

  const filters = scope.dateFilters || {
    year: null,
    start: null,
    end: null
  };

  const request = pool.request();
  bindDateParameters(request, filters);

  if (scope.campusId) {
    request.input('campusId', sql.UniqueIdentifier, scope.campusId);
  }

  if (scope.studentId) {
    request.input('studentId', sql.NVarChar(100), scope.studentId);
  }

  if (scope.classSourcedId) {
    request.input(
      'classSourcedId',
      sql.NVarChar(100),
      scope.classSourcedId
    );
  }

  const studentCondition = scope.studentId
    ? 'AND p.CompassPersonId = @studentId'
    : '';

  const campusCondition = scope.campusId
    ? 'AND p.CampusGuid = @campusId'
    : '';

  let classJoin = '';
  let classCondition = '';

  if (scope.classSourcedId) {
    classJoin = `
      INNER JOIN gold.dimStudent AS s
        ON s.CompassPersonId = p.CompassPersonId
      INNER JOIN gold.factStudentClassMembership AS m
        ON m.StudentKey = s.StudentKey
       AND m.IsCurrent = 1
      INNER JOIN gold.dimClass AS c
        ON c.ClassKey = m.ClassKey
    `;

    classCondition = `
      AND (
        c.CompassClassId = @classSourcedId
        OR c.ClassCode = @classSourcedId
      )
    `;
  }

  const campusScope = !scope.studentId && !scope.classSourcedId;
  const result = await request.query(`
    SELECT
      p.CompassPersonId,
      ${campusScope
        ? `COALESCE(p.PeriodStart, CONVERT(datetime2, p.AttendanceDate), p.PeriodFinish, p.SourceUpdatedTimestamp) AS PeriodStart,
           p.PrevalentOverallStatusId, p.Description`
        : `p.AttendanceDate, p.PeriodStart, p.PeriodFinish, p.ExpectedMinutes,
           p.PrevalentOverallStatusId, p.Description, p.PeriodCode, p.CampusGuid, p.SourceUpdatedTimestamp`}
    FROM gold.fact_attendance_period AS p
    ${classJoin}
    INNER JOIN gold.dimDate AS d
      ON d.Date = p.AttendanceDate
    WHERE 1 = 1
      ${studentCondition}
      ${campusCondition}
      ${classCondition}
      ${applyDateFilter(request, filters)}
    ORDER BY p.PeriodStart DESC${campusScope ? ', p.AttendancePeriodFactKey ASC' : ''}
    ${campusScope ? 'FOR JSON PATH' : ''};
  `);

  const analytics = buildAttendanceAnalytics(
    students,
    campusScope ? decodeAttendanceJson(result.recordset) : result.recordset
  );

  cacheSet(cacheKey, analytics);
  return analytics;
}

function readFilters(request, response) {
  const dateFilters = getDateFilter(request, response);
  if (!dateFilters) return undefined;

  return { dateFilters };
}

// -----------------------------------------------------------------------------
// Student analytics
// -----------------------------------------------------------------------------

router.get(
  '/students/:compassPersonId/attendance-analytics',
  async (request, response) => {
    try {
      const studentId = request.params.compassPersonId;

      if (!studentId || studentId.length > 100) {
        return response.status(400).json({
          error: 'Invalid Compass student ID.'
        });
      }

      const filters = readFilters(request, response);
      if (!filters) return;

      const pool = await request.app.locals.getDatabasePool();

      const result = await getAnalytics(pool, {
        studentId,
        campusId: getCampusScope(request),
        ...filters
      });

      response.json(result);
    } catch (error) {
      console.error('Student attendance analytics failed:', error);
      response.status(503).json({
        error: 'Unable to load student attendance analytics.'
      });
    }
  }
);

// -----------------------------------------------------------------------------
// Student attendance history
// -----------------------------------------------------------------------------

router.get(
  '/students/:compassPersonId/attendance',
  async (request, response) => {
    try {
      const paging = getPaging(request, response);
      if (!paging) return;

      const studentId = request.params.compassPersonId;

      if (!studentId || studentId.length > 100) {
        return response.status(400).json({
          error: 'Invalid Compass student ID.'
        });
      }

      const filters = readFilters(request, response);
      if (!filters) return;

      const pool = await request.app.locals.getDatabasePool();
      const query = pool.request();
      query.input('studentId', sql.NVarChar(100), studentId);
      query.input('campusId', sql.UniqueIdentifier, getCampusScope(request));
      query.input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0);
      query.input('limit', sql.Int, paging.limit);
      query.input('offset', sql.Int, paging.offset);
      bindDateParameters(query, filters.dateFilters);

      const dateWhere = `
        AND (@year IS NULL OR d.CalendarYear = @year)
        AND (@startDate IS NULL OR p.AttendanceDate >= CAST(@startDate AS date))
        AND (@endDate IS NULL OR p.AttendanceDate < CAST(@endDate AS date))
      `;

      const countResult = await query.query(`
        SELECT COUNT_BIG(*) AS total
        FROM gold.fact_attendance_period AS p
        INNER JOIN gold.dimDate AS d
          ON d.Date = p.AttendanceDate
        WHERE p.CompassPersonId = @studentId
          AND (@allCampusAccess = 1 OR EXISTS
          (
            SELECT 1
            FROM gold.dimStudent AS s
            WHERE s.CompassPersonId = p.CompassPersonId
              AND s.HomeCampus = @campusId
          ))
          ${dateWhere}
      `);

      const dataResult = await pool.request()
        .input('studentId', sql.NVarChar(100), studentId)
        .input('campusId', sql.UniqueIdentifier, getCampusScope(request))
        .input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0)
        .input('limit', sql.Int, paging.limit)
        .input('offset', sql.Int, paging.offset)
        .input('year', sql.SmallInt, filters.dateFilters.year)
        .input('startDate', sql.DateTime2, filters.dateFilters.start)
        .input('endDate', sql.DateTime2, filters.dateFilters.end)
        .query(`
          SELECT
            CAST(p.PeriodLineId AS NVARCHAR(100)) AS id,
            p.AttendanceDate AS attendanceDate,
            p.PeriodStart AS periodStart,
            p.PeriodFinish AS periodFinish,
            p.PeriodCode AS period,
            p.ExpectedMinutes AS expectedMinutes,
            p.PrevalentOverallStatusId AS attendanceCode,
            p.Description AS details,
            CASE
              WHEN p.PrevalentOverallStatusId = '${NOT_MARKED_STATUS_ID}'
                THEN 'Not Marked'
              WHEN p.PrevalentOverallStatusId = '${PRESENT_STATUS_ID}'
                THEN 'Present'
              WHEN LOWER(COALESCE(p.Description, '')) LIKE '%present%'
                THEN 'Present'
              ELSE COALESCE(
                NULLIF(
                  LTRIM(RTRIM(
                    LEFT(
                      COALESCE(p.Description, ''),
                      CHARINDEX(CHAR(10), COALESCE(p.Description, '') + CHAR(10)) - 1
                    )
                  )),
                  ''
                ),
                'Absent'
              )
            END AS status
          FROM gold.fact_attendance_period AS p
          INNER JOIN gold.dimDate AS d
            ON d.Date = p.AttendanceDate
          WHERE p.CompassPersonId = @studentId
            AND (@allCampusAccess = 1 OR EXISTS
            (
              SELECT 1
              FROM gold.dimStudent AS s
              WHERE s.CompassPersonId = p.CompassPersonId
                AND s.HomeCampus = @campusId
            ))
            ${dateWhere}
          ORDER BY p.PeriodStart DESC
          OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;
        `);

      const total = Number(countResult.recordset[0].total);

      response.json({
        data: dataResult.recordset.map(row => ({
          id: String(row.id),
          date: row.attendanceDate,
          period: row.period ?? '',
          status: row.status,
          attendanceCode: row.attendanceCode ?? '',
          attendanceReason: row.details ?? row.status,
          details: row.details ?? '',
          periodStart: row.periodStart,
          periodFinish: row.periodFinish,
          expectedMinutes: row.expectedMinutes
        })),
        page: {
          limit: paging.limit,
          offset: paging.offset,
          total,
          totalPages: Math.ceil(total / paging.limit)
        }
      });
    } catch (error) {
      console.error('Student attendance history failed:', error);
      response.status(503).json({
        error: 'Unable to load student attendance history.'
      });
    }
  }
);

// -----------------------------------------------------------------------------
// All student attendance statistics
// -----------------------------------------------------------------------------

router.get('/students/attendance-analytics', async (request, response) => {
  try {
    const filters = readFilters(request, response);
    if (!filters) return;

    const campusId = getCampusScope(request, request.query.campusId
      ? String(request.query.campusId)
      : null);

    const cacheKey = `studentStats:${JSON.stringify({ campusId, ...filters })}`;
    if (request.query.refresh !== '1') {
      const cached = cacheGet(cacheKey);
      if (cached) return response.json(cached);
    }

    const pool = await request.app.locals.getDatabasePool();

    const students = await getStudents(pool, { campusId });

    const requestSql = pool.request();
    bindDateParameters(requestSql, filters.dateFilters);

    if (campusId) {
      requestSql.input('campusId', sql.UniqueIdentifier, campusId);
    }

    const campusCondition = campusId
      ? 'AND p.CampusGuid = @campusId'
      : '';

    const result = await requestSql.query(`
      SELECT
        p.CompassPersonId,
        COUNT_BIG(*) AS totalPeriods,
        SUM(CASE WHEN p.PrevalentOverallStatusId = '${PRESENT_STATUS_ID}'
          THEN 1 ELSE 0 END) AS present,
        SUM(CASE WHEN p.PrevalentOverallStatusId = '${NOT_MARKED_STATUS_ID}'
          THEN 1 ELSE 0 END) AS notMarked,
        SUM(CASE
          WHEN p.PrevalentOverallStatusId NOT IN (
            '${PRESENT_STATUS_ID}',
            '${NOT_MARKED_STATUS_ID}'
          ) THEN 1 ELSE 0 END) AS absent
      FROM gold.fact_attendance_period AS p
      INNER JOIN gold.dimDate AS d
        ON d.Date = p.AttendanceDate
      WHERE 1 = 1
        ${campusCondition}
        AND (@year IS NULL OR d.CalendarYear = @year)
        AND (@startDate IS NULL OR p.AttendanceDate >= CAST(@startDate AS date))
        AND (@endDate IS NULL OR p.AttendanceDate < CAST(@endDate AS date))
      GROUP BY p.CompassPersonId;
    `);

    const statsByStudent = new Map(
      result.recordset.map(row => [
        String(row.CompassPersonId),
        row
      ])
    );

    const studentStats = {};

    for (const student of students) {
      const id = String(student.CompassPersonId);
      const row = statsByStudent.get(id);

      const present = Number(row?.present ?? 0);
      const absent = Number(row?.absent ?? 0);
      const notMarked = Number(row?.notMarked ?? 0);
      const marked = present + absent;

      studentStats[id] = {
        compassPersonId: id,
        studentCode: student.StudentCode ?? '',
        name: [
          student.GivenName,
          student.FamilyName
        ].filter(Boolean).join(' '),
        totalPeriods: Number(row?.totalPeriods ?? 0),
        present,
        absent,
        notMarked,
        schoolRefusal: 0,
        rate: marked
          ? Number(((present / marked) * 100).toFixed(1))
          : 0
      };
    }

    const resultBody = { studentStats };
    cacheSet(cacheKey, resultBody);
    response.json(resultBody);
  } catch (error) {
    console.error('Student attendance statistics failed:', error);
    response.status(503).json({
      error: 'Unable to load student attendance statistics.'
    });
  }
});

// -----------------------------------------------------------------------------
// Campus analytics
// -----------------------------------------------------------------------------

router.get('/campuses/attendance-analytics', async (request, response) => {
  try {
    const filters = readFilters(request, response);
    if (!filters) return;

    const campusId = getCampusScope(request, request.query.campusId
      ? String(request.query.campusId)
      : null);

    const pool = await request.app.locals.getDatabasePool();

    const result = await getAnalytics(pool, {
      campusId,
      ...filters
    }, request.query.refresh === '1');

    response.json(result);
  } catch (error) {
    console.error('Campus attendance analytics failed:', error);
    response.status(503).json({
      error: 'Unable to load campus attendance analytics.'
    });
  }
});

router.get(
  '/campuses/:campusId/attendance-analytics',
  async (request, response) => {
    try {
      const filters = readFilters(request, response);
      if (!filters) return;

      const campusId = request.params.campusId;

      if (
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(campusId)
      ) {
        return response.status(400).json({
          error: 'campusId must be a valid GUID.'
        });
      }
      if (!request.campusAccess.allCampusAccess
        && campusId.toLowerCase() !== String(request.campusAccess.campusId).toLowerCase()) {
        return response.status(403).json({
          error: 'You can only access data for your assigned campus.'
        });
      }

      const pool = await request.app.locals.getDatabasePool();

      const result = await getAnalytics(pool, {
        campusId,
        ...filters
      }, request.query.refresh === '1');

      response.json(result);
    } catch (error) {
      console.error('Campus attendance analytics failed:', error);
      response.status(503).json({
        error: 'Unable to load campus attendance analytics.'
      });
    }
  }
);

// -----------------------------------------------------------------------------
// Class analytics
// -----------------------------------------------------------------------------

router.get(
  '/classes/:classSourcedId/attendance-analytics',
  async (request, response) => {
    try {
      const filters = readFilters(request, response);
      if (!filters) return;

      const classSourcedId = request.params.classSourcedId;

      if (!classSourcedId || classSourcedId.length > 100) {
        return response.status(400).json({
          error: 'Invalid class identifier.'
        });
      }

      const pool = await request.app.locals.getDatabasePool();

      const result = await getAnalytics(pool, {
        classSourcedId,
        campusId: getCampusScope(request),
        ...filters
      });

      response.json(result);
    } catch (error) {
      console.error('Class attendance analytics failed:', error);
      response.status(503).json({
        error: 'Unable to load class attendance analytics.'
      });
    }
  }
);

// -----------------------------------------------------------------------------
// General paginated attendance
// -----------------------------------------------------------------------------

router.get('/attendance', async (request, response) => {
  try {
    const paging = getPaging(request, response);
    if (!paging) return;

    const filters = readFilters(request, response);
    if (!filters) return;

    const pool = await request.app.locals.getDatabasePool();

    const query = pool.request();
    query.input('campusId', sql.UniqueIdentifier, getCampusScope(request));
    query.input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0);
    query.input('limit', sql.Int, paging.limit);
    query.input('offset', sql.Int, paging.offset);
    bindDateParameters(query, filters.dateFilters);

    const result = await query.query(`
      SELECT
        CAST(p.PeriodLineId AS NVARCHAR(100)) AS id,
        p.CompassPersonId,
        s.StudentCode,
        COALESCE(s.PreferredFirstName, s.FirstName) AS FirstName,
        COALESCE(s.PreferredLastName, s.LastName) AS LastName,
        p.AttendanceDate,
        p.PeriodStart,
        p.PeriodFinish,
        p.PeriodCode,
        p.ExpectedMinutes,
        p.PrevalentOverallStatusId,
        p.Description
      FROM gold.fact_attendance_period AS p
      INNER JOIN gold.dimStudent AS s
        ON s.CompassPersonId = p.CompassPersonId
      INNER JOIN gold.dimDate AS d
        ON d.Date = p.AttendanceDate
      WHERE
        (@allCampusAccess = 1 OR s.HomeCampus = @campusId)
        AND
        (@year IS NULL OR d.CalendarYear = @year)
        AND (@startDate IS NULL OR p.AttendanceDate >= CAST(@startDate AS date))
        AND (@endDate IS NULL OR p.AttendanceDate < CAST(@endDate AS date))
      ORDER BY p.PeriodStart DESC
      OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;
    `);

    const countQuery = pool.request();
    countQuery.input('campusId', sql.UniqueIdentifier, getCampusScope(request));
    countQuery.input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0);
    bindDateParameters(countQuery, filters.dateFilters);

    const count = await countQuery.query(`
      SELECT COUNT_BIG(*) AS total
      FROM gold.fact_attendance_period AS p
      INNER JOIN gold.dimDate AS d
        ON d.Date = p.AttendanceDate
      INNER JOIN gold.dimStudent AS s
        ON s.CompassPersonId = p.CompassPersonId
      WHERE
        (@allCampusAccess = 1 OR s.HomeCampus = @campusId)
        AND
        (@year IS NULL OR d.CalendarYear = @year)
        AND (@startDate IS NULL OR p.AttendanceDate >= CAST(@startDate AS date))
        AND (@endDate IS NULL OR p.AttendanceDate < CAST(@endDate AS date));
    `);

    const total = Number(count.recordset[0].total);

    response.json({
      data: result.recordset.map(row => ({
        id: String(row.id),
        compassPersonId: row.CompassPersonId,
        studentCode: row.StudentCode ?? '',
        studentName: [
          row.FirstName,
          row.LastName
        ].filter(Boolean).join(' '),
        date: row.AttendanceDate,
        period: row.PeriodCode ?? '',
        periodStart: row.PeriodStart,
        periodFinish: row.PeriodFinish,
        expectedMinutes: row.ExpectedMinutes,
        attendanceCode: row.PrevalentOverallStatusId,
        details: row.Description ?? ''
      })),
      page: {
        limit: paging.limit,
        offset: paging.offset,
        total,
        totalPages: Math.ceil(total / paging.limit)
      }
    });
  } catch (error) {
    console.error('General attendance query failed:', error);
    response.status(503).json({
      error: 'Unable to load attendance records from Gold.'
    });
  }
});

export default router;
