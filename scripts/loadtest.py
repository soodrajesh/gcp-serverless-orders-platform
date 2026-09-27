#!/usr/bin/env python3
"""Fire N concurrent orders at the gateway and wait for each to reach a terminal state.

    loadtest.py <gateway-host> <jwt> <sku> <n> [amount]
Prints one JSON summary: counts by outcome, stock-relevant totals and end-to-end latency (POST -> terminal state).
"""
import json
import sys
import time
import urllib.error
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

host, jwt, sku, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
amount = float(sys.argv[5]) if len(sys.argv) > 5 else 25.0
base = f"https://{host}"


def call(method, path, body=None, key=None):
    req = urllib.request.Request(base + path, method=method, data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Authorization", f"Bearer {jwt}")
    req.add_header("Content-Type", "application/json")
    if key:
        req.add_header("Idempotency-Key", key)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def one(i):
    t0 = time.time()
    st, b = call("POST", "/orders", {"sku": sku, "qty": 1, "amount": amount, "customer": f"load-{i}"}, key=str(uuid.uuid4()))
    if st != 202:
        return {"http": st, "status": "REJECTED"}
    oid = b["order_id"]
    for _ in range(90):
        st, o = call("GET", f"/orders/{oid}")
        if st == 200 and o["status"] != "PENDING":
            return {"http": 202, "status": o["status"], "reason": o.get("reason"), "secs": round(time.time() - t0, 2)}
        time.sleep(1)
    return {"http": 202, "status": "TIMEOUT"}


with ThreadPoolExecutor(max_workers=20) as ex:
    res = list(ex.map(one, range(n)))

secs = sorted(r["secs"] for r in res if r.get("status") == "CONFIRMED")
q = lambda p: secs[min(len(secs) - 1, int(len(secs) * p))] if secs else None  # noqa: E731
print(json.dumps({
    "orders": n,
    "confirmed": sum(r["status"] == "CONFIRMED" for r in res),
    "failed_out_of_stock": sum(r["status"] == "FAILED" and r.get("reason") == "OUT_OF_STOCK" for r in res),
    "other": sum(r["status"] not in ("CONFIRMED",) and not (r["status"] == "FAILED" and r.get("reason") == "OUT_OF_STOCK") for r in res),
    "p50_s": q(0.5), "p95_s": q(0.95),
}))
