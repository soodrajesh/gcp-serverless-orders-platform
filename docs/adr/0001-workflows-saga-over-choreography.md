# ADR 0001 — Cloud Workflows orchestrates the order saga (not event choreography)

**Status:** accepted

An order touches three services (orders, inventory, payments) and must end in exactly one of: confirmed, or failed with the stock put back. With **choreography** (services reacting to each other's events) the compensation logic is scattered and the current state of a given order is nowhere. With **orchestration** the whole flow — including retries and undo — is one readable file ([`workflows/order-saga.yaml`](../../workflows/order-saga.yaml)), every step is logged per execution, and adding a step is a local change.

**Decisions inside the saga**
- *Business failures are handled outcomes.* Out-of-stock (HTTP 409) and declined (402) end with the order `FAILED` and the execution `SUCCEEDED`; only an unexpected crash makes an execution `FAILED`, and only that pages (alert). This keeps the alert meaningful.
- *Retry only what is retryable.* Every service call goes through one `send` subworkflow that retries 429/500/502/503/504 (5 retries, 1→15 s exponential backoff); 4xx business answers (402 declined, 409 out of stock) are never retried. Every callee is idempotent, so retrying is safe. (The first version retried only the payment call; a 40-way burst then crashed 3 sagas on `reserve` — see [runbook 05](../runbooks/05-incident-response.md).)
- *Compensate what was done.* Payment failure releases the reservation; out-of-stock has nothing to release and never reaches payments.
- *orders-api stays the single writer of order state:* the saga PATCHes status through an internal endpoint rather than writing Firestore itself.

**Trade-off:** Workflows adds a control-plane dependency and per-step cost (cents at this scale), and the YAML DSL is less expressive than code.
