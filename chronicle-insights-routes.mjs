import express from 'express';
import sql from 'mssql/msnodesqlv8.js';

const router = express.Router();

const DOMAINS = ['WELLBEING', 'NCCD', 'OUTREACH', 'INCLUSION', 'BEHAVIOUR', 'ATTENDANCE', 'OTHER'];
const DEFAULT_WINDOW_DAYS = 365;

function fail(response, label, error) {
  console.error(`${label} failed:`, error);
  response.status(503).json({ error: `Unable to load ${label} from Gold.` });
}

function validId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 100;
}

// Returns { from, to } Date values, or { error }.
function readWindow(query) {
  const parse = (value, label) => {
    if (value === undefined || value === '') return { value: null };
    const date = new Date(String(value));
    if (Number.isNaN(date.getTime())) return { error: `${label} must be a valid ISO date.` };
    return { value: date };
  };
  const from = parse(query.from, 'from');
  if (from.error) return { error: from.error };
  const to = parse(query.to, 'to');
  if (to.error) return { error: to.error };

  const end = to.value ?? new Date();
  const start = from.value ?? new Date(end.getTime() - DEFAULT_WINDOW_DAYS * 86400000);
  if (start > end) return { error: 'from must be on or before to.' };
  return { from: start, to: end };
}

function bindWindow(request, window) {
  return request
    .input('from', sql.DateTime2, window.from)
    .input('to', sql.DateTime2, window.to);
}

const iso = (value) => (value ? new Date(value).toISOString() : null);
const num = (value) => Number(value ?? 0);

// Per-student counts used by both the student summary and the class roster.
const COUNT_COLUMNS = `
  COUNT(CASE WHEN v.ChronicleEntryKey IS NOT NULL AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 END) AS TotalEntries,
  SUM(CASE WHEN v.InsightDomain = 'WELLBEING' AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS WellbeingEntries,
  SUM(CASE WHEN v.InsightDomain = 'WELLBEING' AND v.IsHighRisk = 1 AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS WellbeingHighRisk,
  SUM(CASE WHEN v.IsDisclosure = 1 AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS Disclosures,
  MAX(CASE WHEN v.InsightDomain = 'WELLBEING' AND v.EventDate <= @to THEN v.EventDate END) AS LastWellbeingDate,
  SUM(CASE WHEN v.InsightDomain = 'NCCD' AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS NccdEntries,
  SUM(CASE WHEN v.InsightDomain = 'NCCD' THEN 1 ELSE 0 END) AS NccdEntriesAllTime,
  MAX(CASE WHEN v.InsightDomain = 'NCCD' THEN v.EventDate END) AS LastNccdDate,
  SUM(CASE WHEN v.InsightDomain = 'INCLUSION' AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS InclusionEntries,
  SUM(CASE WHEN v.InsightDomain = 'OUTREACH' AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS OutreachEntries,
  SUM(CASE WHEN v.InsightDomain = 'OUTREACH' AND v.OutreachEngagement = 'High' AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS OutreachHigh,
  SUM(CASE WHEN v.InsightDomain = 'OUTREACH' AND v.OutreachEngagement = 'Medium' AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS OutreachMedium,
  SUM(CASE WHEN v.InsightDomain = 'OUTREACH' AND v.OutreachEngagement = 'Low' AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS OutreachLow,
  SUM(CASE WHEN v.InsightDomain = 'OUTREACH' AND v.OutreachEngagement = 'Not Present' AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS OutreachNotPresent,
  SUM(CASE WHEN v.InsightDomain = 'OUTREACH' AND v.IsAssertiveOutreach = 1 AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS AssertiveOutreach,
  SUM(CASE WHEN v.InsightDomain = 'OUTREACH' AND v.OutreachLocation = 'YP Home' AND v.EventDate >= @from AND v.EventDate <= @to THEN 1 ELSE 0 END) AS OutreachHomeVisits,
  MAX(CASE WHEN v.InsightDomain = 'OUTREACH' AND v.EventDate <= @to THEN v.EventDate END) AS LastOutreachDate`;

