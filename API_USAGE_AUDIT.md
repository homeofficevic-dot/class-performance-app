# API usage and SQL source audit

This audit describes routes registered by the current [API server](./server.mjs) and the Angular clients in the sibling application. It is not a contract for the older `server_DevWorking.mjs` or for API paths that only appear in unused frontend services.

## Student picker performance and call flow

The Add Students picker previously called `GET /api/compass/students` as soon as the incident form initialized. That endpoint has no search or paging and retrieves every matching student, current class aggregates, and pastoral assignments before sending a response. In one local run, the legacy endpoint did not finish within the 90-second client timeout.

The picker now makes an on-demand request when opened; typing adds a debounced `q` parameter:

```http
GET /api/compass/students/search?limit=50
GET /api/compass/students/search?q=charley&limit=50
```

In the Angular app, [incident-form.component.ts](../student-wellbeing-app/src/app/modules/incidents/incident-form.component.ts) calls [CompassStudentService.searchStudents](../student-wellbeing-app/src/app/services/compass-student.service.ts) when the dialog opens and after 250 ms of typing. [student-profile-page.component.ts](../student-wellbeing-app/src/app/modules/student-profile/student-profile-page.component.ts) uses the same search instead of eagerly downloading the directory. Requests are cancelled when a newer query is typed.

### Search contract

| Parameter | Meaning |
|---|---|
| `q` | Optional text matched against first/preferred/last names, username, student code, year level, current class code, or house name. Maximum 100 characters. |
| `limit` | 1–50; default 50. |
| `offset` | 0–10,000; default 0. |
| `studentKeys` and `incidentId` | Optional together: comma-separated list of 1–50 positive keys plus the incident ID. The API only returns keys already linked to that incident; this supports editing students no longer in the BlendED campus directory without exposing arbitrary student-key lookup. |

Interactive searches are restricted to the current BlendED campus. Search terms are SQL parameters; LIKE wildcard characters in user input are escaped. Matching students are ordered by last name, first name, then key. A maximum of 51 rows is read to calculate `page.hasMore`, and only the requested page is returned.

The SQL reads `gold.dimStudent`, `gold.dimCampus`, `gold.factStudentClassMembership`, and `wellbeing.vw_StudentCurrentPastoralAssignment`. It returns student identity/status fields, current class and house display values, and `PastoralAssignmentHasConflict`. Multiple house values are displayed as a list; conflict state is not hidden by selecting an arbitrary assignment.

Example:

```powershell
curl.exe -G "http://127.0.0.1:4201/api/compass/students/search" `
  -H "x-dev-staff-key: <active StaffKey>" `
  --data-urlencode "q=charley" `
  --data-urlencode "limit=25"
