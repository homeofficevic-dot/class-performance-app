import express from 'express';
import sql from 'mssql/msnodesqlv8.js';

const router = express.Router();

const resources = {
  houses: {
    table: 'wellbeing.House',
    id: 'HouseId',
    columns: ['HouseCode', 'HouseName', 'Description', 'IsActive', 'EffectiveStartDate', 'EffectiveEndDate']
  },
  assignments: {
    table: 'wellbeing.StaffRoleAssignment',
    id: 'StaffAssignmentId',
    columns: ['StaffKey', 'CompassStaffId', 'StaffEmail', 'AssignedRole', 'HouseAssignment', 'YearLevelResponsibility', 'EffectiveStartDate', 'EffectiveEndDate', 'IsActive']
  },
  locations: {
    table: 'wellbeing.SchoolLocation',
    id: 'LocationId',
    columns: ['LocationCode', 'LocationName', 'LocationDescription', 'LocationCategory', 'ResponsibleDepartment', 'ResponsibleStaffKey', 'IsActive', 'DisplayOrder']
  },
  types: {
    table: 'wellbeing.IncidentType',
    id: 'IncidentTypeId',
    columns: ['IncidentTypeCode', 'IncidentTypeName', 'IncidentTypeDescription', 'IsActive', 'DisplayOrder']
  },
  classifications: {
    table: 'wellbeing.IncidentClassification',
    id: 'ClassificationId',
    columns: ['ClassificationCode', 'ClassificationName', 'ClassificationDescription', 'SeverityLevel', 'PolicyReference', 'RequiresApproval', 'RequiresParentNotification', 'ApprovalRoleRequired', 'IsActive', 'DisplayOrder']
  },
  policyLevels: {
    table: 'wellbeing.BehaviourPolicyLevel',
    id: 'PolicyLevelId',
    columns: ['PolicyLevelCode', 'PolicyLevelName', 'PolicyLevelDescription', 'SeverityScore', 'IsActive', 'DisplayOrder']
  },
  consequences: {
    table: 'wellbeing.Consequence',
    id: 'ConsequenceId',
    columns: ['ConsequenceCode', 'ConsequenceName', 'ConsequenceDescription', 'PolicyLevelId', 'SeverityLevel', 'RequiresApproval', 'RequiresParentNotification', 'ApprovalRoleRequired', 'EstimatedDurationDays', 'DisplayOrder', 'IsActive']
  },
  incidentDefinitions: {
    table: 'wellbeing.IncidentDefinition',
    id: 'IncidentDefinitionId',
    columns: ['DefinitionCode', 'DefinitionName', 'Description', 'ClassificationId', 'IncidentTypeId', 'PolicyLevelId', 'ApplicableYearLevels', 'ApplicableLocationIds', 'IsActive', 'EffectiveStartDate', 'EffectiveEndDate']
  }
  ,
  consequencePolicyRules: {
    table: 'wellbeing.ConsequencePolicyRule',
    id: 'ConsequencePolicyRuleId',
    columns: ['ConsequenceId', 'PolicyLevelId', 'IncidentTypeId', 'ClassificationId', 'IsEligible', 'RequiresApproval', 'EffectiveStartDate', 'EffectiveEndDate']
  },
  approvalWorkflows: {
    table: 'wellbeing.ApprovalWorkflow',
    id: 'ApprovalWorkflowId',
    columns: ['WorkflowCode', 'WorkflowName', 'Description', 'TriggerCondition', 'IsActive', 'EffectiveStartDate', 'EffectiveEndDate']
  },
  approvalWorkflowSteps: {
    table: 'wellbeing.ApprovalWorkflowStep',
    id: 'ApprovalWorkflowStepId',
    columns: ['ApprovalWorkflowId', 'StepOrder', 'RequiredRole', 'RequiredStaffKey', 'IsRequired']
  },
  workflowInstances: {
    table: 'wellbeing.WorkflowInstance',
    id: 'WorkflowInstanceId',
    columns: ['ApprovalWorkflowId', 'IncidentId', 'StatusCode', 'StartedDate', 'CompletedDate', 'EffectiveStartDate', 'EffectiveEndDate']
  },
  workflowTasks: {
    table: 'wellbeing.WorkflowTask',
    id: 'WorkflowTaskId',
    columns: ['WorkflowInstanceId', 'ApprovalWorkflowStepId', 'AssignedStaffKey', 'StatusCode', 'DueDate', 'CompletedDate', 'CompletedBy', 'Notes']
  },
  workflowApprovals: {
    table: 'wellbeing.WorkflowApproval',
    id: 'WorkflowApprovalId',
    columns: ['WorkflowTaskId', 'ApprovalStatusKey', 'ApproverStaffKey', 'DecisionDate', 'DecisionNotes']
  },
  communicationTemplates: {
    table: 'wellbeing.CommunicationTemplate',
    id: 'CommunicationTemplateId',
    columns: ['TemplateCode', 'TemplateName', 'Channel', 'SubjectTemplate', 'BodyTemplate', 'RecipientRule', 'IsActive']
  },
  parentNotifications: {
    table: 'wellbeing.ParentNotification',
    id: 'ParentNotificationId',
    columns: ['IncidentId', 'StudentKey', 'CommunicationTemplateId', 'Channel', 'Recipient', 'StatusCode', 'SentDate', 'MessageSubject', 'MessageBody']
  },
  parentConsentResponses: {
    table: 'wellbeing.ParentConsentResponse',
    id: 'ParentConsentResponseId',
    columns: ['ParentNotificationId', 'ResponseCode', 'ResponseDate', 'RespondentName', 'Notes']
  },
  schoolCalendar: {
    table: 'wellbeing.SchoolCalendar',
    id: 'SchoolCalendarId',
    columns: ['CalendarDate', 'CalendarType', 'CalendarName', 'IsSchoolDay', 'Notes']
  },
  detentionSchedules: {
    table: 'wellbeing.DetentionSchedule',
    id: 'DetentionScheduleId',
    columns: ['ScheduleName', 'ScheduleDate', 'StartTime', 'EndTime', 'LocationId', 'Capacity', 'IsActive']
  },
  auditEvents: {
    table: 'wellbeing.AuditEvent',
    id: 'AuditEventId',
    columns: ['EventDate', 'Actor', 'Action', 'EntityName', 'EntityId', 'BeforeJson', 'AfterJson', 'CorrelationId', 'IpAddress']
  }
};

