# Class Performance API

Standalone Express REST API for Compass and student wellbeing data. The local wellbeing database is `SchoolDW`; the Angular development proxy forwards `/api` requests to this service on `127.0.0.1:4201`.

## Setup

1. Copy `.env.example` to `.env` beside `server.mjs`. Set `SQL_SERVER=localhost` and `SQL_DATABASE=SchoolDW` when using the local wellbeing database; otherwise use the configured server and database.
2. Set `SQL_AUTH=sql` and provide a SQL Server login in `SQL_USER` and `SQL_PASSWORD`. Use `SQL_AUTH=windows` to use the Windows account running the API instead; this is generally suitable when the API and SQL Server can authenticate the same Windows/domain identity.
3. If SQL Server is on another PC, enable TCP/IP for its instance, configure its TCP port (commonly 1433 for a default instance), allow that port through the database PC's firewall, and restart SQL Server. For SQL Authentication, enable SQL Server and Windows Authentication mode (Mixed Mode), restart SQL Server, and create a database login with only the required `SELECT` permissions.
4. Install dependencies with `npm install`.
5. Start with `npm start`.

Install the matching Microsoft ODBC Driver on the API PC as well; this Node API uses `msnodesqlv8` and does not require SQL Server itself to be installed on that PC. Keep `.env` private and do not commit SQL credentials. When Angular and this API run on the same PC, Angular's `/api` development proxy reaches the API at `127.0.0.1:4201`; the API itself remains bound to loopback.

Incident APIs require an authenticated staff identity and resolve access roles from current `org.StaffHouseAssignment`, `org.StaffPastoralGroupAssignment`, and `wellbeing.IncidentStaffRole` records. For local UI testing only, set `WELLBEING_DEV_AUTH=true` in `.env` and restart the API. The Angular app then shows a local development sign-in backed by active SQL staff records and attaches the selected identity to same-machine API requests. This selector simulates an identity; it does not verify a password or authenticate a real user. The API binds to loopback while this mode is enabled. Leave it false in production; the development identity selector is not a substitute for a trusted production authentication provider.

Compass campus endpoints resolve each request to one active `org.Staff` record, a current `gold.dimStaff` record, and that staff member's current campus from `gold.vwStaffDirectory`. Student, class, attendance, assessment, and Chronicle results are restricted to that campus. Only staff whose resolved campus name is exactly `Victorian Flexible Schools` receive all-campus access. Staff without one current campus assignment are denied; changing the campus selector or sending another campus ID does not grant access.

The configured database identity (the Windows account for Windows Authentication, or the SQL login for SQL Authentication) needs `SELECT` access to the tables used by the endpoints. The `GetStaffBasic`, attendance, learning-needs, and campus notebooks in `../APICALL/` create/populate their respective tables. In particular, `GET /api/compass/staff` requires `dbo.CompassStaffBasic` to exist, and `GET /api/compass/campuses` requires `dbo.CompassCampuses` to exist and be populated by `GetCampus.ipynb`.

## Campus endpoint

`GET /api/compass/campuses` returns campus payloads from `dbo.CompassCampuses` using the same pagination shape as the other payload endpoints:

```json
{
  "data": [{ "campusId": "...", "name": "...", "code": "..." }],
  "page": { "limit": 100, "offset": 0, "total": 1, "hasMore": false }
}
```

Optional query parameters: `limit` (1–500, default 100) and `offset` (non-negative, default 0). Run `GetCampus.ipynb` to sync campus data before requesting it.

## PAT results endpoint

`GET /api/compass/pat-results` returns paginated PATM and PATR results from `[SchoolDW].[silver].[PAT]`, including student details, assessment date, test, scale score, band, strand, and achievement fields. The response uses the standard `{ data, page }` pagination shape.

Optional query parameters:

- `limit` (1–1000, default 1000) and `offset` (non-negative, default 0).
- `search` (up to 100 characters), matched against student name, UniqueId, username, test name, and strand.
- `studentCode` (up to 200 characters), matched against the PAT UniqueId, source ID, external student ID, Compass person ID, or username fields; used to scope results on the Student Profile.
- `classCode` (up to 200 characters), matched against `ClassName`; used to scope results on the Class Profile. `studentCodes` may also be supplied as a JSON array of up to 500 identifiers to scope class results to the selected class roster, including when PAT `ClassName` is not populated.
- `testType` (`PATM` or `PATR`).

The API connection account must have `SELECT` permission on `SchoolDW.silver.PAT`. For example, request `/api/compass/pat-results?limit=50&testType=PATM`.

## Essential Assessment results endpoint

`GET` and `POST /api/compass/essential-assessment-results` return paginated results from `[SchoolDW].[silver].[EssentialAssessment]`, including student, assessment, score, strand, achievement, and growth fields. The API response uses the standard `{ data, page }` pagination shape. GET is convenient for browser testing; POST is used by the app to send larger class and campus rosters.

