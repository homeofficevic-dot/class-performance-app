import 'dotenv/config';

import express from 'express';
import cors from 'cors';
import sql from 'mssql/msnodesqlv8.js';
import adminConfigRouter from './routes/admin-config.routes.mjs';
import { pathToFileURL } from 'node:url';

// ---------------------------------------------------------
// EXPRESS APP SETUP
// ---------------------------------------------------------

const app = express();
const PORT = Number(process.env.PORT || 3000);
const isMainModule = process.argv[1]
    ? import.meta.url === pathToFileURL(process.argv[1]).href
    : false;

if (isMainModule) {
    app.use(express.json({ limit: '10mb' }));
    app.use(express.urlencoded({ extended: true }));
    app.use(cors());
}

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

console.log('');
console.log('═════════════════════════════════════════════════════════════════════');
console.log('🚀 STUDENT WELLBEING API - INITIALIZATION');
console.log('═════════════════════════════════════════════════════════════════════');
console.log('');
console.log('Configuration:');
console.log(`  SQL_SERVER: ${SQL_SERVER}`);
console.log(`  SQL_DATABASE: ${SQL_DATABASE}`);
console.log(`  SQL_DRIVER: ${SQL_DRIVER}`);
console.log(`  SQL_AUTH: ${SQL_AUTH}`);
console.log(`  SQL_TRUST_SERVER_CERTIFICATE: ${SQL_TRUST_SERVER_CERTIFICATE}`);
console.log('');

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
        // Windows authentication
        parts.push('Trusted_Connection=Yes');
    }

    return parts.join(';') + ';';
}

async function getDatabasePool() {
    if (!poolPromise) {
        try {
            const connectionString = getConnectionString();

            console.log('🔗 Connecting to SQL Server...');

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

            poolPromise = pool.connect().then(() => {
                console.log('✅ Database connected successfully!');
                console.log('');
                return pool;
            }).catch(error => {
                poolPromise = undefined;
                console.error('❌ Database connection failed:', error.message);
                throw error;
            });
        } catch (error) {
            poolPromise = undefined;
            throw error;
        }
    }

    return poolPromise;
}

// Make the database connection available to other route modules
app.locals.getDatabasePool = getDatabasePool;
app.locals.sql = sql;

const incidentRoles = {
    read: ['REPORTING_STAFF', 'HEAD_OF_HOUSE', 'PASTORAL_CARE', 'DEPUTY_PRINCIPAL', 'ADMINISTRATION', 'AUTHORIZED_APPROVER'],
    create: ['REPORTING_STAFF', 'ADMINISTRATION'],
    update: ['REPORTING_STAFF', 'PASTORAL_CARE', 'ADMINISTRATION'],
    cancel: ['REPORTING_STAFF', 'PASTORAL_CARE', 'ADMINISTRATION', 'AUTHORIZED_APPROVER']
};
const manageableGroupCodes = ['ADMINISTRATION', 'HEAD_OF_HOUSE', 'PASTORAL_CARE', 'REPORTING_STAFF'];

function requireIncidentRole(allowedRoles) {
    return async (req, res, next) => {
        const principal = req.user;
        const username = String(
            principal?.username
            || principal?.preferred_username
            || principal?.upn
            || ''
        ).trim();
        if (!username) {
            return res.status(401).json({ success: false, error: 'A trusted authenticated staff identity is required.' });
        }

        try {
            const pool = await getDatabasePool();
            const result = await pool.request()
                .input('username', sql.NVarChar(200), username)
                .query(`
                    SELECT DISTINCT resolved.RoleCode
                    FROM
                    (
                        SELECT role.RoleCode
                        FROM wellbeing.IncidentStaffRole AS assignment
                        INNER JOIN wellbeing.IncidentRole AS role
                            ON role.IncidentRoleId = assignment.IncidentRoleId
                        WHERE LOWER(assignment.StaffUsername) = LOWER(@username)
                          AND assignment.IsActive = 1
                          AND role.IsActive = 1
                          AND assignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
                          AND (assignment.EffectiveTo IS NULL OR assignment.EffectiveTo >= CAST(GETDATE() AS DATE))

                        UNION ALL

                        SELECT N'REPORTING_STAFF'
                        FROM org.Staff AS orgStaff
                        INNER JOIN gold.dimStaff AS masterStaff
                            ON masterStaff.StaffKey = orgStaff.MasterStaffKey
                        WHERE orgStaff.IsActive = 1
                          AND masterStaff.IsCurrent = 1
                          AND masterStaff.EffectiveFromUtc <= SYSUTCDATETIME()
                          AND (masterStaff.EffectiveToUtc IS NULL OR masterStaff.EffectiveToUtc >= SYSUTCDATETIME())
                          AND LOWER(masterStaff.Username) = LOWER(@username)

                        UNION ALL

                        SELECT CASE houseAssignment.RoleCode
                                   WHEN N'HEAD_OF_HOUSE' THEN N'HEAD_OF_HOUSE'
                               END
                        FROM org.StaffHouseAssignment AS houseAssignment
                        INNER JOIN org.Staff AS orgStaff
                            ON orgStaff.StaffKey = houseAssignment.StaffKey
                           AND orgStaff.IsActive = 1
                        INNER JOIN gold.dimStaff AS masterStaff
                            ON masterStaff.StaffKey = orgStaff.MasterStaffKey
                           AND masterStaff.IsCurrent = 1
                        WHERE LOWER(masterStaff.Username) = LOWER(@username)
                          AND masterStaff.EffectiveFromUtc <= SYSUTCDATETIME()
                          AND (masterStaff.EffectiveToUtc IS NULL OR masterStaff.EffectiveToUtc >= SYSUTCDATETIME())
                          AND houseAssignment.RoleCode = N'HEAD_OF_HOUSE'
                          AND houseAssignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
                          AND (houseAssignment.EffectiveTo IS NULL OR houseAssignment.EffectiveTo >= CAST(GETDATE() AS DATE))

                        UNION ALL

                        SELECT CASE groupAssignment.RoleCode
                                   WHEN N'PASTORAL_CARE_TEACHER' THEN N'PASTORAL_CARE'
                               END
                        FROM org.StaffPastoralGroupAssignment AS groupAssignment
                        INNER JOIN org.Staff AS orgStaff
                            ON orgStaff.StaffKey = groupAssignment.StaffKey
                           AND orgStaff.IsActive = 1
                        INNER JOIN gold.dimStaff AS masterStaff
                            ON masterStaff.StaffKey = orgStaff.MasterStaffKey
                           AND masterStaff.IsCurrent = 1
                        WHERE LOWER(masterStaff.Username) = LOWER(@username)
                          AND masterStaff.EffectiveFromUtc <= SYSUTCDATETIME()
                          AND (masterStaff.EffectiveToUtc IS NULL OR masterStaff.EffectiveToUtc >= SYSUTCDATETIME())
                          AND groupAssignment.RoleCode = N'PASTORAL_CARE_TEACHER'
                          AND groupAssignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
                          AND (groupAssignment.EffectiveTo IS NULL OR groupAssignment.EffectiveTo >= CAST(GETDATE() AS DATE))
                    ) AS resolved
                    WHERE resolved.RoleCode IS NOT NULL;
                `);
            const roles = result.recordset.map(row => row.RoleCode);
            if (!roles.includes('SUPER_USER') && !roles.some(role => allowedRoles.includes(role))) {
                return res.status(403).json({ success: false, error: 'Your account is not authorized to access this incident operation.' });
            }

            const staff = await pool.request()
                .input('username', sql.NVarChar(200), username)
                .query(`
                    SELECT TOP (2) StaffKey
                    FROM gold.dimStaff
                    WHERE IsCurrent = 1
                      AND EffectiveFromUtc <= SYSUTCDATETIME()
                      AND (EffectiveToUtc IS NULL OR EffectiveToUtc >= SYSUTCDATETIME())
                      AND LOWER(Username) = LOWER(@username);
                `);
            if (staff.recordset.length !== 1) {
                return res.status(403).json({ success: false, error: 'The authenticated account does not resolve to one current staff profile.' });
            }

            req.incidentPrincipal = {
                username,
                staffKey: staff.recordset[0].StaffKey,
                roles
            };
            return next();
        } catch (error) {
            console.error('Unable to authorize incident operation:', error.message);
            return res.status(500).json({ success: false, error: 'Unable to verify incident permissions.' });
        }
    };
}

async function writeIncidentAudit(pool, req, action, incidentId, before, after) {
    await pool.request()
        .input('Actor', sql.NVarChar(255), req.incidentPrincipal.username)
        .input('Action', sql.NVarChar(50), action)
        .input('EntityId', sql.NVarChar(100), String(incidentId))
        .input('BeforeJson', sql.NVarChar(sql.MAX), before === null ? null : JSON.stringify(before))
        .input('AfterJson', sql.NVarChar(sql.MAX), after === null ? null : JSON.stringify(after))
        .input('CorrelationId', sql.NVarChar(100), req.get('x-correlation-id') || null)
        .input('IpAddress', sql.NVarChar(50), req.ip || null)
        .query(`
            INSERT INTO wellbeing.AuditEvent
                (Actor, Action, EntityName, EntityId, BeforeJson, AfterJson, CorrelationId, IpAddress)
            VALUES
                (@Actor, @Action, N'Incident', @EntityId, @BeforeJson, @AfterJson, @CorrelationId, @IpAddress);
        `);
}

async function verifyCurrentStudentYearLevel(pool, req, incidentId, studentKey) {
    return pool.request()
        .input('IncidentId', sql.Int, incidentId)
        .input('StudentKey', sql.Int, studentKey)
        .input('StaffKey', sql.Int, req.incidentPrincipal.staffKey)
        .input('CanManageAll', sql.Bit, req.incidentPrincipal.roles.includes('ADMINISTRATION'))
        .input('Actor', sql.NVarChar(255), req.incidentPrincipal.username)
        .input('CorrelationId', sql.NVarChar(100), req.get('x-correlation-id') || null)
        .input('IpAddress', sql.NVarChar(50), req.ip || null)
        .query(`
            DECLARE @SnapshotChanges TABLE
            (
                StudentKey INT NOT NULL,
                PreviousYearLevel NVARCHAR(50) NULL,
                PreviousResolutionStatus NVARCHAR(40) NULL,
                StudentYearLevelAtIncident NVARCHAR(50) NOT NULL,
                YearLevelResolutionStatus NVARCHAR(40) NOT NULL
            );

            BEGIN TRY
                BEGIN TRANSACTION;

                UPDATE studentLink
                SET StudentYearLevelAtIncident = CONVERT(nvarchar(50), historical.StandardYearLevel),
                    YearLevelResolutionStatus = N'VERIFIED'
                OUTPUT inserted.StudentKey,
                       deleted.StudentYearLevelAtIncident,
                       deleted.YearLevelResolutionStatus,
                       inserted.StudentYearLevelAtIncident,
                       inserted.YearLevelResolutionStatus
                INTO @SnapshotChanges
                FROM wellbeing.IncidentStudent AS studentLink
                INNER JOIN wellbeing.factBehaviourIncident AS incident
                    ON incident.IncidentId = studentLink.IncidentId
                   AND incident.IsDeleted = 0
                   AND (@CanManageAll = 1 OR incident.ReportingStaffKey = @StaffKey)
                INNER JOIN gold.dimStudent AS student
                    ON student.StudentKey = studentLink.StudentKey
                OUTER APPLY
                (
                    SELECT COUNT_BIG(*) AS SourceVersionCount,
                           MAX(TRY_CONVERT
                           (
                               int,
                               RIGHT
                               (
                                   LTRIM(RTRIM(source.year_level)),
                                   PATINDEX
                                   (
                                       N'%[^0-9]%',
                                       REVERSE(LTRIM(RTRIM(source.year_level))) + N'X'
                                   ) - 1
                               )
                           )) AS StandardYearLevel
                    FROM silver.StudentsBasic AS source
                    WHERE source.compass_person_id = student.CompassPersonId
                      AND source.valid_from_utc < DATEADD(DAY, 1, CONVERT(datetime2, incident.IncidentDate))
                      AND (source.valid_to_utc IS NULL
                           OR source.valid_to_utc >= CONVERT(datetime2, incident.IncidentDate))
                ) AS historical
                WHERE studentLink.IncidentId = @IncidentId
                  AND studentLink.StudentKey = @StudentKey
                  AND historical.SourceVersionCount = 1
                  AND historical.StandardYearLevel IS NOT NULL
                  AND
                  (
                      studentLink.YearLevelResolutionStatus IS NULL
                      OR studentLink.YearLevelResolutionStatus <> N'VERIFIED'
                      OR studentLink.StudentYearLevelAtIncident IS NULL
                  );

                IF EXISTS (SELECT 1 FROM @SnapshotChanges)
                BEGIN
                    INSERT INTO wellbeing.AuditEvent
                        (Actor, Action, EntityName, EntityId, BeforeJson, AfterJson, CorrelationId, IpAddress)
                    SELECT @Actor, N'VERIFY_STUDENT_YEAR_LEVEL', N'Incident', CONVERT(nvarchar(100), @IncidentId),
                           (SELECT StudentKey, PreviousYearLevel AS StudentYearLevelAtIncident,
                                   PreviousResolutionStatus AS YearLevelResolutionStatus
                            FROM @SnapshotChanges
                            FOR JSON PATH),
                           (SELECT StudentKey, StudentYearLevelAtIncident, YearLevelResolutionStatus
                            FROM @SnapshotChanges
                            FOR JSON PATH),
                           @CorrelationId, @IpAddress;
                END;

                COMMIT TRANSACTION;
            END TRY
            BEGIN CATCH
                IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
                THROW;
            END CATCH;

            SELECT StudentKey, StudentYearLevelAtIncident, YearLevelResolutionStatus
            FROM @SnapshotChanges;
        `);
}

