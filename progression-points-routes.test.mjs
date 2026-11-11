import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import express from 'express';

import progressionPointsRouter from './progression-points-routes.mjs';

const assignedCampusId = '11111111-1111-1111-1111-111111111111';
const otherCampusId = '22222222-2222-2222-2222-222222222222';
const app = express();
let server;
let baseUrl;
let lastQuery = '';

app.use((request, response, next) => {
  request.campusAccess = { campusId: assignedCampusId, allCampusAccess: false };
  next();
});
app.locals.getDatabasePool = async () => ({
  request: () => ({
    input() {
      return this;
    },
    async query(query) {
      lastQuery = query;
      return { recordset: [], recordsets: [[], [], [], []] };
    }
  })
});
app.use('/', progressionPointsRouter);

before(async () => {
  server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  if (!server) return;
  await new Promise((resolve, reject) => {
    server.close(error => error ? reject(error) : resolve());
  });
});

test('rejects a non-numeric student identifier before querying SQL', async () => {
  const response = await fetch(`${baseUrl}/domains/not-a-student`);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), {
    error: 'studentId must be a positive StudentKey.'
  });
});

test('rejects invalid progression filters before querying SQL', async () => {
  const response = await fetch(`${baseUrl}/history/123?academicYearId=2024.5`);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), {
    error: 'academicYearId must be a positive integer.'
  });
});

test('rejects exponential integer notation', async () => {
  const response = await fetch(`${baseUrl}/history/123?limit=1e2`);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), {
    error: 'limit must be an integer between 1 and 5000.'
  });
});

test('rejects a malformed campus identifier', async () => {
  const response = await fetch(`${baseUrl}/dimensions/123?campusId=not-a-guid`);
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), {
    error: 'campusId must be a valid GUID.'
  });
});

test('blocks a request to another campus before querying SQL', async () => {
  const response = await fetch(`${baseUrl}/domains/123?campusId=${otherCampusId}`);
  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), {
    error: 'You can only access data for your assigned campus.'
  });

  test('queries only real observations for a valid student', async () => {
    lastQuery = '';
    const response = await fetch(`${baseUrl}/domains/123?academicYearId=2026&subjectId=1`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { data: [] });
    assert.match(lastQuery, /result\.IsSynthetic = 0/);
    assert.match(lastQuery, /result\.ResultLevel = @resultLevel/);
    assert.match(lastQuery, /authorizedStudent\.HomeCampus = @staffCampusId/);
  });
});
