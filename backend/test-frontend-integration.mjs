import { setTimeout } from 'timers/promises';

const API_BASE = 'http://localhost:4201/api';
const FRONTEND_BASE = 'http://localhost:4200';

async function runTests() {
  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('🧪 STUDENT WELLBEING SYSTEM - INTEGRATION TEST SUITE');
  console.log('═══════════════════════════════════════════════════════════════\n');

  let passed = 0;
  let failed = 0;

  // Test 1: Backend Health Check
  try {
    console.log('Test 1: Backend Health Check...');
    const response = await fetch(`${API_BASE}/health`);
    const data = await response.json();
    
    if (response.ok && data.status === 'healthy') {
      console.log('✅ PASS - Backend is healthy\n');
      passed++;
    } else {
      console.log('❌ FAIL - Backend returned unexpected response\n');
      failed++;
    }
  } catch (err) {
    console.log(`❌ FAIL - Backend error: ${err.message}\n`);
    failed++;
  }

  // Test 2: Get Students
  try {
    console.log('Test 2: Get Students (pagination)...');
    const response = await fetch(`${API_BASE}/students?skip=0&take=10`);
    const data = await response.json();
    
    if (response.ok && Array.isArray(data.data)) {
      console.log(`✅ PASS - Retrieved ${data.data.length} students\n`);
      passed++;
    } else {
      console.log('❌ FAIL - Students endpoint failed\n');
      failed++;
    }
  } catch (err) {
    console.log(`❌ FAIL - Students error: ${err.message}\n`);
    failed++;
  }

  // Test 3: Get Single Student
  try {
    console.log('Test 3: Get Single Student...');
    const response = await fetch(`${API_BASE}/students/1`);
    
    if (response.ok) {
      const data = await response.json();
      console.log(`✅ PASS - Student data retrieved\n`);
      passed++;
    } else {
      console.log('❌ FAIL - Single student endpoint failed\n');
      failed++;
    }
  } catch (err) {
    console.log(`❌ FAIL - Single student error: ${err.message}\n`);
    failed++;
  }

  // Test 4: Get Incidents
  try {
    console.log('Test 4: Get Incidents...');
    const response = await fetch(`${API_BASE}/incidents?skip=0&take=10`);
    const data = await response.json();
    
    if (response.ok && Array.isArray(data.data)) {
      console.log(`✅ PASS - Retrieved ${data.data.length} incidents\n`);
      passed++;
    } else {
      console.log('❌ FAIL - Incidents endpoint failed\n');
      failed++;
    }
  } catch (err) {
    console.log(`❌ FAIL - Incidents error: ${err.message}\n`);
    failed++;
  }

  // Test 5: Frontend Availability
  try {
    console.log('Test 5: Frontend Availability...');
    const response = await fetch(FRONTEND_BASE);
    
    if (response.ok || response.status === 200) {
      console.log('✅ PASS - Frontend is accessible on port 4200\n');
      passed++;
    } else {
      console.log(`❌ FAIL - Frontend returned status ${response.status}\n`);
      failed++;
    }
  } catch (err) {
    console.log(`❌ FAIL - Frontend error: ${err.message}\n`);
    failed++;
  }

  // Test 6: API Endpoints Available
  try {
    console.log('Test 6: API Endpoints Structure...');
    const healthResp = await fetch(`${API_BASE}/health`);
    const studentsResp = await fetch(`${API_BASE}/students?skip=0&take=1`);
    const incidentsResp = await fetch(`${API_BASE}/incidents?skip=0&take=1`);
    
    if (healthResp.ok && studentsResp.ok && incidentsResp.ok) {
      console.log('✅ PASS - All core API endpoints are working\n');
      passed++;
    } else {
      console.log('❌ FAIL - Some API endpoints are not responding\n');
      failed++;
    }
  } catch (err) {
    console.log(`❌ FAIL - API structure test error: ${err.message}\n`);
    failed++;
  }

  // Summary
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`📊 TEST SUMMARY: ${passed} passed, ${failed} failed`);
  console.log('═══════════════════════════════════════════════════════════════\n');

  if (failed === 0) {
    console.log('🎉 ALL TESTS PASSED! System is ready for use.');
    console.log('\nAccess the application:');
    console.log('  Frontend: http://localhost:4200');
    console.log('  Backend API: http://localhost:4201/api\n');
    process.exit(0);
  } else {
    console.log(`❌ ${failed} test(s) failed. Please check the errors above.\n`);
    process.exit(1);
  }
}

// Wait for services to stabilize then run tests
await setTimeout(3000);
runTests().catch(err => {
  console.error('Test suite error:', err);
  process.exit(1);
});
