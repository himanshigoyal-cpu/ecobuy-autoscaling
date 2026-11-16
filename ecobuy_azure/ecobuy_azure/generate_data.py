"""Generates synthetic workload data: traffic.csv (hourly hits) and metrics.json (CPU/memory)."""
import csv, json, math, random
from datetime import datetime, timedelta

random.seed(42)
start = datetime(2026, 10, 1)
sale_hours = {200, 201, 202, 203, 450, 451, 452, 453, 454, 640, 641, 642}  # 3 flash sales
rows, metrics = [], []
for h in range(30 * 24):
    t = start + timedelta(hours=h)
    daily = 1 + 0.8 * math.sin((t.hour - 9) / 24 * 2 * math.pi)       # evening peak
    weekend = 1.25 if t.weekday() >= 5 else 1.0
    hits = int(800 * daily * weekend * random.uniform(0.85, 1.15))
    if h in sale_hours:
        hits *= random.randint(4, 6)
    hits = max(hits, 50)
    rows.append([t.strftime("%Y-%m-%d %H:%M"), hits])
    cpu = min(97, 8 + hits / 1000 * 11 + random.uniform(-3, 3))     # 2 fixed servers
    mem = min(90, 35 + hits / 1000 * 3.5 + random.uniform(-2, 2))
    metrics.append({"timestamp": t.isoformat(), "cpu_percent": round(cpu, 1),
                    "memory_percent": round(mem, 1), "instances": 2})
with open("traffic.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["timestamp", "hits"]); w.writerows(rows)
with open("metrics.json", "w") as f:
    json.dump(metrics, f, indent=1)
hits = [r[1] for r in rows]
print("avg hits/hr:", sum(hits)//len(hits), "peak:", max(hits), "peak/avg: %.1f" % (max(hits)/(sum(hits)/len(hits))))
