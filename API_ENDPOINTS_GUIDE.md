# Class Performance API – Endpoint Guide with Real Examples

Base URL (local): `http://127.0.0.1:4201/api/compass`
All examples below were run against the live API; IDs are real records from `DevWorking`. Responses are trimmed.

In Postman, set a collection variable `base = http://127.0.0.1:4201/api/compass` and use `{{base}}/...`.
Some endpoints are slow (10–60 s) because they read large JSON payload tables. Set the Postman request timeout to at least 120 s.

## Conventions

| Item | Rule |
| --- | --- |
| Paging | `limit` (1–500, default 100; 1–1000 for essential assessments) and `offset` (>= 0). Response: `"page": { "limit", "offset", "total", "hasMore" }` |
| Dates | `startDate` / `endDate` must be UTC ISO timestamps ending in `Z`, with start before end, for example `2026-07-01T00:00:00Z` |
| Array filters in a query string | JSON array, URL-encoded: `studentCodes=["MJBOU50"]` |
| Cache | Attendance analytics endpoints cache for 5 minutes. Add `refresh=1` to bypass |
| Errors | `400` bad parameter, `404` not found, `503` database failure; body is `{ "error": "..." }` |

## Typical lookup chain

```text
GET /campuses                       -> campusId
GET /class-performance/staff        -> compassPersonId (staff)
GET /staff/{id}/classes             -> classSourcedId
GET /classes/{classSourcedId}/students -> compassPersonId, studentCode (students)
GET /students/{compassPersonId}/attendance-analytics
```

---

## 1. Health

`GET /health`

```text
GET http://127.0.0.1:4201/api/compass/health
```
```json
{ "configured": true, "database": "DevWorking" }
```
Returns 503 if SQL Server cannot be reached.

## 2. Campuses

`GET /campuses?limit=500&offset=0`

```text
GET http://127.0.0.1:4201/api/compass/campuses?limit=1
```
```json
{
  "data": [{
    "campusId": "1d4ab1ee-dfc0-47b9-9a80-336f7dcbc6dc",
    "code": "Victorian Flexible Schools",
    "name": "Victorian Flexible Schools",
    "emailAddress": "lisa.burgess@saints.vic.edu.au",
    "phoneNumber": "03 9269 6910",
    "isActive": true,
    "isDefault": false
  }],
  "page": { "limit": 1, "offset": 0, "total": 11, "hasMore": true }
}
```

Campus IDs currently in the database:

| Campus | campusId |
| --- | --- |
| Fitzroy North College - By Saints College | `e6412b6a-a98d-4263-873d-508577bdb794` |
| Saints College - North Melbourne | `39afb90c-1824-4319-9f90-ab43d589dabf` |
| BlendED - By Saints College | `5d155d8e-8600-45e6-a21b-b61ba8b1eb1f` |
| Saints College - Ballarat | `429a9056-488f-421a-b5e3-350e15249174` |
| Saints College - Geelong | `f4090d86-fafc-446c-abd9-dead21a93b0a` |
| Saints College - Sunshine | `a7e072a4-2327-4413-852a-a16ea39acca5` |
| Saints College - Colac | `4cd0bb14-57ca-47fa-b03e-96241bc67ac0` |
| Saints College - Bungaree | `ad597e23-61e7-491e-872c-b0e5c5fd82dc` |

Note: students store `homeCampus` as the campusId in upper case; compare case-insensitively.

## 3. Staff

### 3.1 Staff list for the class page (about 25 s)
`GET /class-performance/staff`

```json
{
  "compassPersonId": "43e4d0fb-a1ac-4044-b094-7fd78ca4c789",
  "displayName": "Aakriti Kaur",
  "role": "Compass staff",
  "roleInSchool": "Teacher - Fitzroy North",
  "homeCampus": "e6412b6a-a98d-4263-873d-508577bdb794",
  "classCount": 29
}
```
Returns an array (567 staff). Staff with classes sort first.

### 3.2 Raw staff payloads
`GET /staff?limit=50&offset=0`: paged raw Compass staff JSON.

### 3.3 Classes allocated to a staff member (about 25 s)
`GET /staff/{compassPersonId}/classes`

```text
GET http://127.0.0.1:4201/api/compass/staff/0092a881-5a5d-4494-98bb-0b07e8193805/classes
```
```json
[{
  "classSourcedId": "9257d709-43c8-44a5-ba79-4988ae066768",
  "classCode": "BDHUBCOGPE1",
  "subjectName": "Hub Check Out",
  "roleDescription": "Youth Worker  CAT C - BlendED Metro 1",
  "studentCount": 27,
  "isActive": true
}]
```

