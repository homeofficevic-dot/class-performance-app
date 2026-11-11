
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

function getStatus(row) {
  const description = String(row.Description ?? '').trim();
  const firstLine = description.split(/\r?\n/, 1)[0].trim();
  const normalized = firstLine.toLowerCase();
  const statusId = String(row.PrevalentOverallStatusId ?? '').toLowerCase();

  const isNotMarked =
    statusId === NOT_MARKED_STATUS_ID ||
    normalized === 'not marked';

  const isPresent = !isNotMarked && (
    statusId === PRESENT_STATUS_ID ||
    normalized.includes('present')
  );

  if (isNotMarked) {
    return {
      category: 'Not Marked',
      isNotMarked: true,
      isPresent: false
    };
  }

  if (isPresent) {
    return {
      category: 'Present',
      isNotMarked: false,
      isPresent: true
    };
  }

  let category = firstLine || 'Other Absence';

  if (normalized.includes('refusal') || normalized.includes("can't")) {
    category = "School Refusal / Can't";
  } else if (
    normalized.includes('medical') ||
    normalized.includes('illness') ||
    normalized.includes('sick')
  ) {
    category = 'Medical / Illness';
  } else if (normalized.includes('healthcare')) {
    category = 'Healthcare Off-site';
  } else if (normalized.includes('unapproved')) {
    category = 'Parent Choice (Unapproved)';
  } else if (normalized.includes('approved')) {
    category = 'Parent Choice (Approved)';
  } else if (
    normalized.includes('wellbeing') ||
    normalized.includes('outreach')
  ) {
    category = 'Wellbeing Outreach';
  } else if (
    normalized.includes('educational') ||
    normalized.includes('gathering')
  ) {
    category = 'Educational Activity';
  }

  return {
    category,
    isNotMarked: false,
    isPresent: false
  };
}

function toIsoDate(value) {
  if (!value) return '';

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '' : date.toISOString();
}

function getMonthKey(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';

  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}

export function buildAttendanceAnalytics(students, attendanceRecords) {
  if (!students.length) return emptyAnalytics();

  const studentMap = new Map();

  for (const student of students) {
    const id = String(student.CompassPersonId ?? '');
    if (!id) continue;

    studentMap.set(id, {
      compassPersonId: id,
      studentCode: student.StudentCode || '',
      name: [
        student.GivenName ?? student.FirstName,
        student.FamilyName ?? student.LastName
      ].filter(Boolean).join(' '),
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
    const personId = String(row.CompassPersonId ?? '');
    const stats = studentMap.get(personId);

    if (stats) stats.totalPeriods++;

    const description = String(row.Description ?? '').trim();
    const noteDate = toIsoDate(
      row.PeriodStart ??
      row.AttendanceDate ??
      row.PeriodFinish ??
      row.SourceUpdatedTimestamp
    );

    const { category, isNotMarked, isPresent } = getStatus(row);

    if (isNotMarked) {
      totalNotMarked++;
      if (stats) stats.notMarked++;
    } else if (isPresent) {
      totalPresent++;
      if (stats) stats.present++;
    } else {
      totalAbsent++;
      if (stats) {
        stats.absent++;
        if (category === "School Refusal / Can't") {
          stats.schoolRefusal++;
        }
      }
    }

    if (
      description.length > 15 &&
      description.toLowerCase() !== 'not marked'
    ) {
      if (stats && (!stats.latestNoteDate || noteDate > stats.latestNoteDate)) {
        stats.latestNote = description;
        stats.latestNoteDate = noteDate;
      }

      recentNotes.push({
        studentId: personId,
        studentName: stats?.name || personId,
        date: noteDate,
        category,
        note: description
      });
    }

    categoryMap.set(
      category,
      (categoryMap.get(category) || 0) + 1
    );

    if (noteDate) {
      const key = getMonthKey(noteDate);

      if (key) {
        if (!monthlyMap.has(key)) {
          const date = new Date(`${key}-01T00:00:00`);

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

    stats.rate = marked
      ? Number(((stats.present / marked) * 100).toFixed(1))
      : 0;

    if (stats.rate < 80) atRiskCount++;
    else if (stats.rate < 90) monitorCount++;
    else goodCount++;

    studentStats[id] = stats;
  }

  const totalPeriods = attendanceRecords.length;
  const totalMarked = totalPresent + totalAbsent;

  const statusBreakdown = Array.from(categoryMap.entries())
    .map(([label, count]) => ({
      label,
      count,
      percentage: Number(
        ((count / (totalPeriods || 1)) * 100).toFixed(1)
      )
    }))
    .sort((a, b) => b.count - a.count);

  const monthlyTrend = Array.from(monthlyMap.values())
    .sort((a, b) => a.key.localeCompare(b.key))
    .map(month => {
      const marked = month.present + month.absent;

      return {
        ...month,
        rate: marked
          ? Number(((month.present / marked) * 100).toFixed(1))
          : 0
      };
    });

  recentNotes.sort((a, b) =>
    (b.date || '').localeCompare(a.date || '')
  );

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
      categoryCounts.set(
        category.label,
        (categoryCounts.get(category.label) || 0) + category.count
      );
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

  combined.summary.overallAttendanceRate =
    combined.summary.markedPeriods
      ? Number((
          (combined.summary.presentCount /
            combined.summary.markedPeriods) * 100
        ).toFixed(1))
      : 0;

  combined.statusBreakdown = Array.from(categoryCounts.entries())
    .map(([label, count]) => ({
      label,
      count,
      percentage: Number(
        ((count / (combined.summary.totalPeriods || 1)) * 100).toFixed(1)
      )
    }))
    .sort((a, b) => b.count - a.count);

  combined.monthlyTrend = Array.from(monthlyByKey.values())
    .sort((a, b) => a.key.localeCompare(b.key))
    .map(month => {
      const marked = month.present + month.absent;

      return {
        ...month,
        rate: marked
          ? Number(((month.present / marked) * 100).toFixed(1))
          : 0
      };
    });

  combined.recentNotes.sort((a, b) =>
    (b.date || '').localeCompare(a.date || '')
  );

  combined.recentNotes = combined.recentNotes.slice(0, 20);

  return combined;
}
