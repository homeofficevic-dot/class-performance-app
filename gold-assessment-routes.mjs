import express from 'express';
import sql from 'mssql/msnodesqlv8.js';

const router = express.Router();

const SOURCES = {
  pat: {
    fact: 'gold.factPAT',
    silver: 'silver.PAT',
    codeColumns: ['UniqueId', 'StudentSourceId', 'ExternalStudentId', 'Username', 'CompassUsername'],
    nameColumns: ['s.StudentName', "CONCAT(s.GivenName, N' ', s.FamilyName)", "CONCAT(s.FamilyName, N' ', s.GivenName)"],
    select: `
      f.SilverBusinessKey, f.StudentSourceId, s.StudentName, f.ExternalStudentId, f.UniqueId,
      f.Username, f.TestType, f.TestName, f.AssessmentType, f.AssessmentDate, f.TestDate,
      f.ReportingWindow, f.YearLevel, f.ClassName, f.ScaleScore, f.Band, f.Growth,
      f.SourceMatchStatus AS MatchStatus, f.StudentKey, f.StudentResolutionMethod`
  },
  essential: {
    fact: 'gold.factEssentialAssessment',
    silver: 'silver.EssentialAssessment',
    codeColumns: ['StudentSourceId', 'ExternalStudentId', 'CompassUsername'],
    nameColumns: ['s.StudentName', "CONCAT(s.StudentFirstName, N' ', s.StudentLastName)", "CONCAT(s.StudentLastName, N' ', s.StudentFirstName)"],
    select: `
      f.SilverBusinessKey, f.StudentSourceId, s.StudentName, f.ExternalStudentId,
      f.AssessmentType, f.AssessmentDate, f.TestName, f.YearLevel, f.ClassName, f.Strand,
      f.FocusArea, f.AssessmentRange, f.AssessmentPercentage, f.AchievementLevel,
      f.AssessmentINLP, f.StrandAverageAchievementLevel, f.Growth,
      f.SourceMatchStatus AS MatchStatus, f.StudentKey, f.StudentResolutionMethod`
  }
};

function readStringArray(value, label) {
  if (value === undefined || value === null || value === '') return { values: [] };
  let parsed = value;
  if (typeof value === 'string') {
    try {
      parsed = JSON.parse(value);
    } catch {
      return { error: `${label} must be a valid JSON array.` };
    }
  }
  if (!Array.isArray(parsed) || parsed.length > 500
    || parsed.some((item) => typeof item !== 'string' || item.trim().length > 200)) {
    return { error: `${label} must be an array of up to 500 strings, each 200 characters or fewer.` };
  }
  return { values: [...new Set(parsed.map((item) => item.trim()).filter(Boolean))] };
}

