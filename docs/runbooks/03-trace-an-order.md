# 03 · Trace an order

**When:** "what happened to order X?"

1. **State:** `GET /orders/<id>` ([runbook 02](02-call-the-api.md)) → `status` and, if failed, `reason` (`OUT_OF_STOCK`, `PAYMENT_DECLINED`, `PAYMENT_ERROR`).
2. **The saga run for it** *(Captured — [saga-executions](../evidence/saga-executions.txt))*:
```bash
gcloud workflows executions list order-saga --location $REGION --limit 10 --format='table(name.basename():label=EXECUTION,state,duration)'
gcloud workflows executions describe <execution-id> --workflow order-saga --location $REGION --format='value(result)'
```
`list` shows `STATE`; the saga's own verdict is only in `describe` → `result`: `"confirmed"`, `"failed: OUT_OF_STOCK"`, or `"failed: PAYMENT_DECLINED (stock released)"`. Across the 168 executions in this build: 89 confirmed, 77 out of stock, 2 declined — **all `SUCCEEDED`**, because business failures are handled outcomes. A `FAILED` execution is a crash and pages.
3. **Step-level detail of one execution:**
```bash
gcloud workflows executions describe <execution-id> --workflow order-saga --location $REGION
gcloud logging read 'resource.type="workflows.googleapis.com/Workflow"' --freshness 1h --limit 20
```
4. **Service side:** Cloud Run request logs per service (`gcloud run services logs read orders --region $REGION --limit 50`) and Cloud Trace (one trace per request through the gateway).
5. **Inspect the payment / stock** ([runbook 04](04-operate-stock-and-payments.md)).
