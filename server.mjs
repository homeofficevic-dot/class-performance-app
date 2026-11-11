import 'dotenv/config';

import express from 'express';
import sql from 'mssql/msnodesqlv8.js';
import { resolve } from 'node:path';
import attendanceRouter from './attendance-routes.mjs';
import goldClassRouter from './gold-class-routes.mjs';
import goldAssessmentRouter from './gold-assessment-routes.mjs';
import progressionPointsRouter from './progression-points-routes.mjs';
import chronicleInsightsRouter from './chronicle-insights-routes.mjs';
import organisationRouter from './organisation-routes.mjs';
import wellbeingApp, { incidentRoles, requireIncidentRole } from './backend/server.mjs';

const app = express();

const PORT = Number(process.env.COMPASS_PROXY_PORT || 4201);
const developmentStaffIdentityEnabled =
    process.env.WELLBEING_DEV_AUTH === 'true'
    && process.env.NODE_ENV !== 'production';
const campusUnscopedLegacyApiPrefixes = [
    '/incidents',
    '/students',
    '/wellbeing',
    '/consequences',
    '/org'
];
const campusSharedIncidentReferencePaths = new Set([
    '/wellbeing/reference-data/locations',
    '/wellbeing/reference-data/classifications',
    '/wellbeing/reference-data/incident-types',
    '/wellbeing/reference-data/consequences'
]);

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// ---------------------------------------------------------
// SQL SERVER CONFIGURATION
// ---------------------------------------------------------

const SQL_SERVER = process.env.SQL_SERVER || 'localhost';
const SQL_DATABASE = process.env.SQL_DATABASE || 'SchoolDW';
const SQL_DRIVER = process.env.SQL_DRIVER || 'ODBC Driver 17 for SQL Server';

const SQL_AUTH = (
    process.env.SQL_AUTH || 'windows'
).toLowerCase();

const SQL_TRUST_SERVER_CERTIFICATE =
    String(process.env.SQL_TRUST_SERVER_CERTIFICATE || 'true')
        .toLowerCase() === 'true';

let poolPromise;

function getConnectionString() {
    const parts = [
        `Driver={${SQL_DRIVER}}`,
        `Server=${SQL_SERVER}`,
        `Database=${SQL_DATABASE}`,
        `TrustServerCertificate=${SQL_TRUST_SERVER_CERTIFICATE ? 'Yes' : 'No'}`
    ];

    if (SQL_AUTH === 'sql' || SQL_AUTH === 'sqlserver') {
        const username = process.env.SQL_USER;
        const password = process.env.SQL_PASSWORD;

        if (!username || !password) {
            throw new Error(
                'SQL_USER and SQL_PASSWORD are required for SQL authentication.'
            );
        }

        parts.push(`UID=${username}`);
        parts.push(`PWD=${password}`);
    } else {
        parts.push('Trusted_Connection=Yes');
    }

    return parts.join(';') + ';';
}

async function getDatabasePool() {
    if (!poolPromise) {
        const connectionString = getConnectionString();

        const pool = new sql.ConnectionPool({
            connectionString,
            connectionTimeout: 30000,
            requestTimeout: 60000,
            pool: {
                max: 10,
                min: 0,
                idleTimeoutMillis: 30000
            }
        });

        poolPromise = pool.connect().catch(error => {
            poolPromise = undefined;
            throw error;
        });
    }

    return poolPromise;
}

function isLoopbackRequest(req) {
    const remoteAddress = String(req.socket.remoteAddress || '').replace(/^::ffff:/i, '');
    const hostname = String(req.hostname || '').toLowerCase();
    return ['127.0.0.1', '::1'].includes(remoteAddress)
        && ['localhost', '127.0.0.1', '::1'].includes(hostname);
}

