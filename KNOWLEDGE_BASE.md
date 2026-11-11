# Class Performance API Knowledge Base

## Purpose

The Class Performance API is a local Express service that reads Compass data from SQL Server and serves it to the Angular application. The browser calls `/api/...`; during development Angular forwards those requests to the API. The browser does not connect directly to SQL Server.

## Run Locally

1. Configure `api/.env` with the SQL Server settings. Install dependencies once with `npm install` from `api/`.
2. Start the API with `npm start` from `api/`, or run `npm run start:api` from `class-performance-app/`.
3. In a second terminal, start Angular with `npm start` from `class-performance-app/` and open `http://localhost:3200/`.

The API listens on `127.0.0.1:4201` by default. `class-performance-app/proxy.conf.json` forwards `/api` to that address. Set `COMPASS_PROXY_PORT` to change the API port, and update the proxy target to match.

Check API and database connectivity:

```text
http://127.0.0.1:4201/api/compass/health
```

The health endpoint returns HTTP 200 with the configured database when SQL Server responds, or HTTP 503 if the database connection/query fails.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `SQL_SERVER` | `localhost` | SQL Server host or instance |
| `SQL_DATABASE` | `DevWorking` | Database containing synced Compass tables |
| `SQL_DRIVER` | `ODBC Driver 17 for SQL Server` | ODBC driver used by the Windows SQL connection |
| `SQL_TRUST_SERVER_CERTIFICATE` | `false` | Trust an unverified SQL certificate when set to `true`; local workaround only |
| `COMPASS_PROXY_PORT` | `4201` | API listening port |
| `COMPASS_PHOTOS_DIR` | `C:\\Sanits\\CompassPhotos` | Directory containing `{username}.png` photos |

The API uses Windows trusted-connection authentication. The Windows account running Node needs database access, including `SELECT` permission on the endpoint tables. Keep `.env` private.

## Endpoint Reference

All endpoints use the `/api/compass` prefix and use `GET`.

| Endpoint | Purpose / response |
| --- | --- |
| `/health` | SQL connectivity and configured database status |
| `/pat-results` | Paginated PATM/PATR results from `SchoolDW.silver.PAT`; supports search, test-type, student, and class filters |
| `/class-performance/staff` | Staff summary, class counts, role, and home campus for the class-performance view |
| `/staff` | Paginated raw staff payloads from `dbo.CompassStaffBasic` |
| `/staff/{compassPersonId}/classes` | Active classes and student counts for a staff member |
| `/students` | Student directory fields from `dbo.StudentsBasic` |
| `/students/by-username/{username}` | One student looked up by Compass username, including campus name and code |
| `/students/by-student-code/{studentCode}` | One student looked up by student code, including campus name and code |
| `/students/{compassPersonId}/classes` | Active student class allocations and explicitly linked teachers |
| `/students/{compassPersonId}/attendance` | Paginated attendance history; supports class, date, and sort filters |
| `/students/{compassPersonId}/attendance-analytics` | One student's attendance breakdown, totals, trend, and recent notes |
| `/students/attendance-analytics` | Per-student attendance totals and rates, optionally limited by campus |
| `/classes/{classSourcedId}/students` | Active roster for a class |
| `/classes/{classSourcedId}/attendance` | Attendance payloads for active students in a class |
| `/classes/{classSourcedId}/attendance-analytics` | Class attendance analytics; optional campus and date filters |
| `/classes/{classSourcedId}/learning-needs` | Learning-needs payloads for students in a class |
| `/attendance` | Paginated raw attendance payloads from `dbo.CompassAttendancePeriodLines` |
| `/learning-needs` | Paginated raw learning-needs payloads from `dbo.CompassStudentLearningNeeds` |
| `/campuses` | Paginated campus payloads from `dbo.CompassCampuses` |
| `/campuses/attendance-analytics` | Attendance analytics across all campuses |
| `/campuses/{campusId}/attendance-analytics` | Attendance analytics for one campus |
| `/student-photos/{username}` | Local `{username}.png` image |
| `/person-photos/{username}` | Alias for the local person photo route |

Prepend `/api/compass` to each path in this table. For example: `GET /api/compass/classes/CLASS-ID/students`.

### Example: Get a Student by Username

```http
GET http://127.0.0.1:4201/api/compass/students/by-username/ETHAN.ABBOTT
```

