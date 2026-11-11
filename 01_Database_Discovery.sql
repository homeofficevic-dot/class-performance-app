USE [SchoolDW];
GO

SET NOCOUNT ON;
GO

-- Database and object counts
SELECT
    DB_NAME() AS DatabaseName,
    @@SERVERNAME AS ServerName,
    SYSDATETIMEOFFSET() AS CapturedAt;

SELECT
    (SELECT COUNT(*) FROM sys.tables) AS UserTableCount,
    (SELECT COUNT(*) FROM sys.views) AS ViewCount,
    (SELECT COUNT(*) FROM sys.procedures) AS ProcedureCount,
    (SELECT COUNT(*) FROM sys.objects WHERE type IN ('FN', 'IF', 'TF', 'FS', 'FT')) AS FunctionCount,
    (SELECT COUNT(*) FROM sys.key_constraints WHERE type = 'PK') AS PrimaryKeyConstraintCount,
    (SELECT COUNT(*) FROM sys.key_constraints WHERE type = 'UQ') AS UniqueConstraintCount,
    (SELECT COUNT(*) FROM sys.foreign_keys) AS ForeignKeyCount,
    (SELECT COUNT(*)
     FROM sys.indexes AS ix
     JOIN sys.tables AS t ON t.object_id = ix.object_id
     WHERE ix.index_id > 0 AND ix.is_hypothetical = 0) AS PhysicalUserTableIndexCount,
    (SELECT COUNT(*) FROM sys.indexes WHERE index_id > 0 AND is_hypothetical = 0) AS CatalogIndexCount;

SELECT
    s.name AS SchemaName,
    COUNT(*) AS TableCount
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
GROUP BY s.name
ORDER BY s.name;

-- All tables and estimated row counts
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    COALESCE(SUM(ps.row_count), 0) AS ApproximateRows,
    t.create_date AS CreatedAt,
    t.modify_date AS ModifiedAt
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
LEFT JOIN sys.dm_db_partition_stats AS ps
    ON ps.object_id = t.object_id
   AND ps.index_id IN (0, 1)
GROUP BY s.name, t.name, t.create_date, t.modify_date
ORDER BY s.name, t.name;

-- All views
SELECT
    s.name AS SchemaName,
    v.name AS ViewName,
    OBJECTPROPERTYEX(v.object_id, 'IsSchemaBound') AS IsSchemaBound
FROM sys.views AS v
JOIN sys.schemas AS s ON s.schema_id = v.schema_id
ORDER BY s.name, v.name;

-- Gold entities
SELECT
    t.name AS GoldTable,
    CASE
        WHEN t.name LIKE 'dim%' OR t.name LIKE 'Dim%' THEN 'Dimension'
        WHEN t.name LIKE 'fact%' THEN 'Fact'
        WHEN t.name LIKE 'bridge%' THEN 'Bridge'
        ELSE 'Support / audit'
    END AS EntityType
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
WHERE s.name = 'gold'
ORDER BY EntityType, t.name;

SELECT
    v.name AS GoldView
FROM sys.views AS v
JOIN sys.schemas AS s ON s.schema_id = v.schema_id
WHERE s.name = 'gold'
ORDER BY v.name;

-- Student, class, campus, and academic-calendar structures
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    c.column_id AS Ordinal,
    c.name AS ColumnName,
    ty.name AS DataType,
    c.max_length AS MaxLength,
    c.precision,
    c.scale,
    c.is_nullable AS IsNullable
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.columns AS c ON c.object_id = t.object_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE
    (s.name = 'silver' AND (
        t.name LIKE '%Student%'
        OR t.name IN ('class', 'class_student_membership', 'Campuses', 'Terms', 'OneRosterTerms', 'Calendar')
    ))
    OR (s.name = 'gold' AND (
        t.name LIKE '%Student%'
        OR t.name IN ('dimClass', 'dim_class', 'dimCampus', 'dimDate', 'dim_date', 'factStudentClassMembership')
    ))