## 4. Classes

`{classSourcedId}` accepts the GUID or the class code (for example `FN10HUMACA1`).

### 4.1 Class roster
`GET /classes/{classSourcedId}/students`

```text
GET http://127.0.0.1:4201/api/compass/classes/f0974638-7512-48c8-add4-b3fe88610984/students
```
```json
[{
  "compassPersonId": "cb94b79d-5b54-4b08-83ab-55c40090202d",
  "studentCode": "MJBOU50",
  "givenName": "Mia",
  "familyName": "Bouterakos",
  "username": "MJBOU50",
  "classCode": "FN10HUMACA1",
  "classSourcedId": "f0974638-7512-48c8-add4-b3fe88610984",
  "yearLevel": "FN10",
  "homeCampus": "E6412B6A-A98D-4263-873D-508577BDB794"
}]
```

### 4.2 Class attendance analytics
`GET /classes/{classSourcedId}/attendance-analytics`

Optional: `campusId`, `startDate`, `endDate`.

```text
GET .../classes/f0974638-7512-48c8-add4-b3fe88610984/attendance-analytics?startDate=2026-07-01T00:00:00Z&endDate=2026-10-01T00:00:00Z
```
Response shape (same as section 6.3, plus per-student stats):
```json
{
  "summary": { "totalPeriods": 0, "markedPeriods": 0, "presentCount": 0, "absentCount": 0,
               "notMarkedCount": 0, "overallAttendanceRate": 0, "studentsCount": 0,
               "atRiskCount": 0, "monitorCount": 0, "goodCount": 0 },
  "statusBreakdown": [{ "label": "Present", "count": 0, "percentage": 0 }],
  "monthlyTrend": [{ "key": "2026-09", "label": "Sep", "present": 0, "absent": 0, "notMarked": 0, "rate": 0 }],
  "studentStats": { "<compassPersonId>": { "name": "", "studentCode": "", "totalPeriods": 0, "present": 0, "absent": 0, "schoolRefusal": 0, "rate": 0 } },
  "recentNotes": []
}
```

### 4.3 Other class endpoints
- `GET /classes/{classSourcedId}/attendance`: raw attendance payloads for active students.
- `GET /classes/{classSourcedId}/learning-needs`: learning-needs payloads for the class.

## 5. Students

### 5.1 Student directory (2,069 rows)
`GET /students` (cached 5 minutes; `?refresh=1` to reload)

```json
{
  "compassPersonId": "CBBE218A-5658-4E1F-8501-7DAD65F13271",
  "studentCode": "ETHAN.ABBOTT",
  "firstName": "Ethan",
  "lastName": "Abbott",
  "username": "ETHAN.ABBOTT",
  "yearLevel": "GLV10",
  "homeCampus": "F4090D86-FAFC-446C-ABD9-DEAD21A93B0A",
  "homeCampusName": "Saints College - Geelong",
  "homeCampusCode": "Geelong",
  "gender": "M",
  "dateOfBirth": "28/09/2011",
  "userStatus": 1
}
```

### 5.2 One student by code or username
```text
GET http://127.0.0.1:4201/api/compass/students/by-student-code/MJBOU50
GET http://127.0.0.1:4201/api/compass/students/by-username/MJBOU50
```
Both return one student object like the above. A missing student returns 404.

### 5.3 Student class allocations
`GET /students/{compassPersonId}/classes`

```text
GET .../students/cb94b79d-5b54-4b08-83ab-55c40090202d/classes
```
```json
[{ "classSourcedId": "b2fd615a-df67-4428-9633-adc0bd3bbb25", "classCode": "FN10ARTACA1",
   "subjectName": "FN10ARTACA1", "roleDescription": "", "studentCount": 13, "teachers": [] }]
```

### 5.4 Student photo
`GET /student-photos/{username}` or `/person-photos/{username}` returns `{username}.png` from `COMPASS_PHOTOS_DIR`.

## 6. Attendance

### 6.1 Student attendance records (paged)
`GET /students/{compassPersonId}/attendance`

Params: `limit`, `offset`, `startDate`, `endDate`, `classCode` / class filter, `sortBy` (default `date`), `sortDirection` (`asc` or `desc`).

