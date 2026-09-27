# 02 · Call the API

The gateway accepts only a JWT **signed by `sop-client`** (audience `sop-orders-api`). Build one with IAM `signJwt` (needs `serviceAccountTokenCreator` on `sop-client`, which Terraform grants to the operator):

```bash
GW=$(terraform -chdir=terraform output -raw gateway_host)
CLIENT=$(terraform -chdir=terraform output -raw client_sa)
NOW=$(date +%s)
echo "{\"iss\":\"$CLIENT\",\"sub\":\"$CLIENT\",\"aud\":\"sop-orders-api\",\"iat\":$NOW,\"exp\":$((NOW+3000))}" > /tmp/claims.json
gcloud iam service-accounts sign-jwt /tmp/claims.json /tmp/client.jwt --iam-account=$CLIENT
JWT=$(cat /tmp/client.jwt)
```
**Create an order** (asynchronous; `Idempotency-Key` is required):
```bash
curl -s -X POST https://$GW/orders -H "Authorization: Bearer $JWT" -H "Idempotency-Key: $(uuidgen)" \
  -H 'Content-Type: application/json' -d '{"sku":"WIDGET","qty":2,"amount":50,"customer":"ana"}'
# 202 {"order_id":"…","status":"PENDING"}
curl -s https://$GW/orders/<order_id> -H "Authorization: Bearer $JWT"     # poll until status != PENDING
```
Retrying with the **same** `Idempotency-Key` returns the same order with `200` (no second order, no second event). *Captured:* [order-lifecycle](../evidence/order-lifecycle.txt).

**What the edge says** *(Captured — [edge-auth](../evidence/edge-auth.txt))*

| Request | Result |
|---|---|
| no token | `401 Jwt is missing` |
| Google ID token of a person | `401 Jwt issuer is not configured` |
| signed by `sop-client`, wrong audience | `403 Audiences in Jwt are not allowed` |
| valid JWT, `/internal/...` | `404` (not in the OpenAPI spec) |
| bypass the gateway, call Cloud Run directly | `403` |

Order body: `sku` (string), `qty` (integer ≥ 1), `amount` (> 0), `customer` (string). Invalid → `400` with the reason.