ORDER BY s.name, t.name, c.column_id;

-- Assessment source column definitions
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    c.column_id AS Ordinal,
    c.name AS ColumnName,
    ty.name AS DataType,
    c.max_length AS MaxLength,
    c.precision,
    c.scale,
    c.is_nullable AS IsNullable
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.columns AS c ON c.object_id = t.object_id
JOIN sys.types AS ty ON ty.user_type_id = c.user_type_id
WHERE s.name = 'silver'
  AND t.name IN ('PAT', 'EssentialAssessment')
ORDER BY t.name, c.column_id;

-- Primary keys and unique constraints
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    kc.name AS ConstraintName,
    kc.type_desc AS ConstraintType,
    STRING_AGG(CONVERT(nvarchar(max), c.name), ', ')
        WITHIN GROUP (ORDER BY ic.key_ordinal) AS KeyColumns
FROM sys.key_constraints AS kc
JOIN sys.tables AS t ON t.object_id = kc.parent_object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.index_columns AS ic
    ON ic.object_id = kc.parent_object_id
   AND ic.index_id = kc.unique_index_id
JOIN sys.columns AS c
    ON c.object_id = ic.object_id
   AND c.column_id = ic.column_id
GROUP BY s.name, t.name, kc.name, kc.type_desc
ORDER BY s.name, t.name, kc.type_desc, kc.name;

-- Foreign keys, including enforcement state
SELECT
    fk.name AS ForeignKeyName,
    OBJECT_SCHEMA_NAME(fk.parent_object_id) AS ChildSchema,
    OBJECT_NAME(fk.parent_object_id) AS ChildTable,
    pc.name AS ChildColumn,
    OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS ParentSchema,
    OBJECT_NAME(fk.referenced_object_id) AS ParentTable,
    rc.name AS ParentColumn,
    fk.is_disabled AS IsDisabled,
    fk.is_not_trusted AS IsNotTrusted,
    fk.delete_referential_action_desc AS OnDelete,
    fk.update_referential_action_desc AS OnUpdate
FROM sys.foreign_keys AS fk
JOIN sys.foreign_key_columns AS fkc
    ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns AS pc
    ON pc.object_id = fkc.parent_object_id
   AND pc.column_id = fkc.parent_column_id
JOIN sys.columns AS rc
    ON rc.object_id = fkc.referenced_object_id
   AND rc.column_id = fkc.referenced_column_id
ORDER BY ChildSchema, ChildTable, ForeignKeyName, fkc.constraint_column_id;

-- All physical indexes, their key/include columns, and filters
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    ix.name AS IndexName,
    ix.type_desc AS IndexType,
    ix.is_unique AS IsUnique,
    ix.is_primary_key AS IsPrimaryKey,
    ix.is_unique_constraint AS IsUniqueConstraint,
    ix.has_filter AS HasFilter,
    ix.filter_definition AS FilterDefinition,
    STRING_AGG(
        CASE WHEN ic.is_included_column = 0 THEN CONVERT(nvarchar(max), c.name) END,
        ', '
    ) WITHIN GROUP (ORDER BY ic.key_ordinal) AS KeyColumns,
    STRING_AGG(
        CASE WHEN ic.is_included_column = 1 THEN CONVERT(nvarchar(max), c.name) END,
        ', '
    ) AS IncludedColumns
FROM sys.indexes AS ix
JOIN sys.tables AS t ON t.object_id = ix.object_id
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
JOIN sys.index_columns AS ic
    ON ic.object_id = ix.object_id
   AND ic.index_id = ix.index_id
JOIN sys.columns AS c
    ON c.object_id = ic.object_id
   AND c.column_id = ic.column_id
WHERE ix.index_id > 0
  AND ix.is_hypothetical = 0
GROUP BY
    s.name, t.name, ix.name, ix.type_desc, ix.is_unique,
    ix.is_primary_key, ix.is_unique_constraint, ix.has_filter, ix.filter_definition
