# Phase 3 consequence engine

## Database deployment

Deploy after the core wellbeing schema and legacy reference-data migration:

1. `19_Migrate_Legacy_Behaviour_ReferenceData.sql`
2. `20_Incident_Roles.sql`
3. `21_Consequence_Engine.sql`
4. `23_Configure_Application_Detention_Workflow.sql`
5. `22_Test_Consequence_Engine.sql`
6. `24_Test_Application_Detention_Workflow.sql`

For the local SQL Server instance, run from PowerShell with a Windows-authenticated account:

```powershell
sqlcmd -S localhost -d SchoolDW -E -b -i "C:\Sanits\Saints Student\api\20_Incident_Roles.sql"
sqlcmd -S localhost -d SchoolDW -E -b -i "C:\Sanits\Saints Student\api\21_Consequence_Engine.sql"
sqlcmd -S localhost -d SchoolDW -E -b -i "C:\Sanits\Saints Student\api\23_Configure_Application_Detention_Workflow.sql"
sqlcmd -S localhost -d SchoolDW -E -b -i "C:\Sanits\Saints Student\api\22_Test_Consequence_Engine.sql"
sqlcmd -S localhost -d SchoolDW -E -b -i "C:\Sanits\Saints Student\api\24_Test_Application_Detention_Workflow.sql"
```

The scripts are rerunnable. The schema changes are additive; rollback should use a reviewed database backup/restore or a separately approved reverse migration. Do not drop the audit or assignment columns after assignments have been recorded.

## Endpoints

All endpoints require the existing trusted staff identity middleware and an active `wellbeing.IncidentStaffRole` assignment. They fail closed when identity or role assignment cannot be verified.

| Method | Path | Purpose | Authorization |
|---|---|---|---|
| GET | `/api/incidents/{incidentId}/consequences/eligible?studentKey={key}&proposedDate=YYYY-MM-DD` | Return only consequences currently eligible for the incident snapshot and proposed date | Existing incident read roles |
| GET | `/api/incidents/{incidentId}/consequences` | List assignments and current workflow state | Existing incident read roles |
| GET | `/api/consequences/work-queue` | List open in-app consequence workflow tasks for the authenticated user's roles | Existing incident read roles |
| GET | `/api/consequences/{assignmentId}/audit` | Read immutable decision and workflow audit events | Existing incident read roles |
| POST | `/api/incidents/{incidentId}/consequences` | Assign a consequence; send `Idempotency-Key` UUID | Reporting staff or administration |
| POST | `/api/consequences/{assignmentId}/approve` | Approve a pending assignment | Authorized approver, assigned role, or administration |
| POST | `/api/consequences/{assignmentId}/reject` | Reject a pending assignment | Authorized approver, assigned role, or administration |
| POST | `/api/consequences/{assignmentId}/complete` | Mark an approved/active assignment complete | Assigned staff, assigned role, or administration |
| POST | `/api/consequences/{assignmentId}/cancel` | Cancel a non-terminal assignment | Original assigner or administration |

Assignment request:

```json
{
  "studentKey": 123,
  "consequenceId": 10,
  "scheduledStartDate": "2026-03-10",
  "assignmentReason": "Optional note"
}
```

Workflow action request:

```json
{
  "notes": "Optional audit note"
}
```

Eligibility is recalculated inside the assignment stored procedure while holding a transaction-scoped application lock keyed by student and scheduled date. The server does not accept a client-supplied eligibility result. Stored decisions retain the incident year-level snapshot, rule version, applied-rule JSON, role resolution, actor, and workflow audit events. For the configured detention group, a student can have at most one active detention assignment on a date, regardless of which detention type is selected. Cancelled and rejected assignments do not consume that limit. The group-wide check is repeated inside the locked transaction to prevent concurrent requests from bypassing the rule.

## Configuration and known data gaps

- Staff-role assignments are maintained in `wellbeing.IncidentStaffRole`; consequence-specific primary/delegate assignments are maintained in `wellbeing.ConsequenceRoleAssignment`. Multiple active matches are reported as conflicts and are not resolved by selecting an arbitrary staff member.
- The legacy `tblConsequences` values are preserved as imported. `23_Configure_Application_Detention_Workflow.sql` adds a separate application-managed override for legacy consequence 57: Pastoral Care must approve and process it. Each active consequence whose configured name contains “detention” is placed in the `DETENTION` restriction group with a limit of one per student/date.
- An approval-required assignment creates a role-targeted `IN_APP` notification in the same SQL transaction. Authorized role members can retrieve pending work from `GET /api/consequences/work-queue`. This is not email delivery; the API does not send email or prove that any recipient has received an email.
- To roll back only this configuration without deleting audit/history or assignments, run a reviewed transaction:

```sql
BEGIN TRANSACTION;
UPDATE workflow
SET IsActive = 0, ModifiedDate = SYSUTCDATETIME(), ModifiedBy = N'approved rollback'
FROM wellbeing.ConsequenceApplicationWorkflow AS workflow
INNER JOIN wellbeing.tblConsequences AS consequence
    ON consequence.ConsequenceId = workflow.ConsequenceId
WHERE consequence.LegacyConsequenceId = 57;
UPDATE wellbeing.ConsequenceRestrictionGroup
SET IsActive = 0
WHERE RestrictionGroupCode = N'DETENTION';
COMMIT TRANSACTION;
```

Existing assignments and notification records remain intact. Re-run the application configuration script only after resolving the rollback cause.
- Calendar restrictions are consequence-specific in `wellbeing.ConsequenceCalendarRule`. When `RequiresSchoolDay=1`, a proposed date must have an explicit `SchoolCalendar` entry marked as a school day; missing calendar dates fail closed. No school-day restriction is inferred for consequences without a configured calendar rule. Cycle-day rules remain ineligible until a cycle calendar source is configured.
- The database currently has no verified incident year-level snapshots. The engine intentionally returns no eligible consequences when a historical year level is unresolved.
- Legacy approval status remains unknown for imported consequences unless an applicable policy rule or separate application override applies. Other consequences with unknown approval configuration enter `AWAITING_REVIEW`.
- No outbound email mechanism is configured. Role-targeted in-app tasks are persisted; production staff must have the Pastoral Care role through the existing wellbeing or organisation group assignments to access the queue.
- The one-detention-per-day restriction is an explicit application rule and intentionally supersedes the legacy multiple-per-day flag for detention assignments. It does not impose a restriction on non-detention consequences.

## Manual concurrent-request check

Use two SQL sessions against the same verified incident/student/detention-date fixture and distinct idempotency keys. Submit two different detention consequences for that student/date at once. One may commit; the other must observe the committed detention and fail eligibility with SQL error `51207`. Reusing one idempotency key with the identical payload returns the original assignment; reusing it for different input raises `51205`.
