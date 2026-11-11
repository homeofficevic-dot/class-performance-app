# Step 1 database assessment

Assessment completed against local `SchoolDW` before completion objects were
deployed.

| Area | Finding |
|---|---|
| Authoritative student identity | `gold.dimStudent.StudentKey` (`BIGINT`) |
| Authoritative staff identity | `gold.dimStaff.StaffKey` (`INT`) |
| Legacy tables | `DC_College_Organisation`, `DC_StudentManagement_Organisation`, `DC_House_Heads`, and `DC_Level_CoOrdinators` were not present in local `SchoolDW` |
| Existing organisation model | None before Step 1; the new `org` model is now deployed |
| Existing student pastoral model | None before Step 1; demo assignments are tagged `DEMO` |
| Source policy | No legacy relationships were fabricated; verified-source staging remains available |

`gold.dimStudent` and `gold.dimStaff` are not interchangeable with source
employee/student identifiers. The migration staging contract preserves source
system and source record IDs and requires an explicit verification flag.
