const express = require('express');
const router = express.Router();
const incidentController = require('../controllers/incident.controller');

// GET all incidents with pagination and filters
router.get('/', incidentController.getAll.bind(incidentController));

// GET incident by ID
router.get('/:id', incidentController.getById.bind(incidentController));

// POST create new incident
router.post('/', incidentController.create.bind(incidentController));

// PUT update incident
router.put('/:id', incidentController.update.bind(incidentController));

// DELETE incident
router.delete('/:id', incidentController.delete.bind(incidentController));

// POST approve incident
router.post('/:id/approve', incidentController.approve.bind(incidentController));

// POST reject incident
router.post('/:id/reject', incidentController.reject.bind(incidentController));

module.exports = router;
