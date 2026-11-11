-- ============================================================================
-- Standard school locations
-- Database: SchoolDW
-- Schema: wellbeing
-- Safe to run repeatedly: existing LocationCode values are not duplicated.
-- ============================================================================

USE SchoolDW;
GO

SET XACT_ABORT ON;
BEGIN TRANSACTION;

DECLARE @Locations TABLE (
    LocationCode NVARCHAR(50) NOT NULL,
    LocationName NVARCHAR(100) NOT NULL,
    LocationDescription NVARCHAR(500) NULL,
    LocationCategory NVARCHAR(100) NULL,
    ResponsibleDepartment NVARCHAR(100) NULL,
    IsActive BIT NOT NULL,
    DisplayOrder INT NOT NULL
);

INSERT INTO @Locations
    (LocationCode, LocationName, LocationDescription, LocationCategory, ResponsibleDepartment, IsActive, DisplayOrder)
VALUES
    ('CLASSROOM', 'Classroom', 'General teaching and learning spaces.', 'Classroom', 'Teaching and Learning', 1, 1),
    ('LIBRARY', 'Library', 'School library and resource centre.', 'Learning Facility', 'Teaching and Learning', 1, 2),
    ('SCIENCE_BLOCK', 'Science Block', 'Science classrooms and laboratories.', 'Classroom', 'Teaching and Learning', 1, 3),
    ('COMPUTER_LAB', 'Computer Lab', 'Computer laboratory and technology learning space.', 'Learning Facility', 'Information Technology', 1, 4),
    ('PLAYGROUND', 'Playground', 'General student playground area.', 'Outdoor Area', 'Student Wellbeing', 1, 5),
    ('SPORTS_OVAL', 'Sports Oval', 'Outdoor oval and sports field.', 'Sports Facility', 'Sport and Recreation', 1, 6),
    ('GYMNASIUM', 'Gymnasium', 'Indoor sports and physical education facility.', 'Sports Facility', 'Sport and Recreation', 1, 7),
    ('MULTIPURPOSE_HALL', 'Multipurpose Hall', 'Hall used for assemblies, events and activities.', 'Assembly Facility', 'Administration', 1, 8),
    ('CANTEEN', 'Canteen', 'School canteen and food service area.', 'Student Facility', 'Student Services', 1, 9),
    ('ADMIN_OFFICE', 'Administration Office', 'Main administration and reception area.', 'Administration', 'Administration', 1, 10),
    ('STAFFROOM', 'Staffroom', 'Staff common room and meeting area.', 'Staff Facility', 'Administration', 1, 11),
    ('CARPARK', 'Car Park', 'School vehicle and visitor parking area.', 'Transport Area', 'Facilities', 1, 12),
    ('SCHOOL_BUS', 'School Bus', 'School bus and student transport area.', 'Transport Area', 'Transport', 1, 13);

INSERT INTO wellbeing.tblSchoolLocations
    (LocationCode, LocationName, LocationDescription, LocationCategory,
     ResponsibleDepartment, IsActive, DisplayOrder, CreatedBy, ModifiedBy)
SELECT
    source.LocationCode,
    source.LocationName,
    source.LocationDescription,
    source.LocationCategory,
    source.ResponsibleDepartment,
    source.IsActive,
    source.DisplayOrder,
    'SEED',
    'SEED'
FROM @Locations AS source
WHERE NOT EXISTS (
    SELECT 1
    FROM wellbeing.tblSchoolLocations AS target
    WHERE target.LocationCode = source.LocationCode
);

COMMIT TRANSACTION;
GO

SELECT
    LocationId,
    LocationCode,
    LocationName,
    LocationDescription,
    LocationCategory,
    ResponsibleDepartment,
    ResponsibleStaffKey,
    IsActive,
    DisplayOrder,
    CreatedDate,
    CreatedBy,
    ModifiedDate,
    ModifiedBy
FROM wellbeing.tblSchoolLocations
WHERE LocationCode IN (
    'CLASSROOM', 'LIBRARY', 'SCIENCE_BLOCK', 'COMPUTER_LAB',
    'PLAYGROUND', 'SPORTS_OVAL', 'GYMNASIUM', 'MULTIPURPOSE_HALL',
    'CANTEEN', 'ADMIN_OFFICE', 'STAFFROOM', 'CARPARK', 'SCHOOL_BUS'
)
ORDER BY DisplayOrder;
GO
