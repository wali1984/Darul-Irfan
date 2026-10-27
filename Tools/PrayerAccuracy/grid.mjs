// Cross-check of prayer times: the adhan engine (same algorithm and
// parameters as the app's adhan-swift) against the Aladhan API (an
// independent implementation), for a grid of cities, seasons and DST edges.
import { Coordinates, CalculationMethod, PrayerTimes, Madhab, HighLatitudeRule } from 'adhan';
import fs from 'node:fs';

const cities = [
  ['Dar-ul-Irfan (Munara)', 32.6678, 72.5133, 'Asia/Karachi', 'Karachi'],
  ['Lahore', 31.5204, 74.3587, 'Asia/Karachi', 'Karachi'],
  ['Karachi', 24.8607, 67.0011, 'Asia/Karachi', 'Karachi'],
  ['New York', 40.7128, -74.0060, 'America/New_York', 'NorthAmerica'],
  ['Houston', 29.7604, -95.3698, 'America/Chicago', 'NorthAmerica'],
  ['Toronto', 43.6532, -79.3832, 'America/Toronto', 'NorthAmerica'],
  ['Vancouver', 49.2827, -123.1207, 'America/Vancouver', 'NorthAmerica'],
  ['London', 51.5074, -0.1278, 'Europe/London', 'MoonsightingCommittee'],
  ['Oslo', 59.9139, 10.7522, 'Europe/Oslo', 'MuslimWorldLeague'],
  ['Makkah', 21.3891, 39.8579, 'Asia/Riyadh', 'UmmAlQura'],
  ['Dubai', 25.2048, 55.2708, 'Asia/Dubai', 'Dubai'],
  ['Cairo', 30.0444, 31.2357, 'Africa/Cairo', 'Egyptian'],
  ['Jakarta', -6.2088, 106.8456, 'Asia/Jakarta', 'Singapore'],
  ['Sydney', -33.8688, 151.2093, 'Australia/Sydney', 'MuslimWorldLeague'],
  ['Auckland', -36.8485, 174.7633, 'Pacific/Auckland', 'MuslimWorldLeague'],
  ['Quito', -0.1807, -78.4678, 'America/Guayaquil', 'MuslimWorldLeague'],
];
const dates = ['2026-01-15', '2026-03-08', '2026-03-29', '2026-06-21', '2026-11-01', '2026-12-21'];
const aladhanMethod = { Karachi: 1, NorthAmerica: 2, MuslimWorldLeague: 3, UmmAlQura: 4, Egyptian: 5, Dubai: 16, Singapore: 11, MoonsightingCommittee: 15 };
const names = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];
const aladhanNames = { fajr: 'Fajr', sunrise: 'Sunrise', dhuhr: 'Dhuhr', asr: 'Asr', maghrib: 'Maghrib', isha: 'Isha' };

function hm(date, tz) {
  return new Intl.DateTimeFormat('en-GB', { timeZone: tz, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(date);
}
function minutes(t) { const [h, m] = t.split(':').map(Number); return h * 60 + m; }

const mode = process.argv[2] ?? 'regional'; // 'regional' or 'karachi' (the app default)
const rows = [];
let worst = 0;
for (const [name, lat, lon, tz, regional] of cities) {
  const methodName = mode === 'karachi' ? 'Karachi' : regional;
  for (const day of dates) {
    const [y, m, d] = day.split('-').map(Number);
    const params = CalculationMethod[methodName]();
    params.madhab = Madhab.Hanafi;
    const highLat = HighLatitudeRule.recommended(new Coordinates(lat, lon));
    params.highLatitudeRule = highLat;
    const times = new PrayerTimes(new Coordinates(lat, lon), new Date(y, m - 1, d), params);
    const engine = Object.fromEntries(names.map(n => [n, hm(times[n], tz)]));

    const latAdj = highLat === 'seventhofthenight' ? 2 : highLat === 'twilightangle' ? 3 : 1;
    const url = `https://api.aladhan.com/v1/timings/${String(d).padStart(2, '0')}-${String(m).padStart(2, '0')}-${y}` +
      `?latitude=${lat}&longitude=${lon}&method=${aladhanMethod[methodName]}&school=1&latitudeAdjustmentMethod=${latAdj}&timezonestring=${encodeURIComponent(tz)}`;
    let reference = null;
    try {
      const response = await fetch(url);
      const body = await response.json();
      reference = body.data?.timings ?? null;
    } catch { reference = null; }
    const diffs = {};
    if (reference) {
      for (const n of names) {
        const ref = reference[aladhanNames[n]].slice(0, 5);
        diffs[n] = minutes(engine[n]) - minutes(ref);
        worst = Math.max(worst, Math.abs(diffs[n]));
      }
    }
    rows.push({ city: name, date: day, method: methodName, engine, aladhan: reference && Object.fromEntries(names.map(n => [n, reference[aladhanNames[n]].slice(0, 5)])), diffs });
    await new Promise(r => setTimeout(r, 150));
  }
}
fs.writeFileSync(`grid_${mode}.json`, JSON.stringify(rows, null, 1));
for (const row of rows) {
  const flag = Object.values(row.diffs).some(v => Math.abs(v) > 2) ? '  <-- differs' : '';
  console.log(`${row.city.padEnd(22)} ${row.date} ${row.method.padEnd(22)} ${names.map(n => `${n[0]}${row.engine[n]}(${row.diffs[n] ?? '?'})`).join(' ')}${flag}`);
}
console.log('worst |engine - aladhan| minutes:', worst);