const requiredFields = {
  houses: ['HouseCode', 'HouseName', 'EffectiveStartDate'],
  assignments: ['StaffKey', 'CompassStaffId', 'AssignedRole', 'EffectiveStartDate'],
  locations: ['LocationCode', 'LocationName'],
  types: ['IncidentTypeCode', 'IncidentTypeName'],
  classifications: ['ClassificationCode', 'ClassificationName'],
  policyLevels: ['PolicyLevelCode', 'PolicyLevelName'],
  consequences: ['ConsequenceCode', 'ConsequenceName', 'PolicyLevelId'],
  incidentDefinitions: ['DefinitionCode', 'DefinitionName', 'EffectiveStartDate'],
  consequencePolicyRules: ['ConsequenceId'],
  approvalWorkflows: ['WorkflowCode', 'WorkflowName', 'EffectiveStartDate'],
  approvalWorkflowSteps: ['ApprovalWorkflowId', 'StepOrder', 'RequiredRole'],
  workflowInstances: ['ApprovalWorkflowId'],
  workflowTasks: ['WorkflowInstanceId', 'ApprovalWorkflowStepId'],
  workflowApprovals: ['WorkflowTaskId', 'ApprovalStatusKey'],
  communicationTemplates: ['TemplateCode', 'TemplateName', 'Channel', 'BodyTemplate'],
  parentNotifications: ['IncidentId', 'StudentKey', 'Channel'],
  parentConsentResponses: ['ParentNotificationId', 'ResponseCode'],
  schoolCalendar: ['CalendarDate', 'CalendarType', 'CalendarName'],
  detentionSchedules: ['ScheduleName', 'ScheduleDate', 'StartTime', 'EndTime'],
  auditEvents: ['Actor', 'Action', 'EntityName', 'EntityId']
};

