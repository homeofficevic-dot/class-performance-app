# Compass and Class Performance API – Reference

Reference for the Compass data API served by [server.mjs](./server.mjs) (routes in [gold-class-routes.mjs](./gold-class-routes.mjs) and [attendance-routes.mjs](./attendance-routes.mjs); analytics logic in [attendance-analytics.mjs](./attendance-analytics.mjs)). All data comes from the SchoolDW **Gold** layer. The complete mounted API, including wellbeing, organisation, authentication, admin, and frontend caller coverage, is in [API_USAGE_AUDIT.md](./API_USAGE_AUDIT.md).

> The older [API_ENDPOINTS_GUIDE.md](./API_ENDPOINTS_GUIDE.md) describes the previous `server_DevWorking.mjs` (payload-table based) server. Endpoints for PAT/Essential Assessment results, raw staff/attendance/learning-needs payloads, and campus-by-id assessments are **not served by `server.mjs`**; see [Not available](#not-available-in-servermjs).

## 1. Overview

| Item | Value |
|---|---|
| Runtime | Node.js (ES modules), Express 5, `mssql` + `msnodesqlv8` |
| Start | `npm start` (runs `node server.mjs`) |
| Default port | `4201` (`COMPASS_PROXY_PORT`) |
| Base URL | `http://127.0.0.1:4201` |
| API prefix | `/api/compass` (health is `/api/health`) |
| Format | JSON (`express.json` limit 10 MB). This Compass route family is read-only. Other mounted API families include writes. |
| Auth | Mixed by route family. Compass student search and class-performance routes require an incident read role; several attendance and analytics routes currently have no route-level guard. See [API_USAGE_AUDIT.md](./API_USAGE_AUDIT.md#authentication-and-exposure). |
| CORS | Not configured. |

### Configuration (`.env`)

| Variable | Default | Purpose |
|---|---|---|
| `COMPASS_PROXY_PORT` | `4201` | HTTP port |
| `SQL_SERVER` | `localhost` | SQL Server host |
| `SQL_DATABASE` | `SchoolDW` | Database |
| `SQL_DRIVER` | `ODBC Driver 17 for SQL Server` | ODBC driver |
| `SQL_AUTH` | `windows` | `windows` (trusted connection) or `sql`/`sqlserver` |
| `SQL_USER`, `SQL_PASSWORD` | – | Required when `SQL_AUTH=sql` |
| `SQL_TRUST_SERVER_CERTIFICATE` | `true` | Trust server cert |
| `COMPASS_PHOTOS_DIR` | `C:\Sanits\CompassPhotos` | Folder of `{username}.png` photos |
| `NODE_ENV` | – | `development` adds `details` (raw error text) to 500 responses |

Connection pool: max 10, connection timeout 30 s, request timeout 60 s. The server exits at startup if SQL Server is unreachable.

## 2. Conventions

### Identifiers
| Name | Meaning |
|---|---|
| `compassPersonId` | Compass person GUID string (student or staff), max 100 chars |
| `classSourcedId` | Compass class ID (`CompassClassId`). The class **code** is also accepted by class roster and class attendance endpoints |
| `campusId` | Campus GUID (`CampusGuid`) |
| `studentCode` | School student code (case-insensitive lookup) |

### Query parameters

**Paging** (`/students/{id}/attendance`, `/attendance`): `limit` 1–500 (default 100), `offset` ≥ 0 (default 0).

**Date filters** (all attendance endpoints):

| Param | Rules |
|---|---|
| `year` | Four digits, matches `gold.dimDate.CalendarYear` |
| `startDate`, `endDate` | Both or neither. Any value `new Date()` can parse (ISO 8601 recommended, e.g. `2026-07-01T00:00:00Z`). `startDate` must be before `endDate`. Filter is `AttendanceDate >= startDate AND AttendanceDate < endDate` (end exclusive, compared as dates) |

`year` can be combined with `startDate`/`endDate`.

### Caching
Analytics endpoints (`*/attendance-analytics`, except the per-student totals list) use an in-memory cache, key = scope + filters, TTL **5 minutes**. There is **no** `refresh` parameter in this server; restart to clear.

### Errors
Body is always `{ "error": "message" }`.

| Status | When |
|---|---|
| 400 | Invalid ID, paging or date parameter |
| 404 | Student not found; unknown route (`{ error, method, path }`) |
| 500 | `/health` failure, `/students/by-username`, `/students`, unhandled errors (`details` only if `NODE_ENV=development`) |
| 503 | Database query failure in all other routes |

## 3. Endpoint index

| # | Method | Path | Purpose |
|---|---|---|---|
| 1 | GET | `/api/health` | DB connectivity check |
| 2 | GET | `/api/compass/campuses` | Campus list |
| 3 | GET | `/api/compass/students` | Full student directory |
| 4 | GET | `/api/compass/students/search` | Bounded SQL-backed student search; use this instead of downloading the directory |
| 5 | GET | `/api/compass/students/by-username/{username}` | Student by username |
| 6 | GET | `/api/compass/students/by-student-code/{studentCode}` | Student by code |
| 7 | GET | `/api/compass/students/{compassPersonId}/classes` | Student's classes + teachers |
| 8 | GET | `/api/compass/class-performance/staff` | Staff who teach current classes |
| 9 | GET | `/api/compass/staff/{compassPersonId}/classes` | A staff member's classes |
| 10 | GET | `/api/compass/classes/{classSourcedId}/students` | Class roster |
| 11 | GET | `/api/compass/students/{compassPersonId}/attendance` | Student attendance records (paged) |
| 12 | GET | `/api/compass/students/{compassPersonId}/attendance-analytics` | Student analytics |
| 13 | GET | `/api/compass/students/attendance-analytics` | Per-student totals (optionally per campus) |
| 14 | GET | `/api/compass/campuses/attendance-analytics` | Campus analytics (`?campusId=`) |
| 15 | GET | `/api/compass/campuses/{campusId}/attendance-analytics` | Campus analytics (path) |
| 16 | GET | `/api/compass/classes/{classSourcedId}/attendance-analytics` | Class analytics |
| 17 | GET | `/api/compass/attendance` | All attendance records (paged) |
| 18 | GET | `/api/compass/student-photos/{username}` | Photo PNG |
| 19 | GET | `/api/compass/person-photos/{username}` | Photo PNG (alias) |

Typical lookup chain:

```text
GET /campuses                              -> campusId
GET /class-performance/staff               -> compassPersonId (staff)
GET /staff/{id}/classes                    -> classSourcedId
GET /classes/{classSourcedId}/students     -> compassPersonId (students)
GET /students/{compassPersonId}/attendance-analytics
```

---

## 4. Endpoints

### 4.1 `GET /api/health`
Runs `SELECT 1`.

**200**
```json
{ "status": "OK", "database": "SchoolDW", "connected": true, "timestamp": "2026-11-06T02:58:05.935Z" }
```
**500** `{ "status": "ERROR", "connected": false, "error": "..." }`

### 4.2 `GET /api/compass/campuses`
Source: `gold.vwCampus`, ordered by name. Not paged (always returns everything).

**200**
```json
{
  "data": [{ "campusId": "1d4ab1ee-dfc0-47b9-9a80-336f7dcbc6dc", "code": "VFS", "name": "Victorian Flexible Schools" }],
  "page": { "limit": 1, "offset": 0, "total": 1, "hasMore": false }
}
```
**503** `Unable to load campuses from Gold.`

### 4.3 `GET /api/compass/students`
Legacy full-directory endpoint. It joins the student dimension, current campus, current class memberships, and pastoral-assignment view; it is unpaged and can take over 90 seconds to respond in the local database. Use the bounded search endpoint below for user pickers.

**200**
```json
[{
  "StudentKey": 101, "CompassPersonId": "…", "Username": "CHARLEY.BRADY", "StudentCode": "CBRAD01",
  "FirstName": "Charley", "LastName": "Brady", "PreferredFirstName": null, "PreferredLastName": null,
  "YearLevel": "7", "HomeCampus": "1d4ab1ee-…", "Gender": "F", "Nationality": "Australian",
  "DateOfBirth": "2012-03-04", "UserStatus": "Active"
}]
```

### Student search (recommended)
`GET /api/compass/students/search?q=smith&limit=25&offset=0`

This authenticated endpoint queries MSSQL directly and returns no more than 50 students per request. `q` is optional and searches name, username, student code, year level, current class, and house. Interactive results are restricted to the BlendED campus, consistent with the legacy list. `limit` is 1–50; `offset` is 0–10,000. Response includes the same current class/house and pastoral-conflict fields as the old list, plus `page.hasMore`.

Incident editing may use `studentKeys=101,102&incidentId=123` to hydrate the already-selected students from current Gold profiles; this lookup is limited to 50 positive student keys already linked to the requested incident, and preserves historical snapshot display when a current profile is no longer available.

Example:
```text
GET http://127.0.0.1:4201/api/compass/students/search?q=charley&limit=25
```

**200**
```json
{
  "success": true,
  "data": [{ "StudentKey": 101, "StudentCode": "CBRAD01", "FirstName": "Charley", "LastName": "Brady" }],
  "page": { "limit": 25, "offset": 0, "hasMore": false },
  "query": "charley"
}
```
**400** invalid query, key list, or page arguments · **401/403** no authenticated staff identity or insufficient role · **503** Gold query failure.

### 4.4 `GET /api/compass/students/by-username/{username}`
Case-insensitive, trimmed match on `Username`. First match by `StudentKey`.

**200** (camelCase)
```json
{
  "studentKey": 101, "compassPersonId": "…", "username": "CHARLEY.BRADY", "studentCode": "CBRAD01",
  "firstName": "Charley", "lastName": "Brady", "preferredFirstName": null, "preferredLastName": null,
  "yearLevel": "7", "homeCampus": "1d4ab1ee-…"
}
```
**400** `Username is required.` · **404** `{ "error": "Student not found in Gold layer.", "username": "…" }` · **500** DB error.

### 4.5 `GET /api/compass/students/by-student-code/{studentCode}`
Same response shape as 4.4. Case-insensitive match on `StudentCode`; code must be 1–100 chars.
**400** `Student code is required.` · **404** `{ error, studentCode }` · **503**.

### 4.6 `GET /api/compass/students/{compassPersonId}/classes`
Current class memberships (`IsCurrent = 1`) with each class's current teachers.

**200**
```json
[{
  "classSourcedId": "…", "classCode": "7MATH", "subjectName": "Mathematics",
  "roleDescription": "Student", "studentCount": 18,
  "teachers": [{
    "compassPersonId": "…", "displayName": "Jane Smith", "role": "Teacher", "username": "jane.smith",
    "photoUrl": "/api/compass/person-photos/jane.smith"
  }]
}]
```
**400** `Invalid Compass student ID.` · **503**.

### 4.7 `GET /api/compass/class-performance/staff`
Staff (from `gold.vwStaffDirectory`) with at least one current class (`gold.factTeacherClass`), ordered by last/first name.

**200**
```json
[{ "compassPersonId": "…", "displayName": "Jane Smith", "role": "Teacher", "roleInSchool": "Teacher", "homeCampus": "…", "classCount": 4 }]
```
`role` defaults to `"Teacher"`; `roleInSchool`/`homeCampus` are omitted when null. **503** `Unable to load staff from Gold.`

### 4.8 `GET /api/compass/staff/{compassPersonId}/classes`
All classes (current and not) for a staff member, ordered by class code.

**200**
```json
[{ "classSourcedId": "…", "classCode": "7MATH", "subjectName": "Mathematics", "roleDescription": "Teacher", "studentCount": 18, "isActive": true }]
```
`studentCount` counts current memberships. **400** `Invalid Compass staff ID.` · **503**.

### 4.9 `GET /api/compass/classes/{classSourcedId}/students`
Current roster. `{classSourcedId}` matches `CompassClassId` **or** `ClassCode`. Names prefer the preferred name. Ordered by family then given name.

**200**
```json
[{ "compassPersonId": "…", "username": "…", "studentCode": "…", "givenName": "Charley", "familyName": "Brady", "yearLevel": "7", "homeCampus": "…", "classCode": "7MATH" }]
```
**400** `Invalid class identifier.` · **503**. An unknown class returns `[]`.

### 4.10 `GET /api/compass/students/{compassPersonId}/attendance`
Period-level attendance rows from `gold.fact_attendance_period`, newest first. Supports paging and date filters.

`GET /api/compass/students/{id}/attendance?limit=50&offset=0&startDate=2026-07-01T00:00:00Z&endDate=2026-10-01T00:00:00Z`

**200**
```json
{
  "data": [{
    "id": "123456", "date": "2026-09-14T00:00:00.000Z", "period": "P1", "status": "Present",
    "attendanceCode": "fdec4cbf-dce9-4421-90de-29a0f4891461", "attendanceReason": "Present", "details": "",
    "periodStart": "2026-09-14T09:00:00.000Z", "periodFinish": "2026-09-14T10:00:00.000Z", "expectedMinutes": 60
  }],
  "page": { "limit": 50, "offset": 0, "total": 312, "totalPages": 7 }
}
```
`status`: `Not Marked` (status ID `21625425-…`), `Present` (ID `fdec4cbf-…` or description contains "present"), otherwise the first line of `Description`, falling back to `Absent`.
**400** invalid ID / paging / dates · **503**.

### 4.11 Attendance analytics (shared response)

Endpoints 11, 13, 14, 15 return the same structure for different scopes.

| Endpoint | Scope |
|---|---|
| `/students/{compassPersonId}/attendance-analytics` | One student |
| `/campuses/attendance-analytics?campusId={guid}` | Campus (all campuses if `campusId` omitted) |
| `/campuses/{campusId}/attendance-analytics` | Campus; `campusId` must be a GUID, else **400** `campusId must be a valid GUID.` |
| `/classes/{classSourcedId}/attendance-analytics` | Current roster of a class (ID or code) |

All accept `year`, `startDate`, `endDate`. Cached 5 minutes. The campus endpoints accept `refresh=1` to bypass and update the cache. **503** on failure. If the scope contains no students, an empty analytics object (all zeros/empty collections) is returned.

**200**
```json
{
  "summary": {
    "totalPeriods": 1200, "markedPeriods": 1100, "presentCount": 980, "absentCount": 120, "notMarkedCount": 100,
    "overallAttendanceRate": 89.1, "studentsCount": 25, "atRiskCount": 3, "monitorCount": 8, "goodCount": 14
  },
  "statusBreakdown": [{ "label": "Present", "count": 980, "percentage": 81.7 }],
  "monthlyTrend": [{ "key": "2026-09", "label": "Sep", "present": 300, "absent": 40, "notMarked": 10, "rate": 88.2 }],
  "studentStats": {
    "<compassPersonId>": {
      "compassPersonId": "…", "studentCode": "…", "name": "Charley Brady", "totalPeriods": 48, "notMarked": 2,
      "present": 40, "absent": 6, "schoolRefusal": 1, "rate": 87.0, "latestNote": "…", "latestNoteDate": "2026-09-12"
    }
  },
  "recentNotes": [{ "studentId": "…", "studentName": "…", "date": "2026-09-12", "category": "Unexplained", "note": "…" }]
}
```
Calculation rules:
- `rate` = present ÷ (present + absent) × 100, one decimal. **Not Marked periods are excluded** from the denominator.
- Student bands: `rate < 80` → at risk, `80 ≤ rate < 90` → monitor, `≥ 90` → good. A student with no marked periods has rate 0 and counts as at risk.
- `statusBreakdown.percentage` = count ÷ total periods.
- `recentNotes`: up to 20 newest, only descriptions longer than 15 characters and not "Not Marked".
- For campus analytics, records with equal period start times are processed in ascending attendance fact-key order; this makes ties in recent notes repeatable.
- `studentsCount` / `studentStats` include every student in scope, even with no records.

### 4.12 `GET /api/compass/students/attendance-analytics`
Fast per-student totals, optionally for one campus (`?campusId={guid}`, matched on student `HomeCampus` and period `CampusGuid`). Supports date filters. Results are cached for five minutes; `refresh=1` bypasses and updates the cache. Note the campus ID is not GUID-validated here; an invalid value results in **503**.

**200**
```json
{
  "studentStats": {
    "<compassPersonId>": {
      "compassPersonId": "…", "studentCode": "…", "name": "Charley Brady",
      "totalPeriods": 48, "present": 40, "absent": 6, "notMarked": 2, "schoolRefusal": 0, "rate": 87
    }
  }
}
```
`schoolRefusal` is always `0` in this endpoint (use 4.11 for the category count).

### 4.16 `GET /api/compass/attendance`
Paged attendance across all students (joined to `gold.dimStudent`), newest first. Supports paging and date filters.

**200**
```json
{
  "data": [{
    "id": "123456", "compassPersonId": "…", "studentCode": "…", "studentName": "Charley Brady",
    "date": "2026-09-14T00:00:00.000Z", "period": "P1", "periodStart": "…", "periodFinish": "…",
    "expectedMinutes": 60, "attendanceCode": "fdec4cbf-…", "details": ""
  }],
  "page": { "limit": 100, "offset": 0, "total": 250000, "totalPages": 2500 }
}
```
**503** `Unable to load attendance records from Gold.` Unfiltered counts over the whole table can be slow; pass a date filter.

### 4.17 / 4.18 `GET /api/compass/student-photos/{username}` and `/person-photos/{username}`
Returns `{COMPASS_PHOTOS_DIR}/{username}.png` (`image/png`). `username` must match `^[a-z0-9][a-z0-9._'-]{0,199}$` (case-insensitive).
**400** `Invalid person username.` · **404** `Person photo not found.` · **500** `Unable to serve person photo.`

### Unknown routes
`404 { "error": "API endpoint not found.", "method": "GET", "path": "/…" }`

---

## 5. Gold data sources

| Endpoint group | Gold objects |
|---|---|
| Students | `gold.dimStudent` |
| Campuses | `gold.vwCampus` |
| Staff / teachers | `gold.vwStaffDirectory`, `gold.dimStaff`, `gold.factTeacherClass` |
| Classes / rosters | `gold.dimClass`, `gold.factStudentClassMembership` |
| Attendance | `gold.fact_attendance_period`, `gold.dimDate` |

Assessment facts (`gold.factPAT`, `gold.factEssentialAssessment`, see `06_`/`07_` SQL scripts) are loaded but **no API endpoints read them yet**.

## 6. Examples (PowerShell)

```powershell
$base = 'http://127.0.0.1:4201/api/compass'
Invoke-RestMethod "$base/campuses"
Invoke-RestMethod "$base/students/by-username/CHARLEY.BRADY"
Invoke-RestMethod "$base/students/<compassPersonId>/attendance?limit=20&year=2026"
Invoke-RestMethod "$base/campuses/<campusId>/attendance-analytics?startDate=2026-07-01T00:00:00Z&endDate=2026-10-01T00:00:00Z"
Invoke-WebRequest "$base/person-photos/jane.smith" -OutFile jane.png
```

## 7. Notes and known limitations

- No authentication, rate limiting or CORS; photos and student PII are served unauthenticated.
- Response casing is inconsistent: `/students` returns PascalCase Gold columns, everything else camelCase.
- Paging shapes differ: campuses use `hasMore`; attendance endpoints use `totalPages`.
- Error statuses differ between routes (500 vs 503) as noted in section 2.
- Analytics endpoints load all matching period rows into memory; use date filters for campus-wide queries.
- `getPage` and `registerPayloadEndpoint` at the bottom of `server.mjs` are unused leftovers (they would serve paged `PayloadJson` tables with `limit` up to 1000).

## Assessment endpoints (gold-assessment-routes.mjs)

Read `gold.factPAT` / `gold.factEssentialAssessment` (joined to Silver only for student names). Same filters as the old guide: `limit` (1–1000, default 1000), `offset`, `studentCode`, `studentCodes` (JSON array), `studentNames` (JSON array), `classCode`, `campusId`, and `testType` (`PATM`/`PATR`, PAT only). Response: `{ data: [...], page: { limit, offset, total, hasMore } }`.

| Method | Path |
|---|---|
| GET | `/pat-results`, `/campuses/pat-results`, `/campuses/{campusId}/pat-results` |
| GET, POST | `/essential-assessment-results`, `/campuses/essential-assessment-results`, `/campuses/{campusId}/essential-assessment-results` |

On POST, filters come from the JSON body. PAT rows expose `ScaleScore`, `Band`, `Growth`; EA rows expose `Strand`, `FocusArea`, `AssessmentPercentage`, `AchievementLevel`. Students are matched on source ID, username, Compass ID or name. `classCode` is applied only when no `studentCode`/`studentCodes`/`studentNames` filter is given (PAT rows have no class and EA class names come from the source file). Optional `search` (≤100 chars) matches student name, test name or IDs.

## Chronicle insights endpoints (chronicle-insights-routes.mjs)

Student- and class-level insights over Chronicle for **Wellbeing**, **NCCD** and **Outreach** (plus Inclusion). Source: `gold.vwChronicleInsightEntry` (`09_Create_ChronicleInsights.sql`), one row per entry per student, built on `gold.fact_chronicle_entry`.

**Domain classification** (first match wins): `NCCD` (category/template contains NCCD) → `OUTREACH` (contains Outreach) → `WELLBEING` (category/template starts with or contains Wellbeing, or Disclosure…) → `INCLUSION` (Inclusive Education) → `BEHAVIOUR` → `ATTENDANCE` → `OTHER`.

**Common query params:** `from`, `to` (ISO dates; default last 365 days to now). Event date is `DateOfIncident`, falling back to `DateRecorded` when it is missing or in the future.

| Method | Path | Purpose |
|---|---|---|
| GET | `/students/{studentId}/chronicle-insights` | Summary for one student. `studentId` = CompassPersonId, student code or username. |
| GET | `/students/{studentId}/chronicle-entries` | Timeline. Extra params: `domain`, `limit` (1–500, default 100), `offset`. Returns `{ page, data }`. |
| GET | `/classes/{classId}/chronicle-insights` | Class roll-up (`summary`) plus one insight object per current student (`students`). `classId` = CompassClassId or class code. |
| GET | `/chronicle/insights/domains` | Domains → templates with entry and student counts, for filters. |

**Summary shape** (student; the class `students[]` items share it):
- `wellbeing`: `entries`, `highRiskEntries` (Rating = Red), `disclosures` (templates starting "Disclosure"), `lastEntryDate`.
- `nccd`: `hasNccdRecord` (all time), `entriesInWindow`, `entriesAllTime`, `category`, `levelOfAdjustment` (latest non-empty), `lastEntryDate`.
- `outreach`: `meetings`, `engagement` (`high`/`medium`/`low`/`notPresent`, from the "Engagement of young person" field), `lowEngagementRate` (% Low + Not Present), `assertiveOutreach`, `homeVisits` (location "YP Home"), `lastMeetingDate`.
- `inclusion.entries`, `totalEntries`.
- `flags`: `wellbeingConcern` (any red wellbeing entry or disclosure in window), `outreachDisengaged` (≥2 meetings and ≥50% Low/Not Present), `nccdRecorded`.

Errors: 400 invalid dates/domain/limit, 404 unknown student or class (no current students), 503 database failure.

## Not available in server.mjs

These documented in the old guide are served only by `server_DevWorking.mjs`: `/staff`, `/attendance` raw payloads, `/learning-needs`, `/classes/{id}/learning-needs`, `refresh=1` cache bypass, and `/campuses/{id}/attendance-analytics` payload version.