function shapeCounts(row) {
  const outreachMeetings = num(row.OutreachEntries);
  const lowEngagement = num(row.OutreachLow) + num(row.OutreachNotPresent);
  const wellbeingHighRisk = num(row.WellbeingHighRisk);
  const disclosures = num(row.Disclosures);
  return {
    totalEntries: num(row.TotalEntries),
    wellbeing: {
      entries: num(row.WellbeingEntries),
      highRiskEntries: wellbeingHighRisk,
      disclosures,
      lastEntryDate: iso(row.LastWellbeingDate)
    },
    nccd: {
      entriesInWindow: num(row.NccdEntries),
      entriesAllTime: num(row.NccdEntriesAllTime),
      hasNccdRecord: num(row.NccdEntriesAllTime) > 0,
      lastEntryDate: iso(row.LastNccdDate),
      category: row.NccdCategory ?? null,
      levelOfAdjustment: row.NccdLevelOfAdjustment ?? null
    },
    inclusion: { entries: num(row.InclusionEntries) },
    outreach: {
      meetings: outreachMeetings,
      engagement: {
        high: num(row.OutreachHigh),
        medium: num(row.OutreachMedium),
        low: num(row.OutreachLow),
        notPresent: num(row.OutreachNotPresent)
      },
      lowEngagementRate: outreachMeetings ? Math.round((lowEngagement / outreachMeetings) * 1000) / 10 : null,
      assertiveOutreach: num(row.AssertiveOutreach),
      homeVisits: num(row.OutreachHomeVisits),
      lastMeetingDate: iso(row.LastOutreachDate)
    },
    flags: {
      wellbeingConcern: wellbeingHighRisk > 0 || disclosures > 0,
      outreachDisengaged: outreachMeetings >= 2 && lowEngagement / outreachMeetings >= 0.5,
      nccdRecorded: num(row.NccdEntriesAllTime) > 0
    }
  };
}

// Materialising the student's entries first keeps the view's field look-ups from being re-evaluated per aggregate.
function summaryQuery(keyExpression) {
  return `
    SELECT v.StudentKey, v.ChronicleEntryKey, v.InsightDomain, v.EventDate, v.IsHighRisk, v.IsDisclosure,
           v.OutreachEngagement, v.OutreachLocation, v.IsAssertiveOutreach, v.NccdCategory, v.NccdLevelOfAdjustment
    INTO #entries
    FROM gold.vwChronicleInsightEntry AS v
    WHERE v.StudentKey IN (${keyExpression});

    SELECT
      s.StudentKey, s.CompassPersonId, s.StudentCode, s.Username, s.FirstName, s.LastName,
      s.YearLevel, s.CampusYearlevel, s.HomeCampus,
      nc.NccdCategory, nc.NccdLevelOfAdjustment,
      ${COUNT_COLUMNS}
    FROM gold.dimStudent AS s
    LEFT JOIN #entries AS v ON v.StudentKey = s.StudentKey
    OUTER APPLY (
      SELECT TOP 1 n.NccdCategory, n.NccdLevelOfAdjustment
      FROM #entries AS n
      WHERE n.StudentKey = s.StudentKey AND n.InsightDomain = 'NCCD' AND n.NccdCategory IS NOT NULL
      ORDER BY n.EventDate DESC
    ) AS nc
    WHERE s.StudentKey IN (${keyExpression})
    GROUP BY s.StudentKey, s.CompassPersonId, s.StudentCode, s.Username, s.FirstName, s.LastName,
             s.YearLevel, s.CampusYearlevel, s.HomeCampus, nc.NccdCategory, nc.NccdLevelOfAdjustment
    ORDER BY s.LastName, s.FirstName;`;
}

const studentWhere = '(s.CompassPersonId = @studentId OR s.StudentCode = @studentId OR s.Username = @studentId)';

// Resolving the key separately keeps the OR lookup from defeating predicate push-down into the view.
async function resolveStudentKey(pool, studentId, campusAccess) {
  const result = await pool.request()
    .input('studentId', sql.NVarChar(100), studentId)
    .input('campusId', sql.UniqueIdentifier, campusAccess.campusId)
    .input('allCampusAccess', sql.Bit, campusAccess.allCampusAccess ? 1 : 0)
    .query(`
      SELECT TOP 1 s.StudentKey
      FROM gold.dimStudent AS s
      WHERE ${studentWhere}
        AND (@allCampusAccess = 1 OR s.HomeCampus = @campusId)
      ORDER BY s.StudentKey
    `);
  return result.recordset.length ? result.recordset[0].StudentKey : null;
}

// Student-level insight summary across Wellbeing, NCCD and Outreach.
router.get('/students/:studentId/chronicle-insights', async (request, response) => {
  const { studentId } = request.params;
  if (!validId(studentId)) return response.status(400).json({ error: 'Invalid student identifier.' });
  const window = readWindow(request.query);
  if (window.error) return response.status(400).json({ error: window.error });

  try {
    const pool = await request.app.locals.getDatabasePool();
    const studentKey = await resolveStudentKey(pool, studentId, request.campusAccess);
    if (studentKey === null) return response.status(404).json({ error: 'Student not found.' });
    const result = await bindWindow(pool.request().input('studentKey', sql.Int, studentKey), window)
      .query(summaryQuery('@studentKey'));

    const row = result.recordset[0];
    response.json({
      student: {
        compassPersonId: row.CompassPersonId, studentCode: row.StudentCode, username: row.Username,
        firstName: row.FirstName, lastName: row.LastName, yearLevel: row.YearLevel,
        campusYearLevel: row.CampusYearlevel, homeCampus: row.HomeCampus
      },
      window: { from: window.from.toISOString(), to: window.to.toISOString() },
      ...shapeCounts(row)
    });
  } catch (error) {
    fail(response, 'student chronicle insights', error);
  }
});

