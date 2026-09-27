"""orders-api: owns order state. Public routes go through API Gateway; /internal/* is for the saga only (IAM)."""

import json
import os
import uuid

from flask import Flask, jsonify, request

from app.common import db, now

app = Flask(__name__)
NAMESPACE = uuid.UUID("6f1c2f0e-6a3e-4d0e-9c6b-5b1f5d7e7a10")
STATUSES = {"PENDING", "CONFIRMED", "FAILED"}
_pub = None


def publisher():
    global _pub
    if _pub is None:
        from google.cloud import pubsub_v1

        _pub = pubsub_v1.PublisherClient()
    return _pub


def validate(b: dict) -> str | None:
    if not isinstance(b, dict):
        return "body must be a JSON object"
    for k in ("sku", "qty", "amount", "customer"):
        if k not in b:
            return f"missing field: {k}"
    if not isinstance(b["qty"], int) or isinstance(b["qty"], bool) or b["qty"] < 1:
        return "qty must be an integer >= 1"
    if not isinstance(b["amount"], (int, float)) or isinstance(b["amount"], bool) or b["amount"] <= 0:
        return "amount must be > 0"
    if not isinstance(b["sku"], str) or not b["sku"] or not isinstance(b["customer"], str) or not b["customer"]:
        return "sku and customer must be non-empty strings"
    return None


def order_id_for(idem_key: str) -> str:
    """Same Idempotency-Key -> same order id, so a client retry can never create a second order."""
    return str(uuid.uuid5(NAMESPACE, idem_key))


def valid_id(oid: str) -> bool:
    """Order ids are UUIDs we generated. Anything else (path tricks, slashes, junk) is a 404, never a Firestore call."""
    try:
        return str(uuid.UUID(oid)) == oid.lower()
    except (ValueError, AttributeError):
        return False


def public_view(d: dict) -> dict:
    return {k: (v.isoformat() if hasattr(v, "isoformat") else v) for k, v in d.items()}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/orders")
def create():
    key = request.headers.get("Idempotency-Key", "").strip()
    if not key:
        return jsonify(error="Idempotency-Key header is required"), 400
    body = request.get_json(silent=True)
    err = validate(body)
    if err:
        return jsonify(error=err), 400
    oid = order_id_for(key)
    ref = db().collection("orders").document(oid)
    doc = {
        "order_id": oid,
        "sku": body["sku"],
        "qty": body["qty"],
        "amount": float(body["amount"]),
        "customer": body["customer"],
        "status": "PENDING",
        "created_at": now(),
        "updated_at": now(),
    }
    from google.api_core.exceptions import AlreadyExists

    try:
        ref.create(doc)
    except AlreadyExists:
        return jsonify(public_view(ref.get().to_dict())), 200
    try:
        publisher().publish(os.environ["TOPIC"], json.dumps({"order_id": oid}).encode()).result(timeout=30)
    except Exception:  # noqa: BLE001 - the event never left: undo the order so the client's retry starts clean
        ref.delete()
        return jsonify(error="could not enqueue the order, please retry with the same Idempotency-Key"), 503
    return jsonify(order_id=oid, status="PENDING"), 202


@app.get("/orders/<oid>")
def get_order(oid):
    if not valid_id(oid):
        return jsonify(error="not found"), 404
    snap = db().collection("orders").document(oid).get()
    if not snap.exists:
        return jsonify(error="not found"), 404
    return jsonify(public_view(snap.to_dict()))


@app.get("/internal/orders/<oid>")
def internal_get(oid):
    return get_order(oid)


@app.patch("/internal/orders/<oid>/status")
def set_status(oid):
    if not valid_id(oid):
        return jsonify(error="not found"), 404
    b = request.get_json(silent=True) or {}
    if b.get("status") not in STATUSES:
        return jsonify(error="bad status"), 400
    ref = db().collection("orders").document(oid)
    if not ref.get().exists:
        return jsonify(error="not found"), 404
    upd = {"status": b["status"], "updated_at": now()}
    if b.get("reason"):
        upd["reason"] = b["reason"]
    ref.update(upd)
    return jsonify(order_id=oid, **{k: v for k, v in upd.items() if k != "updated_at"})