const legacyReferenceRouter = express.Router();

app.get('/api/auth/me', requireIncidentRole(incidentRoles.read), async (req, res) => {
    try {
        const pool = await getDatabasePool();
        const result = await pool.request()
            .input('staffKey', sql.Int, req.incidentPrincipal.staffKey)
            .query(`
                SELECT StaffKey, Username,
                       LTRIM(RTRIM(CONCAT(FirstName, N' ', LastName))) AS DisplayName,
                       EmailAddress
                FROM gold.dimStaff
                WHERE StaffKey = @staffKey;
            `);
        res.json({
            success: true,
            data: {
                ...result.recordset[0],
                roles: req.incidentPrincipal.roles
            }
        });
    } catch (error) {
        console.error('Unable to load the authenticated staff profile:', error.message);
        res.status(500).json({ success: false, error: 'Unable to load the authenticated staff profile.' });
    }
});

legacyReferenceRouter.get('/locations', requireIncidentRole(incidentRoles.read), async (_req, res) => {
    try {
        const pool = await getDatabasePool();
        const result = await pool.request().query(`
            SELECT DISTINCT location.LocationId, location.LocationName, location.DisplayOrder
            FROM wellbeing.tblSchoolLocations AS location
            INNER JOIN wellbeing.IncidentClassificationLocation AS mapping
                ON mapping.LocationId = location.LocationId
            WHERE location.IsActive = 1
            ORDER BY location.DisplayOrder, location.LocationName;
        `);
        res.json({ success: true, data: result.recordset });
    } catch (error) {
        console.error('Unable to load incident locations:', error.message);
        res.status(500).json({ success: false, error: 'Unable to load incident locations.' });
    }
});

legacyReferenceRouter.get('/classifications', requireIncidentRole(incidentRoles.read), async (req, res) => {
    const locationId = Number(req.query.locationId);
    if (!Number.isInteger(locationId) || locationId < 1) {
        return res.status(400).json({ success: false, error: 'A valid locationId is required.' });
    }
    try {
        const pool = await getDatabasePool();
        const result = await pool.request()
            .input('locationId', sql.Int, locationId)
            .query(`
                SELECT classification.ClassificationId, classification.ClassificationName,
                       classification.LegacyGeneralClassificationId, classification.DisplayOrder
                FROM wellbeing.IncidentClassificationLocation AS mapping
                INNER JOIN wellbeing.tblIncidentClassifications AS classification
                    ON classification.ClassificationId = mapping.ClassificationId
                WHERE mapping.LocationId = @locationId
                  AND classification.IsActive = 1
                ORDER BY classification.DisplayOrder, classification.ClassificationName;
            `);
        res.json({ success: true, data: result.recordset });
    } catch (error) {
        console.error('Unable to load incident classifications:', error.message);
        res.status(500).json({ success: false, error: 'Unable to load incident classifications.' });
    }
});

legacyReferenceRouter.get('/incident-types', requireIncidentRole(incidentRoles.read), async (req, res) => {
    const classificationId = Number(req.query.classificationId);
    if (!Number.isInteger(classificationId) || classificationId < 1) {
        return res.status(400).json({ success: false, error: 'A valid classificationId is required.' });
    }
    try {
        const pool = await getDatabasePool();
        const result = await pool.request()
            .input('classificationId', sql.Int, classificationId)
            .query(`
                SELECT incidentType.IncidentTypeId, incidentType.IncidentTypeName,
                       incidentType.LegacyIncidentTypeId, incidentType.LegacyIncidentLevel,
                       incidentType.DisplayOrder
                FROM wellbeing.IncidentTypeClassification AS mapping
                INNER JOIN wellbeing.tblIncidentTypes AS incidentType
                    ON incidentType.IncidentTypeId = mapping.IncidentTypeId
                WHERE mapping.ClassificationId = @classificationId
                  AND incidentType.IsActive = 1
                ORDER BY incidentType.DisplayOrder, incidentType.IncidentTypeName;
            `);
        res.json({ success: true, data: result.recordset });
    } catch (error) {
        console.error('Unable to load incident types:', error.message);
        res.status(500).json({ success: false, error: 'Unable to load incident types.' });
    }
});

legacyReferenceRouter.get('/consequences', requireIncidentRole(incidentRoles.read), async (req, res) => {
    const incidentTypeId = Number(req.query.incidentTypeId);
    const classificationId = Number(req.query.classificationId);
    const locationId = Number(req.query.locationId);
    const incidentDate = String(req.query.incidentDate || '');
    if (!Number.isInteger(incidentTypeId) || incidentTypeId < 1
        || !Number.isInteger(classificationId) || classificationId < 1
        || !Number.isInteger(locationId) || locationId < 1
        || !validSqlDate(incidentDate)) {
        return res.status(400).json({
            success: false,
            error: 'Valid locationId, classificationId, incidentTypeId, and incidentDate (YYYY-MM-DD) are required.'
        });
    }
    try {
        const pool = await getDatabasePool();
        const configurationResult = await pool.request().query(`
            SELECT
                CONVERT(bit, CASE WHEN OBJECT_ID(N'wellbeing.ConsequenceApplicationWorkflow', N'U') IS NULL THEN 0 ELSE 1 END) AS HasApplicationWorkflow,
                CONVERT(bit, CASE WHEN OBJECT_ID(N'wellbeing.ConsequenceRestrictionGroupMember', N'U') IS NULL
                                      OR OBJECT_ID(N'wellbeing.ConsequenceRestrictionGroup', N'U') IS NULL
                                  THEN 0 ELSE 1 END) AS HasRestrictionGroups;
        `);
        const { HasApplicationWorkflow, HasRestrictionGroups } = configurationResult.recordset[0];
        const workflowApply = HasApplicationWorkflow
            ? `
                OUTER APPLY
                (
                    SELECT TOP (1) configured.RequiresApproval, configured.ApprovalRoleCode,
                                   configured.ProcessingRoleCode, configured.WorkflowDescription
                    FROM wellbeing.ConsequenceApplicationWorkflow AS configured
                    WHERE configured.ConsequenceId = consequence.ConsequenceId
                      AND configured.IsActive = 1
                      AND configured.EffectiveStartDate <= @incidentDate
                      AND (configured.EffectiveEndDate IS NULL OR configured.EffectiveEndDate >= @incidentDate)
                    ORDER BY configured.EffectiveStartDate DESC
                ) AS workflow
            `
            : `
                OUTER APPLY
                (
                    SELECT CONVERT(bit, NULL) AS RequiresApproval,
                           CONVERT(nvarchar(50), NULL) AS ApprovalRoleCode,
                           CONVERT(nvarchar(50), NULL) AS ProcessingRoleCode,
                           CONVERT(nvarchar(500), NULL) AS WorkflowDescription
                ) AS workflow
            `;
        const restrictionApply = HasRestrictionGroups
            ? `
                OUTER APPLY
                (
                    SELECT MIN(restrictionGroup.MaxAssignmentsPerStudentPerDate) AS MaxAssignmentsPerStudentPerDate
                    FROM wellbeing.ConsequenceRestrictionGroupMember AS groupMember
                    INNER JOIN wellbeing.ConsequenceRestrictionGroup AS restrictionGroup
                        ON restrictionGroup.RestrictionGroupCode = groupMember.RestrictionGroupCode
                       AND restrictionGroup.IsActive = 1
                    WHERE groupMember.ConsequenceId = consequence.ConsequenceId
                ) AS dailyLimit
            `
            : `
                OUTER APPLY
                (
                    SELECT CONVERT(int, NULL) AS MaxAssignmentsPerStudentPerDate
                ) AS dailyLimit
            `;
        const result = await pool.request()
            .input('incidentTypeId', sql.Int, incidentTypeId)
            .input('classificationId', sql.Int, classificationId)
            .input('locationId', sql.Int, locationId)
            .input('incidentDate', sql.Date, incidentDate)
            .query(`
                SELECT consequence.ConsequenceId, consequence.ConsequenceName,
                       consequence.ConsequenceDescription, consequence.LegacyConsequenceId,
                       consequence.LegacyAllowsMultiplePerDay, consequence.LegacyLength,
                       consequence.LegacyProcessorRole, consequence.LegacyApprovalStatusKnown,
                       consequence.RequiresScheduledEndDate, consequence.EstimatedDurationDays,
                       consequence.RequiresApproval, consequence.ApprovalRoleRequired,
                       consequence.RequiresParentNotification,
                       workflow.RequiresApproval AS ApplicationRequiresApproval,
                       workflow.ApprovalRoleCode AS ApplicationApprovalRoleCode,
                       workflow.ProcessingRoleCode AS ApplicationProcessingRoleCode,
                       workflow.WorkflowDescription AS ApplicationWorkflowDescription,
                       COALESCE(dailyLimit.MaxAssignmentsPerStudentPerDate, 0) AS ApplicationMaxAssignmentsPerStudentPerDate,
                       CONVERT(bit, CASE WHEN dailyLimit.MaxAssignmentsPerStudentPerDate = 1 THEN 1 ELSE 0 END) AS ApplicationSinglePerDay,
                       COALESCE(JSON_QUERY((
                           SELECT template.LegacyCommunicationTemplateId AS TemplateId,
                                  template.TemplateDescription AS Description,
                                  template.TemplateSubject AS Subject,
                                  template.EventType,
                                  (
                                      SELECT STRING_AGG(recipient.RoleName, N', ')
                                      FROM
                                      (
                                          SELECT DISTINCT recipientRole.RoleName
                                          FROM (VALUES
                                              (CASE WHEN template.SendToStudent = 1 THEN N'Student' END),
                                              (CASE WHEN template.SendToParent = 1 THEN N'Parent/Guardian' END),
                                              (CASE WHEN template.SendToPastoralCareTeacher = 1 THEN N'Pastoral Care Teacher' END),
                                              (CASE WHEN template.SendToHeadOfHouse = 1 THEN N'Head of House' END),
                                              (CASE WHEN template.SendToDeputyPrincipal = 1 THEN N'Deputy Principal' END)
                                          ) AS recipientRole(RoleName)
                                          WHERE recipientRole.RoleName IS NOT NULL
                                      ) AS recipient
                                  ) AS RecipientRoles
                           FROM wellbeing.LegacyConsequenceCommunicationTemplate AS template
                           WHERE template.LegacyConsequenceId = consequence.LegacyConsequenceId
                           FOR JSON PATH
                       )), N'[]') AS CommunicationTemplatesJson,
                       COALESCE(JSON_QUERY((
                           SELECT allowedDay.LegacyDay, allowedDay.LegacyYearLevel,
                                  allowedDay.IsAllowed, allowedDay.IsCycleDay
                           FROM wellbeing.ConsequenceAllowedDay AS allowedDay
                           WHERE allowedDay.ConsequenceId = consequence.ConsequenceId
                           FOR JSON PATH
                       )), N'[]') AS AllowedDayRulesJson,
                       COALESCE(JSON_QUERY((
                           SELECT allowedYearLevel.YearLevel
                           FROM wellbeing.ConsequenceAllowedYearLevel AS allowedYearLevel
                           WHERE allowedYearLevel.ConsequenceId = consequence.ConsequenceId
                           FOR JSON PATH
                       )), N'[]') AS AllowedYearLevelsJson
                FROM wellbeing.IncidentTypeConsequence AS mapping
                INNER JOIN wellbeing.tblConsequences AS consequence
                    ON consequence.ConsequenceId = mapping.ConsequenceId
                ${workflowApply}
                ${restrictionApply}
                INNER JOIN wellbeing.IncidentClassificationLocation AS locationMapping
                    ON locationMapping.ClassificationId = mapping.ClassificationId
                   AND locationMapping.LocationId = @locationId
                INNER JOIN wellbeing.IncidentTypeClassification AS typeMapping
                    ON typeMapping.ClassificationId = mapping.ClassificationId
                   AND typeMapping.IncidentTypeId = mapping.IncidentTypeId
                WHERE mapping.IncidentTypeId = @incidentTypeId
                  AND mapping.ClassificationId = @classificationId
                  AND consequence.IsActive = 1
                  AND
                  (
                      NOT EXISTS
                      (
                          SELECT 1
                          FROM wellbeing.IncidentDefinition AS configured
                          WHERE configured.ClassificationId = mapping.ClassificationId
                            AND configured.IncidentTypeId = mapping.IncidentTypeId
                            AND configured.IsActive = 1
                      )
                      OR EXISTS
                      (
                          SELECT 1
                          FROM wellbeing.IncidentDefinition AS configured
                          WHERE configured.ClassificationId = mapping.ClassificationId
                            AND configured.IncidentTypeId = mapping.IncidentTypeId
                            AND configured.IsActive = 1
                            AND configured.EffectiveStartDate <= @incidentDate
                            AND (configured.EffectiveEndDate IS NULL OR configured.EffectiveEndDate >= @incidentDate)
                            AND (configured.ApplicableLocationIds IS NULL
                                 OR N',' + REPLACE(configured.ApplicableLocationIds, N' ', N'') + N','
                                    LIKE N'%,' + CONVERT(NVARCHAR(20), @locationId) + N',%')
                      )
                  )
                ORDER BY consequence.DisplayOrder, consequence.ConsequenceName;
            `);
        const data = result.recordset.map(row => ({
            ...row,
            CommunicationTemplates: JSON.parse(row.CommunicationTemplatesJson),
            AllowedDayRules: JSON.parse(row.AllowedDayRulesJson),
            AllowedYearLevels: JSON.parse(row.AllowedYearLevelsJson)
        }));
        const configurationWarnings = [];
        if (!HasApplicationWorkflow) {
            configurationWarnings.push(
                'Application consequence workflows are not installed. Apply api/21_Consequence_Engine.sql to enable workflow-specific consequence rules.'
            );
        }
        if (!HasRestrictionGroups) {
            configurationWarnings.push(
                'Application consequence restriction groups are not installed. Apply api/21_Consequence_Engine.sql to enable cross-consequence daily limits.'
            );
        }
        res.json({ success: true, data, configurationWarnings });
    } catch (error) {
        console.error('Unable to load incident consequences:', error.message);
        res.status(500).json({ success: false, error: 'Unable to load incident consequences.' });
    }
});