const numericFields = new Set(['StaffKey', 'ResponsibleStaffKey', 'PolicyLevelId', 'ClassificationId', 'IncidentTypeId', 'SeverityLevel', 'SeverityScore', 'DisplayOrder', 'EstimatedDurationDays', 'ConsequenceId', 'ApprovalWorkflowId', 'ApprovalWorkflowStepId', 'WorkflowInstanceId', 'WorkflowTaskId', 'ApprovalStatusKey', 'ApproverStaffKey', 'AssignedStaffKey', 'IncidentId', 'StudentKey', 'CommunicationTemplateId', 'ParentNotificationId', 'LocationId', 'Capacity', 'StepOrder']);

function getResource(key) {
  return resources[key];
}

function validateRecord(resourceKey, definition, body, isCreate) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return 'Request body must be an object.';
  const unknown = Object.keys(body).filter(column => !definition.columns.includes(column));
  if (unknown.length) return `Unsupported fields: ${unknown.join(', ')}.`;
  if (isCreate) {
    const missing = (requiredFields[resourceKey] || []).filter(column => body[column] === undefined || body[column] === null || body[column] === '');
    if (missing.length) return `Required fields missing: ${missing.join(', ')}.`;
  }
  for (const column of numericFields) {
    if (body[column] !== undefined && body[column] !== null && body[column] !== '' && !Number.isInteger(Number(body[column]))) {
      return `${column} must be a whole number.`;
    }
  }
  for (const column of ['EffectiveStartDate', 'EffectiveEndDate']) {
    if (body[column] !== undefined && body[column] !== null && body[column] !== '' && Number.isNaN(Date.parse(body[column]))) {
      return `${column} must be a valid date.`;
    }
  }
  if (body.EffectiveStartDate && body.EffectiveEndDate && new Date(body.EffectiveEndDate) < new Date(body.EffectiveStartDate)) {
    return 'Effective end date cannot be before effective start date.';
  }
  return null;
}

function parseId(value) {
  const id = Number(value);
  return Number.isInteger(id) && id > 0 ? id : null;
}

function sendDatabaseError(res, error) {
  const message = String(error?.message || '');
  if (/duplicate|unique constraint/i.test(message)) {
    return res.status(409).json({ success: false, error: 'A configuration record with the same code already exists.' });
  }
  if (/foreign key|reference constraint|cannot insert the value NULL/i.test(message)) {
    return res.status(400).json({ success: false, error: 'The configuration references an invalid or missing related record.' });
  }
  return res.status(500).json({ success: false, error: 'The administration request could not be completed.' });
}

function isAdministrator(req) {
  if (process.env.NODE_ENV !== 'production') return true;
  const role = String(req.user?.role || '').toLowerCase();
  return ['admin', 'administrator', 'wellbeing-admin'].includes(role);
}

function rejectUnauthorized(req, res) {
  if (isAdministrator(req)) return false;
  res.status(403).json({ success: false, error: 'Administrator role required.' });
  return true;
}

function addInput(request, column, value, sql) {
  if (value === undefined) return;
  if (['IsActive', 'IsEligible', 'IsRequired', 'IsSchoolDay', 'RequiresApproval', 'RequiresParentNotification'].includes(column)) {
    request.input(column, sql.Bit, Boolean(value));
  } else if (['StaffKey', 'ResponsibleStaffKey', 'PolicyLevelId', 'ClassificationId', 'IncidentTypeId', 'SeverityLevel', 'SeverityScore', 'DisplayOrder', 'EstimatedDurationDays'].includes(column)) {
    request.input(column, sql.Int, value === '' || value === null ? null : Number(value));
  } else if (column.includes('Date')) {
    request.input(column, sql.Date, value || null);
  } else {
    request.input(column, sql.NVarChar(sql.MAX), value ?? null);
  }
}