Optional query parameters: `limit` (1–1000, default 50) and `offset` (non-negative, default 0). For GET, provide `studentCode=<identifier>` for one student, `studentCodes=<URL-encoded JSON array>` and/or `studentNames=<URL-encoded JSON array>` for a roster, and/or `classCode=<class name>`. For POST, the JSON body can include `studentCodes` (up to 5000 student identifiers such as Compass person ID, student source ID, external student ID, or Compass username), `studentNames` (up to 5000 names), and/or `classCode`. When roster identifiers or names are provided, results are scoped to those students, even when their source class label differs from the Compass class code. Campus profile results are scoped to the selected campus's roster because EssentialAssessment does not contain a campus column.

The PAT endpoint also accepts the optional `studentNames=<URL-encoded JSON array>` filter. This lets class roster views match assessment results when imported student IDs differ from Compass identifiers.

The API connection account must have `SELECT` permission on `SchoolDW.silver.EssentialAssessment`.

The class-performance staff endpoint also returns the Compass `roleInSchool` and `homeCampus` fields. Compass may include a campus or program description after the role (for example, `Teacher Fitzroy North` or `Youth Worker CAT C - BlendED Metro 1`); the class profile includes entries beginning with `Teacher` or `Youth Worker` and filters staff by the selected campus.

`GET /api/compass/students` returns student identity, year level, campus, gender, nationality, date of birth, and user status from `dbo.StudentsBasic`. The Student Profile displays date of birth and calculated age only on the selected student's profile; the campus dashboard uses demographic fields for aggregated distributions and grouped age ranges. Indigenous type, living arrangement, primary risk driver, and OOHC status display only when supplied by the student record; they are not currently included in the `GetStudent.ipynb` sync. Keep this endpoint local and restrict database access as described above.

`GET /api/compass/students/by-username/{username}` returns one student matching the Compass username, with `homeCampusName` and `homeCampusCode` joined from `dbo.CompassCampuses`. It returns 404 if no student matches and 409 if duplicate usernames exist.

`GET /api/compass/students/by-student-code/{studentCode}` returns one student by student code with the same campus fields. Use `by-username` for a Compass username; `/students/username/{username}` is not a registered route.

`GET /api/compass/student-photos/{username}` and `GET /api/compass/person-photos/{username}` serve the matching `{username}.png` from `C:\Sanits\CompassPhotos`. The folder can be changed with `COMPASS_PHOTOS_DIR`. The API validates usernames and serves only PNG files from that directory; a missing image returns 404, and profile avatars fall back to initials.

`GET /api/compass/students/{compassPersonId}/attendance` returns a paginated attendance history for one student. It accepts `limit` (1–500, default 100), `offset` (default 0), optional `classSourcedId` to scope records to an active class allocation, and optional `startDate`/`endDate` UTC ISO timestamps (inclusive start, exclusive end). `sortBy` supports `year`, `term`, `week`, `date`, `student`, `attendance`, and `attendanceCode`; `sortDirection` supports `asc` or `desc`. Each record includes the Compass status ID as `attendanceCode` and its readable description as `attendanceReason`.

`GET /api/compass/students/{compassPersonId}/classes` returns the student's active class allocations and only the teachers explicitly linked to that student and class (`CompassTeacherClasses.StudentSourcedId` and `ClassSourcedId`). It also returns the active student count for each class. Run the teacher/class sync that populates those student-specific links; class-only teacher assignments are intentionally not shown as belonging to an individual student.

`GET /api/compass/students/{compassPersonId}/attendance-analytics` returns the student's attendance-category breakdown, monthly trend, attendance totals, and recent notes. Student attendance categories are calculated from that student's attendance rows only.

`GET /api/compass/students/attendance-analytics` returns attendance-period totals, present/absent counts, school-refusal counts, and attendance rates keyed by Compass person ID for students in `dbo.StudentsBasic`. Pass `campusId=<Compass campus ID>` to limit summaries to one campus; omit it for all campuses. The server aggregates values in SQL and caches results per campus for five minutes; pass `refresh=1` to force recalculation. Because unscoped aggregation covers the full attendance history, the Campus Dashboard waits for a campus selection before requesting attendance.

`GET /api/compass/campuses/{campusId}/attendance-analytics` returns the selected campus's attendance summary, status-category breakdown, monthly trend, per-student statistics, and recent notes. `GET /api/compass/campuses/attendance-analytics` returns the same analytics across all campuses. Both retrieve attendance rows in bounded batches by Compass person ID, reuse the attendance-person index, and cache results for five minutes. Pass `refresh=1` to force recalculation. This supports the all-campus and selected-campus views without an unfiltered attendance-history scan.

`GET /api/compass/classes/{classSourcedId}/attendance-analytics` also accepts optional `campusId=<Compass campus ID>` and the optional UTC `startDate`/`endDate` range (inclusive start, exclusive end). When supplied, both the class attendance charts and student statistics are limited to the selected date range and, when provided, students assigned to that campus. The Class Profile campus and reporting-period selectors request matching analytics for the selected class.

Run [`create-attendance-person-index.sql`](./create-attendance-person-index.sql) to improve the performance of attendance aggregation and campus/person lookups. The student attendance details endpoint does not require the attendance-person index to exist.
# class-performance-app
