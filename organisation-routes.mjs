import express from 'express';

const router = express.Router();
const READ_ROLES = new Set(['organisation-administrator', 'wellbeing-administrator', 'head-of-house', 'pastoral-care-teacher', 'read-only-authorised-staff']);
const WRITE_ROLES = new Set(['organisation-administrator', 'wellbeing-administrator']);

const sqlFor = req => req.app.locals.sql;
const poolFor = req => req.app.locals.getDatabasePool();
const result = (res, data, status = 200) => res.status(status).json({ success: true, data });

function id(value, name) {
    const parsed = Number(value);
    if (!Number.isSafeInteger(parsed) || parsed < 1) {
        const error = new Error(`${name} must be a positive integer.`);
        error.status = 400;
        throw error;
    }
    return parsed;
}

function date(value) {
    if (value == null || value === '') return null;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value))) {
        const error = new Error('Date must use YYYY-MM-DD format.');
        error.status = 400;
        throw error;
    }
    return value;
}

function guard(write = false) {
    return (req, res, next) => {
        const roles = new Set((req.get('x-user-roles') || '').toLowerCase().split(',').map(x => x.trim()).filter(Boolean));
        if (process.env.API_AUTH_REQUIRED === 'true' && !req.get('authorization')) {
            return res.status(401).json({ success: false, error: 'Authentication required.' });
        }
        const allowed = write ? WRITE_ROLES : READ_ROLES;
        if (process.env.API_AUTH_REQUIRED === 'true' && ![...roles].some(role => allowed.has(role))) {
            return res.status(403).json({ success: false, error: 'Insufficient permission.' });
        }
        req.actor = req.get('x-user-id') || 'api';
        return next();
    };
}

async function procedure(req, name, inputs) {
    const request = (await poolFor(req)).request();
    for (const [key, type, value] of inputs) request.input(key, type, value);
    return request.execute(name);
}

router.get('/wellbeing/students/:studentKey/pastoral-assignment', guard(), async (req, res, next) => {
    try {
        const sql = sqlFor(req);
        const output = await procedure(req, 'org.usp_GetStudentPastoralAssignment', [
            ['StudentKey', sql.BigInt, id(req.params.studentKey, 'studentKey')],
            ['AsAtDate', sql.Date, date(req.query.asAtDate)]
        ]);
        if (!output.recordset?.length) return result(res, null);
        return result(res, output.recordset[0]);
    } catch (error) { return next(error); }
});

router.get('/wellbeing/students/:studentKey/pastoral-history', guard(), async (req, res, next) => {
    try {
        const sql = sqlFor(req);
        const output = await (await poolFor(req)).request()
            .input('studentKey', sql.BigInt, id(req.params.studentKey, 'studentKey'))
            .query(`SELECT StudentPastoralAssignmentID,StudentKey,HouseID,PastoralGroupID,EffectiveFrom,EffectiveTo,AssignmentStatus,SourceSystem,SourceRecordID FROM wellbeing.vw_StudentPastoralAssignments WHERE StudentKey=@studentKey ORDER BY EffectiveFrom DESC,StudentPastoralAssignmentID DESC;`);
        return result(res, output.recordset);
    } catch (error) { return next(error); }
});

router.post('/wellbeing/students/:studentKey/pastoral-assignment', guard(true), async (req, res, next) => {
    try {
        const body = req.body || {};
        if (!body.effectiveFrom || (!body.houseKey && !body.pastoralGroupKey)) return res.status(400).json({ success: false, error: 'effectiveFrom and a House or pastoral group are required.' });
        const sql = sqlFor(req);
        const studentKey = id(req.params.studentKey, 'studentKey');
        const common = [
            ['StudentKey', sql.BigInt, studentKey],
            ['EffectiveFrom', sql.Date, body.effectiveFrom],
            ['EffectiveTo', sql.Date, body.effectiveTo || null],
            ['SourceSystem', sql.NVarChar(100), body.sourceSystem || 'API'],
            ['SourceAssignmentId', sql.NVarChar(150), body.sourceRecordId || null],
            ['Actor', sql.NVarChar(255), req.actor]
        ];
        if (body.houseKey) await procedure(req, 'org.usp_AssignStudentHouse', [['StudentKey', sql.BigInt, studentKey], ['HouseKey', sql.Int, id(body.houseKey, 'houseKey')], ...common.slice(1)]);
        if (body.pastoralGroupKey) await procedure(req, 'org.usp_AssignStudentPastoralGroup', [['StudentKey', sql.BigInt, studentKey], ['PastoralGroupKey', sql.Int, id(body.pastoralGroupKey, 'pastoralGroupKey')], ...common.slice(1)]);
        return result(res, { studentKey }, 201);
    } catch (error) { return next(error); }
});