async function writeAudit(pool, req, action, definition, recordId, before, after) {
  try {
    await pool.request()
      .input('user', sql.NVarChar(255), req.get('x-user-email') || req.user?.email || 'administrator')
      .input('action', sql.NVarChar(50), action)
      .input('tableName', sql.NVarChar(100), definition.table)
      .input('recordId', sql.NVarChar(100), String(recordId))
      .input('oldValue', sql.NVarChar(sql.MAX), before ? JSON.stringify(before) : null)
      .input('newValue', sql.NVarChar(sql.MAX), after ? JSON.stringify(after) : null)
      .input('correlationId', sql.NVarChar(100), req.get('x-correlation-id') || null)
      .input('ipAddress', sql.NVarChar(50), req.ip || null)
      .query(`
        INSERT INTO wellbeing.AuditEvent
          (Actor, Action, EntityName, EntityId, BeforeJson, AfterJson, CorrelationId, IpAddress)
        VALUES (@user, @action, @tableName, @recordId, @oldValue, @newValue, @correlationId, @ipAddress)
      `);
  } catch (error) {
    console.error('Administration audit event failed:', error);
    throw error;
  }
}

router.use((req, res, next) => rejectUnauthorized(req, res) ? undefined : next());

router.get('/resources', (_req, res) => {
  res.json({
    success: true,
    data: Object.entries(resources).map(([key, value]) => ({ key, id: value.id, columns: value.columns }))
  });
});

router.get('/:resource', async (req, res) => {
  const definition = getResource(req.params.resource);
  if (!definition) return res.status(404).json({ success: false, error: 'Unknown administration resource.' });
  try {
    const pool = await req.app.locals.getDatabasePool();
    const search = String(req.query.search || '').trim();
    const active = req.query.active;
    const page = Math.max(1, Number.parseInt(req.query.page, 10) || 1);
    const limit = Math.min(100, Math.max(1, Number.parseInt(req.query.limit, 10) || 100));
    const offset = (page - 1) * limit;
    const sortColumn = definition.columns.includes(String(req.query.sortBy))
      ? String(req.query.sortBy)
      : definition.id;
    const sortDirection = String(req.query.sortDirection).toLowerCase() === 'asc' ? 'ASC' : 'DESC';
    const request = pool.request();
    const predicates = [];
    if (search) {
      request.input('search', sql.NVarChar(200), `%${search}%`);
      predicates.push(`(${definition.columns.filter(column => /Name|Code|Description|Role|Category|Reference|House|Email/i.test(column)).map(column => `[${column}] LIKE @search`).join(' OR ')})`);
    }
    if (active === 'true' || active === 'false') {
      request.input('active', sql.Bit, active === 'true');
      predicates.push('[IsActive] = @active');
    }
    const whereClause = predicates.length ? ` WHERE ${predicates.join(' AND ')}` : '';
    const countResult = await request.query(`SELECT COUNT(*) AS total FROM ${definition.table}${whereClause}`);
    const tieBreaker = sortColumn === definition.id ? '' : `, [${definition.id}] DESC`;
    const result = await request.query(`
      SELECT * FROM ${definition.table}${whereClause}
      ORDER BY [${sortColumn}] ${sortDirection}${tieBreaker}
      OFFSET ${offset} ROWS FETCH NEXT ${limit} ROWS ONLY
    `);
    const total = Number(countResult.recordset[0]?.total || 0);
    res.json({
      success: true,
      data: result.recordset,
      pagination: { page, limit, total, pages: Math.max(1, Math.ceil(total / limit)) }
    });
  } catch (error) {
    console.error(`Admin ${req.params.resource} list failed:`, error);
    res.status(500).json({ success: false, error: 'Unable to load administration data.' });
  }
});

