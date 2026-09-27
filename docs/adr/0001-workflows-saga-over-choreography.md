# ADR 0001 — Cloud Workflows orchestrates the order saga (not event choreography)

**Status:** accepted

An order touches three services (orders, inventory, payments) and must end in exactly one of: confirmed, or failed with the stock put back. With **choreography** (services reacting to each other's events) the compensation logic is scattered and the current state of a given order is nowhere. With **orchestration** the whole flow — including retries and undo — is one readable file ([`workflows/order-saga.yaml`](../../workflows/order-saga.yaml)), every step is logged per execution, and adding a step is a local change.

**Decisions inside the saga**
- *Business failures are handled outcomes.* Out-of-stock (HTTP 409) and declined (402) end with the order `FAILED` and the execution `SUCCEEDED`; only an unexpected crash makes an execution `FAILED`, and only that pages (alert). This keeps the alert meaningful.
- *Retry only what is retryable.* `http.default_retry_predicate` (429/502/503/504) with 1→10 s exponential backoff, 4 retries; a 402 is not retried.
- *Compensate what was done.* Payment failure releases the reservation; out-of-stock has nothing to release and never reaches payments.
- *orders-api stays the single writer of order state:* the saga PATCHes status through an internal endpoint rather than writing Firestore itself.

**Trade-off:** Workflows adds a control-plane dependency and per-step cost (cents at this scale), and the YAML DSL is less expressive than code.
