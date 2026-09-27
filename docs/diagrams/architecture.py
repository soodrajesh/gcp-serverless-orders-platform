#!/usr/bin/env python3
"""Generates docs/img/architecture.svg (PNG via docs/diagrams/render.py).

    python3 docs/diagrams/architecture.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from archlib import Diagram  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "img", "architecture.svg")

W, H = 1780, 1520
d = Diagram(W, H, "Serverless Orders Platform on Google Cloud",
            "API Gateway · Cloud Run · Pub/Sub + Eventarc · Cloud Workflows saga · Firestore · Terraform")

d.group(190, 100, 1480, 700, "Google Cloud project  ·  europe-west1", "#1a73e8", dash=False, fill="#f8faff", label_w=330)

# ── request lane ─────────────────────────────────────────────────────────────────────────────────
d.node("client", 70, 250, "API client", "user", "actor", "self-signed JWT\n(signJwt as sop-client)")
d.node("gw", 340, 250, "API Gateway", "lb", "network", "JWT signature +\naudience checked")
d.node("orders", 620, 250, "", "run", "compute")
d.text(620, 172, "orders-api", 12.5, "#202124", "600", "middle")
d.text(620, 187, "Cloud Run · idempotent create", 10.5, "#5f6368", "400", "middle")
d.text(620, 200, "owns order state", 10.5, "#5f6368", "400", "middle")
d.node("fs", 1330, 250, "Firestore", "db", "data", "orders · stock ·\nreservations · payments")

d.edge("client", "gw", "h", num=1, label="Bearer JWT")
d.edge("gw", "orders", "h", num=2, label="own SA identity")
d.path([(650, 235), (1300, 235)], num=3, label="create order = PENDING", lab_at=(1000, 235))

# ── saga lane ────────────────────────────────────────────────────────────────────────────────────
d.node("topic", 620, 470, "Pub/Sub", "bolt", "data", "order-events")
d.node("ea", 850, 470, "Eventarc", "filter", "network", "trigger")
d.node("wf", 1080, 470, "Workflows", "pipeline", "compute", "order-saga\nretries + compensation")
d.edge("orders", "topic", "v", num=4, label="OrderCreated", lab_dy=0, half_a=30, half_b=30)
d.edge("topic", "ea", "h")
d.edge("ea", "wf", "h", num=5)

d.node("inv", 1330, 400, "inventory", "run", "compute", "reserve · release\ntransactional")
d.node("pay", 1330, 570, "payments", "run", "compute", "idempotent charge\ndeclines > 1000")
d.path([(1110, 470), (1200, 470), (1200, 400), (1300, 400)], num=6, label="reserve", lab_at=(1250, 388))
d.path([(1200, 470), (1200, 570), (1300, 570)], num=None)
d.text(1205, 590, "charge", 11.5, "#3c4043")
d.text(1205, 603, "(retry on 503)", 10.5, "#5f6368")
d.path([(1360, 400), (1460, 400), (1460, 250), (1360, 250)], num=None)
d.path([(1360, 570), (1460, 570), (1460, 400)], num=None)
d.path([(1080, 440), (1080, 275), (650, 275)], num=8, color="#5f6368", label="PATCH final status", lab_at=(860, 275))

d.badge(250, 640, "7", "#d93025")
d.text(270, 645, "Compensation: if stock is short or the charge is declined, the saga calls inventory /release (when stock was reserved) and marks the order FAILED.", 12.5, "#d93025", "600")
d.text(240, 700, "Business failures (out of stock, declined) are handled outcomes: the order ends FAILED and the execution SUCCEEDS.", 12, "#5f6368", "600")
d.text(240, 718, "Only an unexpected crash makes an execution FAILED, and that pages someone.", 12, "#5f6368", "600")

# ── ops / governance ─────────────────────────────────────────────────────────────────────────────
d.band(190, 840, 1480, 190, "OBSERVABILITY  ·  the platform reports on itself", "#1e8e3e", "#f6fcf8")
d.node("o1", 330, 940, "Dashboard", "chart", "ops", "saga status · latency\nrequests · Firestore writes")
d.node("o2", 640, 940, "Saga-failed alert", "bolt", "ops", "any FAILED execution")
d.node("o3", 950, 940, "5xx alert", "bolt", "ops", "orders-api errors")
d.node("o4", 1260, 940, "Logs + Trace", "policy", "ops", "one trace per request")
d.node("o5", 1520, 940, "Budget", "money", "ops", "€ alerts 50 / 100 %")

d.band(190, 1050, 1480, 130, "GOVERNANCE  ·  preventive controls", "#d93025", "#fff8f7")
d.text(220, 1094, "Every service has its own identity; nothing is public (no allUsers). Only the gateway may call orders-api; only the saga may call inventory and payments.", 12.5, "#3c4043")
d.text(220, 1118, "Internal routes (/internal/*) are not in the OpenAPI spec, so the gateway cannot reach them · No service-account keys · Dedicated Cloud Build SA, digest-pinned image", 12.5, "#3c4043")
d.text(220, 1142, "Idempotency-Key → deterministic order id (retries can't double-order) · Firestore transactions prevent overselling · state in a versioned private bucket", 12.5, "#3c4043")

d.legend(34, 1215, "Numbered flows", [
    ("1", "The client has a JWT signed by the dedicated sop-client service account (iam signJwt; audience sop-orders-api) and calls the gateway"),
    ("2", "API Gateway verifies the signature against sop-client's public keys plus issuer and audience, rejects everything else (401), and calls orders-api with its own service-account identity"),
    ("3", "orders-api validates the body and creates the order as PENDING; the order id derives from the Idempotency-Key, so a retry returns the same order"),
    ("4", "It publishes OrderCreated to Pub/Sub and answers 202 immediately; the client polls GET /orders/{id}"),
    ("5", "Eventarc delivers the event to Cloud Workflows, starting one saga execution"),
    ("6", "The saga reserves stock (inventory, Firestore transaction) then charges (payments); a 503 from payments is retried with exponential backoff"),
    ("7", "If stock is short or the charge is declined, the saga compensates: releases the reservation and marks the order FAILED with a reason"),
    ("8", "On success (or after compensation) the saga PATCHes the final status through the internal API: orders-api stays the single writer of order state"),
], w=1710)
d.key(34, 1450)

if __name__ == "__main__":
    d.save(OUT)
    print("wrote", os.path.abspath(OUT))