app.get('/api/auth/dev/staff', async (req, res) => {
    if (!developmentStaffIdentityEnabled) {
        return res.status(404).json({ success: false, error: 'Development staff identity is disabled.' });
    }
    if (!isLoopbackRequest(req)) {
        return res.status(403).json({ success: false, error: 'Development staff identity is only available from this computer.' });
    }

    try {
        const pool = await getDatabasePool();
        const result = await pool.request().query(`
            SELECT masterStaff.StaffKey, masterStaff.Username,
                   COALESCE(NULLIF(orgStaff.DisplayName, N''), masterStaff.FirstName + N' ' + masterStaff.LastName) AS DisplayName,
                   masterStaff.EmailAddress,
                   staffDirectory.HomeCampus AS CampusId,
                   campus.CampusName,
                   CONVERT(bit, CASE WHEN campus.CampusName = N'Victorian Flexible Schools' THEN 1 ELSE 0 END) AS AllCampusAccess,
                   COALESCE(roles.RoleNames, N'Reporting Staff') AS RoleNames
            FROM org.Staff AS orgStaff
            INNER JOIN gold.dimStaff AS masterStaff
                ON masterStaff.StaffKey = orgStaff.MasterStaffKey
               AND masterStaff.IsCurrent = 1
               AND masterStaff.EffectiveFromUtc <= SYSUTCDATETIME()
               AND (masterStaff.EffectiveToUtc IS NULL OR masterStaff.EffectiveToUtc >= SYSUTCDATETIME())
            INNER JOIN gold.vwStaffDirectory AS staffDirectory
                ON staffDirectory.StaffKey = masterStaff.StaffKey
            INNER JOIN gold.dimCampus AS campus
                ON campus.CompassCampusId = staffDirectory.HomeCampus
               AND campus.IsCurrent = 1
            OUTER APPLY
            (
                SELECT STRING_AGG(roleName.RoleName, N', ') AS RoleNames
                FROM
                (
                    SELECT DISTINCT CASE assignment.RoleCode
                        WHEN N'HEAD_OF_HOUSE' THEN N'Head of House'
                    END AS RoleName
                    FROM org.StaffHouseAssignment AS assignment
                    WHERE assignment.StaffKey = orgStaff.StaffKey
                      AND assignment.RoleCode = N'HEAD_OF_HOUSE'
                      AND assignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
                      AND (assignment.EffectiveTo IS NULL OR assignment.EffectiveTo >= CAST(GETDATE() AS DATE))

                    UNION

                    SELECT DISTINCT CASE assignment.RoleCode
                        WHEN N'PASTORAL_CARE_TEACHER' THEN N'Pastoral Care'
                    END
                    FROM org.StaffPastoralGroupAssignment AS assignment
                    WHERE assignment.StaffKey = orgStaff.StaffKey
                      AND assignment.RoleCode = N'PASTORAL_CARE_TEACHER'
                      AND assignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
                      AND (assignment.EffectiveTo IS NULL OR assignment.EffectiveTo >= CAST(GETDATE() AS DATE))

                    UNION

                    SELECT DISTINCT incidentRole.RoleName
                    FROM wellbeing.IncidentStaffRole AS assignment
                    INNER JOIN wellbeing.IncidentRole AS incidentRole
                        ON incidentRole.IncidentRoleId = assignment.IncidentRoleId
                       AND incidentRole.IsActive = 1
                    WHERE LOWER(assignment.StaffUsername) = LOWER(masterStaff.Username)
                      AND assignment.IsActive = 1
                      AND assignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
                      AND (assignment.EffectiveTo IS NULL OR assignment.EffectiveTo >= CAST(GETDATE() AS DATE))
                ) AS roleName
                WHERE roleName.RoleName IS NOT NULL
            ) AS roles
            WHERE orgStaff.IsActive = 1
              AND NULLIF(LTRIM(RTRIM(masterStaff.Username)), N'') IS NOT NULL
            ORDER BY DisplayName, masterStaff.StaffKey;
        `);
        res.json({ success: true, data: result.recordset });
    } catch (error) {
        console.error('GET /api/auth/dev/staff failed:', error.message);
        res.status(500).json({ success: false, error: 'Unable to load development staff identities from SQL.' });
    }
});