router.put('/wellbeing/students/:studentKey/pastoral-assignment/:assignmentId', guard(true), async (req, res, next) => {
    try {
        const sql = sqlFor(req);
        const studentKey = id(req.params.studentKey, 'studentKey');
        const assignmentId = id(req.params.assignmentId, 'assignmentId');
        const body = req.body || {};
        const pool = await poolFor(req);
        const request = pool.request()
            .input('studentKey', sql.BigInt, studentKey)
            .input('assignmentId', sql.BigInt, assignmentId)
            .input('fromDate', sql.Date, body.effectiveFrom || null)
            .input('toDate', sql.Date, body.effectiveTo || null)
            .input('actor', sql.NVarChar(255), req.actor);
        const table = body.pastoralGroupKey ? 'org.StudentPastoralGroupAssignment' : 'org.StudentHouseAssignment';
        const key = body.pastoralGroupKey ? 'StudentPastoralGroupAssignmentKey' : 'StudentHouseAssignmentKey';
        const output = await request.query(`
            UPDATE ${table}
            SET EffectiveFrom=COALESCE(@fromDate,EffectiveFrom),
                EffectiveTo=@toDate,
                CreatedBy=@actor
            WHERE ${key}=@assignmentId AND StudentKey=@studentKey;
            SELECT @@ROWCOUNT AS updated;
        `);
        if (!output.recordset[0].updated) return res.status(404).json({ success: false, error: 'Assignment not found.' });
        return result(res, { assignmentId });
    } catch (error) { return next(error); }
});

router.get('/org/houses', guard(), async (req, res, next) => {
    try {
        const output = await (await poolFor(req)).request().query(`SELECT HouseKey AS houseId,HouseCode AS houseCode,HouseName AS houseName,IsActive AS isActive,EffectiveFrom AS effectiveFrom,EffectiveTo AS effectiveTo FROM org.House ORDER BY HouseName;`);
        return result(res, output.recordset);
    } catch (error) { return next(error); }
});

router.get('/org/houses/:houseId', guard(), async (req, res, next) => {
    try {
        const sql = sqlFor(req); const output = await (await poolFor(req)).request().input('id', sql.Int, id(req.params.houseId, 'houseId')).query(`SELECT HouseKey AS houseId,HouseCode AS houseCode,HouseName AS houseName,IsActive AS isActive,EffectiveFrom AS effectiveFrom,EffectiveTo AS effectiveTo FROM org.House WHERE HouseKey=@id;`);
        if (!output.recordset.length) return res.status(404).json({ success: false, error: 'House not found.' });
        return result(res, output.recordset[0]);
    } catch (error) { return next(error); }
});

router.post('/org/houses', guard(true), async (req, res, next) => {
    try {
        const { houseCode, houseName } = req.body || {};
        if (!houseCode || !houseName) return res.status(400).json({ success: false, error: 'houseCode and houseName are required.' });
        const sql = sqlFor(req); const output = await (await poolFor(req)).request().input('code', sql.NVarChar(100), houseCode).input('name', sql.NVarChar(200), houseName).query(`INSERT org.House(HouseCode,HouseName,EffectiveFrom,SourceSystem,SourceHouseId) OUTPUT inserted.HouseKey AS houseId VALUES(@code,@name,CAST(GETDATE() AS date),N'API',@code);`);
        return result(res, output.recordset[0], 201);
    } catch (error) { return next(error); }
});

router.put('/org/houses/:houseId', guard(true), async (req, res, next) => {
    try {
        const sql = sqlFor(req); const output = await (await poolFor(req)).request().input('id', sql.Int, id(req.params.houseId, 'houseId')).input('code', sql.NVarChar(100), req.body?.houseCode || null).input('name', sql.NVarChar(200), req.body?.houseName || null).input('active', sql.Bit, req.body?.isActive ?? null).query(`UPDATE org.House SET HouseCode=COALESCE(@code,HouseCode),HouseName=COALESCE(@name,HouseName),IsActive=COALESCE(@active,IsActive),ModifiedDate=SYSUTCDATETIME() WHERE HouseKey=@id; SELECT @@ROWCOUNT AS updated;`);
        if (!output.recordset[0].updated) return res.status(404).json({ success: false, error: 'House not found.' });
        return result(res, { houseId: Number(req.params.houseId) });
    } catch (error) { return next(error); }
});

