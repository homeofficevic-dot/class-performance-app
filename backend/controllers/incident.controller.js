const incidentService = require('../services/incident.service');

class IncidentController {
  async getAll(req, res) {
    try {
      const page = parseInt(req.query.page) || 1;
      const limit = parseInt(req.query.limit) || 10;
      const filters = {
        studentKey: req.query.studentKey ? parseInt(req.query.studentKey) : null,
        status: req.query.status,
        incidentType: req.query.incidentType,
        startDate: req.query.startDate,
        endDate: req.query.endDate
      };

      const result = await incidentService.getAllIncidents(page, limit, filters);
      
      if (!result.success) {
        return res.status(500).json(result);
      }

      res.json(result);
    } catch (error) {
      console.error('Error in getAll:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }

  async getById(req, res) {
    try {
      const incidentId = parseInt(req.params.id);
      const result = await incidentService.getIncidentById(incidentId);
      
      if (!result.success) {
        return res.status(404).json(result);
      }

      res.json(result);
    } catch (error) {
      console.error('Error in getById:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }

  async create(req, res) {
    try {
      const {
        studentKey,
        incidentDateTime,
        incidentTypeCode,
        severity,
        description,
        locationCode,
        reportedByStaffKey
      } = req.body;

      // Validation
      if (!studentKey || !incidentDateTime || !incidentTypeCode || !severity || !reportedByStaffKey) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: studentKey, incidentDateTime, incidentTypeCode, severity, reportedByStaffKey'
        });
      }

      const result = await incidentService.createIncident({
        studentKey,
        incidentDateTime,
        incidentTypeCode,
        severity,
        description,
        locationCode,
        reportedByStaffKey
      });

      if (!result.success) {
        return res.status(500).json(result);
      }

      res.status(201).json(result);
    } catch (error) {
      console.error('Error in create:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }

  async update(req, res) {
    try {
      const incidentId = parseInt(req.params.id);
      const updates = req.body;

      const result = await incidentService.updateIncident(incidentId, updates);
      
      if (!result.success) {
        return res.status(500).json(result);
      }

      res.json(result);
    } catch (error) {
      console.error('Error in update:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }

  async delete(req, res) {
    try {
      const incidentId = parseInt(req.params.id);
      const result = await incidentService.deleteIncident(incidentId);
      
      if (!result.success) {
        return res.status(500).json(result);
      }

      res.json(result);
    } catch (error) {
      console.error('Error in delete:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }

  async approve(req, res) {
    try {
      const incidentId = parseInt(req.params.id);
      const { approverStaffKey, notes } = req.body;

      if (!approverStaffKey) {
        return res.status(400).json({
          success: false,
          error: 'approverStaffKey is required'
        });
      }

      const result = await incidentService.approveIncident(incidentId, approverStaffKey, notes || '');
      
      if (!result.success) {
        return res.status(500).json(result);
      }

      res.json(result);
    } catch (error) {
      console.error('Error in approve:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }

  async reject(req, res) {
    try {
      const incidentId = parseInt(req.params.id);
      const { rejectorStaffKey, notes } = req.body;

      if (!rejectorStaffKey) {
        return res.status(400).json({
          success: false,
          error: 'rejectorStaffKey is required'
        });
      }

      const result = await incidentService.rejectIncident(incidentId, rejectorStaffKey, notes || '');
      
      if (!result.success) {
        return res.status(500).json(result);
      }

      res.json(result);
    } catch (error) {
      console.error('Error in reject:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
}

module.exports = new IncidentController();