ORDER BY s.name, t.name, ix.name;

-- Stored procedures and other procedure modules
SELECT
    s.name AS SchemaName,
    p.name AS ProcedureName,
    p.create_date AS CreatedAt,
    p.modify_date AS ModifiedAt,
    OBJECTPROPERTY(p.object_id, 'IsEncrypted') AS IsEncrypted
FROM sys.procedures AS p
JOIN sys.schemas AS s ON s.schema_id = p.schema_id
ORDER BY s.name, p.name;

-- Declared object dependencies. Dynamic SQL dependencies may not appear here.
SELECT DISTINCT
    OBJECT_SCHEMA_NAME(d.referencing_id) AS ReferencingSchema,
    OBJECT_NAME(d.referencing_id) AS ReferencingObject,
    COALESCE(d.referenced_schema_name, OBJECT_SCHEMA_NAME(d.referenced_id)) AS ReferencedSchema,
    d.referenced_entity_name AS ReferencedObject,
    d.is_schema_bound_reference AS IsSchemaBound
FROM sys.sql_expression_dependencies AS d
WHERE d.referencing_id IS NOT NULL
ORDER BY ReferencingSchema, ReferencingObject, ReferencedSchema, ReferencedObject;

-- Assessment and school-identity references in stored modules
SELECT
    s.name AS SchemaName,
    o.name AS ModuleName,
    o.type_desc AS ModuleType,
    CASE WHEN m.definition LIKE '%silver.PAT%' THEN 1 ELSE 0 END AS ReferencesPAT,
    CASE WHEN m.definition LIKE '%silver.EssentialAssessment%' THEN 1 ELSE 0 END AS ReferencesEssentialAssessment,
    CASE WHEN m.definition LIKE '%silver.StudentClasses%' THEN 1 ELSE 0 END AS ReferencesStudentClasses,
    CASE WHEN m.definition LIKE '%silver.StudentsBasic%' THEN 1 ELSE 0 END AS ReferencesStudentsBasic,
    CASE WHEN m.definition LIKE '%silver.Campuses%' THEN 1 ELSE 0 END AS ReferencesCampuses,
    CASE WHEN m.definition LIKE '%OneRosterTerms%' OR m.definition LIKE '%silver.Terms%' THEN 1 ELSE 0 END AS ReferencesTerms
FROM sys.sql_modules AS m
JOIN sys.objects AS o ON o.object_id = m.object_id
JOIN sys.schemas AS s ON s.schema_id = o.schema_id
WHERE o.type IN ('P', 'V', 'FN', 'IF', 'TF')
  AND (
       m.definition LIKE '%silver.PAT%'
    OR m.definition LIKE '%silver.EssentialAssessment%'
    OR m.definition LIKE '%silver.StudentClasses%'
    OR m.definition LIKE '%silver.StudentsBasic%'
    OR m.definition LIKE '%silver.Campuses%'
    OR m.definition LIKE '%OneRosterTerms%'
    OR m.definition LIKE '%silver.Terms%'
  )
ORDER BY s.name, o.name;

-- ETL control, run, and mapping table population
SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    COALESCE(SUM(ps.row_count), 0) AS ApproximateRows
FROM sys.tables AS t
JOIN sys.schemas AS s ON s.schema_id = t.schema_id
LEFT JOIN sys.dm_db_partition_stats AS ps
    ON ps.object_id = t.object_id
   AND ps.index_id IN (0, 1)
WHERE s.name IN ('metadata', 'audit', 'dbo', 'gold')
  AND (
       t.name LIKE '%config%'
    OR t.name LIKE '%dependency%'
    OR t.name LIKE '%mapping%'
    OR t.name LIKE '%watermark%'
    OR t.name LIKE '%load%'
    OR t.name LIKE '%batch%'
    OR t.name LIKE '%audit%'
    OR t.name LIKE '%reconciliation%'
  )
GROUP BY s.name, t.name
ORDER BY s.name, t.name;
GO