router.delete('/org/houses/:houseId', guard(true), async (req, res, next) => {
    try {
        const sql = sqlFor(req);
        const output = await (await poolFor(req)).request()
            .input('id', sql.Int, id(req.params.houseId, 'houseId'))
            .query(`UPDATE org.House SET IsActive=0,EffectiveTo=COALESCE(EffectiveTo,CAST(GETDATE() AS date)),ModifiedDate=SYSUTCDATETIME() WHERE HouseKey=@id AND IsActive=1; SELECT @@ROWCOUNT AS updated;`);
        if (!output.recordset[0].updated) return res.status(404).json({ success: false, error: 'Active House not found.' });
        return result(res, { houseId: Number(req.params.houseId), deleted: true });
    } catch (error) { return next(error); }
});

router.get('/org/pastoral-groups', guard(), async (req, res, next) => {
    try {
        const output = await (await poolFor(req)).request().query(`SELECT PastoralGroupKey AS pastoralGroupId,GroupCode AS pastoralGroupCode,GroupName AS pastoralGroupName,IsActive AS isActive,EffectiveFrom AS effectiveFrom,EffectiveTo AS effectiveTo FROM org.PastoralGroup ORDER BY GroupName;`);
        return result(res, output.recordset);
    } catch (error) { return next(error); }
});

router.get('/org/pastoral-groups/:groupId', guard(), async (req, res, next) => {
    try {
        const sql = sqlFor(req); const output = await (await poolFor(req)).request().input('id', sql.Int, id(req.params.groupId, 'groupId')).query(`SELECT PastoralGroupKey AS pastoralGroupId,GroupCode AS pastoralGroupCode,GroupName AS pastoralGroupName,IsActive AS isActive FROM org.PastoralGroup WHERE PastoralGroupKey=@id;`);
        if (!output.recordset.length) return res.status(404).json({ success: false, error: 'Pastoral group not found.' });
        return result(res, output.recordset[0]);
    } catch (error) { return next(error); }
});

router.post('/org/pastoral-groups', guard(true), async (req, res, next) => {
    try {
        const { pastoralGroupCode, pastoralGroupName } = req.body || {};
        if (!pastoralGroupCode || !pastoralGroupName) return res.status(400).json({ success: false, error: 'pastoralGroupCode and pastoralGroupName are required.' });
        const sql = sqlFor(req); const output = await (await poolFor(req)).request().input('code', sql.NVarChar(100), pastoralGroupCode).input('name', sql.NVarChar(200), pastoralGroupName).query(`INSERT org.PastoralGroup(GroupCode,GroupName,EffectiveFrom,SourceSystem,SourceGroupId) OUTPUT inserted.PastoralGroupKey AS pastoralGroupId VALUES(@code,@name,CAST(GETDATE() AS date),N'API',@code);`);
        return result(res, output.recordset[0], 201);
    } catch (error) { return next(error); }
});

router.put('/org/pastoral-groups/:groupId', guard(true), async (req, res, next) => {
    try {
        const sql = sqlFor(req); const output = await (await poolFor(req)).request().input('id', sql.Int, id(req.params.groupId, 'groupId')).input('code', sql.NVarChar(100), req.body?.pastoralGroupCode || null).input('name', sql.NVarChar(200), req.body?.pastoralGroupName || null).input('active', sql.Bit, req.body?.isActive ?? null).query(`UPDATE org.PastoralGroup SET GroupCode=COALESCE(@code,GroupCode),GroupName=COALESCE(@name,GroupName),IsActive=COALESCE(@active,IsActive),ModifiedDate=SYSUTCDATETIME() WHERE PastoralGroupKey=@id; SELECT @@ROWCOUNT AS updated;`);
        if (!output.recordset[0].updated) return res.status(404).json({ success: false, error: 'Pastoral group not found.' });
        return result(res, { pastoralGroupId: Number(req.params.groupId) });
    } catch (error) { return next(error); }
});

