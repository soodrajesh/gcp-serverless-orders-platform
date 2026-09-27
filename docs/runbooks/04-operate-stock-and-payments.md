# 04 · Operate stock & payments

The internal services are IAM-only; call them with your own identity token (project owners/`run.invoker` holders):
```bash
OPT=$(gcloud auth print-identity-token)
INV=$(terraform -chdir=terraform output -raw inventory_url); PAY=$(terraform -chdir=terraform output -raw payments_url)

curl -s -X PUT $INV/stock/WIDGET -H "Authorization: Bearer $OPT" -H 'Content-Type: application/json' -d '{"qty": 1000}'   # seed / set
curl -s $INV/stock/WIDGET -H "Authorization: Bearer $OPT"                                                                 # read
curl -s $PAY/payments/<order_id> -H "Authorization: Bearer $OPT"                                                          # {state, attempts, amount}
```
*Captured:* the flaky-customer order shows `state: CHARGED, attempts: 2` (the first attempt returned 503; Workflows retried). An order that was declined has `state: DECLINED`; an out-of-stock order has **no** payment document (404) because payments was never called.

**Manual stock correction after an incident:** set the quantity with the `PUT` above; reservations for in-flight orders are separate documents and are not affected.

**Payment rules (demo):** amount > 1000 → `402 DECLINED`; customer containing `flaky` → first attempt `503`.
