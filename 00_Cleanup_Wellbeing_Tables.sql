-- ============================================================================
-- DATABASE SCHEMA FIX - Cleanup Script
-- ============================================================================
-- Purpose: Drop problematic fact tables to allow fresh creation
-- Run this BEFORE re-running 01_Create_Wellbeing_Transactional_Tables.sql
-- ============================================================================

USE SchoolDW;
GO

PRINT '';
PRINT '============================================================================';
PRINT 'Cleaning up transactional tables for fresh creation...';
PRINT '============================================================================';
PRINT '';

-- Drop tables in reverse order of dependencies
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factAuditTrail') AND type in (N'U'))
BEGIN
    DROP TABLE wellbeing.factAuditTrail;
    PRINT '✓ Dropped: wellbeing.factAuditTrail';
END
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factIncidentNotification') AND type in (N'U'))
BEGIN
    DROP TABLE wellbeing.factIncidentNotification;
    PRINT '✓ Dropped: wellbeing.factIncidentNotification';
END
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factWellbeingNote') AND type in (N'U'))
BEGIN
    DROP TABLE wellbeing.factWellbeingNote;
    PRINT '✓ Dropped: wellbeing.factWellbeingNote';
END
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factStudentSupportPlan') AND type in (N'U'))
BEGIN
    DROP TABLE wellbeing.factStudentSupportPlan;
    PRINT '✓ Dropped: wellbeing.factStudentSupportPlan';
END
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factPastoralIntervention') AND type in (N'U'))
BEGIN
    DROP TABLE wellbeing.factPastoralIntervention;
    PRINT '✓ Dropped: wellbeing.factPastoralIntervention';
END
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factApprovalHistory') AND type in (N'U'))
BEGIN
    DROP TABLE wellbeing.factApprovalHistory;
    PRINT '✓ Dropped: wellbeing.factApprovalHistory';
END
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factConsequenceAssignment') AND type in (N'U'))
BEGIN
    DROP TABLE wellbeing.factConsequenceAssignment;
    PRINT '✓ Dropped: wellbeing.factConsequenceAssignment';
END
GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'wellbeing.factBehaviourIncident') AND type in (N'U'))
BEGIN
    DROP TABLE wellbeing.factBehaviourIncident;
    PRINT '✓ Dropped: wellbeing.factBehaviourIncident';
END
GO

PRINT '';
PRINT '============================================================================';
PRINT 'Cleanup Complete!';
PRINT '';
PRINT 'Next Step:';
PRINT '  Run: sqlcmd -S <server> -d SchoolDW -i 01_Create_Wellbeing_Transactional_Tables.sql';
PRINT '============================================================================';
PRINT '';
