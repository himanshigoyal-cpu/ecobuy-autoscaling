"""Usage: python3 loadtest.py http://<alb-dns> ; phases: baseline, peak, cooldown. Writes results.csv"""
import sys, time, csv, threading, urllib.request, statistics

url = sys.argv[1].rstrip("/")
PHASES = [("baseline", 2, 120), ("peak", 25, 900), ("cooldown", 2, 300)]  # name, threads, seconds
results, lock = [], threading.Lock()

def worker(phase, stop):
    while time.time() < stop:
        t = time.time()
        try:
            code = urllib.request.urlopen(url + "/load?n=200", timeout=10).status
        except Exception:
            code = 0
        with lock:
            results.append((phase, t, (time.time() - t) * 1000, code))

for name, threads, secs in PHASES:
    print("phase:", name)
    stop = time.time() + secs
    ts = [threading.Thread(target=worker, args=(name, stop)) for _ in range(threads)]
    [t.start() for t in ts]; [t.join() for t in ts]
    r = [x[2] for x in results if x[0] == name]
    err = sum(1 for x in results if x[0] == name and x[3] != 200)
    r.sort()
    print(f"  requests={len(r)} avg={statistics.mean(r):.0f}ms p95={r[int(len(r)*.95)-1]:.0f}ms errors={err}")

with open("results.csv", "w", newline="") as f:
    csv.writer(f).writerows([("phase", "epoch", "ms", "status"), *results])