app.use('/api/wellbeing/reference-data', legacyReferenceRouter);

const userGroupsRouter = express.Router();
userGroupsRouter.get('/', requireIncidentRole(['SUPER_USER']), async (_req, res) => {
    try {
        const pool = await getDatabasePool();
        const [staffResult, groupResult] = await Promise.all([
            pool.request().query(`
                SELECT staff.StaffKey, staff.Username,
                       LTRIM(RTRIM(CONCAT(staff.FirstName, N' ', staff.LastName))) AS DisplayName,
                       staff.EmailAddress,
                       COALESCE(manual.GroupCodes, N'') AS AssignedGroupCodes,
                       COALESCE(effective.GroupCodes, N'') AS EffectiveGroupCodes,
                       CONVERT(bit, CASE WHEN orgStaff.StaffKey IS NULL THEN 0 ELSE 1 END) AS IsOrgStaff
                FROM gold.dimStaff AS staff
                LEFT JOIN org.Staff AS orgStaff
                    ON orgStaff.MasterStaffKey = staff.StaffKey
                   AND orgStaff.IsActive = 1
                OUTER APPLY
                (
                    SELECT STRING_AGG(roles.RoleCode, N',') AS GroupCodes
                    FROM
                    (
                        SELECT DISTINCT role.RoleCode
                        FROM wellbeing.IncidentStaffRole AS assignment
                        INNER JOIN wellbeing.IncidentRole AS role
                            ON role.IncidentRoleId = assignment.IncidentRoleId
                        WHERE LOWER(assignment.StaffUsername) = LOWER(staff.Username)
                          AND assignment.IsActive = 1
                          AND role.IsActive = 1
                          AND assignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
                          AND (assignment.EffectiveTo IS NULL OR assignment.EffectiveTo >= CAST(GETDATE() AS DATE))
                          AND role.RoleCode IN (N'ADMINISTRATION', N'HEAD_OF_HOUSE', N'PASTORAL_CARE', N'REPORTING_STAFF')
                    ) AS roles
                ) AS manual
                OUTER APPLY
                (
                    SELECT STRING_AGG(roles.RoleCode, N',') AS GroupCodes
                    FROM
                    (
                        SELECT DISTINCT role.RoleCode
                        FROM wellbeing.IncidentStaffRole AS assignment
                        INNER JOIN wellbeing.IncidentRole AS role
                            ON role.IncidentRoleId = assignment.IncidentRoleId
                        WHERE LOWER(assignment.StaffUsername) = LOWER(staff.Username)
                          AND assignment.IsActive = 1
                          AND role.IsActive = 1
                          AND assignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
                          AND (assignment.EffectiveTo IS NULL OR assignment.EffectiveTo >= CAST(GETDATE() AS DATE))
                        UNION
                        SELECT N'REPORTING_STAFF' WHERE orgStaff.StaffKey IS NOT NULL
                        UNION
                        SELECT N'HEAD_OF_HOUSE'
                        FROM org.StaffHouseAssignment AS assignment
                        WHERE assignment.StaffKey = orgStaff.StaffKey
                          AND assignment.RoleCode = N'HEAD_OF_HOUSE'
                          AND assignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
                          AND (assignment.EffectiveTo IS NULL OR assignment.EffectiveTo >= CAST(GETDATE() AS DATE))
                        UNION
                        SELECT N'PASTORAL_CARE'
                        FROM org.StaffPastoralGroupAssignment AS assignment
                        WHERE assignment.StaffKey = orgStaff.StaffKey
                          AND assignment.RoleCode = N'PASTORAL_CARE_TEACHER'
                          AND assignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
                          AND (assignment.EffectiveTo IS NULL OR assignment.EffectiveTo >= CAST(GETDATE() AS DATE))
                    ) AS roles
                ) AS effective
                WHERE staff.IsCurrent = 1
                  AND staff.EffectiveFromUtc <= SYSUTCDATETIME()
                  AND (staff.EffectiveToUtc IS NULL OR staff.EffectiveToUtc >= SYSUTCDATETIME())
                  AND NULLIF(LTRIM(RTRIM(staff.Username)), N'') IS NOT NULL
                ORDER BY staff.LastName, staff.FirstName, staff.StaffKey;
            `),
            pool.request().query(`
                SELECT RoleCode AS GroupCode, RoleName AS GroupName
                FROM wellbeing.IncidentRole
                WHERE IsActive = 1
                  AND RoleCode IN (N'ADMINISTRATION', N'HEAD_OF_HOUSE', N'PASTORAL_CARE', N'REPORTING_STAFF')
                ORDER BY CASE RoleCode
                    WHEN N'ADMINISTRATION' THEN 1
                    WHEN N'HEAD_OF_HOUSE' THEN 2
                    WHEN N'PASTORAL_CARE' THEN 3
                    ELSE 4 END;
            `)
        ]);
        res.json({
            success: true,
            data: {
                groups: groupResult.recordset,
                users: staffResult.recordset.map(staff => ({
                    ...staff,
                    assignedGroups: staff.AssignedGroupCodes ? staff.AssignedGroupCodes.split(',') : [],
                    effectiveGroups: staff.EffectiveGroupCodes ? staff.EffectiveGroupCodes.split(',') : []
                }))
            }
        });
    } catch (error) {
        console.error('Unable to load user group management data:', error.message);
        res.status(500).json({ success: false, error: 'Unable to load users and groups.' });
    }
});

userGroupsRouter.put('/:staffKey', requireIncidentRole(['SUPER_USER']), async (req, res) => {
    const staffKey = Number(req.params.staffKey);
    const requestedGroups = req.body?.groups;
    if (!Number.isSafeInteger(staffKey) || staffKey < 1
        || !Array.isArray(requestedGroups)
        || requestedGroups.some(code => !manageableGroupCodes.includes(code))
        || new Set(requestedGroups).size !== requestedGroups.length) {
        return res.status(400).json({
            success: false,
            error: 'Provide a valid staff key and a unique groups array containing only Admin, Head of House, Pastoral Care, or Staff.'
        });
    }

    let transaction;
    try {
        const pool = await getDatabasePool();
        transaction = new sql.Transaction(pool);
        await transaction.begin(sql.ISOLATION_LEVEL.SERIALIZABLE);
        const staffResult = await transaction.request()
            .input('staffKey', sql.Int, staffKey)
            .query(`
                SELECT TOP (2) Username
                FROM gold.dimStaff WITH (UPDLOCK, HOLDLOCK)
                WHERE StaffKey = @staffKey
                  AND IsCurrent = 1
                  AND EffectiveFromUtc <= SYSUTCDATETIME()
                  AND (EffectiveToUtc IS NULL OR EffectiveToUtc >= SYSUTCDATETIME())
                  AND NULLIF(LTRIM(RTRIM(Username)), N'') IS NOT NULL;
            `);
        if (staffResult.recordset.length !== 1) {
            await transaction.rollback();
            return res.status(404).json({ success: false, error: 'The current staff record was not found or is ambiguous.' });
        }

        const username = staffResult.recordset[0].Username;
        const priorResult = await transaction.request()
            .input('username', sql.NVarChar(200), username)
            .query(`
                SELECT role.RoleCode
                FROM wellbeing.IncidentStaffRole AS assignment WITH (UPDLOCK, HOLDLOCK)
                INNER JOIN wellbeing.IncidentRole AS role
                    ON role.IncidentRoleId = assignment.IncidentRoleId
                WHERE LOWER(assignment.StaffUsername) = LOWER(@username)
                  AND assignment.IsActive = 1
                  AND assignment.EffectiveFrom <= CAST(GETDATE() AS DATE)
                  AND (assignment.EffectiveTo IS NULL OR assignment.EffectiveTo >= CAST(GETDATE() AS DATE))
                  AND role.RoleCode IN (N'ADMINISTRATION', N'HEAD_OF_HOUSE', N'PASTORAL_CARE', N'REPORTING_STAFF');
            `);
        const previousGroups = priorResult.recordset.map(row => row.RoleCode);
        const beforeJson = JSON.stringify({ groups: previousGroups });
        const today = new Date();
        const todayIso = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

        for (const groupCode of manageableGroupCodes) {
            const roleResult = await transaction.request()
                .input('RoleCode', sql.NVarChar(50), groupCode)
                .query('SELECT IncidentRoleId FROM wellbeing.IncidentRole WHERE RoleCode = @RoleCode AND IsActive = 1;');
            if (!roleResult.recordset.length) {
                throw new Error(`The configured ${groupCode} group is missing from wellbeing.IncidentRole.`);
            }
            const roleId = roleResult.recordset[0].IncidentRoleId;
            if (requestedGroups.includes(groupCode)) {
                await transaction.request()
                    .input('username', sql.NVarChar(200), username)
                    .input('roleId', sql.Int, roleId)
                    .input('actor', sql.NVarChar(200), req.incidentPrincipal.username)
                    .query(`
                        IF NOT EXISTS
                        (
                            SELECT 1 FROM wellbeing.IncidentStaffRole WITH (UPDLOCK, HOLDLOCK)
                            WHERE LOWER(StaffUsername) = LOWER(@username)
                              AND IncidentRoleId = @roleId
                              AND IsActive = 1
                              AND EffectiveFrom <= CAST(GETDATE() AS DATE)
                              AND (EffectiveTo IS NULL OR EffectiveTo >= CAST(GETDATE() AS DATE))
                        )
                            INSERT INTO wellbeing.IncidentStaffRole
                                (StaffUsername, IncidentRoleId, EffectiveFrom, IsActive, CreatedBy)
                            VALUES (@username, @roleId, CAST(GETDATE() AS DATE), 1, @actor);
                    `);
            } else {
                await transaction.request()
                    .input('username', sql.NVarChar(200), username)
                    .input('roleId', sql.Int, roleId)
                    .input('effectiveTo', sql.Date, todayIso)
                    .query(`
                        UPDATE wellbeing.IncidentStaffRole
                        SET IsActive = 0, EffectiveTo = @effectiveTo
                        WHERE LOWER(StaffUsername) = LOWER(@username)
                          AND IncidentRoleId = @roleId
                          AND IsActive = 1
                          AND EffectiveFrom <= @effectiveTo
                          AND (EffectiveTo IS NULL OR EffectiveTo >= @effectiveTo);
                    `);
            }
        }

        await transaction.request()
            .input('Actor', sql.NVarChar(255), req.incidentPrincipal.username)
            .input('Action', sql.NVarChar(50), 'UPDATE_GROUPS')
            .input('EntityName', sql.NVarChar(100), 'StaffGroupMembership')
            .input('EntityId', sql.NVarChar(100), String(staffKey))
            .input('BeforeJson', sql.NVarChar(sql.MAX), beforeJson)
            .input('AfterJson', sql.NVarChar(sql.MAX), JSON.stringify({ groups: requestedGroups }))
            .input('CorrelationId', sql.NVarChar(100), req.get('x-correlation-id') || null)
            .input('IpAddress', sql.NVarChar(50), req.ip || null)
            .query(`
                INSERT INTO wellbeing.AuditEvent
                    (Actor, Action, EntityName, EntityId, BeforeJson, AfterJson, CorrelationId, IpAddress)
                VALUES
                    (@Actor, @Action, @EntityName, @EntityId, @BeforeJson, @AfterJson, @CorrelationId, @IpAddress);
            `);
        await transaction.commit();
        res.json({ success: true, data: { StaffKey: staffKey, Username: username, assignedGroups: requestedGroups } });
    } catch (error) {
        if (transaction) {
            try {
                await transaction.rollback();
            } catch (rollbackError) {
                console.error('User group update rollback failed:', rollbackError.message);
            }
        }
        console.error('Unable to update staff group memberships:', error.message);
        res.status(500).json({ success: false, error: 'Unable to update group memberships.' });
    }
});

app.use('/api/admin/user-groups', userGroupsRouter);
app.use('/api/admin/config', adminConfigRouter);
app.use('/api/wellbeing', adminConfigRouter);

// ---------------------------------------------------------
// LOGGING MIDDLEWARE
// ---------------------------------------------------------

app.use((req, res, next) => {
    console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
    next();
});

// ---------------------------------------------------------
// HEALTH CHECK
// ---------------------------------------------------------

app.get('/api/health', async (req, res) => {
    try {
        const pool = await getDatabasePool();

        // Test database connectivity
        await pool.request().query('SELECT 1 AS DatabaseConnected');

        res.json({
            status: 'OK',
            database: SQL_DATABASE,
            connected: true,
            timestamp: new Date().toISOString(),
            message: 'Student Wellbeing API is running'
        });
    } catch (error) {
        console.error('❌ Health check failed:', error.message);

        res.status(500).json({
            status: 'ERROR',
            connected: false,
            error: error.message
        });
    }
});

