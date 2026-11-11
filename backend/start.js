#!/usr/bin/env node

/**
 * Student Wellbeing System - Startup Script
 * Starts backend API and runs system tests
 */

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

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

async function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
    log('\n', 'cyan');
    log('════════════════════════════════════════════════════════════════════════', 'cyan');
    log('🚀 STUDENT WELLBEING SYSTEM - STARTUP', 'cyan');
    log('════════════════════════════════════════════════════════════════════════', 'cyan');
    log('', 'reset');

    // Check if backend directory exists
    const backendDir = process.cwd();
    if (!fs.existsSync(path.join(backendDir, 'server.js'))) {
        log('❌ Error: server.js not found in current directory', 'red');
        process.exit(1);
    }

    log('📂 Backend Directory: ' + backendDir, 'gray');
    log('', 'reset');

    // Check .env file
    const envPath = path.join(backendDir, '.env');
    if (fs.existsSync(envPath)) {
        log('✅ .env file found', 'green');
        
        // Read and display config
        const envContent = fs.readFileSync(envPath, 'utf8');
        const sqlServer = envContent.match(/SQL_SERVER=(.+)/)?.[1] || 'localhost';
        const sqlDatabase = envContent.match(/SQL_DATABASE=(.+)/)?.[1] || 'SchoolDW';
        const sqlAuth = envContent.match(/SQL_AUTH=(.+)/)?.[1] || 'windows';
        
        log(`   Server: ${sqlServer}`, 'gray');
        log(`   Database: ${sqlDatabase}`, 'gray');
        log(`   Auth: ${sqlAuth}`, 'gray');
    } else {
        log('⚠️  .env file not found - using defaults', 'yellow');
    }
    log('', 'reset');

    // Check node_modules
    if (!fs.existsSync(path.join(backendDir, 'node_modules'))) {
        log('📦 Installing dependencies...', 'yellow');
        await new Promise((resolve, reject) => {
            const npm = spawn('npm', ['install'], { cwd: backendDir, stdio: 'inherit' });
            npm.on('close', code => {
                if (code === 0) resolve();
                else reject(new Error(`npm install failed with code ${code}`));
            });
        });
        log('✅ Dependencies installed', 'green');
        log('', 'reset');
    }

    // Start server
    log('🔧 Starting Backend API...', 'cyan');
    log('', 'reset');

    const server = spawn('node', ['server.js'], { 
        cwd: backendDir,
        stdio: 'inherit'
    });

    let startupComplete = false;

    server.on('close', (code) => {
        if (!startupComplete) {
            log(`\n❌ Server exited with code ${code}`, 'red');
            process.exit(code);
        }
    });

    // Wait for server to start, then run tests
    await sleep(5000);

    log('\n', 'cyan');
    log('════════════════════════════════════════════════════════════════════════', 'cyan');
    log('🧪 RUNNING SYSTEM TESTS', 'cyan');
    log('════════════════════════════════════════════════════════════════════════', 'cyan');
    log('', 'reset');

    // Run test suite
    await new Promise((resolve) => {
        const tests = spawn('node', ['test-system.js'], { 
            cwd: backendDir,
            stdio: 'inherit'
        });

        tests.on('close', () => {
            startupComplete = true;
            resolve();
        });
    });

    log('\n', 'cyan');
    log('════════════════════════════════════════════════════════════════════════', 'cyan');
    log('✅ SYSTEM READY', 'cyan');
    log('════════════════════════════════════════════════════════════════════════', 'cyan');
    log('', 'reset');

    log('🌐 Access the system:', 'cyan');
    log('   Frontend: http://localhost:4200', 'yellow');
    log('   Backend:  http://localhost:4201/api/health', 'yellow');
    log('', 'reset');

    log('📚 Documentation:', 'cyan');
    log('   START: GET_STARTED.md', 'gray');
    log('   API: BACKEND_API_SETUP.md', 'gray');
    log('   FRONTEND: ANGULAR_FRONTEND_IMPLEMENTATION.md', 'gray');
    log('', 'reset');

    // Keep server running
    log('Server is running. Press Ctrl+C to stop.', 'gray');
    log('', 'reset');
}

main().catch(error => {
    log(`\n❌ Error: ${error.message}`, 'red');
    process.exit(1);
});