```

The `x-dev-staff-key` header is only for loopback development when `WELLBEING_DEV_AUTH=true` and `NODE_ENV` is not `production`. In normal use, the host authentication integration must supply `req.user`; the exact production token/cookie mechanism is not implemented in these route files. A successful response is:

```json
{
  "success": true,
  "data": [{
    "StudentKey": 101,
    "StudentCode": "CBRAD01",
    "FirstName": "Charley",
    "LastName": "Brady",
    "ClassName": "7MATH",
    "HouseName": "Example House",
    "PastoralAssignmentHasConflict": false
  }],
  "page": { "limit": 25, "offset": 0, "hasMore": false },
  "query": "charley"
}
```

The response values above are illustrative. In local smoke tests, an unfiltered first page returned five rows in about 0.9 seconds; a broad `q=a` search took about 2.9 seconds for five rows. These are single end-to-end measurements, not performance guarantees. A non-paged legacy `GET /api/compass/students` request exceeded the 90-second client timeout in the same environment. The legacy endpoint remains for compatibility, but new picker code should use `/students/search`.

## Architecture and access control

- Angular development proxy: `/api/*` to `http://127.0.0.1:4201`.
- The main Express process mounts Compass, attendance, class, assessment, Chronicle, organisation, wellbeing, incident, and admin routers. These routes share the SQL pool configured in `api/server.mjs`.
- Default SQL target: `localhost` / `SchoolDW` using Windows authentication; `.env` may override it. Gold-layer endpoints query MSSQL directly; wellbeing and organisation routes query the corresponding `wellbeing` or `org` tables, views, and stored procedures.
- Most wellbeing incident routes use `requireIncidentRole`, which resolves the authenticated username against `gold.dimStaff`, `org.Staff`, role assignments, and group assignments. The route requires a trusted `req.user` principal. Development identity emulation is loopback-only.
- Organisation routes use a separate `API_AUTH_REQUIRED` guard and role headers (`x-user-roles`, `x-user-id`). When `API_AUTH_REQUIRED` is not enabled, this guard does not enforce authentication. Do not treat it as equivalent to the incident-role guard.
- Some Compass attendance, assessment, Chronicle, and organization-reference endpoints do not have route-level incident-role middleware. Enforce access at the hosting boundary before exposing the service outside its trusted environment.
- Read endpoint registration is not proof that the operation is reachable to an unauthenticated user; actual access depends on the middleware and host identity integration described above.

## Route inventory

### Health and staff identity

| Method and path | Purpose and SQL source | Frontend/use |
|---|---|---|
| `GET /api/health` | Connection check (`SELECT 1`). | Health probes. The outer API server's route handles this path before the mounted wellbeing app. |
| `GET /api/auth/dev/staff` | Loopback-only development identities and role labels from `org.Staff`, `gold.dimStaff`, and role/group assignment data. | Incident form/list local identity selector; only available when development identity is enabled. |
| `GET /api/auth/me` | Authenticated staff profile and resolved roles from `gold.dimStaff`. | Incident form's reporting staff identity. |
| `GET /api/admin/user-groups` | Super-user list of staff and group/effective role memberships from `gold.dimStaff`, `org.Staff`, and wellbeing role/group tables. | User/group administration page. |
| `PUT /api/admin/user-groups/:staffKey` | Replace a staff member's managed group memberships; transactional SQL writes and audit. Body: `{ "groups": ["REPORTING_STAFF"] }`. | User/group administration page. Requires `SUPER_USER`. |

`AuthService` also declares `POST /api/auth/login`, `POST /api/auth/logout`, and `POST /api/auth/refresh`. No matching handlers are registered in this API server; they must be supplied by an external authentication service or should be treated as unavailable here.

### Incident reporting, history, and consequences

All paths below are under `/api`. Incident reads require an incident read role. Create/update/cancel/consequence workflow operations use their specific role checks. Incident writes use MSSQL transactions and write audit records.

| Method and path | Purpose / request | SQL source | Angular caller |
|---|---|---|---|
| `GET /api/wellbeing/reference-data/locations` | Active incident locations. | `wellbeing.tblSchoolLocations`, `wellbeing.IncidentClassificationLocation` | `IncidentService.getIncidentLocations`; form and list filters. |
| `GET /api/wellbeing/reference-data/classifications?locationId=ID` | Classifications mapped to a location. | `wellbeing.IncidentClassificationLocation`, `wellbeing.tblIncidentClassifications` | `getIncidentClassifications`; form and list filters. |
| `GET /api/wellbeing/reference-data/incident-types?classificationId=ID` | Active types mapped to classification. | `wellbeing.IncidentTypeClassification`, `wellbeing.tblIncidentTypes` | `getIncidentTypes`; form and list filters. |
| `GET /api/wellbeing/reference-data/consequences?locationId=ID&classificationId=ID&incidentTypeId=ID&incidentDate=YYYY-MM-DD` | Consequence options and configured dates/roles/communication metadata. | Wellbeing consequence and legacy mapping/rule/template tables. | `getIncidentConsequenceOptions`; incident form. |
| `GET /api/incidents?page=1&limit=10&...filters` | Paged incident directory with supported filters and sorting. | `wellbeing.vwIncidentDirectory` and related incident tables. | Incident list. |
| `GET /api/incidents/:id` | Incident details plus historical `IncidentStudent` snapshots. | `wellbeing.vwIncidentDirectory`, `wellbeing.IncidentStudent`. | Incident form edit and incident details. |
| `POST /api/incidents` | Create incident; send `Idempotency-Key`. Body includes student keys, date/time, location, classification/type, description, reporting staff, and notes. | Wellbeing incident tables, Gold student/staff data, audit tables. | Incident form. |
| `PUT /api/incidents/:id` | Update permitted incident fields. | Wellbeing incident and audit tables. | Incident form edit. |
| `POST /api/incidents/:id/cancel` | Controlled cancellation with audit. | Wellbeing incident and audit tables. | Incident details/actions. |
| `DELETE /api/incidents/:id` | Compatibility alias for controlled cancellation; it does not physically delete history. | Wellbeing incident and audit tables. | Legacy clients only. |
| `GET /api/incidents/:id/audit?page=1&limit=25` | Paged audit history for an incident. | `wellbeing.AuditEvent` / incident audit records. | Incident details. |
| `GET /api/students?page=1&limit=10` | Paged Gold student directory. | Count and page queries against `gold.dimStudent`. | `StudentService.getStudents` if used. |
| `GET /api/students/:studentKey` | Student record by Gold key. | `gold.dimStudent`. | `StudentService.getStudentById` if used. |
| `GET /api/students/:studentKey/incidents?page=1&limit=5` | Resolve student identifier and return historical incidents. | `gold.dimStudent`, `wellbeing.IncidentStudent`, `wellbeing.vwIncidentDirectory`. | Incident form's prior-history review and student history. |
| `GET /api/incidents/:id/consequences/eligible?studentKey=ID&proposedDate=YYYY-MM-DD` | Evaluate eligible consequence options for a student/date. | Wellbeing consequence rules, incident snapshot, calendar and existing assignment data. | Incident consequence flow. |
| `POST /api/incidents/:id/consequences` | Assign one selected consequence; send `Idempotency-Key` and student/consequence/scheduled-date fields. Server revalidates eligibility. | Wellbeing assignment/rule/audit tables and stored procedures. | Incident consequence flow. |
| `GET /api/incidents/:id/consequences` | List incident consequence assignments and workflow state. | Wellbeing consequence assignment/workflow tables. | Incident details. |
| `GET /api/consequences/work-queue` | Return open in-app consequence notifications matching the authenticated user's resolved roles. | `wellbeing.ConsequenceWorkflowNotification`, consequence assignments, and staff role/group data. | Callable by authenticated staff; no Angular work-queue screen currently consumes it. |
| `GET /api/consequences/:assignmentId/audit` | Consequence workflow audit. | Wellbeing consequence audit tables. | Incident details. |
| `POST /api/consequences/:assignmentId/approve` | Approve assignment; body may include notes. | `wellbeing.usp_TransitionIncidentConsequence` and workflow/audit tables. | Authorized review actions. |
| `POST /api/consequences/:assignmentId/reject` | Reject assignment; body may include notes. | Same transition procedure. | Authorized review actions. |
| `POST /api/consequences/:assignmentId/complete` | Mark assignment completed; body may include notes. | Same transition procedure. | Authorized processing actions. |
| `POST /api/consequences/:assignmentId/cancel` | Cancel assignment; body may include notes. | Same transition procedure. | Authorized workflow actions. |

The incident create form calls location/classification/type/consequence reference endpoints as selections change. It sends the incident first and consequence assignment separately. Detention approval rules are application overrides, kept separate from the imported legacy values. Saving an approval-required assignment creates an in-app role notification in the assignment transaction; `GET /api/consequences/work-queue` exposes it to authenticated role members. Parent/student/staff email delivery is not implemented; legacy communication templates are recipient metadata only.

### Student pastoral assignments and organisation management

All of these paths are mounted at `/api` from [organisation-routes.mjs](./organisation-routes.mjs). Data is read from or written to `org.*` tables, views, and procedures. Read/write guards use `API_AUTH_REQUIRED` and the role headers described above.

| Method and path | Use |
|---|---|
| `GET /api/wellbeing/students/:studentKey/pastoral-assignment?asAtDate=YYYY-MM-DD` | Current or as-at-date House/group/Pastoral Care Teacher/Head of House lookup using `org.usp_GetStudentPastoralAssignment`. |
| `GET /api/wellbeing/students/:studentKey/pastoral-history` | Effective-dated student assignment history. |
| `POST /api/wellbeing/students/:studentKey/pastoral-assignment` | Create effective-dated student pastoral assignment. |
| `PUT /api/wellbeing/students/:studentKey/pastoral-assignment/:assignmentId` | Update assignment dates/status. |
| `GET /api/org/houses`, `GET /api/org/houses/:houseId` | List or retrieve houses. |
| `POST /api/org/houses`, `PUT /api/org/houses/:houseId`, `DELETE /api/org/houses/:houseId` | Create, update, or deactivate house records; delete is a soft deactivation. |
| `GET /api/org/pastoral-groups`, `GET /api/org/pastoral-groups/:groupId` | List or retrieve pastoral groups. |
| `POST /api/org/pastoral-groups`, `PUT /api/org/pastoral-groups/:groupId`, `DELETE /api/org/pastoral-groups/:groupId` | Create, update, or deactivate pastoral groups; delete is a soft deactivation. |
| `GET /api/org/staff?search=TEXT&active=true&limit=25&offset=0` | Search/paginate staff. |
| `GET /api/org/staff/:staffId` | Retrieve staff record. |
| `GET /api/org/staff/:staffId/responsibilities` | Read staff House/group responsibilities. |
| `GET /api/org/houses/:houseId/staff` | List House staff assignments. |
| `GET /api/org/pastoral-groups/:groupId/staff` | List pastoral-group staff assignments. |
| `POST /api/org/houses/:houseId/staff-assignments` | Assign staff responsibility to House. |
| `POST /api/org/pastoral-groups/:groupId/staff-assignments` | Assign staff responsibility to group. |
| `PUT /api/org/houses/:houseId/staff-assignments/:assignmentId` | Update House staff effective dates/role. |
| `PUT /api/org/pastoral-groups/:groupId/staff-assignments/:assignmentId` | Update group staff effective dates/role. |

Angular callers: the pastoral admin uses [pastoral.service.ts](../student-wellbeing-app/src/app/modules/pastoral/pastoral.service.ts); group/user management calls `/api/admin/user-groups`. The displayed student profile is sourced from Compass/Gold; this organisation API is the effective-dated responsibility source, not a replacement student master.

### Generic wellbeing configuration

`/api/admin/config` and the legacy alias `/api/wellbeing` are mounted from [admin-config.routes.mjs](./backend/routes/admin-config.routes.mjs). The UI uses [admin-config.service.ts](../student-wellbeing-app/src/app/shared/admin/admin-config.service.ts).

| Method and path | Operation |
|---|---|
| `GET /api/admin/config/resources` | Enumerate configurable resource keys and metadata. |
| `GET /api/admin/config/:resource?limit=25&offset=0` | Paginated read of a configured resource. |
| `POST /api/admin/config/:resource` | Create a row; body keys must be among that resource's configured columns and required fields. |
| `PUT /api/admin/config/:resource/:id` | Update a configured row. |
| `DELETE /api/admin/config/:resource/:id` | Deactivate/soft-delete rather than ordinary physical deletion. |

Resource keys: `houses`, `assignments`, `locations`, `types`, `classifications`, `policyLevels`, `consequences`, `incidentDefinitions`, `consequencePolicyRules`, `approvalWorkflows`, `approvalWorkflowSteps`, `workflowInstances`, `workflowTasks`, `workflowApprovals`, `communicationTemplates`, `parentNotifications`, `parentConsentResponses`, `schoolCalendar`, `detentionSchedules`, `auditEvents`. These CRUD resources use legacy `wellbeing.*` tables and are distinct from the newer `org.*` pastoral routes.

### Compass, class, attendance, Chronicle, and assessment

These routes are mounted at `/api/compass`. Their primary source is the SchoolDW Gold layer. [API_DOCUMENTATION.md](./API_DOCUMENTATION.md) provides detailed parameters and response shapes for the Compass/class/attendance routes.

| Method and path | Purpose / source | Frontend use |
|---|---|---|
| `GET /api/compass/students/search?q=...&limit=...&offset=...` | Bounded student lookup from `gold.dimStudent`, current campus/classes, and pastoral view. | Incident form and student profile selectors. |
| `GET /api/compass/students` | Legacy unpaged directory; includes current classes and House/pastoral assignment. | Compatibility only; not used by the updated pickers. |
| `GET /api/compass/students/by-username/:username` | Student from `gold.dimStudent`. | Compass/student helper. |
| `GET /api/compass/students/by-student-code/:studentCode` | Student profile from `gold.dimStudent`. | Student profile page route. |
| `GET /api/compass/campuses` | Campus list from `gold.vwCampus`. | Campus and attendance selectors. |
| `GET /api/compass/class-performance/staff` | Staff with current classes from Gold directory/class facts. | Student profile staff selector. |
| `GET /api/compass/staff/:compassPersonId/classes` | Teacher's class allocations. | Class/profile screens. |
| `GET /api/compass/classes/:classSourcedId/students` | Current class roster. | Class screens. |
| `GET /api/compass/students/:compassPersonId/classes` | Student classes and current teachers. | Student profile. |
| `GET /api/compass/students/:compassPersonId/attendance` | Paged attendance from `gold.fact_attendance_period`, date dimensions, and student dimension. | Student attendance screens. |
| `GET /api/compass/students/:compassPersonId/attendance-analytics` | Student attendance summaries/analytics. | Compass student service. |
| `GET /api/compass/students/attendance-analytics` | Campus-filterable student attendance analytics. | Attendance dashboard/service. |
| `GET /api/compass/campuses/attendance-analytics?campusId=...` | Campus attendance analytics. | Attendance dashboard/service. |
| `GET /api/compass/campuses/:campusId/attendance-analytics` | Campus analytics path alias. | Attendance dashboard/service. |
| `GET /api/compass/classes/:classSourcedId/attendance-analytics` | Class attendance analytics. | Class profile/attendance. |
| `GET /api/compass/attendance?limit=100&offset=0` | Paged period attendance. | Attendance record service. |
| `GET /api/compass/students/:studentId/chronicle-insights` | Student wellbeing/inclusion/outreach summaries from Chronicle Gold views. | Chronicle insights service. |
| `GET /api/compass/students/:studentId/chronicle-entries` | Student Chronicle entries from Gold insight views. | Chronicle insights service. |
| `GET /api/compass/classes/:classId/chronicle-insights` | Class Chronicle summaries. | Chronicle insights service. |
| `GET /api/compass/chronicle/insights/domains` | Available Chronicle insight domains. | Chronicle insights screens. |
| `GET /api/compass/pat-results`, `GET /api/compass/campuses/pat-results`, `GET /api/compass/campuses/:campusId/pat-results` | Paged PAT assessments from assessment fact/silver sources. | Assessment service when used. |
| `GET, POST /api/compass/essential-assessment-results`, `GET, POST /api/compass/campuses/essential-assessment-results`, `GET, POST /api/compass/campuses/:campusId/essential-assessment-results` | Paged essential-assessment results; POST is also registered by the current router. | Assessment service when used. |
| `GET /api/compass/student-photos/:username`, `GET /api/compass/person-photos/:username` | Serve `{username}.png` from `COMPASS_PHOTOS_DIR`; read role required. | Student/staff photos. |

Attendance routes accept `year`, or `startDate` plus `endDate`, and relevant routes accept `limit`/`offset`. Analytics use an in-memory five-minute cache. Route-level auth is inconsistent across the Compass subrouters: the student search and class-performance routes are guarded; attendance, Chronicle, and assessment handlers are not guarded in these modules.

## Frontend-only paths not implemented by this API server

The following paths are present in frontend service methods, but no matching route is registered in the current API server:

- `/api/students/search`, `/api/students/at-risk`
- `/api/students/:id/support-plan`
- `/api/students/:id/wellbeing-notes` (`GET` and `POST`)
- `/api/students/:id/risk-assessment`
- `/api/classes/:classCode/students`, `/api/year-levels/:yearLevel/students`
- `/api/staff` (incident service's staff-dropdown helper)
- `/api/compass/staff` (raw paged staff helper; class-performance staff is available at `/api/compass/class-performance/staff`)
- `/api/compass/learning-needs`
- `/api/incidents/search`, `/api/incidents/export`, `/api/incidents/stats`
- `/api/incidents/:id/approve`, `/api/incidents/:id/reject` (the registered workflow paths are `/api/consequences/:assignmentId/approve|reject`)

Calls to these paths receive the API 404 response unless another server/proxy provides them. The supported student endpoints in this server are `/api/students`, `/api/students/:id`, and `/api/students/:id/incidents`.

## SQL and operational notes

- All search values and incident parameters are passed as SQL parameters in the current route implementations. Generic configuration table/column names come from a server-side allowlist, not directly from request text.
- Connection defaults are in [server.mjs](./server.mjs). Requests share a SQL connection pool (max 10; SQL request timeout 60 seconds).
- `GET /api/compass/students` is intentionally retained for compatibility but is unbounded. Do not use it to populate interactive pickers or new screens.
- The new student-search endpoint has been syntax checked and smoke tested against local MSSQL with a valid local development staff identity. Invalid `limit=0` returns HTTP 400. Full production authentication and authorization behavior must be validated in the deployment host.