app.use('/api', async (req, res, next) => {
    if (req.user || !developmentStaffIdentityEnabled || !req.get('x-dev-staff-key')) {
        return next();
    }
    if (!isLoopbackRequest(req)) {
        return res.status(403).json({ success: false, error: 'Development staff identity is only available from this computer.' });
    }

    const staffKey = Number(req.get('x-dev-staff-key'));
    if (!Number.isSafeInteger(staffKey) || staffKey < 1) {
        return res.status(401).json({ success: false, error: 'Select a valid local development staff identity.' });
    }

    try {
        const pool = await getDatabasePool();
        const result = await pool.request()
            .input('staffKey', sql.Int, staffKey)
            .query(`
                SELECT TOP (2) masterStaff.Username,
                       COALESCE(NULLIF(orgStaff.DisplayName, N''), masterStaff.FirstName + N' ' + masterStaff.LastName) AS DisplayName,
                       staffDirectory.HomeCampus AS CampusId,
                       campus.CampusName
                FROM org.Staff AS orgStaff
                INNER JOIN gold.dimStaff AS masterStaff
                    ON masterStaff.StaffKey = orgStaff.MasterStaffKey
                   AND masterStaff.IsCurrent = 1
                   AND masterStaff.EffectiveFromUtc <= SYSUTCDATETIME()
                   AND (masterStaff.EffectiveToUtc IS NULL OR masterStaff.EffectiveToUtc >= SYSUTCDATETIME())
                INNER JOIN gold.vwStaffDirectory AS staffDirectory
                    ON staffDirectory.StaffKey = masterStaff.StaffKey
                INNER JOIN gold.dimCampus AS campus
                    ON campus.CompassCampusId = staffDirectory.HomeCampus
                   AND campus.IsCurrent = 1
                WHERE orgStaff.IsActive = 1
                  AND masterStaff.StaffKey = @staffKey
                  AND campus.CampusName IS NOT NULL
                  AND NULLIF(LTRIM(RTRIM(masterStaff.Username)), N'') IS NOT NULL;
            `);
        if (result.recordset.length !== 1) {
            return res.status(401).json({ success: false, error: 'The selected staff identity is not a unique active SQL staff record.' });
        }
        req.user = {
            username: result.recordset[0].Username,
            displayName: result.recordset[0].DisplayName
        };
        return next();
    } catch (error) {
        console.error('Unable to resolve local development staff identity:', error.message);
        return res.status(500).json({ success: false, error: 'Unable to verify the selected development staff identity.' });
    }
});

app.use('/api', async (req, res, next) => {
    if (req.path === '/health' || req.path === '/auth/dev/staff') {
        return next();
    }

    const username = String(
        req.user?.username || req.user?.preferred_username || req.user?.upn || ''
    ).trim();
    if (!username) {
        return res.status(401).json({ success: false, error: 'A trusted authenticated staff identity is required.' });
    }

    try {
        const pool = await getDatabasePool();
        const result = await pool.request()
            .input('username', sql.NVarChar(200), username)
            .query(`
                SELECT TOP (2)
                    orgStaff.StaffKey,
                    staffDirectory.HomeCampus AS CampusId,
                    campus.CampusName
                FROM org.Staff AS orgStaff
                INNER JOIN gold.dimStaff AS masterStaff
                    ON masterStaff.StaffKey = orgStaff.MasterStaffKey
                   AND masterStaff.IsCurrent = 1
                   AND masterStaff.EffectiveFromUtc <= SYSUTCDATETIME()
                   AND (masterStaff.EffectiveToUtc IS NULL OR masterStaff.EffectiveToUtc >= SYSUTCDATETIME())
                INNER JOIN gold.vwStaffDirectory AS staffDirectory
                    ON staffDirectory.StaffKey = masterStaff.StaffKey
                INNER JOIN gold.dimCampus AS campus
                    ON campus.CompassCampusId = staffDirectory.HomeCampus
                   AND campus.IsCurrent = 1
                WHERE orgStaff.IsActive = 1
                  AND LOWER(masterStaff.Username) = LOWER(@username)
                  AND campus.CampusName IS NOT NULL;
            `);

        if (result.recordset.length !== 1) {
            return res.status(403).json({
                success: false,
                error: 'Your account must match one active SchoolDW staff record with a current campus assignment.'
            });
        }

        const staffCampus = result.recordset[0];
        const allCampusAccess = staffCampus.CampusName === 'Victorian Flexible Schools';
        req.campusAccess = {
            staffKey: staffCampus.StaffKey,
            campusId: staffCampus.CampusId,
            campusName: staffCampus.CampusName,
            allCampusAccess
        };

        if (!allCampusAccess) {
            const path = req.path.toLowerCase();
            const isSharedIncidentReferenceRead =
                req.method === 'GET' && campusSharedIncidentReferencePaths.has(path);
            if (!isSharedIncidentReferenceRead && campusUnscopedLegacyApiPrefixes.some(prefix =>
                path === prefix || path.startsWith(`${prefix}/`)
            )) {
                return res.status(403).json({
                    success: false,
                    error: 'This endpoint is unavailable until campus-scoped access is implemented.'
                });
            }

            const campusPathMatch = req.path.match(
                /(?:^|\/)campuses\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})(?:\/|$)/i
            );
            const requestedCampus = String(
                req.params.campusId || campusPathMatch?.[1] || req.query.campusId || req.body?.campusId || ''
            ).trim();
            if (requestedCampus && requestedCampus.toLowerCase() !== String(staffCampus.CampusId).toLowerCase()) {
                return res.status(403).json({
                    success: false,
                    error: 'You can only access data for your assigned campus.'
                });
            }
        }

        return next();
    } catch (error) {
        console.error('Unable to resolve active staff campus access:', error.message);
        return res.status(500).json({ success: false, error: 'Unable to verify your active staff campus assignment.' });
    }
});