// Student chronicle timeline, filterable by domain.
router.get('/students/:studentId/chronicle-entries', async (request, response) => {
  const { studentId } = request.params;
  if (!validId(studentId)) return response.status(400).json({ error: 'Invalid student identifier.' });
  const window = readWindow(request.query);
  if (window.error) return response.status(400).json({ error: window.error });

  const domain = request.query.domain ? String(request.query.domain).toUpperCase() : null;
  if (domain && !DOMAINS.includes(domain)) {
    return response.status(400).json({ error: `domain must be one of ${DOMAINS.join(', ')}.` });
  }
  const limit = Number(request.query.limit ?? 100);
  const offset = Number(request.query.offset ?? 0);
  if (!Number.isInteger(limit) || limit < 1 || limit > 500) {
    return response.status(400).json({ error: 'limit must be an integer between 1 and 500.' });
  }
  if (!Number.isInteger(offset) || offset < 0) {
    return response.status(400).json({ error: 'offset must be a non-negative integer.' });
  }

  try {
    const pool = await request.app.locals.getDatabasePool();
    const studentKey = await resolveStudentKey(pool, studentId, request.campusAccess);
    if (studentKey === null) return response.status(404).json({ error: 'Student not found.' });
    const result = await bindWindow(pool.request().input('studentKey', sql.Int, studentKey), window)
      .input('domain', sql.VarChar(20), domain)
      .input('limit', sql.Int, limit)
      .input('offset', sql.Int, offset)
      .query(`
        SELECT
          COUNT(*) OVER () AS TotalRows,
          v.EntryId, v.InsightDomain, v.Category, v.Template, v.Rating, v.Points, v.IsResolved,
          v.EventDate, v.DateRecorded, v.PrimaryFieldName, v.PrimaryFieldData,
          v.OutreachEngagement, v.OutreachLocation, v.IsAssertiveOutreach, v.NccdCategory, v.NccdLevelOfAdjustment,
          st.FirstName AS StaffFirstName, st.LastName AS StaffLastName
        FROM gold.vwChronicleInsightEntry AS v
        LEFT JOIN gold.dimStaff AS st ON st.StaffKey = v.StaffKey AND st.StaffKey > 0
        WHERE v.StudentKey = @studentKey
          AND v.EventDate >= @from AND v.EventDate <= @to
          AND (@domain IS NULL OR v.InsightDomain = @domain)
        ORDER BY v.EventDate DESC, v.ChronicleEntryKey DESC
        OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY
        OPTION (RECOMPILE);
      `);

    response.json({
      page: { limit, offset, total: result.recordset.length ? num(result.recordset[0].TotalRows) : 0 },
      data: result.recordset.map((row) => ({
        entryId: row.EntryId,
        domain: row.InsightDomain,
        category: row.Category,
        template: row.Template,
        rating: row.Rating || null,
        points: row.Points,
        isResolved: Boolean(row.IsResolved),
        eventDate: iso(row.EventDate),
        dateRecorded: iso(row.DateRecorded),
        summaryField: row.PrimaryFieldName,
        summary: row.PrimaryFieldData,
        recordedBy: [row.StaffFirstName, row.StaffLastName].filter(Boolean).join(' ') || null,
        outreachEngagement: row.OutreachEngagement ?? undefined,
        outreachLocation: row.OutreachLocation ?? undefined,
        isAssertiveOutreach: row.IsAssertiveOutreach === null ? undefined : Boolean(row.IsAssertiveOutreach),
        nccdCategory: row.NccdCategory ?? undefined,
        nccdLevelOfAdjustment: row.NccdLevelOfAdjustment ?? undefined
      }))
    });
  } catch (error) {
    fail(response, 'student chronicle entries', error);
  }
});

