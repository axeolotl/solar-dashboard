#!/usr/bin/env python3
"""Generate synthetic SolexMidi log files (same layout as the WLAN SD card:
<dir>/YYYY/MM/YYYYMMDD.TXT, tab separated, CRLF, German date format) for the
last DAYS days up to today, 5-minute resolution.

usage: gen-testdata.py <target-dir> [days]   (default 14)
"""
import datetime as dt, math, os, random, sys

base = sys.argv[1]
days = int(sys.argv[2]) if len(sys.argv) > 2 else 14
random.seed(1)
end = dt.datetime.combine(dt.date.today(), dt.time(23, 55))
start = dt.datetime.combine(dt.date.today() - dt.timedelta(days=days - 1), dt.time(0, 0))
hdr = ("Date\tS1\tS2\tS3\tS4\tS5\tS6\tS7\tS8\tS9\tS10\tV40\tCS10\tFlowRotor\t"
       "RPS_Temperature\tRPS_Pressure\tR1\tR2\tR3\tR4\tR5\tDate2\tHeat\tHeat_today\t"
       "Heat_week\tPower\tExtra")
heat, today, t, files, rows_total = 100000, 0, start, {}, 0
while t <= end:
    if t.hour == 0 and t.minute == 0:
        today = 0
    h = t.hour + t.minute / 60
    sun = max(0, math.sin((h - 7) / 12 * math.pi)) * (0.4 + 0.6 * random.random()) if 7 < h < 19 else 0
    s1 = 15 + 70 * sun + random.random()
    if random.random() < 0.002:
        s1 = 999  # sensor outlier, removed by init-db.sql
    s2 = 40 + 20 * sun + 5 * math.sin(t.date().toordinal())
    pump = 100 if sun > 0.2 else 0
    power = int(3000 * sun) if pump else 0
    e = power * 5 // 60
    heat += e
    today += e
    ts = t.strftime("%d.%m.%Y %H:%M:%S")
    row = ([ts] + [f"{x:.1f}" for x in (s1, s2, 30 + 30 * sun, 20, 20, 20, 20, 20, 25 + 35 * sun, 0)]
           + ["0", "0", "5.0", "25", "2.1", str(pump), "0", str(pump if sun > 0.3 else 0), "0", "0",
              ts, str(heat), str(today), "0", str(power), "x"])
    files.setdefault(t.date(), []).append("\t".join(row))
    t += dt.timedelta(minutes=5)
for d, rows in files.items():
    p = f"{base}/{d:%Y}/{d:%m}"
    os.makedirs(p, exist_ok=True)
    with open(f"{p}/{d:%Y%m%d}.TXT", "w", newline="") as f:
        f.write("\r\n".join([hdr] + rows) + "\r\n")
    rows_total += len(rows)
print(f"{len(files)} files, {rows_total} rows in {base}")
