# Organisation and pastoral assignment deployment

## Order

1. `00_Create_Wellbeing_Schema.sql` (if the wellbeing schema is not deployed)
2. `01_Create_Wellbeing_Transactional_Tables.sql` (if required)
3. Ensure `gold.dimStudent` and `gold.dimStaff` are deployed and populated.
4. `10_Create_Organisation_Schema.sql`
5. `11_Create_Organisation_Indexes_Views.sql`
6. `12_Create_Organisation_Procedures.sql`
7. Load verified extracts into the staging tables created by `13_Organisation_Migration.sql`.
8. Run `13_Organisation_Migration.sql`.
9. Run `14_Organisation_Reconciliation.sql`; investigate every non-empty result set.
10. Run `15_Organisation_SQL_Tests.sql` in a disposable database.
11. Run `17_Complete_Step1_SQL_Objects.sql`.
12. Run `19_Create_Requested_Assignment_Tables.sql`.
13. Run `18_Seed_Organisation_Demo_Data.sql` only in local/demo environments.
14. Run `15_Organisation_SQL_Tests.sql` in a disposable database or within its rollback transaction.

Run each file in SQL Server Management Studio or `sqlcmd` against `SchoolDW`. Stop
if a script fails. All DDL is guarded except indexes; if rerunning a deployed
database, create each index only once or run the index statements through your
standard index deployment tool.

## Rollback

Do not delete migrated history. First disable application writes, record the
deployment version, and remove only newly created objects in reverse dependency
order after an approved backup: procedures/views, assignment tables, audit and
staging tables, then reference tables. Existing legacy source data is not changed.
To correct a migration, fix the staging extract and rerun the idempotent migration;
use dated `EffectiveFrom`/`EffectiveTo` rows to preserve history.

The architecture and ERD are documented in `09_Organisation_Architecture.md`.

The local `SchoolDW` deployment has been completed. Demo data is tagged with
`SourceSystem = 'DEMO'`: four houses (Banksia, Waratah, Grevillea, Wattle),
eight pastoral groups, four heads of house, eight pastoral-care teachers, and
assignments for the first 100 students. Rerunning the seed is idempotent.