// Class-level insights: roll-up plus one row per current student.
router.get('/classes/:classId/chronicle-insights', async (request, response) => {
  const { classId } = request.params;
  if (!validId(classId)) return response.status(400).json({ error: 'Invalid class identifier.' });
  const window = readWindow(request.query);
  if (window.error) return response.status(400).json({ error: window.error });

  try {
    const pool = await request.app.locals.getDatabasePool();
    const roster = await pool.request()
      .input('classId', sql.NVarChar(100), classId)
      .input('campusId', sql.UniqueIdentifier, request.campusAccess.campusId)
      .input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0)
      .query(`
      SELECT DISTINCT m.StudentKey, m.ClassCode
      FROM gold.factStudentClassMembership AS m
      INNER JOIN gold.dimStudent AS s ON s.StudentKey = m.StudentKey
      WHERE m.IsCurrent = 1 AND m.StudentKey IS NOT NULL
        AND (m.CompassClassId = @classId OR m.ClassCode = @classId)
        AND (@allCampusAccess = 1 OR s.HomeCampus = @campusId);
    `);
    if (!roster.recordset.length) return response.status(404).json({ error: 'Class not found or has no current students.' });

    // Keys come from the database as integers, so inlining them is safe and lets the view be filtered early.
    const keyList = [...new Set(roster.recordset.map((row) => Number(row.StudentKey)))].filter(Number.isInteger).join(',');
    const result = await bindWindow(pool.request(), window).query(summaryQuery(keyList));
    const students = result.recordset.map((row) => ({
      compassPersonId: row.CompassPersonId,
      studentCode: row.StudentCode,
      username: row.Username,
      firstName: row.FirstName,
      lastName: row.LastName,
      yearLevel: row.YearLevel,
      campusYearLevel: row.CampusYearlevel,
      ...shapeCounts(row)
    }));
    const count = (predicate) => students.filter(predicate).length;
    const sum = (select) => students.reduce((total, student) => total + select(student), 0);
    const outreachMeetings = sum((s) => s.outreach.meetings);
    const lowEngagement = sum((s) => s.outreach.engagement.low + s.outreach.engagement.notPresent);

    response.json({
      classCode: roster.recordset[0].ClassCode,
      window: { from: window.from.toISOString(), to: window.to.toISOString() },
      summary: {
        studentCount: students.length,
        wellbeing: {
          studentsWithEntries: count((s) => s.wellbeing.entries > 0),
          studentsWithConcern: count((s) => s.flags.wellbeingConcern),
          entries: sum((s) => s.wellbeing.entries),
          highRiskEntries: sum((s) => s.wellbeing.highRiskEntries),
          disclosures: sum((s) => s.wellbeing.disclosures)
        },
        nccd: {
          studentsWithNccdRecord: count((s) => s.nccd.hasNccdRecord),
          studentsWithEntriesInWindow: count((s) => s.nccd.entriesInWindow > 0),
          entriesInWindow: sum((s) => s.nccd.entriesInWindow)
        },
        outreach: {
          studentsWithOutreach: count((s) => s.outreach.meetings > 0),
          studentsDisengaged: count((s) => s.flags.outreachDisengaged),
          meetings: outreachMeetings,
          assertiveOutreach: sum((s) => s.outreach.assertiveOutreach),
          homeVisits: sum((s) => s.outreach.homeVisits),
          lowEngagementRate: outreachMeetings ? Math.round((lowEngagement / outreachMeetings) * 1000) / 10 : null
        },
        inclusion: { studentsWithEntries: count((s) => s.inclusion.entries > 0) }
      },
      students
    });
  } catch (error) {
    fail(response, 'class chronicle insights', error);
  }
});

// Domain taxonomy and volumes; useful for building filters.
router.get('/chronicle/insights/domains', async (request, response) => {
  const window = readWindow(request.query);
  if (window.error) return response.status(400).json({ error: window.error });

  try {
    const pool = await request.app.locals.getDatabasePool();
    const result = await bindWindow(pool.request(), window)
      .input('campusId', sql.UniqueIdentifier, request.campusAccess.campusId)
      .input('allCampusAccess', sql.Bit, request.campusAccess.allCampusAccess ? 1 : 0)
      .query(`
      SELECT entry.InsightDomain, entry.Template, COUNT(*) AS Entries,
             COUNT(DISTINCT entry.StudentKey) AS Students
      FROM gold.vwChronicleInsightEntry AS entry
      INNER JOIN gold.dimStudent AS student ON student.StudentKey = entry.StudentKey
      WHERE EventDate >= @from AND EventDate <= @to
        AND (@allCampusAccess = 1 OR student.HomeCampus = @campusId)
      GROUP BY InsightDomain, Template
      ORDER BY InsightDomain, Entries DESC;
    `);

    const domains = new Map();
    for (const row of result.recordset) {
      if (!domains.has(row.InsightDomain)) domains.set(row.InsightDomain, { domain: row.InsightDomain, entries: 0, templates: [] });
      const domain = domains.get(row.InsightDomain);
      domain.entries += num(row.Entries);
      domain.templates.push({ template: row.Template, entries: num(row.Entries), students: num(row.Students) });
    }
    response.json({ window: { from: window.from.toISOString(), to: window.to.toISOString() }, domains: [...domains.values()] });
  } catch (error) {
    fail(response, 'chronicle domains', error);
  }
});

export default router;
