const NOT_MARKED_STATUS_ID = '21625425-4deb-4957-81be-897914dcff18';
const PRESENT_STATUS_ID = 'fdec4cbf-dce9-4421-90de-29a0f4891461';

function emptyAnalytics() {
  return {
    summary: {
      totalPeriods: 0,
      markedPeriods: 0,
      presentCount: 0,
      absentCount: 0,
      notMarkedCount: 0,
      overallAttendanceRate: 0,
      studentsCount: 0,
      atRiskCount: 0,
      monitorCount: 0,
      goodCount: 0
    },
    statusBreakdown: [],
    monthlyTrend: [],
    studentStats: {},
    recentNotes: []
  };
}

export function buildAttendanceAnalytics(students, attendanceRecords) {
  if (!students.length) return emptyAnalytics();

  const studentMap = new Map();
  for (const student of students) {
    const compassPersonId = String(student.CompassPersonId ?? '');
    if (!compassPersonId) continue;
    studentMap.set(compassPersonId, {
      compassPersonId,
      studentCode: student.StudentCode || '',
      name: [student.GivenName, student.FamilyName].filter(Boolean).join(' '),
      totalPeriods: 0,
      notMarked: 0,
      present: 0,
      absent: 0,
      schoolRefusal: 0,
      rate: 0,
      latestNote: '',
      latestNoteDate: ''
    });
  }

  const categoryMap = new Map();
  const monthlyMap = new Map();
  const recentNotes = [];
  let totalPresent = 0;
  let totalAbsent = 0;
  let totalNotMarked = 0;

  for (const row of attendanceRecords) {
    let payload;
    try {
      payload = JSON.parse(row.PayloadJson);
    } catch {
      continue;
    }

    const personId = String(row.CompassPersonId || payload.compassPersonId || '');
    const studentStats = studentMap.get(personId);
    if (studentStats) studentStats.totalPeriods++;

    const description = String(payload.description || '').trim();
    const firstLine = description.split(/\r?\n/, 1)[0].trim();
    const normalizedDescription = firstLine.toLowerCase();
    const statusId = String(payload.prevalentOverallStatusId || '').toLowerCase();
    const isNotMarked = statusId === NOT_MARKED_STATUS_ID || normalizedDescription === 'not marked';
    const isPresent = !isNotMarked
      && (statusId === PRESENT_STATUS_ID || normalizedDescription.includes('present'));

    let category = 'Present';
    if (isNotMarked) {
      category = 'Not Marked';
      totalNotMarked++;
      if (studentStats) studentStats.notMarked++;
    } else if (isPresent) {
      totalPresent++;
      if (studentStats) studentStats.present++;
    } else {
      totalAbsent++;
      if (studentStats) studentStats.absent++;
      if (normalizedDescription.includes('refusal') || normalizedDescription.includes("can't")) {
        category = "School Refusal / Can't";
        if (studentStats) studentStats.schoolRefusal++;
      } else if (
        normalizedDescription.includes('medical')
        || normalizedDescription.includes('illness')
        || normalizedDescription.includes('sick')
      ) {
        category = 'Medical / Illness';
      } else if (normalizedDescription.includes('healthcare')) {
        category = 'Healthcare Off-site';
      } else if (normalizedDescription.includes('unapproved')) {
        category = 'Parent Choice (Unapproved)';
      } else if (normalizedDescription.includes('approved')) {
        category = 'Parent Choice (Approved)';
      } else if (normalizedDescription.includes('wellbeing') || normalizedDescription.includes('outreach')) {
        category = 'Wellbeing Outreach';
      } else if (normalizedDescription.includes('educational') || normalizedDescription.includes('gathering')) {
        category = 'Educational Activity';
      } else {
        category = firstLine || 'Other Absence';
      }
    }

    if (description && description !== 'Not Marked' && description.length > 15) {
      const noteDate = payload.start || payload.finish || payload.updatedTimestamp || '';
      if (studentStats && (!studentStats.latestNoteDate || noteDate > studentStats.latestNoteDate)) {
        studentStats.latestNote = description;
        studentStats.latestNoteDate = noteDate;
      }
      recentNotes.push({
        studentId: personId,
        studentName: studentStats?.name || personId,
        date: noteDate,
        category,
        note: description
      });
      if (recentNotes.length > 50) {
        recentNotes.sort((first, second) => (second.date || '').localeCompare(first.date || ''));
        recentNotes.length = 50;
      }
    }

    categoryMap.set(category, (categoryMap.get(category) || 0) + 1);

    const dateValue = payload.start || payload.finish;
    if (dateValue) {
      const date = new Date(dateValue);
      if (!Number.isNaN(date.getTime())) {
        const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
        if (!monthlyMap.has(key)) {
          monthlyMap.set(key, {
            key,
            label: date.toLocaleString('en-US', { month: 'short' }),
            present: 0,
            absent: 0,
            notMarked: 0
          });
        }
        const month = monthlyMap.get(key);
        if (isPresent) month.present++;
        else if (isNotMarked) month.notMarked++;
        else month.absent++;
      }
    }
  }

  const studentStats = {};
  let atRiskCount = 0;
  let monitorCount = 0;
  let goodCount = 0;
  for (const [id, stats] of studentMap.entries()) {
    const marked = stats.present + stats.absent;
    stats.rate = marked ? Number(((stats.present / marked) * 100).toFixed(1)) : 0;
    if (stats.rate < 80) atRiskCount++;
    else if (stats.rate < 90) monitorCount++;
    else goodCount++;
    studentStats[id] = stats;
  }

  const totalMarked = totalPresent + totalAbsent;
  const totalPeriods = attendanceRecords.length;
  const statusBreakdown = Array.from(categoryMap.entries())
    .map(([label, count]) => ({
      label,
      count,
      percentage: Number(((count / (totalPeriods || 1)) * 100).toFixed(1))
    }))
    .sort((first, second) => second.count - first.count);
  const monthlyTrend = Array.from(monthlyMap.values())
    .sort((first, second) => first.key.localeCompare(second.key))
    .map((month) => {
      const marked = month.present + month.absent;
      return {
        ...month,
        rate: marked ? Number(((month.present / marked) * 100).toFixed(1)) : 0
      };
    });
  recentNotes.sort((first, second) => (second.date || '').localeCompare(first.date || ''));

  return {
    summary: {
      totalPeriods,
      markedPeriods: totalMarked,
      presentCount: totalPresent,
      absentCount: totalAbsent,
      notMarkedCount: totalNotMarked,
      overallAttendanceRate: totalMarked
        ? Number(((totalPresent / totalMarked) * 100).toFixed(1))
        : 0,
      studentsCount: studentMap.size,
      atRiskCount,
      monitorCount,
      goodCount
    },
    statusBreakdown,
    monthlyTrend,
    studentStats,
    recentNotes: recentNotes.slice(0, 20)
  };
}