// ---------------------------------------------------------
// INCIDENTS ENDPOINTS
// ---------------------------------------------------------

const incidentsRouter = express.Router();

function validSqlDate(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        return false;
    }
    const parsed = new Date(`${value}T00:00:00Z`);
    return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().slice(0, 10) === value;
}

function consequenceError(res, error, operation) {
    console.error(`Unable to ${operation}:`, error.message);
    const number = Number(error.number);
    const status = number === 51201 || number === 51210 ? 404
        : [51200, 51202, 51203].includes(number) ? 400
            : [51205, 51207, 51211, 51212, 51213, 51214, 51215].includes(number) ? 409
                : number === 51206 ? 422 : 500;
    res.status(status).json({
        success: false,
        error: status === 500 ? 'The consequence operation could not be completed.' : error.message
    });
}

incidentsRouter.get('/:id/consequences/eligible', requireIncidentRole(incidentRoles.read), async (req, res) => {
    const incidentId = Number(req.params.id);
    const studentKey = Number(req.query.studentKey);
    const proposedDate = String(req.query.proposedDate || '');
    if (!Number.isInteger(incidentId) || incidentId < 1
        || !Number.isInteger(studentKey) || studentKey < 1
        || !validSqlDate(proposedDate)) {
        return res.status(400).json({
            success: false,
            error: 'incidentId, studentKey, and proposedDate (YYYY-MM-DD) are required and must be valid.'
        });
    }
    try {
        const pool = await getDatabasePool();
        const incident = await pool.request()
            .input('IncidentId', sql.Int, incidentId)
            .query(`
                SELECT IncidentId
                FROM wellbeing.factBehaviourIncident
                WHERE IncidentId = @IncidentId;
            `);
        if (!incident.recordset.length) {
            return res.status(404).json({ success: false, error: 'Incident was not found.' });
        }
        const yearLevelSnapshot = req.incidentPrincipal.roles.some(role =>
            incidentRoles.create.includes(role)
        ) ? await verifyCurrentStudentYearLevel(pool, req, incidentId, studentKey) : null;
        const result = await pool.request()
            .input('IncidentId', sql.Int, incidentId)
            .input('StudentKey', sql.Int, studentKey)
            .input('ProposedDate', sql.Date, proposedDate)
            .execute('wellbeing.usp_GetEligibleIncidentConsequences');
        res.json({
            success: true,
            data: result.recordset,
            yearLevelSnapshot: yearLevelSnapshot?.recordset[0] || null
        });
    } catch (error) {
        consequenceError(res, error, 'load eligible consequences');
    }
});

incidentsRouter.get('/:id/consequences', requireIncidentRole(incidentRoles.read), async (req, res) => {
    const incidentId = Number(req.params.id);
    if (!Number.isInteger(incidentId) || incidentId < 1) {
        return res.status(400).json({ success: false, error: 'A valid incident identifier is required.' });
    }
    try {
        const pool = await getDatabasePool();
        const incident = await pool.request()
            .input('IncidentId', sql.Int, incidentId)
            .query(`
                SELECT IncidentId
                FROM wellbeing.factBehaviourIncident
                WHERE IncidentId = @IncidentId;
            `);
        if (!incident.recordset.length) {
            return res.status(404).json({ success: false, error: 'Incident was not found.' });
        }
        const result = await pool.request()
            .input('IncidentId', sql.Int, incidentId)
            .query(`
                SELECT assignment.ConsequenceAssignmentId, assignment.IncidentId, assignment.StudentKey,
                       assignment.ConsequenceId, consequence.ConsequenceName,
                       consequence.ConsequenceDescription, assignment.ScheduledStartDate,
                       assignment.ProcessingStatus, assignment.RequiresApproval,
                       assignment.ApprovalConfigurationKnown, assignment.AssignedRoleCode,
                       assignment.AssignedStaffKey, assignment.RoleResolutionStatus,
                       assignment.StudentYearLevelAtIncident, assignment.RuleVersion,
                       assignment.CreatedDate, assignment.CreatedBy, assignment.ModifiedDate,
                       assignment.ModifiedBy
                FROM wellbeing.factConsequenceAssignment AS assignment
                INNER JOIN wellbeing.tblConsequences AS consequence
                    ON consequence.ConsequenceId = assignment.ConsequenceId
                WHERE assignment.IncidentId = @IncidentId
                ORDER BY assignment.CreatedDate DESC, assignment.ConsequenceAssignmentId DESC;
            `);
        res.json({ success: true, data: result.recordset });
    } catch (error) {
        consequenceError(res, error, 'load incident consequences');
    }
});

incidentsRouter.post('/:id/consequences', requireIncidentRole(incidentRoles.create), async (req, res) => {
    const incidentId = Number(req.params.id);
    const { studentKey, consequenceId, scheduledStartDate, scheduledEndDate, assignmentReason } = req.body || {};
    const student = Number(studentKey);
    const consequence = Number(consequenceId);
    const idempotencyKey = String(req.get('Idempotency-Key') || '');
    if (!Number.isInteger(incidentId) || incidentId < 1
        || !Number.isInteger(student) || student < 1
        || !Number.isInteger(consequence) || consequence < 1
        || !validSqlDate(scheduledStartDate)
        || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(idempotencyKey)
        || (assignmentReason !== undefined && assignmentReason !== null
            && (typeof assignmentReason !== 'string' || assignmentReason.length > 1000))) {
        return res.status(400).json({
            success: false,
        error: 'Provide valid studentKey, consequenceId, scheduledStartDate, an optional scheduledEndDate and assignmentReason (max 1000 characters), and an Idempotency-Key UUID.'
        });
    }
    if (scheduledEndDate !== undefined && scheduledEndDate !== null && scheduledEndDate !== ''
        && (!validSqlDate(scheduledEndDate) || scheduledEndDate < scheduledStartDate)) {
        return res.status(400).json({ success: false, error: 'scheduledEndDate must be a valid date on or after scheduledStartDate.' });
    }

    let transaction;
    try {
        const pool = await getDatabasePool();
        const consequenceConfig = await pool.request()
        .input('ConsequenceId', sql.Int, consequence)
        .query(`
            SELECT RequiresScheduledEndDate
            FROM wellbeing.tblConsequences
            WHERE ConsequenceId = @ConsequenceId
              AND IsActive = 1;
        `);
        if (!consequenceConfig.recordset.length) {
        return res.status(400).json({ success: false, error: 'The selected consequence is inactive or invalid.' });
        }
        if (consequenceConfig.recordset[0].RequiresScheduledEndDate && !scheduledEndDate) {
        return res.status(400).json({ success: false, error: 'An end date is required for the selected consequence.' });
        }

        await verifyCurrentStudentYearLevel(pool, req, incidentId, student);
        transaction = new sql.Transaction(pool);
        await transaction.begin(sql.ISOLATION_LEVEL.SERIALIZABLE);
        const result = await transaction.request()
        .input('IncidentId', sql.Int, incidentId)
        .input('StudentKey', sql.Int, student)
        .input('ConsequenceId', sql.Int, consequence)
            .input('ScheduledStartDate', sql.Date, scheduledStartDate)
            .input('AssigningStaffKey', sql.Int, req.incidentPrincipal.staffKey)
            .input('Actor', sql.NVarChar(255), req.incidentPrincipal.username)
            .input('AssignmentReason', sql.NVarChar(1000), assignmentReason || null)
            .input('IdempotencyKey', sql.UniqueIdentifier, idempotencyKey)
            .execute('wellbeing.usp_AssignIncidentConsequence');
        const assignment = result.recordset[0];
        const existingAssignment = await transaction.request()
            .input('ConsequenceAssignmentId', sql.Int, assignment.ConsequenceAssignmentId)
            .query(`
                SELECT ScheduledEndDate
                FROM wellbeing.factConsequenceAssignment
                WHERE ConsequenceAssignmentId = @ConsequenceAssignmentId;
            `);
        const existingEndDate = existingAssignment.recordset[0]?.ScheduledEndDate
            ? new Date(existingAssignment.recordset[0].ScheduledEndDate).toISOString().slice(0, 10)
            : null;
        const requestedEndDate = scheduledEndDate || null;
        if (assignment?.DuplicateSubmission && existingEndDate !== requestedEndDate) {
            await transaction.rollback();
            return res.status(409).json({
                success: false,
                error: 'This Idempotency-Key was already used with a different consequence end date.'
            });
        }
        if (scheduledEndDate) {
            await transaction.request()
                .input('ConsequenceAssignmentId', sql.Int, assignment.ConsequenceAssignmentId)
                .input('ScheduledEndDate', sql.Date, scheduledEndDate)
                .input('EndDateJson', sql.NVarChar(10), scheduledEndDate)
                .input('Actor', sql.NVarChar(255), req.incidentPrincipal.username)
                .query(`
                    UPDATE wellbeing.factConsequenceAssignment
                    SET ScheduledEndDate = @ScheduledEndDate,
                        RulesAppliedJson = CASE
                            WHEN ISJSON(RulesAppliedJson) = 1
                                THEN JSON_MODIFY(RulesAppliedJson, '$.scheduledEndDate', @EndDateJson)
                            ELSE RulesAppliedJson
                        END,
                        ModifiedDate = SYSUTCDATETIME(),
                        ModifiedBy = @Actor
                    WHERE ConsequenceAssignmentId = @ConsequenceAssignmentId;
                `);
        }
        const savedAssignment = await transaction.request()
            .input('ConsequenceAssignmentId', sql.Int, assignment.ConsequenceAssignmentId)
            .query(`
                SELECT assignment.ConsequenceAssignmentId, assignment.IncidentId, assignment.StudentKey,
                       assignment.ConsequenceId, consequence.ConsequenceName,
                       consequence.ConsequenceDescription, assignment.ScheduledStartDate,
                       assignment.ScheduledEndDate, assignment.ProcessingStatus,
                       assignment.RequiresApproval, assignment.ApprovalConfigurationKnown,
                       assignment.AssignedRoleCode, assignment.AssignedStaffKey,
                       assignment.RoleResolutionStatus, assignment.StudentYearLevelAtIncident,
                       assignment.RuleVersion, assignment.CreatedDate, assignment.CreatedBy
                FROM wellbeing.factConsequenceAssignment AS assignment
                INNER JOIN wellbeing.tblConsequences AS consequence
                    ON consequence.ConsequenceId = assignment.ConsequenceId
                WHERE assignment.ConsequenceAssignmentId = @ConsequenceAssignmentId;
            `);
        await transaction.commit();
        res.status(assignment?.DuplicateSubmission ? 200 : 201).json({
            success: true,
            data: savedAssignment.recordset[0],
            duplicateSubmission: Boolean(assignment?.DuplicateSubmission)
        });
    } catch (error) {
        if (transaction) {
            try {
                await transaction.rollback();
            } catch (rollbackError) {
                console.error('Consequence assignment rollback failed:', rollbackError.message);
            }
        }
        consequenceError(res, error, 'assign incident consequence');
    }
});

const consequenceWorkflowRoles = [
    'HEAD_OF_HOUSE', 'PASTORAL_CARE', 'DEPUTY_PRINCIPAL',
    'ADMINISTRATION', 'AUTHORIZED_APPROVER'
];
const consequenceWorkflowRouter = express.Router();

consequenceWorkflowRouter.get('/work-queue', requireIncidentRole(incidentRoles.read), async (req, res) => {
    try {
        const pool = await getDatabasePool();
        const result = await pool.request()
            .input('RoleCodes', sql.NVarChar(sql.MAX), req.incidentPrincipal.roles.join(','))
            .input('StaffKey', sql.Int, req.incidentPrincipal.staffKey)
            .query(`
                SELECT notification.ConsequenceWorkflowNotificationId,
                       notification.RoleCode, notification.NotificationType,
                       notification.Channel, notification.CreatedDate,
                       assignment.ConsequenceAssignmentId, assignment.IncidentId,
                       assignment.StudentKey, assignment.ConsequenceId,
                       consequence.ConsequenceName, assignment.ScheduledStartDate,
                       assignment.ScheduledEndDate, assignment.ProcessingStatus,
                       assignment.AssignedStaffKey, assignment.RoleResolutionStatus
                FROM wellbeing.ConsequenceWorkflowNotification AS notification
                INNER JOIN wellbeing.factConsequenceAssignment AS assignment
                    ON assignment.ConsequenceAssignmentId = notification.ConsequenceAssignmentId
                INNER JOIN wellbeing.tblConsequences AS consequence
                    ON consequence.ConsequenceId = assignment.ConsequenceId
                WHERE notification.RoleCode IN
                    (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@RoleCodes, N','))
                  AND (assignment.AssignedStaffKey IS NULL OR assignment.AssignedStaffKey = @StaffKey)
                  AND assignment.ProcessingStatus IN
                      (N'AWAITING_APPROVAL', N'AWAITING_REVIEW', N'APPROVED', N'SCHEDULED', N'PROCESSING')
                ORDER BY notification.CreatedDate, notification.ConsequenceWorkflowNotificationId;
            `);
        res.json({ success: true, data: result.recordset });
    } catch (error) {
        consequenceError(res, error, 'load consequence workflow queue');
    }
});

