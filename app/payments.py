"""payments: idempotent charge. Declines large amounts (402) and fails the first attempt for 'flaky' customers (503)."""

from flask import Flask, jsonify, request

from app.common import db, now

app = Flask(__name__)
LIMIT = 1000.0


def decide(amount: float, customer: str, attempt: int) -> tuple[int, str]:
    if amount > LIMIT:
        return 402, "DECLINED"
    if "flaky" in customer and attempt == 1:
        return 503, "UPSTREAM_UNAVAILABLE"
    return 200, "CHARGED"


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/charge")
def charge():
    from google.cloud import firestore

    b = request.get_json(silent=True) or {}
    oid, amount, customer = b.get("order_id"), b.get("amount"), b.get("customer", "")
    if not oid or not isinstance(amount, (int, float)) or amount <= 0:
        return jsonify(error="order_id and positive amount required"), 400
    client = db()
    ref = client.collection("payments").document(oid)

    @firestore.transactional
    def run(t):
        snap = ref.get(transaction=t)
        prev = snap.to_dict() if snap.exists else {}
        if prev.get("state") == "CHARGED":
            return 200, "ALREADY_CHARGED", prev.get("attempts", 1)
        attempt = prev.get("attempts", 0) + 1
        code, state = decide(float(amount), customer, attempt)
        t.set(ref, {"order_id": oid, "amount": float(amount), "attempts": attempt, "state": state, "at": now()})
        return code, state, attempt

    try:
        code, state, attempt = run(client.transaction(max_attempts=15))
    except Exception as exc:
        from google.api_core import exceptions as gx

        if isinstance(exc, (gx.Aborted, gx.ServiceUnavailable, gx.DeadlineExceeded, gx.RetryError)):
            return jsonify(error="CONTENTION"), 503
        raise
    return jsonify(order_id=oid, state=state, attempts=attempt), code


@app.get("/payments/<oid>")
def get_payment(oid):
    s = db().collection("payments").document(oid).get()
    return (
        (jsonify({k: (v.isoformat() if hasattr(v, "isoformat") else v) for k, v in s.to_dict().items()}), 200)
        if s.exists
        else (jsonify(error="not found"), 404)
    )
