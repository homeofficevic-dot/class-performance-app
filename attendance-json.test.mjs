import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeAttendanceJson } from './attendance-json.mjs';
import { buildAttendanceAnalytics } from './attendance-analytics.mjs';

const column = 'JSON_F52E2B61-18A1-11d1-B105-00805F49916B';

test('decodes SQL JSON chunks as UTC and preserves analytics', () => {
  const students = [{ CompassPersonId: 'student', GivenName: 'Alex' }];
  const raw = [{
    CompassPersonId: 'student',
    AttendanceDate: new Date('2026-03-01T00:00:00Z'),
    PeriodStart: new Date('2026-03-01T00:30:00Z'),
    Description: 'School refusal - discussion',
    PrevalentOverallStatusId: null
  }];
  const json = JSON.stringify([{
    CompassPersonId: 'student',
    AttendanceDate: '2026-03-01',
    PeriodStart: '2026-03-01T00:30:00',
    Description: 'School refusal - discussion'
  }]);
  const split = Math.floor(json.length / 2);
  const decoded = decodeAttendanceJson([{ [column]: json.slice(0, split) }, { [column]: json.slice(split) }]);
  assert.equal(decoded[0].PeriodStart, '2026-03-01T00:30:00Z');
  assert.deepEqual(buildAttendanceAnalytics(students, decoded), buildAttendanceAnalytics(students, raw));
});

test('does not silently accept malformed JSON results', () => {
  assert.deepEqual(decodeAttendanceJson([]), []);
  assert.throws(() => decodeAttendanceJson([{}]));
  assert.throws(() => decodeAttendanceJson([{ [column]: '{}' }]));
  assert.throws(() => decodeAttendanceJson([{ [column]: '{' }]));
  assert.deepEqual(decodeAttendanceJson([{ [column]: '[]' }]), []);
});