This returns one student object, including `homeCampus`, `homeCampusName`, and `homeCampusCode`. It returns HTTP 404 when no username matches, HTTP 409 if the database contains duplicate matches, and HTTP 400 for a blank or overlong username. URL-encode usernames containing reserved URL characters.

To look up by student code instead, use `/api/compass/students/by-student-code/ETHAN.ABBOTT`. The username route requires the `by-username` path segment; `/api/compass/students/username/...` is not registered.

### Example: Get One Student's Classes

Replace `{compassPersonId}` with the student's Compass person ID (not their student code), then request:

```http
GET http://127.0.0.1:4201/api/compass/students/12345/classes
```

The endpoint returns a JSON array of that student's active class allocations. For example:

```json
[
	{
		"classSourcedId": "class-abc",
		"classCode": "10ENG",
		"subjectName": "English",
		"roleDescription": "English",
		"studentCount": 22,
		"teachers": [
			{
				"compassPersonId": "staff-21",
				"displayName": "Alex Teacher",
				"role": "Teacher",
				"roleInSchool": "Teacher North Campus",
				"username": "ateacher",
				"photoUrl": "/api/compass/person-photos/ateacher"
			}
		]
	}
]
```

Each array item represents one class. `teachers` contains only teachers linked to both this student and class in `dbo.CompassTeacherClasses`; it is not a list of every teacher assigned to the class. `studentCount` is the active enrollment count. An empty array means no matching active class allocations were found. This endpoint does not use pagination.

### Query Parameters

- Paginated payload endpoints and student attendance accept `limit` (1–500, default 100) and `offset` (default 0; non-negative integer). Paginated responses contain `data` and `page`, including `limit`, `offset`, `total`, and `hasMore`.
- Student attendance also accepts `classSourcedId`, `startDate`, `endDate`, `sortBy`, and `sortDirection`. Dates must be UTC ISO timestamps; the start is inclusive and end is exclusive. Sort fields are `year`, `term`, `week`, `date`, `student`, `attendance`, and `attendanceCode`; direction is `asc` or `desc`.
- Student and class attendance analytics accept the same optional `startDate` and `endDate` range. Class analytics can also accept `campusId`.
- `/students/attendance-analytics` accepts `campusId` and `refresh=1`.
- Campus analytics endpoints accept `refresh=1` to bypass their five-minute in-memory cache.

## Data Dependencies

Compass sync notebooks in `APICALL/` populate the SQL tables. Common endpoint dependencies include:

| Table | Used by |
| --- | --- |
| `dbo.StudentsBasic` | Student directory and campus student selection |
| `dbo.CompassStudentClasses` | Class rosters, class membership, and student allocations |
| `dbo.CompassTeacherClasses` | Staff allocations and student-linked teacher details |
| `dbo.CompassStaffBasic` | Staff information |
| `dbo.CompassAttendancePeriodLines` | Attendance history and analytics |
| `dbo.CompassStudentLearningNeeds` | Learning-needs records |
| `dbo.CompassCampuses` | Campus list |

Run `api/create-attendance-person-index.sql` before using analytics that rely on the attendance-person index. Campus analytics also benefit from the student/campus index created by that script. Campus data must be synced with `APICALL/GetCampus.ipynb`; other endpoints similarly require their source tables to be populated.

## Troubleshooting

| Symptom | Likely cause and action |
| --- | --- |
| Angular logs `http proxy error` and `ECONNREFUSED 127.0.0.1:4201` | The API is stopped or listening on another port. Start it with `npm run start:api` and ensure the port matches `proxy.conf.json`. |
| `/api/compass/health` returns 503 | The API is reachable, but SQL Server, authentication, database selection, or the health query failed. Check API terminal output and `SQL_*` settings. |
| An endpoint returns 503 | Check the API terminal for the endpoint-specific SQL error; verify the required table exists, is populated, and the API account has read access. |
| An endpoint returns 400 | Correct invalid pagination, ID length, date range, or sort parameters described above. |
| A photo returns 404 | Confirm the username matches a `{username}.png` file in `COMPASS_PHOTOS_DIR`. |

## Security

Student identity, attendance, and learning-needs data are sensitive. The API binds to loopback (`127.0.0.1`); keep it local unless a separately reviewed deployment provides appropriate authentication, authorization, network controls, and TLS. Grant the API account only the database permissions it needs. Do not commit `.env` or expose exact student-level data unnecessarily.