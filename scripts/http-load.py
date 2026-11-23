import argparse
import collections
import concurrent.futures
import json
import threading
import time
import urllib.error
import urllib.request

p = argparse.ArgumentParser()
p.add_argument('url')
p.add_argument('--seconds', type=int, default=180)
p.add_argument('--workers', type=int, default=8)
p.add_argument('--pause', type=float, default=0.05)
p.add_argument('--output', required=True)
p.add_argument('--allow-errors', action='store_true')
a = p.parse_args()
stop = time.monotonic() + a.seconds
counts = collections.Counter()
lock = threading.Lock()

def worker():
    while time.monotonic() < stop:
        try:
            with urllib.request.urlopen(a.url, timeout=5) as r:
                r.read()
                code = str(r.status)
        except urllib.error.HTTPError as e:
            code = str(e.code)
            e.close()
        except Exception as e:
            code = type(e).__name__
        with lock:
            counts[code] += 1
        time.sleep(a.pause)

with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as pool:
    list(pool.map(lambda _: worker(), range(a.workers)))
result = {'url':a.url,'seconds':a.seconds,'workers':a.workers,
          'counts':dict(counts),'total':sum(counts.values())}
print(json.dumps(result, indent=2))
with open(a.output, 'w') as f:
    json.dump(result, f, indent=2)
errors = sum(v for k, v in counts.items() if not k.startswith('2'))
raise SystemExit(0 if a.allow_errors or (result['total'] and not errors) else 1)
