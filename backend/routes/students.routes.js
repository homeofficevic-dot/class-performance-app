const express = require('express');
const router = express.Router();
const studentController = require('../controllers/student.controller');

// GET all students with pagination and filters
router.get('/', studentController.getAll.bind(studentController));

// GET student by ID
router.get('/:id', studentController.getById.bind(studentController));

// GET student's incidents
router.get('/:id/incidents', studentController.getIncidents.bind(studentController));

// GET student's support plan
router.get('/:id/support-plan', studentController.getSupportPlan.bind(studentController));

// GET student's wellbeing notes
router.get('/:id/wellbeing-notes', studentController.getWellbeingNotes.bind(studentController));

// POST add wellbeing note
router.post('/:id/wellbeing-notes', studentController.addWellbeingNote.bind(studentController));

// GET student's risk assessment
router.get('/:id/risk-assessment', studentController.getRiskAssessment.bind(studentController));

module.exports = router;