consequenceWorkflowRouter.get('/:assignmentId/audit', requireIncidentRole(incidentRoles.read), async (req, res) => {
    const assignmentId = Number(req.params.assignmentId);
    if (!Number.isInteger(assignmentId) || assignmentId < 1) {
        return res.status(400).json({ success: false, error: 'A valid consequence assignment identifier is required.' });
    }
    try {
        const pool = await getDatabasePool();
        const result = await pool.request()
            .input('AssignmentId', sql.Int, assignmentId)
            .query(`
                SELECT ConsequenceDecisionAuditId, ConsequenceAssignmentId, IncidentId,
                       StudentKey, StudentYearLevelAtIncident, ConsequenceId, Decision,
                       RulesAppliedJson, AssignedRoleCode, AssignedStaffKey, Actor,
                       EventDate, Notes
                FROM wellbeing.ConsequenceDecisionAudit
                WHERE ConsequenceAssignmentId = @AssignmentId
                ORDER BY EventDate DESC, ConsequenceDecisionAuditId DESC;
            `);
        if (!result.recordset.length) {
            const assignment = await pool.request()
                .input('AssignmentId', sql.Int, assignmentId)
                .query(`
                    SELECT ConsequenceAssignmentId
                    FROM wellbeing.factConsequenceAssignment
                    WHERE ConsequenceAssignmentId = @AssignmentId;
                `);
            if (!assignment.recordset.length) {
                return res.status(404).json({ success: false, error: 'Consequence assignment was not found.' });
            }
            return res.json({ success: true, data: [] });
        }
        res.json({ success: true, data: result.recordset });
    } catch (error) {
        consequenceError(res, error, 'load consequence audit history');
    }
});

for (const action of ['approve', 'reject', 'complete', 'cancel']) {
    consequenceWorkflowRouter.post(
        `/:assignmentId/${action}`,
        requireIncidentRole(action === 'cancel'
            ? [...incidentRoles.cancel, ...consequenceWorkflowRoles]
            : action === 'complete'
                ? [...consequenceWorkflowRoles, 'REPORTING_STAFF']
                : consequenceWorkflowRoles),
        async (req, res) => {
            const assignmentId = Number(req.params.assignmentId);
            const notes = req.body?.notes;
            if (!Number.isInteger(assignmentId) || assignmentId < 1
                || (notes !== undefined && notes !== null
                    && (typeof notes !== 'string' || notes.length > 1000))) {
                return res.status(400).json({
                    success: false,
                    error: 'A valid assignment identifier and optional notes (max 1000 characters) are required.'
                });
            }
            try {
                const pool = await getDatabasePool();
                const assignmentResult = await pool.request()
                    .input('AssignmentId', sql.Int, assignmentId)
                    .query(`
                        SELECT IncidentId, AssignedRoleCode, AssignedStaffKey, AssigningStaffKey
                        FROM wellbeing.factConsequenceAssignment
                        WHERE ConsequenceAssignmentId = @AssignmentId;
                    `);
                const assignment = assignmentResult.recordset[0];
                if (!assignment) {
                    return res.status(404).json({ success: false, error: 'Consequence assignment was not found.' });
                }
                const roles = req.incidentPrincipal.roles;
                const isAdmin = roles.includes('ADMINISTRATION');
                const hasAssignedRole = assignment.AssignedRoleCode
                    && roles.includes(assignment.AssignedRoleCode);
                const isAssignedStaff = Number(assignment.AssignedStaffKey) === Number(req.incidentPrincipal.staffKey);
                const isReporter = Number(assignment.AssigningStaffKey) === Number(req.incidentPrincipal.staffKey);
                const authorized = isAdmin
                    || (['approve', 'reject'].includes(action)
                        && (roles.includes('AUTHORIZED_APPROVER') || hasAssignedRole))
                    || (action === 'complete' && (isAssignedStaff || hasAssignedRole))
                    || (action === 'cancel' && isReporter);
                if (!authorized) {
                    return res.status(403).json({
                        success: false,
                        error: 'Your assigned role does not authorize this consequence workflow action.'
                    });
                }
                const result = await pool.request()
                    .input('ConsequenceAssignmentId', sql.Int, assignmentId)
                    .input('Action', sql.NVarChar(20), action.toUpperCase())
                    .input('Actor', sql.NVarChar(255), req.incidentPrincipal.username)
                    .input('ActorStaffKey', sql.Int, req.incidentPrincipal.staffKey)
                    .input('Notes', sql.NVarChar(1000), notes || null)
                    .execute('wellbeing.usp_TransitionIncidentConsequence');
                res.json({ success: true, data: result.recordset[0] });
            } catch (error) {
                consequenceError(res, error, `${action} consequence assignment`);
            }
        }
    );
}

app.use('/api/consequences', consequenceWorkflowRouter);