router.delete('/org/pastoral-groups/:groupId', guard(true), async (req, res, next) => {
    try {
        const sql = sqlFor(req);
        const output = await (await poolFor(req)).request()
            .input('id', sql.Int, id(req.params.groupId, 'groupId'))
            .query(`UPDATE org.PastoralGroup SET IsActive=0,EffectiveTo=COALESCE(EffectiveTo,CAST(GETDATE() AS date)),ModifiedDate=SYSUTCDATETIME() WHERE PastoralGroupKey=@id AND IsActive=1; SELECT @@ROWCOUNT AS updated;`);
        if (!output.recordset[0].updated) return res.status(404).json({ success: false, error: 'Active pastoral group not found.' });
        return result(res, { pastoralGroupId: Number(req.params.groupId), deleted: true });
    } catch (error) { return next(error); }
});

router.get('/org/staff', guard(), async (req, res, next) => {
    try {
        const sql = sqlFor(req); const limit = Math.min(100, Math.max(1, Number(req.query.limit) || 25)); const offset = Math.max(0, Number(req.query.offset) || 0); const search = String(req.query.search || '');
        const output = await (await poolFor(req)).request().input('search', sql.NVarChar(250), `%${search}%`).input('active', sql.Bit, req.query.active == null ? null : req.query.active === 'true').input('limit', sql.Int, limit).input('offset', sql.Int, offset).query(`SELECT StaffKey AS staffId,MasterStaffKey AS masterStaffKey,DisplayName AS displayName,EmailAddress AS emailAddress,IsActive AS isActive FROM org.Staff WHERE (@active IS NULL OR IsActive=@active) AND (@search=N'%%' OR DisplayName LIKE @search OR EmailAddress LIKE @search) ORDER BY DisplayName OFFSET @offset ROWS FETCH NEXT @limit ROWS ONLY;`);
        return result(res, { items: output.recordset, limit, offset });
    } catch (error) { return next(error); }
});

router.get('/org/staff/:staffId', guard(), async (req, res, next) => {
    try {
        const sql = sqlFor(req); const output = await (await poolFor(req)).request().input('id', sql.Int, id(req.params.staffId, 'staffId')).query(`SELECT StaffKey AS staffId,MasterStaffKey AS masterStaffKey,DisplayName AS displayName,EmailAddress AS emailAddress,IsActive AS isActive FROM org.Staff WHERE StaffKey=@id;`);
        if (!output.recordset.length) return res.status(404).json({ success: false, error: 'Staff member not found.' });
        return result(res, output.recordset[0]);
    } catch (error) { return next(error); }
});

router.get('/org/staff/:staffId/responsibilities', guard(), async (req, res, next) => {
    try {
        const sql = sqlFor(req); const output = await (await poolFor(req)).request().input('id', sql.Int, id(req.params.staffId, 'staffId')).query(`SELECT N'House' AS assignmentType,HouseKey AS relatedKey,RoleCode AS roleCode,EffectiveFrom,EffectiveTo FROM org.StaffHouseAssignment WHERE StaffKey=@id UNION ALL SELECT N'PastoralGroup',PastoralGroupKey,RoleCode,EffectiveFrom,EffectiveTo FROM org.StaffPastoralGroupAssignment WHERE StaffKey=@id ORDER BY EffectiveFrom DESC;`);
        return result(res, output.recordset);
    } catch (error) { return next(error); }
});

router.get('/org/houses/:houseId/staff', guard(), async (req, res, next) => {
    try { const sql = sqlFor(req); return result(res, (await procedure(req, 'org.usp_GetHouseStaff', [['HouseKey', sql.Int, id(req.params.houseId, 'houseId')], ['AsAtDate', sql.Date, date(req.query.asAtDate)]])).recordset); } catch (error) { return next(error); }
});
router.get('/org/pastoral-groups/:groupId/staff', guard(), async (req, res, next) => {
    try { const sql = sqlFor(req); return result(res, (await procedure(req, 'org.usp_GetPastoralGroupStaff', [['PastoralGroupKey', sql.Int, id(req.params.groupId, 'groupId')], ['AsAtDate', sql.Date, date(req.query.asAtDate)]])).recordset); } catch (error) { return next(error); }
});