```text
GET .../students/cb94b79d-5b54-4b08-83ab-55c40090202d/attendance?limit=1&offset=0
```
```json
{
  "data": [{
    "id": "051fa2fb-f159-411e-9cce-f584e8ea7d99",
    "date": "2026-12-10T03:15:00Z",
    "period": "F6",
    "status": "Not Marked",
    "attendanceCode": "21625425-4deb-4957-81be-897914dcff18",
    "attendanceReason": "Not Marked",
    "details": "Not Marked"
  }],
  "page": { "limit": 1, "offset": 0, "total": 371, "hasMore": true }
}
```

### 6.2 Raw attendance (admin or debug)
`GET /attendance?limit=50&offset=0` returns raw payload rows from `dbo.CompassAttendancePeriodLines`.

### 6.3 Student attendance analytics
`GET /students/{compassPersonId}/attendance-analytics` (optional `startDate`, `endDate`)

```text
GET .../students/cb94b79d-5b54-4b08-83ab-55c40090202d/attendance-analytics
```
```json
{
  "summary": { "totalPeriods": 371, "markedPeriods": 101, "presentCount": 24, "absentCount": 77,
               "notMarkedCount": 270, "overallAttendanceRate": 23.8, "studentsCount": 1,
               "atRiskCount": 1, "monitorCount": 0, "goodCount": 0 },
  "statusBreakdown": [
    { "label": "Not Marked", "count": 270, "percentage": 72.8 },
    { "label": "Unexplained", "count": 40, "percentage": 10.8 },
    { "label": "Present", "count": 24, "percentage": 6.5 }
  ],
  "monthlyTrend": [{ "key": "2026-09", "label": "Sep", "present": 24, "absent": 70, "notMarked": 0, "rate": 25.5 }]
}
```

### 6.4 Per-student attendance totals for a campus (fast; used first by the campus dashboard)
`GET /students/attendance-analytics?campusId={campusId}` (omit `campusId` for all campuses)

```text
GET .../students/attendance-analytics?campusId=e6412b6a-a98d-4263-873d-508577bdb794
```
```json
{ "studentStats": { "CB94B79D-5B54-4B08-83AB-55C40090202D": {
    "totalPeriods": 371, "notMarked": 270, "present": 24, "absent": 77, "schoolRefusal": 11, "rate": 23.8 } } }
```
Rate is present divided by (present + absent); "Not Marked" periods are excluded.

### 6.5 Campus attendance charts (heavy; may take minutes)
```text
GET .../campuses/e6412b6a-a98d-4263-873d-508577bdb794/attendance-analytics
GET .../campuses/attendance-analytics            (all campuses)
```
Returns the same shape as section 6.3 plus `studentStats` and `recentNotes`.

## 7. Assessments

### 7.1 PAT results (PATM maths, PATR reading)
`GET /pat-results`

| Param | Meaning |
| --- | --- |
| `limit`, `offset` | Paging |
| `testType` | `PATM` or `PATR` |
| `search` | Free text on name or code |
| `studentCode` | One student code |
| `studentCodes` | JSON array of codes (identifiers) |
| `studentNames` | JSON array of names |
| `classCode` | Class name or code |

```text
GET .../pat-results?limit=50&offset=0&testType=PATM&classCode=Rose
GET .../pat-results?studentCodes=%5B%22113967%22%5D
```
Each row includes `StudentName`, `TestType`, `AssessmentDate`, `YearLevel`, `ScaleScore`, `Band`, `Growth`, `MatchStatus`.

### 7.2 Essential Assessment results (GET or POST)
`/essential-assessment-results` supports **both** methods and the same filters. Limit goes up to 1000.

**GET** (filters in the query string):
```text
GET http://127.0.0.1:4201/api/compass/essential-assessment-results?limit=50&offset=0&classCode=Rose
```
For several students on GET, pass a JSON array: `&studentCodes=["113967","113968"]` (URL-encoded).

**POST** (filters in the JSON body, better for many students because there is no URL length limit):
```text
POST http://127.0.0.1:4201/api/compass/essential-assessment-results?limit=50&offset=0
Content-Type: application/json

{ "studentCodes": ["113967"] }
```
Body fields: `studentCodes` (array), `studentNames` (array), `classCode` (string). On POST, query-string filters are ignored; only `limit` and `offset` come from the URL.

