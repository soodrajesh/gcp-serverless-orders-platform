# 05 · Incident response

| Alert / symptom | First look | Likely cause / action |
|---|---|---|
| **Saga execution FAILED** (means a crash, not a decline) | `gcloud workflows executions list order-saga --filter='state=FAILED' --location $REGION`, then `executions describe` → `error.context` names the step | A service returned a non-retryable error or kept failing after 5 retries. Fix the service, then re-drive the affected orders (below) |
| **API 5xx rate** | `gcloud run services logs read orders --region $REGION --limit 50` | Firestore/Pub/Sub permission lost, bad revision → `gcloud run services update-traffic orders --to-revisions=<prev>=100` |
| Orders stuck `PENDING` | Is there an execution for it? | Eventarc trigger or Pub/Sub problem: `gcloud eventarc triggers describe order-created-to-saga --location $REGION` |
| Clients get 401/403 | [runbook 02](02-call-the-api.md) table | Expired JWT (`exp`), wrong audience/issuer |
| Oversold stock | shouldn't be possible | Reservations are transactional; compare `stock` with `reservations` documents |

**Re-drive a stuck order** (by design the saga exits early on non-`PENDING` orders and every call is idempotent; *this exact command was not exercised live*): republish its event —
```bash
gcloud pubsub topics publish order-events --message='{"order_id":"<id>"}'
```
*Real incident from this build:* under a 40-way burst, 3 executions crashed on `reserve` with HTTP 500 (Firestore transaction contention on one hot stock document; the saga had no retry on that step). Fix: inventory maps contention to a retryable 503, and **every** saga call retries 429/500/502/503/504 with backoff. After the fix, 120 concurrent orders for 60 units → 60 confirmed, 60 out-of-stock, 0 crashed ([stress evidence](../evidence/stress.txt)).
