import assert from 'node:assert/strict';

const baseUrl = process.env.API_BASE_URL || 'http://127.0.0.1:4201/api';
const headers = process.env.API_AUTH_REQUIRED === 'true'
    ? { Authorization: 'Bearer integration-test', 'x-user-roles': 'read-only-authorised-staff' }
    : {};

async function get(path) {
    const response = await fetch(`${baseUrl}${path}`, { headers });
    const body = await response.json();
    return { response, body };
}

async function request(method, path, payload) {
    const response = await fetch(`${baseUrl}${path}`, {
        method,
        headers: { ...headers, 'content-type': 'application/json' },
        body: payload === undefined ? undefined : JSON.stringify(payload)
    });
    const body = await response.json();
    return { response, body };
}

const lookup = await get('/wellbeing/students/3/pastoral-assignment');
assert.equal(lookup.response.status, 200);
assert.equal(lookup.body.success, true);

const history = await get('/wellbeing/students/3/pastoral-history');
assert.equal(history.response.status, 200);
assert.ok(Array.isArray(history.body.data));

const houses = await get('/org/houses');
assert.equal(houses.response.status, 200);
assert.ok(houses.body.data.length > 0);

const groups = await get('/org/pastoral-groups');
assert.equal(groups.response.status, 200);
assert.ok(groups.body.data.length > 0);

const staff = await get('/org/staff?limit=1');
assert.equal(staff.response.status, 200);
assert.equal(staff.body.success, true);
assert.equal(staff.body.data.items.length, 1);

const testSuffix = Date.now().toString();
const houseCreated = await request('POST', '/org/houses', {
    houseCode: `TEST_HOUSE_${testSuffix}`,
    houseName: 'Organisation API Test House'
});
assert.equal(houseCreated.response.status, 201);
const testHouseId = houseCreated.body.data.houseId;
const houseUpdated = await request('PUT', `/org/houses/${testHouseId}`, {
    houseName: 'Organisation API Updated House',
    isActive: true
});
assert.equal(houseUpdated.response.status, 200);
const houseRead = await get(`/org/houses/${testHouseId}`);
assert.equal(houseRead.response.status, 200);
assert.equal(houseRead.body.data.houseName, 'Organisation API Updated House');
await request('DELETE', `/org/houses/${testHouseId}`);

const groupCreated = await request('POST', '/org/pastoral-groups', {
    pastoralGroupCode: `TEST_GROUP_${testSuffix}`,
    pastoralGroupName: 'Organisation API Test Group'
});
assert.equal(groupCreated.response.status, 201);
const testGroupId = groupCreated.body.data.pastoralGroupId;
const groupUpdated = await request('PUT', `/org/pastoral-groups/${testGroupId}`, {
    pastoralGroupName: 'Organisation API Updated Group',
    isActive: true
});
assert.equal(groupUpdated.response.status, 200);
const groupRead = await get(`/org/pastoral-groups/${testGroupId}`);
assert.equal(groupRead.response.status, 200);
assert.equal(groupRead.body.data.pastoralGroupName, 'Organisation API Updated Group');
await request('DELETE', `/org/pastoral-groups/${testGroupId}`);

const invalidDate = await get('/wellbeing/students/3/pastoral-assignment?asAtDate=invalid');
assert.equal(invalidDate.response.status, 400);

const consequences = await get('/wellbeing/consequences?active=true');
assert.equal(consequences.response.status, 200);
assert.ok(consequences.body.data.length > 0);
const policyLevels = await get('/wellbeing/policyLevels?active=true');
assert.equal(policyLevels.response.status, 200);
assert.ok(policyLevels.body.data.length > 0);
const ruleCreated = await request('POST', '/wellbeing/consequencePolicyRules', {
    ConsequenceId: consequences.body.data[0].ConsequenceId,
    PolicyLevelId: policyLevels.body.data[0].PolicyLevelId,
    IsEligible: true,
    RequiresApproval: false,
    EffectiveStartDate: '2026-01-01'
});
assert.equal(ruleCreated.response.status, 201);
const ruleId = ruleCreated.body.data.ConsequencePolicyRuleId;
const ruleUpdated = await request('PUT', `/wellbeing/consequencePolicyRules/${ruleId}`, {
    RequiresApproval: true
});
assert.equal(ruleUpdated.response.status, 200);
assert.equal(ruleUpdated.body.data.RequiresApproval, true);
const ruleDeleted = await request('DELETE', `/wellbeing/consequencePolicyRules/${ruleId}`);
assert.equal(ruleDeleted.response.status, 200);
assert.equal(ruleDeleted.body.rowsAffected, 1);

console.log('Organisation API integration tests passed.');