Real response row (class Rose, total 36):
```json
{
  "data": [{
    "SilverBusinessKey": "25FE8241FEA89C9E2A711B80813290BB955A44896CE78CCEBDED25ECED072EB8",
    "StudentSourceId": "V2113965",
    "StudentName": "CARUANA Zavier",
    "ExternalStudentId": "V2113965",
    "AssessmentType": "PRE",
    "AssessmentDate": "2026-09-01T00:00:00.000Z",
    "TestName": "Statistics (F-10 V2.0)",
    "YearLevel": "9",
    "ClassName": "Rose",
    "Strand": "Statistics (F-10 V2.0)",
    "FocusArea": "Data",
    "AssessmentRange": "7-8",
    "AssessmentPercentage": 18,
    "AchievementLevel": "6",
    "StrandAverageAchievementLevel": "6",
    "MatchStatus": "not_matched"
  }],
  "page": { "limit": 1, "offset": 0, "total": 36, "hasMore": true }
}
```
Essential results are matched by the **student code in the assessment file** (for example `113967` or `V2113965`), not always the Compass `studentCode` (for example `MJBOU50`). Use `studentNames` as a fallback if codes return nothing.

### 7.3 Campus-wide assessments (by campusId)
Both assessment endpoints have campus-scoped routes. Rows are matched to the campus's students (`homeCampus`) by Compass person id, student code, username, or name.

| Route | Scope |
|---|---|
| `GET /campuses/{campusId}/pat-results?limit=1000&offset=0` | One campus |
| `GET\|POST /campuses/{campusId}/essential-assessment-results?limit=1000&offset=0` | One campus (POST body may be empty) |
| `GET /campuses/pat-results`, `GET\|POST /campuses/essential-assessment-results` | All campuses |
| `?campusId=...` on `/pat-results` or `/essential-assessment-results` | Same as the path form |

Example: `GET /api/compass/campuses/e6412b6a-a98d-4263-873d-508577bdb794/pat-results?limit=3` (about 20 s); the Essential route takes about 60 s. The campus dashboard uses these through `CampusCohortAssessmentsComponent`, loading PAT first and Essential only when its toggle is on.

## 8. Learning needs

`GET /learning-needs?limit=50&offset=0` returns raw payloads from `dbo.CompassStudentLearningNeeds`. Per class: `GET /classes/{classSourcedId}/learning-needs`.

---

## Postman recipes

1. **Collection variables:** `base`, `campusId` = `e6412b6a-a98d-4263-873d-508577bdb794`, `classId` = `f0974638-7512-48c8-add4-b3fe88610984`, `personId` = `cb94b79d-5b54-4b08-83ab-55c40090202d`.
2. **Smoke test:** `GET {{base}}/health` should return `configured: true`.
3. **Campus drill-down:** `{{base}}/campuses`, then `{{base}}/students/attendance-analytics?campusId={{campusId}}`.
4. **Class drill-down:** `{{base}}/classes/{{classId}}/students`, then `{{base}}/classes/{{classId}}/attendance-analytics`.
5. **Essential POST:** method POST, Body, raw, JSON: `{ "studentCodes": ["113967"] }`.
6. **Postman test script** to check paging:
   ```javascript
   pm.test("200 and page info", () => {
     pm.response.to.have.status(200);
     const j = pm.response.json();
     pm.expect(j.page).to.have.property("total");
   });
   ```

## Curl equivalents (PowerShell)

```powershell
Invoke-RestMethod "http://127.0.0.1:4201/api/compass/health"
Invoke-RestMethod "http://127.0.0.1:4201/api/compass/students/by-student-code/MJBOU50"
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:4201/api/compass/essential-assessment-results?limit=50&offset=0" `
  -ContentType "application/json" -Body '{ "studentCodes": ["113967"] }' -TimeoutSec 120
```

## Performance notes

| Endpoint | Observed time | Cause |
| --- | --- | --- |
| `/class-performance/staff` | about 25 s | parses 567 JSON payloads and counts classes |
| `/staff/{id}/classes` | about 25 s | joins on `ClassSourcedId OR ClassCode` without indexes |
| `/classes/{id}/students` | about 30 s | joins `StudentsBasic` with an `OR` |
| `/essential-assessment-results` | 12–30 s | text filtering without an index |
| `/campuses/{id}/attendance-analytics` | over 2 minutes | parses every attendance JSON payload |

Indexes on `CompassStudentClasses (ClassSourcedId, ClassCode)` and `CompassTeacherClasses (CompassPersonId)` would help. The attendance index script is `create-attendance-person-index.sql`.
