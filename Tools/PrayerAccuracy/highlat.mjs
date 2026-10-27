// Reproduces the app's new "Automatic" high-latitude logic with adhan-js.
import { Coordinates, CalculationMethod, PrayerTimes, Madhab, HighLatitudeRule } from 'adhan';

function reaches(depression, lat, y, m, d, hour) {
  const start = Date.UTC(y, 0, 1);
  const ordinal = Math.floor((Date.UTC(y, m - 1, d) - start) / 86400000) + 1;
  const g = 2 * Math.PI / 365 * (ordinal - 1 + (hour - 12) / 24);
  const decl = (0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g)
    + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g)) * 180 / Math.PI;
  const toward = lat >= 0 ? decl : -decl;
  return Math.abs(lat) + toward - 90 < -(depression + 0.5);
}
const hm = (date, tz) => new Intl.DateTimeFormat('en-GB', { timeZone: tz, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(date);
const cases = [
  ['Vancouver', 49.2827, -123.1207, 'America/Vancouver', 'NorthAmerica', '2026-06-21'],
  ['London', 51.5074, -0.1278, 'Europe/London', 'MuslimWorldLeague', '2026-06-21'],
  ['Oslo', 59.9139, 10.7522, 'Europe/Oslo', 'MuslimWorldLeague', '2026-03-29'],
  ['Oslo', 59.9139, 10.7522, 'Europe/Oslo', 'MuslimWorldLeague', '2026-01-15'],
  ['Oslo', 59.9139, 10.7522, 'Europe/Oslo', 'MuslimWorldLeague', '2026-03-08'],
  ['Edmonton', 53.5461, -113.4938, 'America/Edmonton', 'NorthAmerica', '2026-06-21'],
  ['Toronto', 43.6532, -79.3832, 'America/Toronto', 'NorthAmerica', '2026-06-21'],
];
for (const [name, lat, lon, tz, method, day] of cases) {
  const [y, m, d] = day.split('-').map(Number);
  const coords = new Coordinates(lat, lon);
  const p = CalculationMethod[method](); p.madhab = Madhab.Hanafi; p.highLatitudeRule = HighLatitudeRule.recommended(coords);
  const base = new PrayerTimes(coords, new Date(y, m - 1, d), p);
  const q = CalculationMethod[method](); q.madhab = Madhab.Hanafi; q.highLatitudeRule = HighLatitudeRule.MiddleOfTheNight;
  const perm = new PrayerTimes(coords, new Date(y, m - 1, d), q);
  const fr = reaches(p.fajrAngle, lat, y, m, d, 0), ir = p.ishaInterval === 0 && reaches(p.ishaAngle, lat, y, m, d, 24);
  const fajr = fr ? perm.fajr : base.fajr, isha = ir ? perm.isha : base.isha;
  console.log(`${name.padEnd(9)} ${day} ${method.padEnd(18)} rule=${p.highLatitudeRule.padEnd(18)} fajr ${hm(base.fajr, tz)} -> ${hm(fajr, tz)} (reached ${fr})  isha ${hm(base.isha, tz)} -> ${hm(isha, tz)} (reached ${ir})`);
}