function createHandler(sourceKey) {
  const source = SOURCES[sourceKey];

  return async (request, response) => {
    const limit = Number(request.query.limit ?? 1000);
    const offset = Number(request.query.offset ?? 0);
    if (!Number.isInteger(limit) || limit < 1 || limit > 1000) {
      return response.status(400).json({ error: 'limit must be an integer between 1 and 1000.' });
    }
    if (!Number.isInteger(offset) || offset < 0) {
      return response.status(400).json({ error: 'offset must be a non-negative integer.' });
    }

    // POST carries filters in the body; GET carries them in the query string.
    const filterSource = request.method === 'POST' ? (request.body ?? {}) : request.query;

    const campusId = String(
      request.params.campusId
      ?? filterSource.campusId
      ?? request.query.campusId
      ?? request.campusAccess?.campusId
      ?? ''
    ).trim();
    if (campusId && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(campusId)) {
      return response.status(400).json({ error: 'campusId must be a valid GUID.' });
    }
    if (campusId && request.campusAccess
      && !request.campusAccess.allCampusAccess
      && campusId.toLowerCase() !== String(request.campusAccess.campusId).toLowerCase()) {
      return response.status(403).json({ error: 'You can only access data for your assigned campus.' });
    }

    const codes = readStringArray(filterSource.studentCodes, 'studentCodes');
    if (codes.error) return response.status(400).json({ error: codes.error });
    const names = readStringArray(filterSource.studentNames, 'studentNames');
    if (names.error) return response.status(400).json({ error: names.error });

    const singleCode = typeof filterSource.studentCode === 'string' ? filterSource.studentCode.trim() : '';
    if (singleCode) codes.values.push(singleCode);

    const classCode = typeof filterSource.classCode === 'string' ? filterSource.classCode.trim() : '';
    if (classCode.length > 200) {
      return response.status(400).json({ error: 'classCode must be 200 characters or fewer.' });
    }

    const search = typeof filterSource.search === 'string' ? filterSource.search.trim() : '';
    if (search.length > 100) {
      return response.status(400).json({ error: 'search must be 100 characters or fewer.' });
    }

    let testType = null;
    if (sourceKey === 'pat' && typeof filterSource.testType === 'string' && filterSource.testType.trim()) {
      testType = filterSource.testType.trim().toUpperCase();
      if (!['PATM', 'PATR'].includes(testType)) {
        return response.status(400).json({ error: 'testType must be PATM or PATR.' });
      }
    }

    const codeMatch = (alias) => source.codeColumns
      .map((column) => `f.${column} = ${alias}`)
      .concat(['CONVERT(nvarchar(100), ds.CompassPersonId) = ' + alias, 'ds.StudentCode = ' + alias, 'ds.Username = ' + alias])
      .join(' OR ');
    const nameMatch = source.nameColumns
      .map((expression) => `LTRIM(RTRIM(${expression})) = n.[value]`)
      .join(' OR ');
    const campusMatch = [
      ...source.codeColumns.flatMap((column) => [`c.StudentCode = f.${column}`, `c.Username = f.${column}`]),
      'c.StudentKey = f.StudentKey'
    ].join(' OR ');

    const hasStudentFilter = codes.values.length > 0 || names.values.length > 0;

    const from = `
      FROM ${source.fact} AS f
      INNER JOIN ${source.silver} AS s
        ON s.SilverBusinessKey = f.SilverBusinessKey
      LEFT JOIN gold.dimStudent AS ds
        ON ds.StudentKey = f.StudentKey
      WHERE (${testType ? 'f.TestType = @testType' : '1 = 1'})
        AND (@classCode IS NULL OR @hasStudentFilter = 1 OR f.ClassName = @classCode)
        AND (
          @search IS NULL
          OR s.StudentName LIKE N'%' + @search + N'%'
          OR f.TestName LIKE N'%' + @search + N'%'
          OR f.StudentSourceId LIKE N'%' + @search + N'%'
          OR f.ExternalStudentId LIKE N'%' + @search + N'%'
        )
        AND (
          @hasStudentFilter = 0
          OR EXISTS (SELECT 1 FROM OPENJSON(@codesJson) AS k WHERE ${codeMatch('k.[value]')})
          OR EXISTS (SELECT 1 FROM OPENJSON(@namesJson) AS n WHERE ${nameMatch})
        )
        AND (
          @campusId IS NULL
          OR EXISTS (SELECT 1 FROM gold.dimStudent AS c WHERE c.HomeCampus = @campusId AND (${campusMatch}))
        )`;

    const bind = (req) => {
      req.input('classCode', sql.NVarChar(200), classCode || null);
      req.input('search', sql.NVarChar(100), search || null);
      req.input('campusId', sql.UniqueIdentifier, campusId || null);
      req.input('hasStudentFilter', sql.Bit, hasStudentFilter ? 1 : 0);
      req.input('codesJson', sql.NVarChar(sql.MAX), JSON.stringify(codes.values));
      req.input('namesJson', sql.NVarChar(sql.MAX), JSON.stringify(names.values));
      if (testType) req.input('testType', sql.NVarChar(10), testType);
      return req;
    };

    try {
      const pool = await request.app.locals.getDatabasePool();
      const count = await bind(pool.request()).query(`SELECT COUNT_BIG(*) AS total ${from};`);
      const result = await bind(pool.request())
        .input('offset', sql.Int, offset)
        .input('limit', sql.Int, limit)
        .query(`
          SELECT ${source.select}
          ${from}
          ORDER BY f.AssessmentDate DESC, f.SilverBusinessKey
          OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;
        `);

      const total = Number(count.recordset[0].total);
      response.json({
        data: result.recordset,
        page: { limit, offset, total, hasMore: offset + result.recordset.length < total }
      });
    } catch (error) {
      console.error(`${sourceKey} assessment query failed:`, error);
      response.status(503).json({ error: 'Unable to load assessment results from Gold.' });
    }
  };
}

router.get(
  ['/pat-results', '/campuses/pat-results', '/campuses/:campusId/pat-results'],
  createHandler('pat')
);

router.route([
  '/essential-assessment-results',
  '/campuses/essential-assessment-results',
  '/campuses/:campusId/essential-assessment-results'
]).get(createHandler('essential')).post(createHandler('essential'));

export default router;