// Make the database connection available to other route modules.
app.locals.getDatabasePool = getDatabasePool;
app.locals.sql = sql;
app.use('/api', organisationRouter);

// ---------------------------------------------------------
// HEALTH CHECK
// ---------------------------------------------------------

app.get('/api/health', async (req, res) => {
    try {
        const pool = await getDatabasePool();

        await pool.request().query('SELECT 1 AS DatabaseConnected');

        res.json({
            status: 'OK',
            database: SQL_DATABASE,
            connected: true,
            timestamp: new Date().toISOString()
        });
    } catch (error) {
        console.error('Health check failed:', error);

        res.status(500).json({
            status: 'ERROR',
            connected: false,
            error: error.message
        });
    }
});

// ---------------------------------------------------------
// COMPASS STUDENTS
// ---------------------------------------------------------

const compassRouter = express.Router();

/**
 * GET /api/compass/students/by-username/:username
 *
 * Example:
 * GET /api/compass/students/by-username/CHARLEY.BRADY
 *
 * Source:
 * gold.dim_student
 */
compassRouter.get(
    '/students/by-username/:username',
    requireIncidentRole(incidentRoles.read),
    async (req, res) => {
        const username = String(req.params.username || '').trim();

        if (!username) {
            return res.status(400).json({
                error: 'Username is required.'
            });
        }

        try {
            const pool = await getDatabasePool();

            const result = await pool.request()
                .input(
                    'username',
                    sql.NVarChar(100),
                    username
                )
                .input('campusId', sql.UniqueIdentifier, req.campusAccess.campusId)
                .input('allCampusAccess', sql.Bit, req.campusAccess.allCampusAccess ? 1 : 0)
                .query(`
                    SELECT TOP (1)
                        s.StudentKey,
                        s.CompassPersonId,
                        s.Username,
                        s.StudentCode,
                        s.FirstName,
                        s.LastName,
                        s.PreferredFirstName,
                        s.PreferredLastName,
                        s.YearLevel,
                        s.CampusYearlevel,
                        s.HomeCampus
                    FROM gold.dimStudent AS s
                    WHERE UPPER(LTRIM(RTRIM(s.Username))) =
                          UPPER(LTRIM(RTRIM(@username)))
                      AND (@allCampusAccess = 1 OR s.HomeCampus = @campusId)
                    ORDER BY s.StudentKey;
                `);

            if (!result.recordset || result.recordset.length === 0) {
                return res.status(404).json({
                    error: 'Student not found in Gold layer.',
                    username
                });
            }

            const student = result.recordset[0];

            return res.status(200).json({
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
            console.error(
                'GET /students/by-username failed:',
                {
                    username,
                    message: error.message,
                    code: error.code,
                    number: error.number,
                    state: error.state,
                    lineNumber: error.lineNumber
                }
            );

            return res.status(500).json({
                error: 'Unable to load the student from gold layer.',
                details: process.env.NODE_ENV === 'development'
                    ? error.message
                    : undefined
            });
        }
    }
);

// ---------------------------------------------------------
// STUDENT LIST
// ---------------------------------------------------------

compassRouter.get('/students/search', requireIncidentRole(incidentRoles.read), async (req, res) => {
    const query = String(req.query.q || '').trim();
    const limit = Number(req.query.limit ?? 50);
    const offset = Number(req.query.offset ?? 0);
    const hasStudentKeys = req.query.studentKeys !== undefined;
    const incidentId = req.query.incidentId === undefined ? null : Number(req.query.incidentId);
    const studentKeys = hasStudentKeys
        ? String(req.query.studentKeys).split(',').map(value => Number(value.trim()))
        : [];

    if (query.length > 100) {
        return res.status(400).json({ success: false, error: 'Search query must be 100 characters or fewer.' });
    }
    if (!Number.isInteger(limit) || limit < 1 || limit > 50
        || !Number.isInteger(offset) || offset < 0 || offset > 10000) {
        return res.status(400).json({ success: false, error: 'limit must be 1-50 and offset must be 0-10000.' });
    }
    if (hasStudentKeys
        && (studentKeys.length < 1
            || studentKeys.length > 50
            || studentKeys.some(key => !Number.isSafeInteger(key) || key < 1)
            || !Number.isSafeInteger(incidentId)
            || incidentId < 1)) {
        return res.status(400).json({ success: false, error: 'studentKeys lookup requires an incidentId and 1-50 positive student keys.' });
    }
    if (incidentId !== null && (!Number.isSafeInteger(incidentId) || incidentId < 1)) {
        return res.status(400).json({ success: false, error: 'incidentId must be a positive integer.' });
    }
    if (!hasStudentKeys && incidentId !== null) {
        return res.status(400).json({ success: false, error: 'incidentId can only be supplied with studentKeys.' });
    }

    const escapeLikePattern = value => value.replace(/[\\%_[\]]/g, character => `\\${character}`);

    try {
        const pool = await getDatabasePool();
        const result = await pool.request()
            .input('queryPattern', sql.NVarChar(202), query ? `%${escapeLikePattern(query)}%` : null)
            .input('studentKeysJson', sql.NVarChar(sql.MAX), JSON.stringify(studentKeys))
            .input('studentKeyLookup', sql.Bit, hasStudentKeys)
            .input('incidentId', sql.Int, incidentId)
            .input('campusId', sql.UniqueIdentifier, req.campusAccess.campusId)
            .input('allCampusAccess', sql.Bit, req.campusAccess.allCampusAccess ? 1 : 0)
            .input('offset', sql.Int, offset)
            .input('take', sql.Int, limit + 1)
            .query(`
                WITH MatchingStudents AS
                (
                    SELECT s.StudentKey, s.CompassPersonId, s.Username, s.StudentCode,
                           s.FirstName, s.LastName, s.PreferredFirstName, s.PreferredLastName,
                           s.YearLevel, s.CampusYearlevel, s.HomeCampus, s.UserStatus
                    FROM gold.dimStudent AS s
                    WHERE
                        (
                        (
                            @studentKeyLookup = 1
                            AND EXISTS
                            (
                                SELECT 1
                                FROM wellbeing.IncidentStudent AS incidentStudent
                                INNER JOIN OPENJSON(@studentKeysJson) AS requested
                                    ON TRY_CONVERT(int, requested.[value]) = incidentStudent.StudentKey
                                WHERE incidentStudent.StudentKey = s.StudentKey
                                  AND incidentStudent.IncidentId = @incidentId
                            )
                        )
                        OR
                        (
                            @studentKeyLookup = 0
                            AND
                            (
                                @queryPattern IS NULL
                                OR s.FirstName LIKE @queryPattern ESCAPE N'\\'
                                OR s.LastName LIKE @queryPattern ESCAPE N'\\'
                                OR s.PreferredFirstName LIKE @queryPattern ESCAPE N'\\'
                                OR s.PreferredLastName LIKE @queryPattern ESCAPE N'\\'
                                OR s.StudentCode LIKE @queryPattern ESCAPE N'\\'
                                OR s.Username LIKE @queryPattern ESCAPE N'\\'
                                OR CONVERT(nvarchar(30), s.YearLevel) LIKE @queryPattern ESCAPE N'\\'
                                OR s.CampusYearlevel LIKE @queryPattern ESCAPE N'\\'
                                OR EXISTS
                                (
                                    SELECT 1
                                    FROM gold.factStudentClassMembership AS membership
                                    WHERE membership.StudentKey = s.StudentKey
                                      AND membership.IsCurrent = 1
                                      AND membership.ClassCode LIKE @queryPattern ESCAPE N'\\'
                                )
                                OR EXISTS
                                (
                                    SELECT 1
                                    FROM wellbeing.vw_StudentCurrentPastoralAssignment AS assignment
                                    WHERE assignment.StudentKey = s.StudentKey
                                      AND assignment.HouseName LIKE @queryPattern ESCAPE N'\\'
                                )
                            )
                        )
                        )
                        AND (@allCampusAccess = 1 OR s.HomeCampus = @campusId)
                )
                SELECT
                    s.StudentKey,
                    s.CompassPersonId,
                    s.Username,
                    s.StudentCode,
                    s.FirstName,
                    s.LastName,
                    s.PreferredFirstName,
                    s.PreferredLastName,
                    s.YearLevel,
                    s.CampusYearlevel,
                    s.HomeCampus,
                    s.UserStatus,
                    CASE WHEN TRY_CONVERT(int, s.UserStatus) = 1
                         THEN N'Active'
                         ELSE N'Unknown / ineligible'
                    END AS StudentStatus,
                    currentClasses.ClassName,
                    pastoral.HouseName,
                    pastoral.HasConflict AS PastoralAssignmentHasConflict
                FROM MatchingStudents AS s
                OUTER APPLY
                (
                    SELECT STRING_AGG(classMembership.ClassCode, N', ') AS ClassName
                    FROM
                    (
                        SELECT DISTINCT NULLIF(LTRIM(RTRIM(m.ClassCode)), N'') AS ClassCode
                        FROM gold.factStudentClassMembership AS m
                        WHERE m.StudentKey = s.StudentKey
                          AND m.IsCurrent = 1
                          AND NULLIF(LTRIM(RTRIM(m.ClassCode)), N'') IS NOT NULL
                    ) AS classMembership
                ) AS currentClasses
                OUTER APPLY
                (
                    SELECT STRING_AGG(assignments.HouseName, N', ') AS HouseName,
                           CONVERT(bit, MAX(CONVERT(int, assignments.HasConflict))) AS HasConflict
                    FROM
                    (
                        SELECT HouseName,
                               CONVERT(bit, MAX(CONVERT(int, HasConflict))) AS HasConflict
                        FROM wellbeing.vw_StudentCurrentPastoralAssignment
                        WHERE StudentKey = s.StudentKey
                        GROUP BY HouseName
                    ) AS assignments
                ) AS pastoral
                ORDER BY s.LastName, s.FirstName, s.StudentKey
                OFFSET @offset ROWS FETCH NEXT @take ROWS ONLY;
            `);

        const hasMore = result.recordset.length > limit;
        const data = hasMore ? result.recordset.slice(0, limit) : result.recordset;
        return res.json({
            success: true,
            data,
            page: { limit, offset, hasMore },
            query
        });
    } catch (error) {
        console.error('GET /api/compass/students/search failed:', error);
        return res.status(503).json({
            success: false,
            error: 'Unable to search students in the Gold layer.',
            details: process.env.NODE_ENV === 'development' ? error.message : undefined
        });
    }
});

compassRouter.get('/students', requireIncidentRole(incidentRoles.read), async (req, res) => {
    try {
        const pool = await getDatabasePool();

        const result = await pool.request()
            .input('allCampusAccess', sql.Bit, req.campusAccess.allCampusAccess ? 1 : 0)
            .input('campusId', sql.UniqueIdentifier, req.campusAccess.campusId)
            .query(`
            SELECT
                s.StudentKey,
                s.CompassPersonId,
                s.Username,
                s.StudentCode,
                s.FirstName,
                s.LastName,
                s.PreferredFirstName,
                s.PreferredLastName,
                s.YearLevel,
                s.CampusYearlevel,
                s.HomeCampus,
                c.CampusName AS HomeCampusName,
                s.Gender,
                s.Nationality,
                CONVERT(varchar(10), s.DateOfBirth, 23) AS DateOfBirth,
                s.UserStatus,
                CASE WHEN TRY_CONVERT(int, s.UserStatus) = 1
                     THEN N'Active'
                     ELSE N'Unknown / ineligible'
                END AS StudentStatus,
                currentClasses.ClassName,
                pastoral.HouseName,
                pastoral.HasConflict AS PastoralAssignmentHasConflict
            FROM gold.dimStudent AS s
            INNER JOIN gold.dimCampus AS c
                ON c.CompassCampusId = s.HomeCampus
               AND c.IsCurrent = 1
            OUTER APPLY (
                SELECT STRING_AGG(classMembership.ClassCode, N', ') AS ClassName
                FROM (
                    SELECT DISTINCT NULLIF(LTRIM(RTRIM(m.ClassCode)), N'') AS ClassCode
                    FROM gold.factStudentClassMembership AS m
                    WHERE m.StudentKey = s.StudentKey
                      AND m.IsCurrent = 1
                      AND NULLIF(LTRIM(RTRIM(m.ClassCode)), N'') IS NOT NULL
                ) AS classMembership
            ) AS currentClasses
            LEFT JOIN wellbeing.vw_StudentCurrentPastoralAssignment AS pastoral
                ON pastoral.StudentKey = s.StudentKey
            WHERE @allCampusAccess = 1 OR s.HomeCampus = @campusId
            ORDER BY s.LastName, s.FirstName;
        `);

        return res.json(result.recordset);

    } catch (error) {
        console.error('GET /students failed:', error);

        return res.status(500).json({
            error: 'Unable to load students from Gold layer.',
            details: process.env.NODE_ENV === 'development'
                ? error.message
                : undefined
        });
    }
});

// ---------------------------------------------------------
// REGISTER COMPASS ROUTES
// ---------------------------------------------------------

app.use('/api/compass', compassRouter);
app.use('/api/compass', requireIncidentRole(incidentRoles.read), goldClassRouter);
app.use('/api/compass', attendanceRouter);
app.use('/api/compass', goldAssessmentRouter);
app.use(
    '/api/student-performance/progression',
    requireIncidentRole(incidentRoles.read),
    progressionPointsRouter
);
app.use('/api/compass', chronicleInsightsRouter);

compassRouter.get('/campuses', async (req, res) => {
    try {
        const pool = await getDatabasePool();
        const result = await pool.request()
            .input('allCampusAccess', sql.Bit, req.campusAccess.allCampusAccess ? 1 : 0)
            .input('campusId', sql.UniqueIdentifier, req.campusAccess.campusId)
            .query(`
            SELECT CampusKey, CampusGuid, CampusCode, CampusName
            FROM gold.vwCampus
            WHERE @allCampusAccess = 1 OR CampusGuid = @campusId
            ORDER BY CampusName;
        `);
        const data = result.recordset.map((row) => ({
            campusId: row.CampusGuid,
            code: row.CampusCode ?? '',
            name: row.CampusName
        }));
        res.json({
            data,
            page: { limit: data.length, offset: 0, total: data.length, hasMore: false }
        });
    } catch (error) {
        console.error('GET /campuses failed:', error);
        res.status(503).json({ error: 'Unable to load campuses from Gold.' });
    }
});

// ---------------------------------------------------------
// STATIC STUDENT PHOTOS
// ---------------------------------------------------------

const photosDirectory = resolve(
    process.env.COMPASS_PHOTOS_DIR || 'C:\\Sanits\\CompassPhotos'
);

app.get(
    ['/api/compass/student-photos/:username', '/api/compass/person-photos/:username'],
    requireIncidentRole(incidentRoles.read),
    async (request, response) => {
        const { username } = request.params;
        if (!/^[a-z0-9][a-z0-9._'-]{0,199}$/i.test(username)) {
            return response.status(400).json({ error: 'Invalid person username.' });
        }

        if (!request.campusAccess.allCampusAccess) {
            try {
                const pool = await getDatabasePool();
                const result = await pool.request()
                    .input('username', sql.NVarChar(200), username)
                    .input('campusId', sql.UniqueIdentifier, request.campusAccess.campusId)
                    .query(`
                        SELECT TOP (1) 1 AS IsInAssignedCampus
                        WHERE EXISTS
                        (
                            SELECT 1
                            FROM gold.dimStudent AS student
                            WHERE student.Username = @username
                              AND student.HomeCampus = @campusId
                        )
                        OR EXISTS
                        (
                            SELECT 1
                            FROM gold.vwStaffDirectory AS staff
                            WHERE staff.Username = @username
                              AND staff.HomeCampus = @campusId
                        );
                    `);
                if (!result.recordset.length) {
                    return response.status(404).json({ error: 'Person photo not found.' });
                }
            } catch (error) {
                console.error('Unable to verify person photo campus:', error.message);
                return response.status(503).json({ error: 'Unable to verify person photo access.' });
            }
        }

        response.sendFile(`${username}.png`, {
            root: photosDirectory,
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
    }
);

// The wellbeing API is hosted by this same process so all API routes use port 4201.
app.use(wellbeingApp);

// ---------------------------------------------------------
// 404 HANDLER
// ---------------------------------------------------------

app.use((req, res) => {
    res.status(404).json({
        error: 'API endpoint not found.',
        method: req.method,
        path: req.originalUrl
    });
});

// ---------------------------------------------------------
// GLOBAL ERROR HANDLER
// ---------------------------------------------------------

app.use((error, req, res, next) => {
    console.error('Unhandled API error:', error);

    res.status(500).json({
        error: 'Internal server error.',
        details: process.env.NODE_ENV === 'development'
            ? error.message
            : undefined
    });
});
function getPage(request, response) {
  const limit = request.query.limit === undefined ? 100 : Number(request.query.limit);
  const offset = request.query.offset === undefined ? 0 : Number(request.query.offset);
  if (!Number.isInteger(limit) || limit < 1 || limit > 1000 || !Number.isInteger(offset) || offset < 0) {
    response.status(400).json({ error: 'limit must be 1-1000 and offset must be >= 0.' });
    return null;
  }
  return { limit, offset };
}

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
// ---------------------------------------------------------
// START SERVER
// ---------------------------------------------------------

async function startServer() {
    try {
        // Verify SQL connectivity before accepting requests.
        await getDatabasePool();

        const onListening = () => {
            console.log('----------------------------------------');
            console.log('Compass API Server Started');
            console.log(`Port: ${PORT}`);
            console.log(`Development staff identity: ${developmentStaffIdentityEnabled ? 'enabled (loopback only)' : 'disabled'}`);
            console.log(`Database: ${SQL_DATABASE}`);
            console.log(`SQL Server: ${SQL_SERVER}`);
            console.log(`Authentication: ${SQL_AUTH}`);
            console.log('----------------------------------------');
            console.log(`Health: http://127.0.0.1:${PORT}/api/health`);
        };
        if (developmentStaffIdentityEnabled) {
            app.listen(PORT, '127.0.0.1', onListening);
        } else {
            app.listen(PORT, onListening);
        }

    } catch (error) {
        console.error('Unable to start Compass API:', error);
        process.exit(1);
    }
}

startServer();