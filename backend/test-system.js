#!/usr/bin/env node

/**
 * Complete System Test Script
 * Tests all backend API endpoints and frontend connectivity
 */

const http = require('http');

const BASE_URL = 'http://localhost:4201';
const FRONTEND_URL = 'http://localhost:4200';

// Color codes for console output
const colors = {
    reset: '\x1b[0m',
    green: '\x1b[32m',
    red: '\x1b[31m',
    yellow: '\x1b[33m',
    cyan: '\x1b[36m',
    gray: '\x1b[90m'
};

function log(message, color = 'reset') {
    console.log(`${colors[color]}${message}${colors.reset}`);
}

function makeRequest(url, options = {}) {
    return new Promise((resolve, reject) => {
        const req = http.get(url, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                resolve({
                    statusCode: res.statusCode,
                    data: data ? JSON.parse(data) : null,
                    headers: res.headers
                });
            });
        });

        req.on('error', reject);
        req.setTimeout(5000, () => {
            req.destroy();
            reject(new Error('Request timeout'));
        });
    });
}

async function runTests() {
    log('\n', 'cyan');
    log('════════════════════════════════════════════════════════════════════════', 'cyan');
    log('🧪 STUDENT WELLBEING SYSTEM - COMPREHENSIVE TEST SUITE', 'cyan');
    log('════════════════════════════════════════════════════════════════════════', 'cyan');
    log('', 'cyan');

    let passedTests = 0;
    let failedTests = 0;

    // Test 1: Health Check
    log('TEST 1: Backend Health Check', 'yellow');
    log('─────────────────────────────', 'gray');
    try {
        const response = await makeRequest(`${BASE_URL}/api/health`);
        if (response.statusCode === 200 && response.data.status === 'OK') {
            log('✅ PASS - Backend is responding', 'green');
            log(`   Endpoint: GET /api/health`, 'gray');
            log(`   Status: ${response.data.status}`, 'gray');
            log(`   Message: ${response.data.message}`, 'gray');
            passedTests++;
        } else {
            log(`❌ FAIL - Unexpected status: ${response.statusCode}`, 'red');
            failedTests++;
        }
    } catch (error) {
        log(`❌ FAIL - ${error.message}`, 'red');
        log(`   Backend may not be running on port 3000`, 'gray');
        failedTests++;
    }
    log('', 'reset');

    // Test 2: Get Incidents
    log('TEST 2: GET /api/incidents Endpoint', 'yellow');
    log('───────────────────────────────────', 'gray');
    try {
        const response = await makeRequest(`${BASE_URL}/api/incidents?page=1&limit=5`);
        if (response.statusCode === 200 && response.data.success) {
            log('✅ PASS - Incidents endpoint working', 'green');
            log(`   Records returned: ${response.data.data.length}`, 'gray');
            log(`   Total available: ${response.data.pagination.total}`, 'gray');
            log(`   Pages: ${response.data.pagination.pages}`, 'gray');
            passedTests++;
        } else {
            log(`❌ FAIL - Response: ${response.statusCode}`, 'red');
            failedTests++;
        }
    } catch (error) {
        log(`⚠️  WARN - ${error.message}`, 'yellow');
        log(`   Database may not have data or is still connecting`, 'gray');
        failedTests++;
    }
    log('', 'reset');

    // Test 3: Get Students
    log('TEST 3: GET /api/students Endpoint', 'yellow');
    log('──────────────────────────────────', 'gray');
    try {
        const response = await makeRequest(`${BASE_URL}/api/students?page=1&limit=5`);
        if (response.statusCode === 200 && response.data.success) {
            log('✅ PASS - Students endpoint working', 'green');
            log(`   Records returned: ${response.data.data.length}`, 'gray');
            log(`   Total available: ${response.data.pagination.total}`, 'gray');
            passedTests++;
        } else {
            log(`❌ FAIL - Response: ${response.statusCode}`, 'red');
            failedTests++;
        }
    } catch (error) {
        log(`⚠️  WARN - ${error.message}`, 'yellow');
        failedTests++;
    }
    log('', 'reset');

    // Test 4: Filtered Query
    log('TEST 4: API with Query Filters', 'yellow');
    log('──────────────────────────────', 'gray');
    try {
        const response = await makeRequest(`${BASE_URL}/api/incidents?page=1&limit=3&status=OPEN`);
        if (response.statusCode === 200) {
            log('✅ PASS - Filtering works', 'green');
            log(`   Query: ?page=1&limit=3&status=OPEN`, 'gray');
            log(`   Records returned: ${response.data.data.length}`, 'gray');
            passedTests++;
        }
    } catch (error) {
        log(`⚠️  WARN - ${error.message}`, 'yellow');
        failedTests++;
    }
    log('', 'reset');

    // Test 5: Frontend
    log('TEST 5: Frontend Angular Application', 'yellow');
    log('────────────────────────────────────', 'gray');
    try {
        const response = await makeRequest(FRONTEND_URL);
        if (response.statusCode === 200) {
            log('✅ PASS - Frontend is running', 'green');
            log(`   URL: http://localhost:4200`, 'gray');
            log(`   Status: ${response.statusCode}`, 'gray');
            passedTests++;
        }
    } catch (error) {
        log(`⚠️  WARN - ${error.message}`, 'yellow');
        log(`   Frontend may still be building`, 'gray');
        failedTests++;
    }
    log('', 'reset');

    // Test 6: Error Handling
    log('TEST 6: API Error Handling', 'yellow');
    log('─────────────────────────', 'gray');
    try {
        const response = await makeRequest(`${BASE_URL}/api/nonexistent`);
        if (response.statusCode === 404) {
            log('✅ PASS - Error handling working', 'green');
            log(`   404 returned for non-existent endpoint`, 'gray');
            passedTests++;
        }
    } catch (error) {
        log(`⚠️  WARN - ${error.message}`, 'yellow');
        failedTests++;
    }
    log('', 'reset');

    // Summary
    log('════════════════════════════════════════════════════════════════════════', 'cyan');
    log('📊 TEST SUMMARY', 'cyan');
    log('════════════════════════════════════════════════════════════════════════', 'cyan');
    log('', 'reset');

    log(`Passed: ${passedTests}`, 'green');
    log(`Failed: ${failedTests}`, failedTests > 0 ? 'red' : 'green');
    log(`Total:  ${passedTests + failedTests}`, 'cyan');
    log('', 'reset');

    // Status
    if (failedTests === 0) {
        log('✅ ALL TESTS PASSED - SYSTEM READY!', 'green');
    } else if (failedTests < 3) {
        log('⚠️  SOME TESTS FAILED - CHECK CONFIGURATION', 'yellow');
    } else {
        log('❌ MAJOR ISSUES - REVIEW CONFIGURATION', 'red');
    }

    log('', 'reset');
    log('════════════════════════════════════════════════════════════════════════', 'cyan');
    log('', 'cyan');

    // Recommendations
    log('📋 NEXT STEPS:', 'cyan');
    log('', 'reset');
    if (passedTests >= 4) {
        log('1. ✅ Backend API is working correctly', 'green');
        log('2. Open http://localhost:4200 to view the frontend', 'gray');
        log('3. Start building your components!', 'gray');
    } else {
        log('1. Check backend console for database connection errors', 'yellow');
        log('2. Verify SQL Server is running', 'yellow');
        log('3. Check .env configuration', 'yellow');
        log('4. Run this test again after fixing issues', 'yellow');
    }
    log('', 'reset');
}

// Run tests
runTests().catch(error => {
    log(`\n❌ Test suite error: ${error.message}`, 'red');
    process.exit(1);
});
