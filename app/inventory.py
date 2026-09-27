"""inventory: stock counts and per-order reservations (idempotent, transactional)."""

from flask import Flask, jsonify, request

from app.common import db, now

app = Flask(__name__)


def _is_transient(exc: Exception) -> bool:
    from google.api_core import exceptions as gx

    return isinstance(exc, (gx.Aborted, gx.ServiceUnavailable, gx.DeadlineExceeded, gx.RetryError, gx.TooManyRequests))


def _txn():
    from google.cloud import firestore

    return firestore


@app.get("/health")
def health():
    return {"status": "ok"}


@app.put("/stock/<sku>")
def seed(sku):
    qty = (request.get_json(silent=True) or {}).get("qty")
    if not isinstance(qty, int) or qty < 0:
        return jsonify(error="qty must be an integer >= 0"), 400
    db().collection("stock").document(sku).set({"qty": qty, "updated_at": now()})
    return jsonify(sku=sku, qty=qty)


@app.get("/stock/<sku>")
def stock(sku):
    s = db().collection("stock").document(sku).get()
    return (jsonify(sku=sku, qty=s.to_dict()["qty"]), 200) if s.exists else (jsonify(error="unknown sku"), 404)


@app.post("/reserve")
def reserve():
    b = request.get_json(silent=True) or {}
    oid, sku, qty = b.get("order_id"), b.get("sku"), b.get("qty")
    if not (oid and sku and isinstance(qty, int) and qty > 0):
        return jsonify(error="order_id, sku, qty required"), 400
    fs = _txn()
    client = db()
    stock_ref, res_ref = client.collection("stock").document(sku), client.collection("reservations").document(oid)

    @fs.transactional
    def run(t):
        res = res_ref.get(transaction=t)
        if res.exists and res.to_dict().get("state") == "RESERVED":
            return "already"  # idempotent replay
        s = stock_ref.get(transaction=t)
        if not s.exists or s.to_dict()["qty"] < qty:
            return "insufficient"
        t.update(stock_ref, {"qty": s.to_dict()["qty"] - qty, "updated_at": now()})
        t.set(res_ref, {"order_id": oid, "sku": sku, "qty": qty, "state": "RESERVED", "at": now()})
        return "reserved"

    try:
        out = run(client.transaction(max_attempts=15))
    except Exception as exc:
        if _is_transient(exc):
            return jsonify(error="CONTENTION", detail=type(exc).__name__), 503  # retryable: the saga retries with backoff
        raise
    if out == "insufficient":
        return jsonify(error="OUT_OF_STOCK"), 409
    return jsonify(order_id=oid, result=out)


@app.post("/release")
def release():
    oid = (request.get_json(silent=True) or {}).get("order_id")
    if not oid:
        return jsonify(error="order_id required"), 400
    fs = _txn()
    client = db()
    res_ref = client.collection("reservations").document(oid)

    @fs.transactional
    def run(t):
        res = res_ref.get(transaction=t)
        if not res.exists or res.to_dict().get("state") != "RESERVED":
            return "nothing to release"
        d = res.to_dict()
        stock_ref = client.collection("stock").document(d["sku"])
        s = stock_ref.get(transaction=t)
        t.update(stock_ref, {"qty": s.to_dict()["qty"] + d["qty"], "updated_at": now()})
        t.update(res_ref, {"state": "RELEASED", "at": now()})
        return "released"

    try:
        return jsonify(order_id=oid, result=run(client.transaction(max_attempts=15)))
    except Exception as exc:
        if _is_transient(exc):
            return jsonify(error="CONTENTION", detail=type(exc).__name__), 503
        raise
