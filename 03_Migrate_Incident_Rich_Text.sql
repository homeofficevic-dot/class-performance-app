-- Stores the rich-text editor HTML without truncation.
USE SchoolDW;
GO

IF COL_LENGTH('wellbeing.factBehaviourIncident', 'DetailedDescription') IS NOT NULL
BEGIN
    ALTER TABLE wellbeing.factBehaviourIncident
    ALTER COLUMN DetailedDescription NVARCHAR(MAX) NULL;
END;
GO

IF COL_LENGTH('wellbeing.factBehaviourIncident', 'FollowUpNotes') IS NULL
BEGIN
    ALTER TABLE wellbeing.factBehaviourIncident
    ADD FollowUpNotes NVARCHAR(MAX) NULL;
END
ELSE
BEGIN
    ALTER TABLE wellbeing.factBehaviourIncident
    ALTER COLUMN FollowUpNotes NVARCHAR(MAX) NULL;
END;
GO
