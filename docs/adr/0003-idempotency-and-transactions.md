# ADR 0003 — Idempotent create, transactional stock

**Status:** accepted

- **Create is idempotent.** `Idempotency-Key` is mandatory; the order id is `uuid5(key)`. A client retry (timeout, double click) hits `create()` on the same document, gets `AlreadyExists`, and receives the existing order with **200** instead of **202** — and does **not** publish a second event. Proven: same key twice → same id, stock decremented once.
- **Stock is reserved in a Firestore transaction** that also records a per-order reservation. Replaying a reserve for the same order is a no-op; a release only returns stock for a reservation that is still `RESERVED`. Under contention Firestore retries the transaction, so stock cannot go negative. Proven: **40 concurrent orders for 25 units → exactly 25 confirmed, 15 `OUT_OF_STOCK`, stock exactly 0.**
- **Payments are idempotent per order**, so a Workflows retry after a lost response cannot double-charge.

**Trade-off:** Pub/Sub delivers at least once, so a saga may start twice; the first step reads the order and exits if it is no longer `PENDING`.
