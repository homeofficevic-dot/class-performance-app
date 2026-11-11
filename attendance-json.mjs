const SQL_JSON_COLUMN = 'JSON_F52E2B61-18A1-11d1-B105-00805F49916B';
const DATE_COLUMNS = ['AttendanceDate', 'PeriodStart', 'PeriodFinish', 'SourceUpdatedTimestamp'];

export function decodeAttendanceJson(recordset) {
  if (!recordset.length) return [];
  if (recordset.some(row => typeof row[SQL_JSON_COLUMN] !== 'string')) {
    throw new Error('SQL Server returned an invalid attendance JSON result.');
  }

  const rows = JSON.parse(recordset.map(row => row[SQL_JSON_COLUMN]).join(''));
  if (!Array.isArray(rows)) {
    throw new Error('SQL Server returned invalid attendance JSON rows.');
  }

  for (const row of rows) {
    for (const column of DATE_COLUMNS) {
      const value = row[column];
      if (typeof value === 'string' && value.includes('T') && !/(?:Z|[+-]\d\d:\d\d)$/i.test(value)) {
        row[column] = `${value}Z`;
      }
    }
  }
  return rows;
}
