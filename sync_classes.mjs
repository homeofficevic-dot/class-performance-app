import sql from 'mssql/msnodesqlv8.js';
import crypto from 'crypto';

const pool = await sql.connect({
  server: 'localhost',
  database: 'DevWorking',
  driver: 'ODBC Driver 17 for SQL Server',
  options: { trustedConnection: true }
});

// Check existing classes in CompassStudentClasses
const existing = await pool.request().query("SELECT DISTINCT ClassCode, ClassSourcedId, COUNT(*) as c FROM dbo.CompassStudentClasses GROUP BY ClassCode, ClassSourcedId");
console.log('Existing in CompassStudentClasses:', existing.recordset);

// Check if BDHUBCTGPE1 exists
const hasCtg = existing.recordset.some(r => r.ClassCode === 'BDHUBCTGPE1');
if (!hasCtg) {
  console.log('Inserting BDHUBCTGPE1 students based on BDHUBCOGPE1 cohort...');
  const baseStudents = await pool.request().query("SELECT * FROM dbo.CompassStudentClasses WHERE ClassCode = 'BDHUBCOGPE1'");
  for (const s of baseStudents.recordset) {
    const classSourcedId = '3484a6d9-b770-4f39-9bb3-78a180a2268d';
    const classCode = 'BDHUBCTGPE1';
    const key = crypto.createHash('sha256').update(`${s.CompassPersonId.toLowerCase()}|${classSourcedId.toLowerCase()}`).digest('hex');
    
    await pool.request()
      .input('key', sql.NVarChar(200), key)
      .input('personId', sql.NVarChar(100), s.CompassPersonId)
      .input('sourcedId', sql.NVarChar(100), s.SourcedId)
      .input('studentCode', sql.NVarChar(100), s.StudentCode)
      .input('classCode', sql.NVarChar(100), classCode)
      .input('subjectName', sql.NVarChar(200), 'Circle Time')
      .input('yearLevel', sql.Int, s.YearLevel)
      .input('givenName', sql.NVarChar(100), s.GivenName)
      .input('familyName', sql.NVarChar(100), s.FamilyName)
      .input('username', sql.NVarChar(200), s.Username)
      .input('identifier', sql.NVarChar(100), s.Identifier)
      .input('classSourcedId', sql.NVarChar(100), classSourcedId)
      .input('classTitle', sql.NVarChar(200), 'Circle Time - BDHUBCTGPE1')
      .query(`
        IF NOT EXISTS (SELECT 1 FROM dbo.CompassStudentClasses WHERE StudentClassKey = @key)
        BEGIN
          INSERT INTO dbo.CompassStudentClasses (
            StudentClassKey, CompassPersonId, SourcedId, StudentCode, ClassCode,
            SubjectName, YearLevel, IsActive, SyncedAt, GivenName, FamilyName,
            Username, Identifier, ClassSourcedId, ClassTitle
          ) VALUES (
            @key, @personId, @sourcedId, @studentCode, @classCode,
            @subjectName, @yearLevel, 1, SYSUTCDATETIME(), @givenName, @familyName,
            @username, @identifier, @classSourcedId, @classTitle
          )
        END
      `);
  }
  console.log('BDHUBCTGPE1 students inserted.');
}

// Check BDHUBCTMN2 as well
const hasCtmn = existing.recordset.some(r => r.ClassCode === 'BDHUBCTMN2');
if (!hasCtmn) {
  console.log('Inserting BDHUBCTMN2 students based on BDHUBCOGPE1 cohort...');
  const baseStudents = await pool.request().query("SELECT * FROM dbo.CompassStudentClasses WHERE ClassCode = 'BDHUBCOGPE1'");
  for (const s of baseStudents.recordset) {
    const classSourcedId = 'e001377d-166a-4a67-9d12-65a143886497';
    const classCode = 'BDHUBCTMN2';
    const key = crypto.createHash('sha256').update(`${s.CompassPersonId.toLowerCase()}|${classSourcedId.toLowerCase()}`).digest('hex');
    
    await pool.request()
      .input('key', sql.NVarChar(200), key)
      .input('personId', sql.NVarChar(100), s.CompassPersonId)
      .input('sourcedId', sql.NVarChar(100), s.SourcedId)
      .input('studentCode', sql.NVarChar(100), s.StudentCode)
      .input('classCode', sql.NVarChar(100), classCode)
      .input('subjectName', sql.NVarChar(200), 'Circle Time')
      .input('yearLevel', sql.Int, s.YearLevel)
      .input('givenName', sql.NVarChar(100), s.GivenName)
      .input('familyName', sql.NVarChar(100), s.FamilyName)
      .input('username', sql.NVarChar(200), s.Username)
      .input('identifier', sql.NVarChar(100), s.Identifier)
      .input('classSourcedId', sql.NVarChar(100), classSourcedId)
      .input('classTitle', sql.NVarChar(200), 'Circle Time - BDHUBCTMN2')
      .query(`
        IF NOT EXISTS (SELECT 1 FROM dbo.CompassStudentClasses WHERE StudentClassKey = @key)
        BEGIN
          INSERT INTO dbo.CompassStudentClasses (
            StudentClassKey, CompassPersonId, SourcedId, StudentCode, ClassCode,
            SubjectName, YearLevel, IsActive, SyncedAt, GivenName, FamilyName,
            Username, Identifier, ClassSourcedId, ClassTitle
          ) VALUES (
            @key, @personId, @sourcedId, @studentCode, @classCode,
            @subjectName, @yearLevel, 1, SYSUTCDATETIME(), @givenName, @familyName,
            @username, @identifier, @classSourcedId, @classTitle
          )
        END
      `);
  }
  console.log('BDHUBCTMN2 students inserted.');
}

const after = await pool.request().query("SELECT DISTINCT ClassCode, ClassSourcedId, COUNT(*) as c FROM dbo.CompassStudentClasses GROUP BY ClassCode, ClassSourcedId");
console.log('After in CompassStudentClasses:', after.recordset);

process.exit(0);
