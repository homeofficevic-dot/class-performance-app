const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const { connect, disconnect } = require('./config/database');

// Import routes
const incidentRoutes = require('./routes/incidents.routes');
const studentRoutes = require('./routes/students.routes');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Logging middleware
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);
  next();
});

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({
    status: 'OK',
    timestamp: new Date(),
    message: 'Student Wellbeing API is running'
  });
});

// API Routes
app.use('/api/incidents', incidentRoutes);
app.use('/api/students', studentRoutes);

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(err.status || 500).json({
    success: false,
    error: err.message || 'Internal Server Error'
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    error: 'Route not found'
  });
});

// Start server
const startServer = async () => {
  try {
    console.log('🚀 Starting Student Wellbeing API...');
    
    // Connect to database
    await connect();
    
    app.listen(PORT, () => {
      console.log(`✅ API Server running on http://localhost:${PORT}`);
      console.log(`📚 API Documentation:`);
      console.log(`   - GET  /api/health`);
      console.log(`   - GET  /api/incidents?page=1&limit=10`);
      console.log(`   - GET  /api/incidents/:id`);
      console.log(`   - POST /api/incidents`);
      console.log(`   - PUT  /api/incidents/:id`);
      console.log(`   - DELETE /api/incidents/:id`);
      console.log(`   - POST /api/incidents/:id/approve`);
      console.log(`   - POST /api/incidents/:id/reject`);
      console.log(`   - GET  /api/students?page=1&limit=10`);
      console.log(`   - GET  /api/students/:id`);
      console.log(`   - GET  /api/students/:id/incidents`);
      console.log(`   - GET  /api/students/:id/support-plan`);
      console.log(`   - GET  /api/students/:id/wellbeing-notes`);
      console.log(`   - POST /api/students/:id/wellbeing-notes`);
      console.log(`   - GET  /api/students/:id/risk-assessment`);
    });
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
};

// Handle graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n🛑 Shutting down...');
  await disconnect();
  process.exit(0);
});

startServer();

module.exports = app;
