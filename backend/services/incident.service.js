const { getPool, sql } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

class IncidentService {
  async getAllIncidents(page = 1, limit = 10, filters = {}) {
    try {
      const pool = getPool();
      const offset = (page - 1) * limit;

      // Build dynamic WHERE clause
      let whereClause = '1=1';
      const request = pool.request();

      if (filters.studentKey) {
        whereClause += ' AND StudentKey = @studentKey';
        request.input('studentKey', sql.Int, filters.studentKey);
      }

      if (filters.status) {
        whereClause += ' AND Status = @status';
        request.input('status', sql.VarChar(50), filters.status);
      }

      if (filters.incidentType) {
        whereClause += ' AND IncidentTypeCode = @incidentType';
        request.input('incidentType', sql.VarChar(50), filters.incidentType);
      }

      if (filters.startDate) {
        whereClause += ' AND IncidentDateTime >= @startDate';
        request.input('startDate', sql.DateTime, new Date(filters.startDate));
      }

      if (filters.endDate) {
        whereClause += ' AND IncidentDateTime <= @endDate';
        request.input('endDate', sql.DateTime, new Date(filters.endDate));
      }

      // Get total count
      const countResult = await request.query(
        `SELECT COUNT(*) as total FROM wellbeing.factBehaviourIncident WHERE ${whereClause}`
      );
      const total = countResult.recordset[0].total;

      // Get paginated data
      const result = await pool.request()
        .query(`
          SELECT TOP ${limit} 
                 IncidentID,
                 StudentKey,
                 IncidentDateTime,
                 IncidentTypeCode,
                 Severity,
                 Description,
                 LocationCode,
                 ReportedByStaffKey,
                 Status,
                 CreatedDate,
                 LastModifiedDate
          FROM wellbeing.factBehaviourIncident
          WHERE ${whereClause}
          ORDER BY IncidentDateTime DESC
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
      console.error('Error fetching incidents:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async getIncidentById(incidentId) {
    try {
      const pool = getPool();
      const result = await pool.request()
        .input('incidentID', sql.Int, incidentId)
        .query(`
          SELECT *
          FROM wellbeing.factBehaviourIncident
          WHERE IncidentID = @incidentID
        `);

      if (result.recordset.length === 0) {
        return {
          success: false,
          error: 'Incident not found'
        };
      }

      return {
        success: true,
        data: result.recordset[0]
      };
    } catch (error) {
      console.error('Error fetching incident:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async createIncident(incidentData) {
    try {
      const pool = getPool();
      
      const result = await pool.request()
        .input('StudentKey', sql.Int, incidentData.studentKey)
        .input('IncidentDateTime', sql.DateTime, new Date(incidentData.incidentDateTime))
        .input('IncidentTypeCode', sql.VarChar(50), incidentData.incidentTypeCode)
        .input('Severity', sql.VarChar(50), incidentData.severity)
        .input('Description', sql.VarChar(sql.MAX), incidentData.description)
        .input('LocationCode', sql.VarChar(50), incidentData.locationCode)
        .input('ReportedByStaffKey', sql.Int, incidentData.reportedByStaffKey)
        .input('Status', sql.VarChar(50), 'OPEN')
        .input('CreatedDate', sql.DateTime, new Date())
        .query(`
          INSERT INTO wellbeing.factBehaviourIncident 
          (StudentKey, IncidentDateTime, IncidentTypeCode, Severity, Description, 
           LocationCode, ReportedByStaffKey, Status, CreatedDate, LastModifiedDate)
          VALUES 
          (@StudentKey, @IncidentDateTime, @IncidentTypeCode, @Severity, @Description,
           @LocationCode, @ReportedByStaffKey, @Status, @CreatedDate, @CreatedDate)
        `);

      return {
        success: true,
        message: 'Incident created successfully',
        rowsAffected: result.rowsAffected[0]
      };
    } catch (error) {
      console.error('Error creating incident:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async updateIncident(incidentId, updates) {
    try {
      const pool = getPool();
      
      let updateQuery = 'UPDATE wellbeing.factBehaviourIncident SET ';
      const request = pool.request();
      const fields = [];

      request.input('incidentID', sql.Int, incidentId);
      request.input('LastModifiedDate', sql.DateTime, new Date());

      for (const [key, value] of Object.entries(updates)) {
        if (value !== undefined && value !== null) {
          fields.push(`${key} = @${key}`);
          
          if (key === 'IncidentDateTime') {
            request.input(key, sql.DateTime, new Date(value));
          } else if (['Severity', 'Status', 'IncidentTypeCode', 'LocationCode', 'Description'].includes(key)) {
            request.input(key, sql.VarChar(sql.MAX), value);
          } else {
            request.input(key, sql.Int, value);
          }
        }
      }

      updateQuery += fields.join(', ') + ', LastModifiedDate = @LastModifiedDate ';
      updateQuery += 'WHERE IncidentID = @incidentID';

      const result = await request.query(updateQuery);

      return {
        success: true,
        message: 'Incident updated successfully',
        rowsAffected: result.rowsAffected[0]
      };
    } catch (error) {
      console.error('Error updating incident:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async deleteIncident(incidentId) {
    try {
      const pool = getPool();
      
      const result = await pool.request()
        .input('incidentID', sql.Int, incidentId)
        .query(`
          DELETE FROM wellbeing.factBehaviourIncident
          WHERE IncidentID = @incidentID
        `);

      return {
        success: true,
        message: 'Incident deleted successfully',
        rowsAffected: result.rowsAffected[0]
      };
    } catch (error) {
      console.error('Error deleting incident:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async approveIncident(incidentId, approverStaffKey, notes) {
    try {
      const pool = getPool();
      
      // Update incident status
      await pool.request()
        .input('incidentID', sql.Int, incidentId)
        .input('status', sql.VarChar(50), 'APPROVED')
        .query(`
          UPDATE wellbeing.factBehaviourIncident
          SET Status = @status, LastModifiedDate = GETDATE()
          WHERE IncidentID = @incidentID
        `);

      // Record approval
      await pool.request()
        .input('incidentID', sql.Int, incidentId)
        .input('approverStaffKey', sql.Int, approverStaffKey)
        .input('approvalStatus', sql.VarChar(50), 'APPROVED')
        .input('notes', sql.VarChar(sql.MAX), notes)
        .query(`
          INSERT INTO wellbeing.factApprovalHistory
          (IncidentID, ApproverStaffKey, ApprovalStatus, Notes, ApprovalDateTime, CreatedDate)
          VALUES
          (@incidentID, @approverStaffKey, @approvalStatus, @notes, GETDATE(), GETDATE())
        `);

      return {
        success: true,
        message: 'Incident approved successfully'
      };
    } catch (error) {
      console.error('Error approving incident:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }

  async rejectIncident(incidentId, rejectorStaffKey, notes) {
    try {
      const pool = getPool();
      
      // Update incident status
      await pool.request()
        .input('incidentID', sql.Int, incidentId)
        .input('status', sql.VarChar(50), 'REJECTED')
        .query(`
          UPDATE wellbeing.factBehaviourIncident
          SET Status = @status, LastModifiedDate = GETDATE()
          WHERE IncidentID = @incidentID
        `);

      // Record rejection
      await pool.request()
        .input('incidentID', sql.Int, incidentId)
        .input('rejectorStaffKey', sql.Int, rejectorStaffKey)
        .input('rejectionStatus', sql.VarChar(50), 'REJECTED')
        .input('notes', sql.VarChar(sql.MAX), notes)
        .query(`
          INSERT INTO wellbeing.factApprovalHistory
          (IncidentID, ApproverStaffKey, ApprovalStatus, Notes, ApprovalDateTime, CreatedDate)
          VALUES
          (@incidentID, @rejectorStaffKey, @rejectionStatus, @notes, GETDATE(), GETDATE())
        `);

      return {
        success: true,
        message: 'Incident rejected successfully'
      };
    } catch (error) {
      console.error('Error rejecting incident:', error);
      return {
        success: false,
        error: error.message
      };
    }
  }
}

module.exports = new IncidentService();
