import express from 'express';
import sql from 'mssql/msnodesqlv8.js';

const router = express.Router();
const GUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_LIMIT = 5000;

const RESULT_COLUMNS = `
    progressionAssessmentId = result.ProgressionAssessmentId,
    resultLevel = result.ResultLevel,
    studentKey = result.StudentKey,
    studentName = result.StudentName,
    campusName = result.CampusName,
    curriculumVersionId = result.CurriculumVersionId,
    frameworkName = result.FrameworkName,
    curriculumVersionName = result.CurriculumVersionName,
    subjectId = result.SubjectId,
    subjectCode = result.SubjectCode,
    subjectName = result.SubjectName,
    domainId = result.DomainId,
    domainCode = result.DomainCode,
    domainName = result.DomainName,
    dimensionId = result.DimensionId,
    dimensionCode = result.DimensionCode,
    dimensionName = result.DimensionName,
    pointCode = result.PointCode,
    pointLabel = result.PointLabel,
    minimumValue = result.MinimumValue,
    maximumValue = result.MaximumValue,
    actualProgressionPoint = result.ActualProgressionPoint,
    previousProgressionPoint = result.PreviousProgressionPoint,
    expectedProgressionPoint = result.ExpectedProgressionPoint,
    growth = result.Growth,
    varianceFromExpected = result.VarianceFromExpected,
    academicYearId = result.AcademicYearId,
    academicYearCode = result.AcademicYearCode,
    academicYearName = result.AcademicYearName,
    yearSequence = result.YearSequence,
    reportingPeriodId = result.ReportingPeriodId,
    reportingPeriodCode = result.ReportingPeriodCode,
    reportingPeriodName = result.ReportingPeriodName,
    periodSequence = result.PeriodSequence,
    reportingPeriodStartDate = result.ReportingPeriodStartDate,
    reportingPeriodEndDate = result.ReportingPeriodEndDate,
    historicalYearLevel = result.HistoricalYearLevel,
    assessmentDate = result.AssessmentDate,
    assessmentSourceCode = result.AssessmentSourceCode,
    assessmentSourceName = result.AssessmentSourceName,
    resultStatus = result.ResultStatus,
    resultNotes = result.ResultNotes`;

function parsePositiveInteger(value, name) {
  if (value === undefined || value === '') return { value: null };
  if (!/^\d+$/.test(String(value))) {
    return { error: `${name} must be a positive integer.` };
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    return { error: `${name} must be a positive integer.` };
  }
  return { value: parsed };
}

function parseFilters(request) {
  const academicYear = parsePositiveInteger(request.query.academicYearId, 'academicYearId');
  if (academicYear.error) return { error: academicYear.error };
  const reportingPeriod = parsePositiveInteger(request.query.reportingPeriodId, 'reportingPeriodId');
  if (reportingPeriod.error) return { error: reportingPeriod.error };
  const subject = parsePositiveInteger(request.query.subjectId, 'subjectId');
  if (subject.error) return { error: subject.error };

  const limit = parsePositiveInteger(request.query.limit ?? '1000', 'limit');
  if (limit.error || limit.value > MAX_LIMIT) {
    return { error: `limit must be an integer between 1 and ${MAX_LIMIT}.` };
  }
  const offsetText = String(request.query.offset ?? '0');
  if (!/^\d+$/.test(offsetText)) {
    return { error: 'offset must be a non-negative integer.' };
  }
  const offset = Number(offsetText);
  if (!Number.isSafeInteger(offset) || offset < 0) {
    return { error: 'offset must be a non-negative integer.' };
  }

  let campusId = null;
  if (request.query.campusId !== undefined && request.query.campusId !== '') {
    campusId = String(request.query.campusId).trim();
    if (!GUID_PATTERN.test(campusId)) {
      return { error: 'campusId must be a valid GUID.' };
    }
    if (!request.campusAccess.allCampusAccess
      && campusId.toLowerCase() !== String(request.campusAccess.campusId).toLowerCase()) {
      return { forbidden: true };
    }
  }

  return {
    values: {
      academicYearId: academicYear.value,
      reportingPeriodId: reportingPeriod.value,
      subjectId: subject.value,
      campusId,
      limit: limit.value,
      offset
    }
  };
}

function bindCommonFilters(query, studentKey, filters, campusAccess) {
  query
    .input('studentKey', sql.BigInt, studentKey)
    .input('academicYearId', sql.Int, filters.academicYearId)
    .input('reportingPeriodId', sql.Int, filters.reportingPeriodId)
    .input('subjectId', sql.Int, filters.subjectId)
    .input('campusFilterId', sql.UniqueIdentifier, filters.campusId)
    .input('staffCampusId', sql.UniqueIdentifier, campusAccess.campusId)
    .input('allCampusAccess', sql.Bit, campusAccess.allCampusAccess ? 1 : 0);
  return query;
}

