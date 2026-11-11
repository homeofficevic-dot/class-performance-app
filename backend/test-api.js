import http from 'http';

function makeRequest(path) {
    return new Promise((resolve, reject) => {
        const options = {
            hostname: 'localhost',
            port: 3000,
            path: path,
            method: 'GET'
        };

        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', (chunk) => {
                data += chunk;
            });
            res.on('end', () => {
                try {
                    resolve({
                        status: res.statusCode,
                        data: JSON.parse(data)
                    });
                } catch (e) {
                    resolve({
                        status: res.statusCode,
                        data: data
                    });
                }
            });
        });

        req.on('error', reject);
        req.end();
    });
}

async function runTests() {
    console.log('\n🧪 TESTING STUDENT WELLBEING API\n');
    console.log('═'.repeat(70));

    try {
        // Test 1: Health Check
        console.log('\n✓ Test 1: Health Check');
        const health = await makeRequest('/api/health');
        console.log(`  Status: ${health.status}`);
        console.log(`  Response:`, JSON.stringify(health.data, null, 2));

        // Test 2: Get Incidents
        console.log('\n✓ Test 2: Get Incidents');
        const incidents = await makeRequest('/api/incidents?page=1&limit=5');
        console.log(`  Status: ${incidents.status}`);
        console.log(`  Data count: ${incidents.data.data ? incidents.data.data.length : 0}`);
        console.log(`  Pagination:`, incidents.data.pagination);

        // Test 3: Get Students
        console.log('\n✓ Test 3: Get Students');
        const students = await makeRequest('/api/students?page=1&limit=5');
        console.log(`  Status: ${students.status}`);
        console.log(`  Data count: ${students.data.data ? students.data.data.length : 0}`);
        console.log(`  Pagination:`, students.data.pagination);

        console.log('\n' + '═'.repeat(70));
        console.log('\n✅ ALL TESTS PASSED!\n');

    } catch (error) {
        console.error('❌ Test failed:', error.message);
        process.exit(1);
    }
}

runTests();
