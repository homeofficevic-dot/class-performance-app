const { getPool, sql } = require('../config/database');

class StudentService {
  async getAllStudents(page = 1, limit = 10, filters = {}) {
    try {
      const pool = getPool();
      const offset = (page - 1) * limit;

      let whereClause = '1=1';
      const request = pool.request();

      if (filters.name) {
        whereClause += ' AND (FirstName LIKE @name OR LastName LIKE @name)';
        request.input('name', sql.VarChar(100), `%${filters.name}%`);
      }

      if (filters.classId) {
        whereClause += ' AND ClassID = @classId';
        request.input('classId', sql.Int, filters.classId);
      }

      if (filters.yearLevel) {
        whereClause += ' AND YearLevel = @yearLevel';
        request.input('yearLevel', sql.VarChar(10), filters.yearLevel);
      }

      // Get total count
      const countResult = await request.query(
        `SELECT COUNT(*) as total FROM gold.dimStudent WHERE ${whereClause}`
      );
      const total = countResult.recordset[0].total;

      // Get paginated data
      const result = await pool.request()
        .query(`
          SELECT TOP ${limit}
                 StudentKey,
                 StudentID,
                 FirstName,
                 LastName,
                 DateOfBirth,
                 Gender,
                 ClassID,
                 YearLevel,
                 EnrollmentDate
          FROM gold.dimStudent
          WHERE ${whereClause}
          ORDER BY FirstName, LastName
          OFFSET ${offset} ROWS
        `);

      return {
        success: true,
        data: result.recordset,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      };
    } catch (error) {
      console.error('Error fetching students:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async getStudentById(studentKey) {
    try {
      const pool = getPool();
      const result = await pool.request()
        .input('studentKey', sql.Int, studentKey)
        .query(`
          SELECT *
          FROM gold.dimStudent
          WHERE StudentKey = @studentKey
        `);

      if (result.recordset.length === 0) {
        return {
          success: false,
          error: 'Student not found'
        };
      }

      return {
        success: true,
        data: result.recordset[0]
      };
    } catch (error) {
      console.error('Error fetching student:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async getStudentIncidents(studentKey) {
    try {
      const pool = getPool();
      const result = await pool.request()
        .input('studentKey', sql.Int, studentKey)
        .query(`
          SELECT TOP 50
                 IncidentID,
                 StudentKey,
                 IncidentDateTime,
                 IncidentTypeCode,
                 Severity,
                 Status
          FROM wellbeing.factBehaviourIncident
          WHERE StudentKey = @studentKey
          ORDER BY IncidentDateTime DESC
        `);

      return {
        success: true,
        data: result.recordset
      };
    } catch (error) {
      console.error('Error fetching student incidents:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async getStudentSupportPlan(studentKey) {
    try {
      const pool = getPool();
      const result = await pool.request()
        .input('studentKey', sql.Int, studentKey)
        .query(`
          SELECT TOP 1
                 PlanID,
                 StudentKey,
                 PlanTitle,
                 Status,
                 CreatedDate,
                 TargetDate,
                 Description
          FROM wellbeing.factStudentSupportPlan
          WHERE StudentKey = @studentKey
          ORDER BY CreatedDate DESC
        `);

      if (result.recordset.length === 0) {
        return {
          success: true,
          data: null
        };
      }

      return {
        success: true,
        data: result.recordset[0]
      };
    } catch (error) {
      console.error('Error fetching support plan:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async getStudentWellbeingNotes(studentKey, limit = 20) {
    try {
      const pool = getPool();
      const result = await pool.request()
        .input('studentKey', sql.Int, studentKey)
        .query(`
          SELECT TOP ${limit}
                 NoteID,
                 StudentKey,
                 NoteContent,
                 NoteType,
                 CreatedByStaffKey,
                 CreatedDate
          FROM wellbeing.factWellbeingNote
          WHERE StudentKey = @studentKey
          ORDER BY CreatedDate DESC
        `);

      return {
        success: true,
        data: result.recordset
      };
    } catch (error) {
      console.error('Error fetching wellbeing notes:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async addWellbeingNote(studentKey, noteContent, noteType, staffKey) {
    try {
      const pool = getPool();
      
      const result = await pool.request()
        .input('StudentKey', sql.Int, studentKey)
        .input('NoteContent', sql.VarChar(sql.MAX), noteContent)
        .input('NoteType', sql.VarChar(50), noteType)
        .input('CreatedByStaffKey', sql.Int, staffKey)
        .input('CreatedDate', sql.DateTime, new Date())
        .query(`
          INSERT INTO wellbeing.factWellbeingNote
          (StudentKey, NoteContent, NoteType, CreatedByStaffKey, CreatedDate)
          VALUES
          (@StudentKey, @NoteContent, @NoteType, @CreatedByStaffKey, @CreatedDate)
        `);

      return {
        success: true,
        message: 'Wellbeing note added successfully',
        rowsAffected: result.rowsAffected[0]
      };
    } catch (error) {
      console.error('Error adding wellbeing note:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async getRiskAssessment(studentKey) {
    try {
      const pool = getPool();
      
      // Count incidents by severity
      const incidentResult = await pool.request()
        .input('studentKey', sql.Int, studentKey)
        .query(`
          SELECT 
            Severity,
            COUNT(*) as count
          FROM wellbeing.factBehaviourIncident
          WHERE StudentKey = @studentKey
            AND IncidentDateTime >= DATEADD(MONTH, -3, GETDATE())
          GROUP BY Severity
        `);

      // Get recent incidents
      const recentResult = await pool.request()
        .input('studentKey', sql.Int, studentKey)
        .query(`
          SELECT TOP 5
            IncidentID,
            IncidentDateTime,
            Severity
          FROM wellbeing.factBehaviourIncident
          WHERE StudentKey = @studentKey
          ORDER BY IncidentDateTime DESC
        `);

      return {
        success: true,
        data: {
          severitySummary: incidentResult.recordset,
          recentIncidents: recentResult.recordset
        }
      };
    } catch (error) {
      console.error('Error getting risk assessment:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
}

module.exports = new StudentService();