const resultFilter = `
    result.StudentKey = @studentKey
    AND result.IsSynthetic = 0
    AND (@academicYearId IS NULL OR result.AcademicYearId = @academicYearId)
    AND (@reportingPeriodId IS NULL OR result.ReportingPeriodId = @reportingPeriodId)
    AND (@subjectId IS NULL OR result.SubjectId = @subjectId)
    AND (@campusFilterId IS NULL OR resultCampus.CompassCampusId = @campusFilterId)
    AND
    (
        @allCampusAccess = 1
        OR EXISTS
        (
            SELECT 1
            FROM gold.dimStudent AS authorizedStudent
            WHERE authorizedStudent.StudentKey = result.StudentKey
              AND authorizedStudent.HomeCampus = @staffCampusId
        )
    )`;

async function handleResults(request, response, resultLevel) {
  const studentKey = Number(request.params.studentId);
  if (!Number.isSafeInteger(studentKey) || studentKey < 1) {
    return response.status(400).json({ error: 'studentId must be a positive StudentKey.' });
  }

  const parsedFilters = parseFilters(request);
  if (parsedFilters.error) return response.status(400).json({ error: parsedFilters.error });
  if (parsedFilters.forbidden) {
    return response.status(403).json({ error: 'You can only access data for your assigned campus.' });
  }
  const filters = parsedFilters.values;

  try {
    const pool = await request.app.locals.getDatabasePool();
    const query = bindCommonFilters(pool.request(), studentKey, filters, request.campusAccess)
      .input('limit', sql.Int, filters.limit)
      .input('offset', sql.Int, filters.offset)
      .input('resultLevel', sql.NVarChar(20), resultLevel);

    const result = await query.query(`
      SELECT ${RESULT_COLUMNS}
      FROM gold.vwActualVsExpectedProgression AS result
      LEFT JOIN gold.dimCampus AS resultCampus
        ON resultCampus.CampusKey = result.CampusKey
      WHERE ${resultFilter}
        AND (@resultLevel IS NULL OR result.ResultLevel = @resultLevel)
      ORDER BY result.YearSequence, result.PeriodSequence, result.AssessmentDate,
               result.DomainId, result.DimensionId, result.ProgressionAssessmentId
      OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;
    `);

    return response.json({ data: result.recordset });
  } catch (error) {
    console.error('Progression results query failed:', error);
    return response.status(503).json({ error: 'Unable to load progression results from Gold.' });
  }
}

router.get('/domains/:studentId', (request, response) => handleResults(request, response, 'DOMAIN'));
router.get('/dimensions/:studentId', (request, response) => handleResults(request, response, 'DIMENSION'));
router.get('/history/:studentId', (request, response) => handleResults(request, response, null));

router.get('/filters/:studentId', async (request, response) => {
  const studentKey = Number(request.params.studentId);
  if (!Number.isSafeInteger(studentKey) || studentKey < 1) {
    return response.status(400).json({ error: 'studentId must be a positive StudentKey.' });
  }

  const parsedFilters = parseFilters(request);
  if (parsedFilters.error) return response.status(400).json({ error: parsedFilters.error });
  if (parsedFilters.forbidden) {
    return response.status(403).json({ error: 'You can only access data for your assigned campus.' });
  }

  try {
    const pool = await request.app.locals.getDatabasePool();
    const query = bindCommonFilters(
      pool.request(),
      studentKey,
      parsedFilters.values,
      request.campusAccess
    );
    const result = await query.query(`
      SELECT DISTINCT result.SubjectId AS subjectId, result.SubjectCode AS subjectCode,
                      result.SubjectName AS subjectName
      FROM gold.vwStudentProgressionHistory AS result
      LEFT JOIN gold.dimCampus AS resultCampus ON resultCampus.CampusKey = result.CampusKey
      WHERE ${resultFilter}
      ORDER BY subjectName;

      SELECT DISTINCT result.AcademicYearId AS academicYearId,
                      result.AcademicYearCode AS academicYearCode,
                      result.AcademicYearName AS academicYearName,
                      result.YearSequence AS yearSequence
      FROM gold.vwStudentProgressionHistory AS result
      LEFT JOIN gold.dimCampus AS resultCampus ON resultCampus.CampusKey = result.CampusKey
      WHERE ${resultFilter}
      ORDER BY yearSequence;

      SELECT DISTINCT result.ReportingPeriodId AS reportingPeriodId,
                      result.ReportingPeriodCode AS reportingPeriodCode,
                      result.ReportingPeriodName AS reportingPeriodName,
                      result.PeriodSequence AS periodSequence
      FROM gold.vwStudentProgressionHistory AS result
      LEFT JOIN gold.dimCampus AS resultCampus ON resultCampus.CampusKey = result.CampusKey
      WHERE ${resultFilter}
      ORDER BY periodSequence;

      SELECT DISTINCT resultCampus.CompassCampusId AS campusId,
                      result.CampusName AS campusName
      FROM gold.vwStudentProgressionHistory AS result
      INNER JOIN gold.dimCampus AS resultCampus ON resultCampus.CampusKey = result.CampusKey
      WHERE ${resultFilter}
      ORDER BY campusName;
    `);

    return response.json({
      subjects: result.recordsets[0],
      academicYears: result.recordsets[1],
      reportingPeriods: result.recordsets[2],
      campuses: result.recordsets[3]
    });
  } catch (error) {
    console.error('Progression filter query failed:', error);
    return response.status(503).json({ error: 'Unable to load progression filters from Gold.' });
  }
});

export default router;