export function mergeAttendanceAnalytics(batches) {
  const combined = emptyAnalytics();
  const categoryCounts = new Map();
  const monthlyByKey = new Map();

  for (const batch of batches) {
    combined.summary.totalPeriods += batch.summary.totalPeriods;
    combined.summary.markedPeriods += batch.summary.markedPeriods;
    combined.summary.presentCount += batch.summary.presentCount;
    combined.summary.absentCount += batch.summary.absentCount;
    combined.summary.notMarkedCount += batch.summary.notMarkedCount;
    combined.summary.studentsCount += batch.summary.studentsCount;
    combined.summary.atRiskCount += batch.summary.atRiskCount;
    combined.summary.monitorCount += batch.summary.monitorCount;
    combined.summary.goodCount += batch.summary.goodCount;
    Object.assign(combined.studentStats, batch.studentStats);

    for (const category of batch.statusBreakdown) {
      categoryCounts.set(category.label, (categoryCounts.get(category.label) || 0) + category.count);
    }
    for (const month of batch.monthlyTrend) {
      const current = monthlyByKey.get(month.key) || {
        key: month.key,
        label: month.label,
        present: 0,
        absent: 0,
        notMarked: 0
      };
      current.present += month.present;
      current.absent += month.absent;
      current.notMarked += month.notMarked;
      monthlyByKey.set(month.key, current);
    }
    combined.recentNotes.push(...batch.recentNotes);
  }

  combined.summary.overallAttendanceRate = combined.summary.markedPeriods
    ? Number(((combined.summary.presentCount / combined.summary.markedPeriods) * 100).toFixed(1))
    : 0;
  combined.statusBreakdown = Array.from(categoryCounts.entries())
    .map(([label, count]) => ({
      label,
      count,
      percentage: Number(((count / (combined.summary.totalPeriods || 1)) * 100).toFixed(1))
    }))
    .sort((first, second) => second.count - first.count);
  combined.monthlyTrend = Array.from(monthlyByKey.values())
    .sort((first, second) => first.key.localeCompare(second.key))
    .map((month) => {
      const marked = month.present + month.absent;
      return {
        ...month,
        rate: marked ? Number(((month.present / marked) * 100).toFixed(1)) : 0
      };
    });
  combined.recentNotes.sort((first, second) => (second.date || '').localeCompare(first.date || ''));
  combined.recentNotes = combined.recentNotes.slice(0, 20);
  return combined;
}
