#!/usr/bin/env bash
# Race N orders against S units of stock and prove: no overselling, no crashed sagas.
#   ./scripts/stress.sh [orders=120] [stock=60]
source "$(dirname "$0")/lib.sh"; set +e
N="${1:-120}"; STOCK="${2:-60}"; TMP="$ROOT/.test-tmp"; mkdir -p "$TMP"
out() { $TF output -raw "$1"; }
GW="$(out gateway_host)"; INV="$(out inventory_url)"; CLIENT="$(out client_sa)"; OPT="$(gcloud auth print-identity-token 2>/dev/null | tail -1)"
NOW=$(date +%s)
python3 -c "import json; print(json.dumps({'iss':'$CLIENT','sub':'$CLIENT','aud':'sop-orders-api','iat':$NOW,'exp':$NOW+3000}))" > "$TMP/stress-claims.json"
gcloud iam service-accounts sign-jwt "$TMP/stress-claims.json" "$TMP/stress.jwt" --iam-account="$CLIENT" --project "$PROJECT_ID" >/dev/null 2>&1
SKU="STRESS$NOW"
curl -s -X PUT "$INV/stock/$SKU" -H "Authorization: Bearer $OPT" -H 'Content-Type: application/json' -d "{\"qty\": $STOCK}" >/dev/null
echo "\$ loadtest: $N concurrent orders for $STOCK units of $SKU"
python3 "$ROOT/scripts/loadtest.py" "$GW" "$(cat "$TMP/stress.jwt")" "$SKU" "$N"
echo "\$ final stock of $SKU: $(curl -s "$INV/stock/$SKU" -H "Authorization: Bearer $OPT")"
echo "\$ saga executions by state:"; gcloud workflows executions list order-saga --location "$REGION" --project "$PROJECT_ID" --limit 1000 --format='value(state)' | sort | uniq -c
