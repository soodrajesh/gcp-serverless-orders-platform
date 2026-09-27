# 06 · Change the saga

The whole flow is [`workflows/order-saga.yaml`](../../workflows/order-saga.yaml). To add a step (e.g. fraud check between reserve and charge):
1. Add the service call with `call: send` (it is idempotent + retried) **before** `charge`.
2. Decide its failure semantics: a business "no" → compensate what was done so far and mark `FAILED` with a new `reason`; a transient error → let `send` retry.
3. Add the compensation for every step that changes state (release stock, refund, …). Compensations must be idempotent.
4. Add a case to `scripts/test.sh` (and, if it can race, to `scripts/stress.sh`).
5. `./scripts/up.sh` (in-place update of the workflow; ~1 min). Running executions finish on the old definition.

**YAML gotchas hit here:** expressions inside flow mappings must be quoted (`{order_id: '${order_id}'}`); a string containing `: ` must be single-quoted around the `${…}` expression; `retry` is a sibling of `try`/`except`, not a child of the call.
