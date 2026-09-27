# Threat model (STRIDE)

| Threat | Control | Proven by |
|---|---|---|
| **S**poofed API client | Gateway accepts only JWTs signed by `sop-client` for one audience; other issuers/audiences rejected | test §2 (401/403 with reasons) |
| **S**poofed internal caller | Services require IAM; only named SAs are invokers; no `allUsers` | test §2, §10 |
| **T**ampered order (double submit) | Mandatory `Idempotency-Key`; deterministic id | test §7 |
| **T**ampered stock (oversell / race) | Firestore transactions + per-order reservation | test §8 (40 vs 25 → 25/15/0) |
| **R**epudiation | One workflow execution per order with per-step logs; Cloud Trace per request | executions listed in test §9 |
| **I**nformation disclosure | `/internal/*` unreachable through the gateway; nothing public; no SA keys | test §2, §10 |
| **D**enial of service | Cloud Run max 5 instances/service; API 5xx + saga-failure alerts; budget | test §11 |
| **E**levation | Each SA scoped to its job; the saga cannot touch Firestore; the gateway cannot call inventory/payments | Terraform IAM |

**Out of scope:** end-user authentication (Identity Platform), rate limiting/quotas at the gateway (needs API keys), WAF/Cloud Armor (needs a load balancer), CMEK, multi-region.