router.post('/:resource', async (req, res) => {
  const definition = getResource(req.params.resource);
  if (!definition) return res.status(404).json({ success: false, error: 'Unknown administration resource.' });
  const validationError = validateRecord(req.params.resource, definition, req.body, true);
  if (validationError) return res.status(400).json({ success: false, error: validationError });
  try {
    const pool = await req.app.locals.getDatabasePool();
    const request = pool.request();
    const values = definition.columns.filter(column => req.body[column] !== undefined);
    if (!values.length) return res.status(400).json({ success: false, error: 'No configurable fields supplied.' });
    values.forEach(column => addInput(request, column, req.body[column], sql));
    const result = await request.query(`
      INSERT INTO ${definition.table} (${values.map(column => `[${column}]`).join(', ')})
      OUTPUT INSERTED.*
      VALUES (${values.map(column => `@${column}`).join(', ')})
    `);
    await writeAudit(pool, req, 'INSERT', definition, result.recordset[0][definition.id], null, result.recordset[0]);
    res.status(201).json({ success: true, data: result.recordset[0] });
  } catch (error) {
    console.error(`Admin ${req.params.resource} create failed:`, error);
    sendDatabaseError(res, error);
  }
});

router.put('/:resource/:id', async (req, res) => {
  const definition = getResource(req.params.resource);
  if (!definition) return res.status(404).json({ success: false, error: 'Unknown administration resource.' });
  const recordId = parseId(req.params.id);
  if (!recordId) return res.status(400).json({ success: false, error: 'Record id must be a positive integer.' });
  const validationError = validateRecord(req.params.resource, definition, req.body, false);
  if (validationError) return res.status(400).json({ success: false, error: validationError });
  try {
    const pool = await req.app.locals.getDatabasePool();
    const request = pool.request().input('recordId', sql.Int, recordId);
    const beforeResult = await pool.request().input('recordId', sql.Int, recordId)
      .query(`SELECT * FROM ${definition.table} WHERE [${definition.id}] = @recordId`);
    const values = definition.columns.filter(column => req.body[column] !== undefined);
    if (!values.length) return res.status(400).json({ success: false, error: 'No configurable fields supplied.' });
    values.forEach(column => addInput(request, column, req.body[column], sql));
    const result = await request.query(`
      UPDATE ${definition.table}
      SET ${values.map(column => `[${column}] = @${column}`).join(', ')}
      OUTPUT INSERTED.*
      WHERE [${definition.id}] = @recordId
    `);
    if (!result.recordset.length) return res.status(404).json({ success: false, error: 'Configuration record not found.' });
    await writeAudit(pool, req, 'UPDATE', definition, recordId, beforeResult.recordset[0], result.recordset[0]);
    res.json({ success: true, data: result.recordset[0] });
  } catch (error) {
    console.error(`Admin ${req.params.resource} update failed:`, error);
    sendDatabaseError(res, error);
  }
});

router.delete('/:resource/:id', async (req, res) => {
  const definition = getResource(req.params.resource);
  if (!definition) return res.status(404).json({ success: false, error: 'Unknown administration resource.' });
  const recordId = parseId(req.params.id);
  if (!recordId) return res.status(400).json({ success: false, error: 'Record id must be a positive integer.' });
  try {
    const pool = await req.app.locals.getDatabasePool();
    const request = pool.request().input('recordId', sql.Int, recordId);
    const beforeResult = await pool.request().input('recordId', sql.Int, recordId)
      .query(`SELECT * FROM ${definition.table} WHERE [${definition.id}] = @recordId`);
    const result = req.params.resource === 'consequencePolicyRules'
      ? await request.query(`UPDATE ${definition.table} SET IsEligible = 0, EffectiveEndDate = COALESCE(EffectiveEndDate, CAST(GETDATE() AS date)), ModifiedDate = GETUTCDATE() WHERE [${definition.id}] = @recordId`)
      : await request.query(`UPDATE ${definition.table} SET IsActive = 0 WHERE [${definition.id}] = @recordId`);
    if (result.rowsAffected[0]) {
      await writeAudit(
        pool,
        req,
        'DEACTIVATE',
        definition,
        recordId,
        beforeResult.recordset[0],
        req.params.resource === 'consequencePolicyRules'
          ? { IsEligible: false, EffectiveEndDate: new Date().toISOString().slice(0, 10) }
          : { IsActive: false }
      );
    }
    res.json({ success: true, rowsAffected: result.rowsAffected[0] });
  } catch (error) {
    console.error(`Admin ${req.params.resource} deactivate failed:`, error);
    sendDatabaseError(res, error);
  }
});

export default router;