router.post('/org/houses/:houseId/staff-assignments', guard(true), async (req, res, next) => {
    try {
        const body = req.body || {}; const sql = sqlFor(req);
        if (!body.staffKey || !body.effectiveFrom) return res.status(400).json({ success: false, error: 'staffKey and effectiveFrom are required.' });
        await procedure(req, 'org.usp_AssignHeadOfHouse', [['StaffKey', sql.Int, id(body.staffKey, 'staffKey')], ['HouseKey', sql.Int, id(req.params.houseId, 'houseId')], ['EffectiveFrom', sql.Date, body.effectiveFrom], ['EffectiveTo', sql.Date, body.effectiveTo || null], ['IsPrimary', sql.Bit, body.isPrimary ?? true], ['SourceSystem', sql.NVarChar(100), body.sourceSystem || 'API'], ['SourceAssignmentId', sql.NVarChar(150), body.sourceRecordId || null], ['Actor', sql.NVarChar(255), req.actor]]);
        return result(res, { assigned: true }, 201);
    } catch (error) { return next(error); }
});
router.post('/org/pastoral-groups/:groupId/staff-assignments', guard(true), async (req, res, next) => {
    try {
        const body = req.body || {}; const sql = sqlFor(req);
        if (!body.staffKey || !body.effectiveFrom) return res.status(400).json({ success: false, error: 'staffKey and effectiveFrom are required.' });
        await procedure(req, 'org.usp_AssignPastoralCareTeacher', [['StaffKey', sql.Int, id(body.staffKey, 'staffKey')], ['PastoralGroupKey', sql.Int, id(req.params.groupId, 'groupId')], ['EffectiveFrom', sql.Date, body.effectiveFrom], ['EffectiveTo', sql.Date, body.effectiveTo || null], ['IsPrimary', sql.Bit, body.isPrimary ?? true], ['IsTemporary', sql.Bit, body.isTemporary ?? false], ['SourceSystem', sql.NVarChar(100), body.sourceSystem || 'API'], ['SourceAssignmentId', sql.NVarChar(150), body.sourceRecordId || null], ['Actor', sql.NVarChar(255), req.actor]]);
        return result(res, { assigned: true }, 201);
    } catch (error) { return next(error); }
});
router.put('/org/houses/:houseId/staff-assignments/:assignmentId', guard(true), async (req, res, next) => {
    try {
        const sql = sqlFor(req);
        const output = await (await poolFor(req)).request()
            .input('houseKey', sql.Int, id(req.params.houseId, 'houseId'))
            .input('assignmentId', sql.BigInt, id(req.params.assignmentId, 'assignmentId'))
            .input('fromDate', sql.Date, req.body?.effectiveFrom || null)
            .input('toDate', sql.Date, req.body?.effectiveTo || null)
            .query(`UPDATE org.StaffHouseAssignment SET EffectiveFrom=COALESCE(@fromDate,EffectiveFrom),EffectiveTo=@toDate WHERE StaffHouseAssignmentKey=@assignmentId AND HouseKey=@houseKey; SELECT @@ROWCOUNT AS updated;`);
        if (!output.recordset[0].updated) return res.status(404).json({ success: false, error: 'Assignment not found.' });
        return result(res, { assignmentId: Number(req.params.assignmentId) });
    } catch (error) { return next(error); }
});
router.put('/org/pastoral-groups/:groupId/staff-assignments/:assignmentId', guard(true), async (req, res, next) => {
    try {
        const sql = sqlFor(req);
        const output = await (await poolFor(req)).request()
            .input('groupKey', sql.Int, id(req.params.groupId, 'groupId'))
            .input('assignmentId', sql.BigInt, id(req.params.assignmentId, 'assignmentId'))
            .input('fromDate', sql.Date, req.body?.effectiveFrom || null)
            .input('toDate', sql.Date, req.body?.effectiveTo || null)
            .query(`UPDATE org.StaffPastoralGroupAssignment SET EffectiveFrom=COALESCE(@fromDate,EffectiveFrom),EffectiveTo=@toDate WHERE StaffPastoralGroupAssignmentKey=@assignmentId AND PastoralGroupKey=@groupKey; SELECT @@ROWCOUNT AS updated;`);
        if (!output.recordset[0].updated) return res.status(404).json({ success: false, error: 'Assignment not found.' });
        return result(res, { assignmentId: Number(req.params.assignmentId) });
    } catch (error) { return next(error); }
});

router.use((error, req, res, next) => {
    const status = error.status || (error.number === 51000 ? 404 : 503);
    console.error('Organisation API error:', { method: req.method, path: req.path, status, code: error.code, number: error.number });
    return res.status(status).json({ success: false, error: status === 503 ? 'Database operation failed.' : error.message });
});

export default router;
