# Runbooks

Each runbook: **When** · **Commands** · **Output** · **If it goes wrong**.

> **Output status.** Blocks headed *Captured* are real output from the live deployment (2026-09-27). Nothing here is invented.

```bash
export PROJECT=$(gcloud config get-value project) REGION=europe-west1
```

| # | Runbook | Use it when |
|---|---|---|
| 01 | [Build & teardown](01-build-and-teardown.md) | Standing the platform up / down |
| 02 | [Call the API](02-call-the-api.md) | Creating / reading orders as a client |
| 03 | [Trace an order](03-trace-an-order.md) | "What happened to order X?" |
| 04 | [Operate stock & payments](04-operate-stock-and-payments.md) | Seeding stock, inspecting a payment |
| 05 | [Incident response](05-incident-response.md) | An alert fires; orders stuck PENDING |
| 06 | [Change the saga](06-change-the-saga.md) | Adding a step or a compensation |
| 07 | [Cost](07-cost.md) | Bill questions |
| 08 | [Troubleshooting](08-troubleshooting.md) | Problems already hit during development |
