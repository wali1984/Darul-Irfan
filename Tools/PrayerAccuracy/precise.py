"""High-precision check (pyephem, VSOP87) of the adhan engine's times.

Definitions used: Fajr/Isha = sun centre at -angle (geometric); sunrise/
Maghrib = upper limb with standard refraction (-0.833 deg); Hanafi Asr =
shadow twice the object plus the noon shadow.
"""
import json
import math
import sys
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

import ephem

ANGLES = {"Karachi": (18, 18), "NorthAmerica": (15, 15), "MuslimWorldLeague": (18, 17),
          "Egyptian": (19.5, 17.5), "Singapore": (20, 18), "UmmAlQura": (18.5, None),
          "Dubai": (18.2, 18.2), "MoonsightingCommittee": (18, 18)}
CITIES = {}
for line in open(sys.argv[2], encoding="utf-8"):
    pass


def observer(lat, lon, day, tz):
    o = ephem.Observer()
    o.lat, o.lon = str(lat), str(lon)
    o.elevation = 0
    local_noon = datetime(day.year, day.month, day.day, 12, tzinfo=ZoneInfo(tz))
    o.date = ephem.Date(local_noon.astimezone(ZoneInfo("UTC")).replace(tzinfo=None))
    return o


def event(o, horizon, rising, use_center, refraction):
    o.horizon = str(horizon)
    o.pressure = 1010 if refraction else 0
    sun = ephem.Sun()
    try:
        when = o.previous_rising(sun, use_center=use_center) if rising else o.next_setting(sun, use_center=use_center)
    except (ephem.AlwaysUpError, ephem.NeverUpError):
        return None
    return ephem.Date(when).datetime()


def compute(lat, lon, day, tz, method):
    o = observer(lat, lon, day, tz)
    sun = ephem.Sun()
    o.pressure = 0
    transit = ephem.Date(o.next_transit(sun) if False else o.previous_transit(sun)).datetime()
    # nearest transit to local noon
    o2 = observer(lat, lon, day, tz)
    o2.pressure = 0
    t_next = ephem.Date(o2.next_transit(sun)).datetime()
    t_prev = ephem.Date(o2.previous_transit(sun)).datetime()
    noon_utc = ephem.Date(o2.date).datetime()
    transit = t_next if abs((t_next - noon_utc).total_seconds()) < abs((t_prev - noon_utc).total_seconds()) else t_prev
    o3 = observer(lat, lon, day, tz)
    o3.pressure = 0
    o3.date = transit
    sun.compute(o3)
    noon_alt = float(sun.alt)
    shadow = 1 / math.tan(noon_alt)
    asr_alt = math.degrees(math.atan(1 / (2 + shadow)))
    fajr_angle, isha_angle = ANGLES[method]
    o4 = observer(lat, lon, day, tz)
    o4.date = transit
    asr = event(o4, asr_alt, False, True, False)
    o5 = observer(lat, lon, day, tz); o5.date = transit
    maghrib = event(o5, -0.8333, False, True, False)
    o6 = observer(lat, lon, day, tz); o6.date = transit
    sunrise = event(o6, -0.8333, True, True, False)
    o7 = observer(lat, lon, day, tz); o7.date = transit
    fajr = event(o7, -fajr_angle, True, True, False)
    isha = None
    if isha_angle:
        o8 = observer(lat, lon, day, tz); o8.date = transit
        isha = event(o8, -isha_angle, False, True, False)
    out = {"fajr": fajr, "sunrise": sunrise, "dhuhr": transit, "asr": asr, "maghrib": maghrib, "isha": isha}
    zone = ZoneInfo(tz)
    return {k: (v.replace(tzinfo=ZoneInfo("UTC")).astimezone(zone).strftime("%H:%M:%S") if v else None) for k, v in out.items()}


rows = json.load(open(sys.argv[1], encoding="utf-8"))
coords = {
    "Dar-ul-Irfan (Munara)": (32.6678, 72.5133, "Asia/Karachi"), "New York": (40.7128, -74.006, "America/New_York"),
    "Toronto": (43.6532, -79.3832, "America/Toronto"), "Vancouver": (49.2827, -123.1207, "America/Vancouver"),
    "Oslo": (59.9139, 10.7522, "Europe/Oslo"), "London": (51.5074, -0.1278, "Europe/London"),
    "Makkah": (21.3891, 39.8579, "Asia/Riyadh"), "Sydney": (-33.8688, 151.2093, "Australia/Sydney"),
    "Houston": (29.7604, -95.3698, "America/Chicago"), "Karachi": (24.8607, 67.0011, "Asia/Karachi"),
}
worst = {}
for row in rows:
    if row["city"] not in coords:
        continue
    lat, lon, tz = coords[row["city"]]
    day = datetime.strptime(row["date"], "%Y-%m-%d")
    precise = compute(lat, lon, day, tz, row["method"])
    line = []
    for name in ("fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"):
        engine = row["engine"][name]
        ref = precise[name]
        if not ref:
            line.append(f"{name[0]}{engine}(n/a)"); continue
        h, m, s = map(int, ref.split(":"))
        eh, em = map(int, engine.split(":"))
        diff = (eh * 60 + em) - (h * 60 + m + s / 60)
        worst[name] = max(worst.get(name, 0), abs(diff))
        line.append(f"{name[0]}{engine}/{ref[:5]}({diff:+.1f})")
    print(f"{row['city'][:14]:14} {row['date']} {row['method'][:12]:12} " + " ".join(line))
print("worst |engine - precise| minutes by prayer:", {k: round(v, 1) for k, v in worst.items()})
