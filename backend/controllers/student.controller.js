const studentService = require('../services/student.service');

class StudentController {
  async getAll(req, res) {
    try {
      const page = parseInt(req.query.page) || 1;
      const limit = parseInt(req.query.limit) || 10;
      const filters = {
        name: req.query.name,
        classId: req.query.classId ? parseInt(req.query.classId) : null,
        yearLevel: req.query.yearLevel
      };

      const result = await studentService.getAllStudents(page, limit, filters);
      
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
      const studentKey = parseInt(req.params.id);
      const result = await studentService.getStudentById(studentKey);
      
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

  async getIncidents(req, res) {
    try {
      const studentKey = parseInt(req.params.id);
      const result = await studentService.getStudentIncidents(studentKey);
      
      if (!result.success) {
        return res.status(500).json(result);
      }

      res.json(result);
    } catch (error) {
      console.error('Error in getIncidents:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }

  async getSupportPlan(req, res) {
    try {
      const studentKey = parseInt(req.params.id);
      const result = await studentService.getStudentSupportPlan(studentKey);
      
      if (!result.success) {
        return res.status(500).json(result);
      }

      res.json(result);
    } catch (error) {
      console.error('Error in getSupportPlan:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }

  async getWellbeingNotes(req, res) {
    try {
      const studentKey = parseInt(req.params.id);
      const limit = parseInt(req.query.limit) || 20;
      const result = await studentService.getStudentWellbeingNotes(studentKey, limit);
      
      if (!result.success) {
        return res.status(500).json(result);
      }

      res.json(result);
    } catch (error) {
      console.error('Error in getWellbeingNotes:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }

  async addWellbeingNote(req, res) {
    try {
      const studentKey = parseInt(req.params.id);
      const { noteContent, noteType, staffKey } = req.body;

      if (!noteContent || !noteType || !staffKey) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: noteContent, noteType, staffKey'
        });
      }

      const result = await studentService.addWellbeingNote(studentKey, noteContent, noteType, staffKey);
      
      if (!result.success) {
        return res.status(500).json(result);
      }

      res.status(201).json(result);
    } catch (error) {
      console.error('Error in addWellbeingNote:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }

  async getRiskAssessment(req, res) {
    try {
      const studentKey = parseInt(req.params.id);
      const result = await studentService.getRiskAssessment(studentKey);
      
      if (!result.success) {
        return res.status(500).json(result);
      }

      res.json(result);
    } catch (error) {
      console.error('Error in getRiskAssessment:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  }
}

module.exports = new StudentController();