// GET all incidents with pagination and filters
incidentsRouter.get('/', requireIncidentRole(incidentRoles.read), async (req, res) => {
    try {
        const page = Math.max(1, parseInt(req.query.page) || 1);
        const limit = Math.min(100, Math.max(1, parseInt(req.query.limit) || 10));
        const offset = (page - 1) * limit;
        const sortColumns = {
            IncidentId: 'IncidentId',
            IncidentNumber: 'IncidentNumber',
            StudentName: 'StudentName',
            ReportingStaffName: 'ReportingStaffName',
            ReceivingStaffName: 'ReceivingStaffName',
            LocationName: 'LocationName',
            IncidentTypeName: 'IncidentTypeName',
            ClassificationName: 'ClassificationName',
            LegacyIncidentLevel: 'LegacyIncidentLevel',
            PolicyLevelName: 'PolicyLevelName',
            IncidentStatusName: 'IncidentStatusName',
            IncidentDate: 'IncidentDate',
            StudentYearLevelsAtIncident: 'StudentYearLevelsAtIncident',
            IncidentTime: 'IncidentTime',
            IncidentSummary: 'IncidentSummary',
            CreatedDate: 'CreatedDate',
            ModifiedDate: 'ModifiedDate'
        };
        const sortColumn = sortColumns[String(req.query.sortBy)] || 'IncidentDate';
        const sortDirection = String(req.query.sortDirection).toLowerCase() === 'asc' ? 'ASC' : 'DESC';

        const pool = await getDatabasePool();
        const request = pool.request()
            .input('campusName', sql.NVarChar(150), 'BlendED - By Saints College');
        const filters = ['CampusName = @campusName'];

        for (const [parameter, column] of [
            ['classificationId', 'ClassificationId'],
            ['locationId', 'LocationId'],
            ['incidentTypeId', 'IncidentTypeId']
        ]) {
            if (req.query[parameter] !== undefined && req.query[parameter] !== '') {
                const value = Number(req.query[parameter]);
                if (!Number.isInteger(value) || value < 1) {
                    return res.status(400).json({ success: false, error: `${parameter} must be a positive integer.` });
                }
                request.input(parameter, sql.Int, value);
                filters.push(`${column} = @${parameter}`);
            }
        }
        if (req.query.studentKey) {
            const studentKey = Number(req.query.studentKey);
            if (!Number.isInteger(studentKey) || studentKey < 1) {
                return res.status(400).json({ success: false, error: 'studentKey must be a positive integer.' });
            }
            request.input('studentKey', sql.Int, studentKey);
            filters.push(`EXISTS (
                SELECT 1 FROM wellbeing.IncidentStudent AS studentLink
                WHERE studentLink.IncidentId = vwIncidentDirectory.IncidentId
                  AND studentLink.StudentKey = @studentKey
            )`);
        }
        for (const [parameter, operator] of [['startDate', '>='], ['endDate', '<=']]) {
            const date = req.query[parameter];
            if (date) {
                const valid = /^\d{4}-\d{2}-\d{2}$/.test(String(date))
                    && !Number.isNaN(Date.parse(`${date}T00:00:00Z`))
                    && new Date(`${date}T00:00:00Z`).toISOString().slice(0, 10) === date;
                if (!valid) {
                    return res.status(400).json({ success: false, error: `${parameter} must be a valid YYYY-MM-DD date.` });
                }
                request.input(parameter, sql.Date, new Date(`${date}T00:00:00Z`));
                filters.push(`IncidentDate ${operator} @${parameter}`);
            }
        }
        if (req.query.startDate && req.query.endDate && req.query.startDate > req.query.endDate) {
            return res.status(400).json({ success: false, error: 'startDate cannot be after endDate.' });
        }
        if (req.query.yearLevelAtIncident) {
            request.input('yearLevelAtIncident', sql.NVarChar(50), String(req.query.yearLevelAtIncident).trim());
            filters.push(`EXISTS (
                SELECT 1 FROM wellbeing.IncidentStudent AS studentLink
                WHERE studentLink.IncidentId = vwIncidentDirectory.IncidentId
                  AND studentLink.StudentYearLevelAtIncident = @yearLevelAtIncident
            )`);
        }
        if (req.query.scope === 'mine') {
            request.input('myStaffKey', sql.Int, req.incidentPrincipal.staffKey);
            filters.push('ReportingStaffKey = @myStaffKey');
        } else if (req.query.scope === 'current') {
            filters.push(`IncidentStatusName IN (N'Draft', N'Active', N'Open', N'Investigating')`);
        } else if (req.query.scope === 'past') {
            filters.push(`IncidentStatusName NOT IN (N'Draft', N'Active', N'Open', N'Investigating')`);
        } else if (req.query.scope && req.query.scope !== 'all') {
            return res.status(400).json({ success: false, error: 'scope must be one of all, mine, current, or past.' });
        }
        if (req.query.type) {
            request.input('incidentTypeName', sql.NVarChar(100), `%${String(req.query.type).trim()}%`);
            filters.push('IncidentTypeName LIKE @incidentTypeName');
        }
        if (req.query.status) {
            request.input('incidentStatusName', sql.NVarChar(100), String(req.query.status));
            filters.push('IncidentStatusName = @incidentStatusName');
        }
        if (req.query.priority) {
            request.input('policyLevelName', sql.NVarChar(100), String(req.query.priority));
            filters.push('(PolicyLevelName = @policyLevelName OR CONVERT(NVARCHAR(20), LegacyIncidentLevel) = @policyLevelName)');
        }
        if (req.query.search) {
            request.input('search', sql.NVarChar(200), `%${String(req.query.search).trim()}%`);
            filters.push(`(
                StudentName LIKE @search OR
                StudentCode LIKE @search OR
                IncidentNumber LIKE @search OR
                IncidentSummary LIKE @search OR
                ReportingStaffName LIKE @search
            )`);
        }
        const whereClause = filters.join(' AND ');

        // Get total count
        const countResult = await request.query(`
            SELECT COUNT(*) AS total
            FROM wellbeing.vwIncidentDirectory AS vwIncidentDirectory
            WHERE ${whereClause}
        `);
        const total = countResult.recordset[0].total;

        // Get paginated data
        const result = await request.query(`
            SELECT *
            FROM wellbeing.vwIncidentDirectory AS vwIncidentDirectory
            WHERE ${whereClause}
            ORDER BY ${sortColumn} ${sortDirection}, IncidentId DESC
            OFFSET ${offset} ROWS
            FETCH NEXT ${limit} ROWS ONLY
        `);

        res.json({
            success: true,
            data: result.recordset,
            pagination: {
                page,
                limit,
                total,
                pages: Math.ceil(total / limit)
            }
        });
    } catch (error) {
        console.error('❌ Error fetching incidents:', error.message);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// GET incident by ID
incidentsRouter.get('/:id/audit', requireIncidentRole(incidentRoles.read), async (req, res) => {
    const incidentId = Number(req.params.id);
    if (!Number.isInteger(incidentId) || incidentId < 1) {
        return res.status(400).json({ success: false, error: 'Incident id must be a positive integer.' });
    }
    try {
        const page = Math.max(1, Number(req.query.page) || 1);
        const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 25));
        const pool = await getDatabasePool();
        const result = await pool.request()
            .input('EntityId', sql.NVarChar(100), String(incidentId))
            .input('offset', sql.Int, (page - 1) * limit)
            .input('limit', sql.Int, limit)
            .query(`
                SELECT AuditEventId, EventDate, Actor, Action, BeforeJson, AfterJson,
                       CorrelationId, IpAddress
                FROM wellbeing.AuditEvent
                WHERE EntityName = N'Incident' AND EntityId = @EntityId
                ORDER BY EventDate DESC, AuditEventId DESC
                OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;
            `);
        res.json({ success: true, data: result.recordset, pagination: { page, limit } });
    } catch (error) {
        console.error('Unable to fetch incident audit history:', error.message);
        res.status(500).json({ success: false, error: 'Unable to load incident audit history.' });
    }
});

incidentsRouter.get('/:id', requireIncidentRole(incidentRoles.read), async (req, res) => {
    try {
        const incidentId = parseInt(req.params.id);
        if (!Number.isInteger(incidentId) || incidentId < 1) {
            return res.status(400).json({ success: false, error: 'Incident id must be a positive integer.' });
        }
        const pool = await getDatabasePool();

        const result = await pool.request()
            .input('incidentID', sql.Int, incidentId)
            .query(`
                SELECT *
                FROM wellbeing.vwIncidentDirectory AS vwIncidentDirectory
                WHERE IncidentId = @incidentID
            `);

        if (result.recordset.length === 0) {
            return res.status(404).json({
                success: false,
                error: 'Incident not found'
            });
        }

        const students = await pool.request()
            .input('incidentID', sql.Int, incidentId)
            .query(`
                SELECT StudentKey, IsPrimary, StudentNameAtIncident, StudentNameSnapshotStatus,
                       StudentYearLevelIdAtIncident, StudentYearLevelAtIncident,
                       StudentClassAtIncident, YearLevelResolutionStatus
                FROM wellbeing.IncidentStudent
                WHERE IncidentId = @incidentID
                ORDER BY IsPrimary DESC, StudentKey;
            `);
        res.json({
            success: true,
            data: {
                ...result.recordset[0],
                StudentKeys: students.recordset.map(row => row.StudentKey),
                StudentSnapshots: students.recordset
            }
        });
    } catch (error) {
        console.error('❌ Error fetching incident:', error.message);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// POST create new incident
incidentsRouter.post('/', requireIncidentRole(incidentRoles.create), async (req, res) => {
    let transaction;
    let transactionCommitted = false;
    try {
        const {
            studentKey: studentIdentifier,
            studentKeys,
            incidentDate,
            incidentTime,
            incidentTypeId,
            classificationId,
            locationId,
            reportingStaffKey: staffIdentifier,
            receivingStaffKey,
            incidentSummary,
            detailedDescription,
            followUpNotes,
            severityIndicators
        } = req.body;
        const requestedStudentIdentifiers = Array.isArray(studentKeys) && studentKeys.length
            ? [...new Set(studentKeys.map(value => String(value).trim()).filter(Boolean))]
            : studentIdentifier === undefined || studentIdentifier === null
                ? []
                : [String(studentIdentifier).trim()];
        const idempotencyKey = req.get('Idempotency-Key') || req.body.idempotencyKey;
        const isUuid = typeof idempotencyKey === 'string'
            && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(idempotencyKey);
        const validDate = typeof incidentDate === 'string'
            && /^\d{4}-\d{2}-\d{2}$/.test(incidentDate)
            && !Number.isNaN(Date.parse(`${incidentDate}T00:00:00Z`))
            && new Date(`${incidentDate}T00:00:00Z`).toISOString().slice(0, 10) === incidentDate;

        const missingFields = [
            ['studentKeys', requestedStudentIdentifiers.length ? requestedStudentIdentifiers : null],
            ['incidentDate', incidentDate],
            ['incidentTime', incidentTime],
            ['incidentTypeId', incidentTypeId],
            ['classificationId', classificationId],
            ['locationId', locationId],
            ['reportingStaffKey', staffIdentifier],
            ['incidentSummary', incidentSummary],
            ['detailedDescription', detailedDescription]
        ].filter(([, value]) => value === undefined || value === null || value === '' || (typeof value === 'number' && !Number.isFinite(value)))
            .map(([name]) => name);

        if (missingFields.length) {
            return res.status(400).json({
                success: false,
                error: `Missing required fields: ${missingFields.join(', ')}`
            });
        }
        if (incidentDate && !validDate) {
            return res.status(400).json({ success: false, error: 'incidentDate must be a valid ISO date in YYYY-MM-DD format.' });
        }
        if (incidentDate) {
            const futureIncidentDate = await (await getDatabasePool()).request()
                .input('IncidentDate', sql.Date, new Date(incidentDate))
                .query('SELECT CASE WHEN @IncidentDate > CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END AS IsFutureDate;');
            if (futureIncidentDate.recordset[0]?.IsFutureDate) {
                return res.status(400).json({ success: false, error: 'Incident date cannot be in the future.' });
            }
        }
        if (typeof incidentSummary !== 'string' || !incidentSummary.trim()
            || typeof detailedDescription !== 'string' || !detailedDescription.trim()) {
            return res.status(400).json({ success: false, error: 'Incident summary and detailed description are required.' });
        }
        if (!/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d{1,7})?)?$/.test(String(incidentTime || ''))) {
            return res.status(400).json({ success: false, error: 'incidentTime must be a valid 24-hour time.' });
        }
        if (!isUuid) {
            return res.status(400).json({ success: false, error: 'A valid Idempotency-Key UUID header is required.' });
        }
        if (![incidentTypeId, classificationId, locationId].every(value => Number.isInteger(Number(value)) && Number(value) > 0)) {
            return res.status(400).json({ success: false, error: 'Incident type, classification and location must be valid positive identifiers.' });
        }

        const pool = await getDatabasePool();
        const locationResult = await pool.request()
            .input('locationId', sql.Int, Number(locationId))
            .query('SELECT LocationId FROM wellbeing.tblSchoolLocations WHERE LocationId = @locationId AND IsActive = 1');
        if (!locationResult.recordset.length) {
            return res.status(400).json({ success: false, error: 'The selected incident location is inactive or invalid.' });
        }

        const relationshipResult = await pool.request()
            .input('locationId', sql.Int, Number(locationId))
            .input('classificationId', sql.Int, Number(classificationId))
            .input('incidentTypeId', sql.Int, Number(incidentTypeId))
            .input('incidentDate', sql.Date, new Date(incidentDate))
            .query(`
                SELECT incidentType.LegacyIncidentLevel
                FROM wellbeing.IncidentClassificationLocation AS locationClassification
                INNER JOIN wellbeing.IncidentTypeClassification AS typeClassification
                    ON typeClassification.ClassificationId = locationClassification.ClassificationId
                INNER JOIN wellbeing.tblIncidentClassifications AS classification
                    ON classification.ClassificationId = typeClassification.ClassificationId
                INNER JOIN wellbeing.tblIncidentTypes AS incidentType
                    ON incidentType.IncidentTypeId = typeClassification.IncidentTypeId
                WHERE locationClassification.LocationId = @locationId
                  AND classification.ClassificationId = @classificationId
                  AND incidentType.IncidentTypeId = @incidentTypeId
                  AND classification.IsActive = 1
                  AND incidentType.IsActive = 1
                  AND
                  (
                      NOT EXISTS
                      (
                          SELECT 1
                          FROM wellbeing.IncidentDefinition AS configured
                          WHERE configured.ClassificationId = classification.ClassificationId
                            AND configured.IncidentTypeId = incidentType.IncidentTypeId
                            AND configured.IsActive = 1
                      )
                      OR EXISTS
                      (
                          SELECT 1
                          FROM wellbeing.IncidentDefinition AS configured
                          WHERE configured.ClassificationId = classification.ClassificationId
                            AND configured.IncidentTypeId = incidentType.IncidentTypeId
                            AND configured.IsActive = 1
                            AND configured.EffectiveStartDate <= @incidentDate
                            AND (configured.EffectiveEndDate IS NULL OR configured.EffectiveEndDate >= @incidentDate)
                            AND (configured.ApplicableLocationIds IS NULL
                                 OR N',' + REPLACE(configured.ApplicableLocationIds, N' ', N'') + N','
                                    LIKE N'%,' + CONVERT(NVARCHAR(20), @locationId) + N',%')
                      )
                  );
            `);
        if (!relationshipResult.recordset.length) {
            return res.status(400).json({
                success: false,
                error: 'The incident type has no active definition for the selected classification, location, and incident date.'
            });
        }
        const legacyIncidentLevel = relationshipResult.recordset[0].LegacyIncidentLevel;

        const staffResult = await pool.request()
            .input('staffIdentifier', sql.NVarChar(200), String(staffIdentifier))
            .query(`
                SELECT DISTINCT TOP (2) StaffKey
                FROM gold.dimStaff
                WHERE TRY_CONVERT(INT, @staffIdentifier) = StaffKey
                   OR CONVERT(NVARCHAR(200), CompassPersonId) = @staffIdentifier
            `);
        if (staffResult.recordset.length !== 1) {
            return res.status(400).json({
                success: false,
                error: staffResult.recordset.length ? 'The reporting staff identifier is ambiguous.' : 'The reporting staff member could not be resolved.'
            });
        }
        const reportingStaffKey = staffResult.recordset[0]?.StaffKey;
        if (!req.incidentPrincipal.roles.includes('ADMINISTRATION')
            && reportingStaffKey !== req.incidentPrincipal.staffKey) {
            return res.status(403).json({ success: false, error: 'Reporting staff must match the authenticated staff account.' });
        }

        const resolvedStudents = [];
        for (const identifier of requestedStudentIdentifiers) {
            const resolved = await pool.request()
                .input('studentIdentifier', sql.NVarChar(200), String(identifier))
                .input('incidentDate', sql.Date, new Date(incidentDate))
                .query(`
                    SELECT DISTINCT TOP (2) student.StudentKey, student.StudentCode,
                           student.FirstName, student.LastName, student.PreferredFirstName,
                           student.PreferredLastName, student.UserStatus,
                           CASE WHEN historical.SourceVersionCount = 1
                                     AND historical.StandardYearLevel IS NOT NULL
                                THEN CONVERT(nvarchar(50), historical.StandardYearLevel)
                           END AS StudentYearLevelAtIncident,
                           CASE WHEN historical.SourceVersionCount = 1
                                     AND historical.StandardYearLevel IS NOT NULL
                                THEN N'VERIFIED' ELSE N'INVESTIGATION_REQUIRED'
                           END AS YearLevelResolutionStatus
                    FROM gold.dimStudent AS student
                    OUTER APPLY
                    (
                        SELECT COUNT_BIG(*) AS SourceVersionCount,
                               MAX(TRY_CONVERT
                               (
                                   int,
                                   RIGHT
                                   (
                                       LTRIM(RTRIM(source.year_level)),
                                       PATINDEX
                                       (
                                           N'%[^0-9]%',
                                           REVERSE(LTRIM(RTRIM(source.year_level))) + N'X'
                                       ) - 1
                                   )
                               )) AS StandardYearLevel
                        FROM silver.StudentsBasic AS source
                        WHERE source.compass_person_id = student.CompassPersonId
                          AND source.valid_from_utc < DATEADD(DAY, 1, CONVERT(datetime2, @incidentDate))
                          AND (source.valid_to_utc IS NULL
                               OR source.valid_to_utc >= CONVERT(datetime2, @incidentDate))
                    ) AS historical
                    WHERE (TRY_CONVERT(INT, @studentIdentifier) = student.StudentKey
                       OR CONVERT(NVARCHAR(200), student.CompassPersonId) = @studentIdentifier
                       OR student.StudentCode = @studentIdentifier
                       OR student.Username = @studentIdentifier)
                `);
            const resolvedKey = resolved.recordset[0]?.StudentKey;
            if (!resolvedKey) {
                return res.status(400).json({
                    success: false,
                    error: `Student could not be resolved: ${identifier}`
                });
            }
            if (resolved.recordset.length !== 1) {
                return res.status(400).json({ success: false, error: 'A selected student identifier is ambiguous.' });
            }
            if (String(resolved.recordset[0].UserStatus ?? '').trim() !== '1') {
                return res.status(400).json({
                    success: false,
                    error: `Student is not eligible for incident reporting or their Compass status is unknown: ${identifier}`
                });
            }
            if (!resolvedStudents.some(student => student.StudentKey === resolvedKey)) {
                resolvedStudents.push(resolved.recordset[0]);
            }
        }

        const primaryStudent = resolvedStudents[0];
        transaction = new sql.Transaction(pool);
        await transaction.begin(sql.ISOLATION_LEVEL.SERIALIZABLE);
        const existing = await transaction.request()
            .input('IdempotencyKey', sql.UniqueIdentifier, idempotencyKey)
            .query(`
                SELECT IncidentId, IncidentNumber, StudentKey, IncidentDate,
                       CONVERT(varchar(8), IncidentTime, 108) AS IncidentTimeText,
                       IncidentTypeId, ClassificationId, LocationId, ReportingStaffKey,
                       ReceivingStaffKey, IncidentSummary, DetailedDescription, FollowUpNotes,
                       SeverityIndicators
                FROM wellbeing.factBehaviourIncident WITH (UPDLOCK, HOLDLOCK)
                WHERE IdempotencyKey = @IdempotencyKey;
            `);
        if (existing.recordset.length) {
            const previous = existing.recordset[0];
            const savedStudents = await transaction.request()
                .input('IncidentId', sql.Int, previous.IncidentId)
                .query('SELECT StudentKey FROM wellbeing.IncidentStudent WHERE IncidentId = @IncidentId;');
            const savedStudentKeys = savedStudents.recordset.map(row => Number(row.StudentKey)).sort((a, b) => a - b);
            const submittedStudentKeys = resolvedStudents.map(student => Number(student.StudentKey)).sort((a, b) => a - b);
            const sameStudents = savedStudentKeys.length === submittedStudentKeys.length
                && savedStudentKeys.every((key, index) => key === submittedStudentKeys[index]);
            const sameRequest = sameStudents
                && Number(previous.IncidentTypeId) === Number(incidentTypeId)
                && Number(previous.ClassificationId) === Number(classificationId)
                && Number(previous.LocationId) === Number(locationId)
                && Number(previous.ReportingStaffKey) === Number(reportingStaffKey)
                && Number(previous.ReceivingStaffKey || 0) === Number(receivingStaffKey || 0)
                && String(previous.IncidentTimeText).slice(0, 5) === String(incidentTime).slice(0, 5)
                && String(previous.IncidentSummary ?? '') === String(incidentSummary)
                && String(previous.DetailedDescription ?? '') === String(detailedDescription || '')
                && String(previous.FollowUpNotes ?? '') === String(followUpNotes || '')
                && String(previous.SeverityIndicators ?? '') === String(severityIndicators || '')
                && new Date(previous.IncidentDate).toISOString().slice(0, 10) === incidentDate;
            if (!sameRequest) {
                await transaction.rollback();
                transactionCommitted = true;
                return res.status(409).json({
                    success: false,
                    error: 'This Idempotency-Key was already used for a different incident submission.'
                });
            }
            await transaction.commit();
            transactionCommitted = true;
            return res.status(200).json({ success: true, data: existing.recordset[0], duplicateSubmission: true });
        }

        const result = await transaction.request()
            .input('StudentKey', sql.Int, primaryStudent.StudentKey)
            .input('StudentCode', sql.NVarChar(100), primaryStudent.StudentCode || null)
            .input('IncidentDate', sql.Date, new Date(incidentDate))
            .input('IncidentTime', sql.Time, incidentTime)
            .input('IncidentTypeId', sql.Int, Number(incidentTypeId))
            .input('ClassificationId', sql.Int, Number(classificationId))
            .input('LegacyIncidentLevel', sql.Int, legacyIncidentLevel ?? null)
            .input('LocationId', sql.Int, Number(locationId))
            .input('ReportingStaffKey', sql.Int, reportingStaffKey)
            .input('ReceivingStaffKey', sql.Int, receivingStaffKey || null)
            .input('IdempotencyKey', sql.UniqueIdentifier, idempotencyKey)
            .input('IncidentSummary', sql.NVarChar(sql.MAX), incidentSummary)
            .input('DetailedDescription', sql.NVarChar(sql.MAX), detailedDescription || '')
            .input('FollowUpNotes', sql.NVarChar(sql.MAX), followUpNotes || '')
            .input('SeverityIndicators', sql.NVarChar(sql.MAX), severityIndicators || '')
            .input('Actor', sql.NVarChar(255), req.incidentPrincipal.username)
            .query(`
                INSERT INTO wellbeing.factBehaviourIncident
                (IncidentNumber, StudentKey, ReportingStaffKey, ReceivingStaffKey, LocationId,
                 IncidentTypeId, ClassificationId, PolicyLevelId, LegacyIncidentLevel, IdempotencyKey, IncidentStatusKey,
                 IncidentDate, IncidentTime, IncidentSummary, DetailedDescription,
                 FollowUpNotes, SeverityIndicators, CreatedDate, CreatedBy, ModifiedDate, ModifiedBy, IsDeleted)
                OUTPUT INSERTED.IncidentId, INSERTED.IncidentNumber
                VALUES
                (CONCAT(
                    'INC-',
                    RIGHT('0000' + CAST(NEXT VALUE FOR wellbeing.IncidentNumberSequence AS VARCHAR(20)), 4),
                    '-',
                    UPPER(LEFT(
                        REPLACE(REPLACE(REPLACE(COALESCE(@StudentCode, 'STUD'), ' ', ''), '.', ''), '-', ''),
                        6
                    ))
                ), @StudentKey, @ReportingStaffKey,
                 @ReceivingStaffKey, @LocationId, @IncidentTypeId, @ClassificationId, NULL, @LegacyIncidentLevel, @IdempotencyKey, 1,
                 @IncidentDate, @IncidentTime, @IncidentSummary, @DetailedDescription,
                 @FollowUpNotes, @SeverityIndicators, GETUTCDATE(), @Actor, GETUTCDATE(), @Actor, 0)
            `);

        const incidentId = result.recordset[0].IncidentId;
        for (const student of resolvedStudents) {
            const studentName = [
                student.PreferredFirstName || student.FirstName,
                student.PreferredLastName || student.LastName
            ].filter(Boolean).join(' ').trim();
            await transaction.request()
                .input('IncidentId', sql.Int, incidentId)
                .input('StudentKey', sql.Int, student.StudentKey)
                .input('IsPrimary', sql.Bit, student.StudentKey === primaryStudent.StudentKey)
                .input('StudentNameAtIncident', sql.NVarChar(300), studentName || null)
                .input('StudentYearLevelAtIncident', sql.NVarChar(50), student.StudentYearLevelAtIncident)
                .input('YearLevelResolutionStatus', sql.NVarChar(40), student.YearLevelResolutionStatus)
                .query(`
                    INSERT INTO wellbeing.IncidentStudent
                        (IncidentId, StudentKey, IsPrimary, StudentNameAtIncident,
                         StudentNameSnapshotStatus, StudentYearLevelAtIncident,
                         StudentYearLevelIdAtIncident, StudentClassAtIncident, YearLevelResolutionStatus)
                    VALUES
                        (@IncidentId, @StudentKey, @IsPrimary, @StudentNameAtIncident,
                         N'PROFILE_AT_ENTRY', @StudentYearLevelAtIncident, NULL, NULL, @YearLevelResolutionStatus);
                `);
        }
        await transaction.request()
            .input('Actor', sql.NVarChar(255), req.incidentPrincipal.username)
            .input('EntityId', sql.NVarChar(100), String(incidentId))
            .input('AfterJson', sql.NVarChar(sql.MAX), JSON.stringify({
                incident: result.recordset[0],
                students: resolvedStudents.map(student => ({
                    StudentKey: student.StudentKey,
                    StudentNameAtIncident: [
                        student.PreferredFirstName || student.FirstName,
                        student.PreferredLastName || student.LastName
                    ].filter(Boolean).join(' ').trim(),
                    StudentYearLevelIdAtIncident: null,
                    StudentYearLevelAtIncident: student.StudentYearLevelAtIncident,
                    YearLevelResolutionStatus: student.YearLevelResolutionStatus
                }))
            }))
            .input('CorrelationId', sql.NVarChar(100), req.get('x-correlation-id') || null)
            .input('IpAddress', sql.NVarChar(50), req.ip || null)
            .query(`
                INSERT INTO wellbeing.AuditEvent
                    (Actor, Action, EntityName, EntityId, AfterJson, CorrelationId, IpAddress)
                VALUES
                    (@Actor, N'CREATE', N'Incident', @EntityId, @AfterJson, @CorrelationId, @IpAddress);
            `);
        await transaction.commit();
        transactionCommitted = true;

        res.status(201).json({
            success: true,
            message: 'Incident created successfully',
            data: result.recordset[0],
            studentKeys: resolvedStudents.map(student => student.StudentKey),
            historicalYearLevelStatus: resolvedStudents.every(student =>
                student.YearLevelResolutionStatus === 'VERIFIED'
            ) ? 'VERIFIED' : 'INVESTIGATION_REQUIRED',
            rowsAffected: result.rowsAffected[0]
        });
    } catch (error) {
        if (transaction && !transactionCommitted) {
            try {
                await transaction.rollback();
            } catch (rollbackError) {
                console.error('Incident transaction rollback failed:', rollbackError.message);
            }
        }
        console.error('❌ Error creating incident:', error.message);
        if (error.number === 2601 || error.number === 2627) {
            return res.status(409).json({ success: false, error: 'The incident submission conflicts with an existing record. Retry with the original idempotency key.' });
        }
        res.status(500).json({
            success: false,
            error: 'Unable to create the incident.'
        });
    }
});

// PUT update incident
incidentsRouter.put('/:id', requireIncidentRole(incidentRoles.update), async (req, res) => {
    let transaction;
    let transactionCommitted = false;
    try {
        const incidentId = parseInt(req.params.id);
        const { incidentSummary, detailedDescription, followUpNotes, severityIndicators, incidentStatusKey, receivingStaffKey,
            incidentDate, incidentTime, locationId, incidentTypeId, classificationId, policyLevelId, studentKeys } = req.body;
        if (!Number.isInteger(incidentId) || incidentId < 1) {
            return res.status(400).json({ success: false, error: 'Incident id must be a positive integer.' });
        }
        if (incidentDate !== undefined) {
            const dateText = String(incidentDate);
            const validDate = /^\d{4}-\d{2}-\d{2}$/.test(dateText)
                && !Number.isNaN(Date.parse(`${dateText}T00:00:00Z`))
                && new Date(`${dateText}T00:00:00Z`).toISOString().slice(0, 10) === dateText;
            if (!validDate) {
                return res.status(400).json({ success: false, error: 'incidentDate must be a valid ISO date in YYYY-MM-DD format.' });
            }
        }
        if (incidentTime !== undefined
            && !/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d{1,7})?)?$/.test(String(incidentTime))) {
            return res.status(400).json({ success: false, error: 'incidentTime must be a valid 24-hour time.' });
        }

        const pool = await getDatabasePool();
        const existingIncident = await pool.request()
            .input('IncidentId', sql.Int, incidentId)
            .query(`
                SELECT *
                FROM wellbeing.factBehaviourIncident
                WHERE IncidentId = @IncidentId AND IsDeleted = 0;
            `);
        if (!existingIncident.recordset.length) {
            return res.status(404).json({ success: false, error: 'Incident not found.' });
        }
        const existingDate = new Date(existingIncident.recordset[0].IncidentDate).toISOString().slice(0, 10);
        if (incidentDate !== undefined && String(incidentDate) !== existingDate) {
            return res.status(409).json({
                success: false,
                error: 'Incident date cannot be changed because historical student snapshots are tied to the original event date.'
            });
        }
        if (!req.incidentPrincipal.roles.includes('ADMINISTRATION')
            && !req.incidentPrincipal.roles.includes('PASTORAL_CARE')
            && Number(existingIncident.recordset[0].ReportingStaffKey) !== Number(req.incidentPrincipal.staffKey)) {
            return res.status(403).json({ success: false, error: 'You may only update incidents you reported.' });
        }
        if (Array.isArray(studentKeys)) {
            const requestedKeys = studentKeys.map(Number);
            if (requestedKeys.some(key => !Number.isInteger(key) || key < 1)) {
                return res.status(400).json({ success: false, error: 'Student identifiers must be positive integer keys.' });
            }
            const existingStudents = await pool.request()
                .input('IncidentId', sql.Int, incidentId)
                .query('SELECT StudentKey FROM wellbeing.IncidentStudent WHERE IncidentId = @IncidentId');
            const savedKeys = existingStudents.recordset.map(row => Number(row.StudentKey)).sort((a, b) => a - b);
            const requestedUniqueKeys = [...new Set(requestedKeys)].sort((a, b) => a - b);
            if (savedKeys.length !== requestedUniqueKeys.length
                || savedKeys.some((key, index) => key !== requestedUniqueKeys[index])) {
                return res.status(409).json({
                    success: false,
                    error: 'Students linked to an incident cannot be replaced because their historical snapshots must be preserved.'
                });
            }
        }

        let legacyIncidentLevel;
        if (locationId !== undefined || classificationId !== undefined || incidentTypeId !== undefined) {
            const current = existingIncident.recordset[0];
            const finalLocationId = Number(locationId ?? current.LocationId);
            const finalClassificationId = Number(classificationId ?? current.ClassificationId);
            const finalIncidentTypeId = Number(incidentTypeId ?? current.IncidentTypeId);
            const finalIncidentDate = incidentDate === undefined ? current.IncidentDate : new Date(incidentDate);
            if (![finalLocationId, finalClassificationId, finalIncidentTypeId]
                .every(value => Number.isInteger(value) && value > 0)) {
                return res.status(400).json({ success: false, error: 'Location, classification and incident type must be valid positive identifiers.' });
            }
            const validRelationship = await pool.request()
                .input('locationId', sql.Int, finalLocationId)
                .input('classificationId', sql.Int, finalClassificationId)
                .input('incidentTypeId', sql.Int, finalIncidentTypeId)
                .input('incidentDate', sql.Date, finalIncidentDate)
                .query(`
                    SELECT incidentType.LegacyIncidentLevel
                    FROM wellbeing.IncidentClassificationLocation AS locationClassification
                    INNER JOIN wellbeing.IncidentTypeClassification AS typeClassification
                        ON typeClassification.ClassificationId = locationClassification.ClassificationId
                    INNER JOIN wellbeing.tblIncidentClassifications AS classification
                        ON classification.ClassificationId = typeClassification.ClassificationId
                    INNER JOIN wellbeing.tblIncidentTypes AS incidentType
                        ON incidentType.IncidentTypeId = typeClassification.IncidentTypeId
                    INNER JOIN wellbeing.IncidentDefinition AS definition
                        ON definition.ClassificationId = classification.ClassificationId
                       AND definition.IncidentTypeId = incidentType.IncidentTypeId
                    INNER JOIN wellbeing.tblSchoolLocations AS location
                        ON location.LocationId = locationClassification.LocationId
                    WHERE locationClassification.LocationId = @locationId
                      AND classification.ClassificationId = @classificationId
                      AND incidentType.IncidentTypeId = @incidentTypeId
                      AND classification.IsActive = 1
                      AND incidentType.IsActive = 1
                          AND location.IsActive = 1
                          AND definition.IsActive = 1
                          AND definition.EffectiveStartDate <= @incidentDate
                          AND (definition.EffectiveEndDate IS NULL OR definition.EffectiveEndDate >= @incidentDate)
                          AND (definition.ApplicableLocationIds IS NULL
                               OR N',' + REPLACE(definition.ApplicableLocationIds, N' ', N'') + N','
                                  LIKE N'%,' + CONVERT(NVARCHAR(20), @locationId) + N',%');
                `);
                if (!validRelationship.recordset.length) {
                    return res.status(400).json({
                        success: false,
                        error: 'The incident type has no active definition for the selected classification, location, and incident date.'
                    });
            }
            legacyIncidentLevel = validRelationship.recordset[0].LegacyIncidentLevel;
        }

        // Build dynamic UPDATE query
        let updateFields = [];

        if (incidentSummary !== undefined) {
            updateFields.push('IncidentSummary = @IncidentSummary');
        }
        if (detailedDescription !== undefined) {
            updateFields.push('DetailedDescription = @DetailedDescription');
        }
        if (followUpNotes !== undefined) {
            updateFields.push('FollowUpNotes = @FollowUpNotes');
        }
        if (severityIndicators !== undefined) {
            updateFields.push('SeverityIndicators = @SeverityIndicators');
        }
        if (incidentStatusKey !== undefined) {
            updateFields.push('IncidentStatusKey = @IncidentStatusKey');
        }
        if (receivingStaffKey !== undefined) {
            updateFields.push('ReceivingStaffKey = @ReceivingStaffKey');
        }
        if (incidentDate !== undefined) {
            updateFields.push('IncidentDate = @IncidentDate');
        }
        if (incidentTime !== undefined) {
            updateFields.push('IncidentTime = @IncidentTime');
        }
        for (const [field, value] of [
            ['LocationId', locationId],
            ['IncidentTypeId', incidentTypeId],
            ['ClassificationId', classificationId],
            ['PolicyLevelId', policyLevelId]
        ]) {
            if (value !== undefined) {
                updateFields.push(`${field} = @${field}`);
            }
        }
        if (legacyIncidentLevel !== undefined) {
            updateFields.push('LegacyIncidentLevel = @LegacyIncidentLevel');
        }

        // Always update ModifiedDate and ModifiedBy
        updateFields.push('ModifiedDate = GETDATE()');
        updateFields.push('ModifiedBy = @ModifiedBy');

        if (updateFields.length === 2) {
            // Only ModifiedDate and ModifiedBy, no actual updates
            return res.status(400).json({
                success: false,
                error: 'No fields to update'
            });
        }

        transaction = new sql.Transaction(pool);
        await transaction.begin();
        const request = transaction.request()
            .input('IncidentId', sql.Int, incidentId)
            .input('ModifiedBy', sql.NVarChar(255), req.incidentPrincipal.username);
        for (const [field, value] of [
            ['IncidentSummary', incidentSummary],
            ['DetailedDescription', detailedDescription],
            ['FollowUpNotes', followUpNotes],
            ['SeverityIndicators', severityIndicators]
        ]) {
            if (value !== undefined) request.input(field, sql.NVarChar(sql.MAX), value);
        }
        for (const [field, value] of [
            ['IncidentStatusKey', incidentStatusKey],
            ['ReceivingStaffKey', receivingStaffKey],
            ['LocationId', locationId],
            ['IncidentTypeId', incidentTypeId],
            ['ClassificationId', classificationId],
            ['PolicyLevelId', policyLevelId],
            ['LegacyIncidentLevel', legacyIncidentLevel]
        ]) {
            if (value !== undefined) request.input(field, sql.Int, Number(value));
        }
        if (incidentDate !== undefined) request.input('IncidentDate', sql.Date, new Date(incidentDate));
        if (incidentTime !== undefined) request.input('IncidentTime', sql.Time, incidentTime);

        const result = await request.query(`
            UPDATE wellbeing.factBehaviourIncident
            SET ${updateFields.join(', ')}
            WHERE IncidentId = @IncidentId
        `);
        if (result.rowsAffected[0] === 0) {
            await transaction.rollback();
            transactionCommitted = true;
            return res.status(404).json({ success: false, error: 'Incident not found.' });
        }
        const updatedIncident = await transaction.request()
            .input('IncidentId', sql.Int, incidentId)
            .query('SELECT * FROM wellbeing.factBehaviourIncident WHERE IncidentId = @IncidentId;');
        await writeIncidentAudit(transaction, req, 'UPDATE', incidentId, existingIncident.recordset[0], updatedIncident.recordset[0]);
        await transaction.commit();
        transactionCommitted = true;
        res.json({
            success: true,
            message: 'Incident updated successfully',
            rowsAffected: result.rowsAffected[0]
        });
    } catch (error) {
        if (transaction && !transactionCommitted) {
            try {
                await transaction.rollback();
            } catch (rollbackError) {
                console.error('Incident update rollback failed:', rollbackError.message);
            }
        }
        console.error('❌ Error updating incident:', error.message);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// Cancel incident without removing its historical student snapshots
const cancelIncident = async (req, res) => {
    let transaction;
    let transactionCommitted = false;
    try {
        const incidentId = parseInt(req.params.id);
        if (!Number.isInteger(incidentId) || incidentId < 1) {
            return res.status(400).json({ success: false, error: 'Incident id must be a positive integer.' });
        }

        const pool = await getDatabasePool();

        transaction = new sql.Transaction(pool);
        await transaction.begin(sql.ISOLATION_LEVEL.SERIALIZABLE);
        const beforeResult = await transaction.request()
            .input('IncidentId', sql.Int, incidentId)
            .query(`
                SELECT * FROM wellbeing.factBehaviourIncident WITH (UPDLOCK, HOLDLOCK)
                WHERE IncidentId = @IncidentId AND IsDeleted = 0;
            `);
        if (!beforeResult.recordset.length) {
            await transaction.rollback();
            transactionCommitted = true;
            return res.status(404).json({ success: false, error: 'Incident not found or already cancelled.' });
        }
        if (!req.incidentPrincipal.roles.includes('ADMINISTRATION')
            && !req.incidentPrincipal.roles.includes('AUTHORIZED_APPROVER')) {
            const incidentOwner = Number(beforeResult.recordset[0].ReportingStaffKey);
            if (incidentOwner !== Number(req.incidentPrincipal.staffKey)) {
                await transaction.rollback();
                transactionCommitted = true;
                return res.status(403).json({ success: false, error: 'You may only cancel incidents you reported.' });
            }
        }
        const result = await transaction.request()
            .input('IncidentId', sql.Int, incidentId)
            .input('Actor', sql.NVarChar(255), req.incidentPrincipal.username)
            .query(`
                UPDATE wellbeing.factBehaviourIncident
                SET IsDeleted = 1,
                    ModifiedDate = GETDATE(),
                    ModifiedBy = @Actor
                WHERE IncidentId = @IncidentId AND IsDeleted = 0
            `);
        if (result.rowsAffected[0] === 0) {
            await transaction.rollback();
            transactionCommitted = true;
            return res.status(404).json({ success: false, error: 'Incident not found.' });
        }
        const afterResult = await transaction.request()
            .input('IncidentId', sql.Int, incidentId)
            .query('SELECT * FROM wellbeing.factBehaviourIncident WHERE IncidentId = @IncidentId;');
        await writeIncidentAudit(transaction, req, 'CANCEL', incidentId, beforeResult.recordset[0], afterResult.recordset[0]);
        await transaction.commit();
        transactionCommitted = true;

        res.json({
            success: true,
            message: 'Incident cancelled. Historical student snapshots have been retained.',
            rowsAffected: result.rowsAffected[0]
        });
    } catch (error) {
        if (transaction && !transactionCommitted) {
            try {
                await transaction.rollback();
            } catch (rollbackError) {
                console.error('Incident cancellation rollback failed:', rollbackError.message);
            }
        }
        console.error('❌ Error deleting incident:', error.message);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
};

incidentsRouter.post('/:id/cancel', requireIncidentRole(incidentRoles.cancel), cancelIncident);
incidentsRouter.delete('/:id', requireIncidentRole(incidentRoles.cancel), cancelIncident);

app.use('/api/incidents', incidentsRouter);

// ---------------------------------------------------------
// STUDENTS ENDPOINTS
// ---------------------------------------------------------

const studentsRouter = express.Router();

// GET all students with pagination and filters
studentsRouter.get('/', requireIncidentRole(incidentRoles.read), async (req, res) => {
    try {
        const page = parseInt(req.query.page) || 1;
        const limit = parseInt(req.query.limit) || 10;
        const offset = (page - 1) * limit;

        const pool = await getDatabasePool();

        // Get total count
        const countResult = await pool.request()
            .query(`SELECT COUNT(*) as total FROM gold.dimStudent`);
        const total = countResult.recordset[0].total;

        // Get paginated data
        const result = await pool.request()
            .query(`
                SELECT StudentKey,
                       CompassPersonId,
                       FirstName,
                       LastName,
                       PreferredFirstName,
                       PreferredLastName,
                       Gender,
                       DateOfBirth,
                       YearLevel,
                       CampusYearlevel,
                       StudentCode,
                       EmailAddress,
                       SchoolEmail
                FROM gold.dimStudent
                ORDER BY FirstName, LastName
                OFFSET ${offset} ROWS
                FETCH NEXT ${limit} ROWS ONLY
            `);

        res.json({
            success: true,
            data: result.recordset,
            pagination: {
                page,
                limit,
                total,
                pages: Math.ceil(total / limit)
            }
        });
    } catch (error) {
        console.error('❌ Error fetching students:', error.message);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

// GET student by ID
studentsRouter.get('/:id/incidents', requireIncidentRole(incidentRoles.read), async (req, res) => {
    try {
        const studentIdentifier = String(req.params.id || '').trim();
        if (!studentIdentifier) {
            return res.status(400).json({ success: false, error: 'Student identifier is required.' });
        }
        const page = Math.max(1, Number(req.query.page) || 1);
        const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 10));
        const pool = await getDatabasePool();
        const student = await pool.request()
            .input('identifier', sql.NVarChar(200), studentIdentifier)
            .query(`
                SELECT DISTINCT TOP (2) StudentKey
                FROM gold.dimStudent
                WHERE TRY_CONVERT(INT, @identifier) = StudentKey
                   OR CONVERT(NVARCHAR(200), CompassPersonId) = @identifier
                   OR StudentCode = @identifier
                   OR Username = @identifier;
            `);
        if (student.recordset.length !== 1) {
            return res.status(student.recordset.length ? 409 : 404).json({
                success: false,
                error: student.recordset.length
                    ? 'Student identifier is ambiguous.'
                    : 'Student could not be resolved.'
            });
        }
        const studentKey = student.recordset[0].StudentKey;
        const result = await pool.request()
            .input('StudentKey', sql.Int, studentKey)
            .input('offset', sql.Int, (page - 1) * limit)
            .input('limit', sql.Int, limit)
            .query(`
                SELECT IncidentId, IncidentNumber, StudentName, StudentCode,
                       StudentYearLevelsAtIncident, YearLevelResolutionStatuses,
                       StudentYearLevelIdsAtIncident, IsDeleted,
                       IncidentDate, IncidentTime, LocationName, IncidentTypeName,
                       ClassificationName, IncidentStatusName, IncidentSummary
                FROM wellbeing.vwIncidentDirectory AS vwIncidentDirectory
                WHERE EXISTS (
                    SELECT 1 FROM wellbeing.IncidentStudent AS studentLink
                    WHERE studentLink.IncidentId = vwIncidentDirectory.IncidentId
                      AND studentLink.StudentKey = @StudentKey
                )
                ORDER BY IncidentDate DESC, IncidentId DESC
                OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;
            `);
        res.json({ success: true, data: result.recordset, pagination: { page, limit } });
    } catch (error) {
        console.error('Unable to fetch student incident history:', error.message);
        res.status(500).json({ success: false, error: 'Unable to load student incident history.' });
    }
});

studentsRouter.get('/:id', requireIncidentRole(incidentRoles.read), async (req, res) => {
    try {
        const studentKey = parseInt(req.params.id);
        const pool = await getDatabasePool();

        const result = await pool.request()
            .input('studentKey', sql.Int, studentKey)
            .query(`
                SELECT *
                FROM gold.dimStudent
                WHERE StudentKey = @studentKey
            `);

        if (result.recordset.length === 0) {
            return res.status(404).json({
                success: false,
                error: 'Student not found'
            });
        }

        res.json({
            success: true,
            data: result.recordset[0]
        });
    } catch (error) {
        console.error('❌ Error fetching student:', error.message);
        res.status(500).json({
            success: false,
            error: error.message
        });
    }
});

app.use('/api/students', studentsRouter);

// ---------------------------------------------------------
// ERROR HANDLING
// ---------------------------------------------------------

// 404 handler
app.use((req, res, next) => {
    if (!isMainModule) {
        return next();
    }

    res.status(404).json({
        success: false,
        error: 'Route not found'
    });
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('❌ Error:', err);
    res.status(err.status || 500).json({
        success: false,
        error: err.message || 'Internal Server Error'
    });
});

// ---------------------------------------------------------
// START SERVER
// ---------------------------------------------------------

const startServer = async () => {
    try {
        // Initialize database connection
        await getDatabasePool();

        // Start Express server
        app.listen(PORT, () => {
            console.log('');
            console.log('═════════════════════════════════════════════════════════════════════');
            console.log(`✅ API Server running on http://localhost:${PORT}`);
            console.log('═════════════════════════════════════════════════════════════════════');
            console.log('');
            console.log('📚 Available Endpoints:');
            console.log(`   GET  http://localhost:${PORT}/api/health`);
            console.log(`   GET  http://localhost:${PORT}/api/incidents?page=1&limit=10`);
            console.log(`   GET  http://localhost:${PORT}/api/incidents/:id`);
            console.log(`   POST http://localhost:${PORT}/api/incidents`);
            console.log(`   GET  http://localhost:${PORT}/api/students?page=1&limit=10`);
            console.log(`   GET  http://localhost:${PORT}/api/students/:id`);
            console.log('');
        });
    } catch (error) {
        console.error('');
        console.error('❌ Failed to start server:', error.message);
        console.error('');
        process.exit(1);
    }
};

// Handle graceful shutdown
process.on('SIGINT', () => {
    console.log('\n🛑 Shutting down gracefully...');
    process.exit(0);
});

if (isMainModule) {
    startServer();
}

export default app;
export { app, incidentRoles, requireIncidentRole };
