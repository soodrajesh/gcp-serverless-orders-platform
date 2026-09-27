# Architecture

![architecture](img/architecture.png)

## Components

| Component | Role | Identity |
|---|---|---|
| API Gateway (`orders-…`) | Public edge; verifies the JWT signed by `sop-client`; calls orders-api | `sop-gateway` |
| `orders` (Cloud Run) | Creates/reads orders, publishes `OrderCreated`, applies saga status updates | `sop-orders` |
| Pub/Sub `order-events` + Eventarc | Decouples accept from process; starts one saga per event | `sop-trigger` |
| Workflows `order-saga` | Reserve → charge → confirm, with retry and compensation | `sop-saga` |
| `inventory`, `payments` (Cloud Run) | Transactional stock; idempotent charge | `sop-inventory`, `sop-payments` |
| Firestore (named DB) | `orders`, `stock`, `reservations`, `payments` | via the three data-owning SAs |

## Order lifecycle

`PENDING` → (`CONFIRMED` | `FAILED` + `reason` ∈ {`OUT_OF_STOCK`, `PAYMENT_DECLINED`, `PAYMENT_ERROR`})

The API is **asynchronous**: `POST /orders` → `202 {order_id}`; the client polls `GET /orders/{id}`.

## Who may call what
| Caller → callee | Allowed |
|---|---|
| internet → gateway | only a JWT signed by `sop-client` for audience `sop-orders-api` |
| gateway → orders | ✅ (`sop-gateway` is invoker) — `/internal/*` is not in the OpenAPI spec, so unreachable |
| saga → orders / inventory / payments | ✅ (`sop-saga` is invoker) |
| anyone else → any service | ❌ 403 (no `allUsers`) |

## Measured behaviour (this build)
End-to-end order latency (POST → terminal state) under a 40-way burst: see the load-test line in [test results](test-results.md) (p50/p95 measured, includes cold starts of three Cloud Run services and a workflow execution).
