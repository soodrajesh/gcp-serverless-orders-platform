#!/usr/bin/env bash
# Live proof against the running platform. Every check asserts something observed, not configured.
# Writes docs/test-results.md. Exit code = number of failed checks.
source "$(dirname "$0")/lib.sh"; set +e
need gcloud; need curl; need python3
PASS=0; FAIL=0; OUT="$ROOT/docs/test-results.md"; TMP="$ROOT/.test-tmp"; mkdir -p "$TMP"
{ echo "# Live test results"; echo; echo "Captured by \`scripts/test.sh\` on $(date -u +%FT%TZ) against project \`$PROJECT_ID\` ($REGION)."; echo; echo '```'; } > "$OUT"
say()   { echo "$*" | tee -a "$OUT"; }
check() { # <name> <expected-regex> <actual>
  if grep -qE -- "$2" <<<"$3"; then PASS=$((PASS+1)); say "  PASS  $1  [$(head -c 100 <<<"$3" | tr '\n' ' ')]"
  else FAIL=$((FAIL+1)); say "  FAIL  $1  (wanted /$2/, got: $(head -c 200 <<<"$3" | tr '\n' ' '))"; fi
}
check_not() { # <name> <forbidden-regex> <actual>
  if grep -qE -- "$2" <<<"$3"; then FAIL=$((FAIL+1)); say "  FAIL  $1  (found /$2/ in: $(head -c 200 <<<"$3" | tr '\n' ' '))"
  else PASS=$((PASS+1)); say "  PASS  $1  [absent: $2]"; fi
}
section() { say ""; say "── $* ──"; }

P="$PROJECT_ID"
out() { $TF output -raw "$1"; }
GW="$(out gateway_host)"; ORD="$(out orders_url)"; INV="$(out inventory_url)"; PAY="$(out payments_url)"
CLIENT="$(out client_sa)"
# The gateway trusts JWTs *signed by* sop-client (iss = the SA email, keys = the SA's public keys), not generic Google ID tokens.
jwt() { # [audience]
  local aud="${1:-sop-orders-api}" now; now=$(date +%s)
  python3 -c "import json,sys; print(json.dumps({'iss':'$CLIENT','sub':'$CLIENT','aud':'$aud','iat':$now,'exp':$now+3000}))" > "$TMP/claims.json"
  rm -f "$TMP/client.jwt"
  gcloud iam service-accounts sign-jwt "$TMP/claims.json" "$TMP/client.jwt" --iam-account="$CLIENT" --project "$P" >/dev/null 2>&1
  cat "$TMP/client.jwt" 2>/dev/null
}
opid() { gcloud auth print-identity-token 2>/dev/null | tail -1; }   # operator identity for the internal services
JWT="$(jwt)"; OPT="$(opid)"
gw()  { curl -s -m 30 -w '\n%{http_code}' "$@"; }
code(){ tail -1 <<<"$1"; }
body(){ sed '$d' <<<"$1"; }
jget(){ python3 -c "import sys,json; d=json.loads(sys.stdin.read() or '{}'); print(d.get('$1',''))"; }
order() { # <idem-key> <json>  -> raw response
  gw -X POST "https://$GW/orders" -H "Authorization: Bearer $JWT" -H "Idempotency-Key: $1" -H 'Content-Type: application/json' -d "$2"; }
wait_order() { # <order-id> <secs> -> final status JSON
  local end=$(( $(date +%s) + $2 )) r
  while :; do r=$(curl -s -m 20 "https://$GW/orders/$1" -H "Authorization: Bearer $JWT")
    [ "$(jget status <<<"$r")" != PENDING ] && [ -n "$(jget status <<<"$r")" ] && break
    [ "$(date +%s)" -lt "$end" ] || break; sleep 2; done; echo "$r"; }
stock() { curl -s -m 20 "$INV/stock/$1" -H "Authorization: Bearer $OPT" | jget qty; }
seed()  { curl -s -m 20 -X PUT "$INV/stock/$1" -H "Authorization: Bearer $OPT" -H 'Content-Type: application/json' -d "{\"qty\": $2}" >/dev/null; }
RUN="$(date +%s)"

section "1. Topology"
check "API Gateway is ACTIVE" 'ACTIVE' "$(gcloud api-gateway gateways list --location "$REGION" --project "$P" --format='value(name.basename(),state)' 2>&1)"
check "workflow order-saga is ACTIVE" 'ACTIVE' "$(gcloud workflows describe order-saga --location "$REGION" --project "$P" --format='value(state)')"
check "Eventarc trigger routes Pub/Sub -> workflow" 'order-saga' "$(gcloud eventarc triggers describe order-created-to-saga --location "$REGION" --project "$P" --format='value(destination.workflow)')"
check "three Cloud Run services deployed" 'inventory.*orders.*payments|inventory orders payments' "$(gcloud run services list --project "$P" --format='value(name)' | sort | tr '\n' ' ')"

section "2. The edge: only a signed client gets in"
r=$(gw -X POST "https://$GW/orders" -H 'Content-Type: application/json' -d '{}')
check "no token -> 401 (Jwt is missing)" '401' "$(code "$r")"; check "…reason" 'missing' "$(body "$r")"
r=$(gw "https://$GW/orders/x" -H 'Authorization: Bearer not.a.jwt')
check "garbage token -> 401" '^401$' "$(code "$r")"
r=$(gw "https://$GW/orders/x" -H "Authorization: Bearer $(jwt other-audience)")
check "valid signature but wrong audience -> 403 (Audiences in Jwt are not allowed)" '^403$' "$(code "$r")"; check "…reason" 'Audiences' "$(body "$r")"
r=$(gw "https://$GW/orders/x" -H "Authorization: Bearer $OPT")
check "a Google ID token (issuer accounts.google.com) is not the client identity -> 401" '^401$' "$(code "$r")"; check "…reason" 'issuer is not configured' "$(body "$r")"
check "internal routes are not exposed by the gateway (404)" '^404$' "$(code "$(gw "https://$GW/internal/orders/x" -H "Authorization: Bearer $JWT")")"
check "orders-api called directly without a token -> 403" '^403$' "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$ORD/orders")"
check "inventory called directly without a token -> 403" '^403$' "$(curl -s -o /dev/null -w '%{http_code}' "$INV/stock/WIDGET")"
r=$(gw "https://$GW/orders/not-a-uuid" -H "Authorization: Bearer $JWT")
check "junk order id -> 404, not a 500 from Firestore" '^404$' "$(code "$r")"
r=$(gw "https://$GW/orders/..%2Finternal%2Forders%2Fx" -H "Authorization: Bearer $JWT")
check "path-traversal attempt in the id -> 4xx, never a 5xx" '^4[0-9][0-9]$' "$(code "$r")"
r=$(order "bad-$RUN" '{"sku":"WIDGET","qty":0,"amount":5,"customer":"x"}')
check "invalid order (qty 0) -> 400 with a reason" '^400$' "$(code "$r")"
r=$(gw -X POST "https://$GW/orders" -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' -d '{"sku":"WIDGET","qty":1,"amount":5,"customer":"x"}')
check "missing Idempotency-Key -> 400" '^400$' "$(code "$r")"

section "3. Happy path: reserve -> charge -> confirm"
seed WIDGET 1000; S0=$(stock WIDGET)
r=$(order "happy-$RUN" '{"sku":"WIDGET","qty":2,"amount":50,"customer":"ana"}'); H_ID=$(jget order_id <<<"$(body "$r")")
check "POST /orders -> 202 Accepted" '^202$' "$(code "$r")"
o=$(wait_order "$H_ID" 90)
check "order reaches CONFIRMED via the saga" 'CONFIRMED' "$(jget status <<<"$o")"
check "stock decremented by exactly 2" "^$((S0-2))\$" "$(stock WIDGET)"
check "payment recorded as CHARGED on the first attempt" 'CHARGED.*1|1.*CHARGED' "$(curl -s "$PAY/payments/$H_ID" -H "Authorization: Bearer $OPT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'], d['attempts'])")"

section "4. Compensation: out of stock (nothing charged)"
r=$(order "oos-$RUN" '{"sku":"WIDGET","qty":999999,"amount":10,"customer":"ana"}'); ID=$(jget order_id <<<"$(body "$r")")
o=$(wait_order "$ID" 90)
check "order FAILED with reason OUT_OF_STOCK" 'FAILED' "$(jget status <<<"$o")"
check "…reason recorded" 'OUT_OF_STOCK' "$(jget reason <<<"$o")"
check "no payment was ever attempted" '^404$' "$(curl -s -o /dev/null -w '%{http_code}' "$PAY/payments/$ID" -H "Authorization: Bearer $OPT")"

section "5. Compensation: payment declined (stock released)"
S1=$(stock WIDGET)
r=$(order "decl-$RUN" '{"sku":"WIDGET","qty":3,"amount":5000,"customer":"ana"}'); ID=$(jget order_id <<<"$(body "$r")")
o=$(wait_order "$ID" 90)
check "order FAILED with reason PAYMENT_DECLINED" 'PAYMENT_DECLINED' "$(jget reason <<<"$o")"
check "reserved stock was released: back to $S1" "^$S1\$" "$(stock WIDGET)"

section "6. Resilience: a flaky payment provider is retried by Workflows"
r=$(order "flaky-$RUN" '{"sku":"WIDGET","qty":1,"amount":20,"customer":"flaky-fred"}'); F_ID=$(jget order_id <<<"$(body "$r")")
o=$(wait_order "$F_ID" 120)
check "order still reaches CONFIRMED" 'CONFIRMED' "$(jget status <<<"$o")"
check "payments saw 2 attempts (503 then success)" 'CHARGED 2' "$(curl -s "$PAY/payments/$F_ID" -H "Authorization: Bearer $OPT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'], d['attempts'])")"

section "7. Idempotency: a client retry cannot create a second order or double-reserve"
S2=$(stock WIDGET)
r1=$(order "idem-$RUN" '{"sku":"WIDGET","qty":1,"amount":9,"customer":"ana"}'); r2=$(order "idem-$RUN" '{"sku":"WIDGET","qty":1,"amount":9,"customer":"ana"}')
check "first call -> 202, retry -> 200" '^202 200$' "$(code "$r1") $(code "$r2")"
check "both calls return the same order id" "^$(jget order_id <<<"$(body "$r1")")\$" "$(jget order_id <<<"$(body "$r2")")"
wait_order "$(jget order_id <<<"$(body "$r1")")" 90 >/dev/null; sleep 5
check "stock decremented once, not twice" "^$((S2-1))\$" "$(stock WIDGET)"

section "8. No overselling under concurrency: 40 orders race for 25 units"
seed LOADTEST 25
lt=$(python3 "$ROOT/scripts/loadtest.py" "$GW" "$JWT" LOADTEST 40)
say "    $lt"
check "exactly 25 confirmed" '"confirmed": 25' "$lt"
check "exactly 15 failed OUT_OF_STOCK" '"failed_out_of_stock": 15' "$lt"
check "no other outcome (no timeouts, no rejects)" '"other": 0' "$lt"
check "stock ended at exactly 0 (never negative)" '^0$' "$(stock LOADTEST)"

section "9. Saga executions"
sleep 5
states=$(gcloud workflows executions list order-saga --location "$REGION" --project "$P" --limit 300 --format='value(state)' 2>/dev/null | sort | uniq -c | tr -s ' ' | tr '\n' ';')
say "    execution states: $states"
check "sagas SUCCEEDED (business failures are handled outcomes)" 'SUCCEEDED' "$states"
check_not "no saga execution crashed (FAILED)" 'FAILED' "$states"

section "10. Service security"
for pair in "orders:sop-gateway sop-saga" "inventory:sop-saga" "payments:sop-saga"; do
  svc="${pair%%:*}"; want="${pair#*:}"
  members=$(gcloud run services get-iam-policy "$svc" --region "$REGION" --project "$P" --format='value(bindings.members)' | tr -d "[]'" )
  for w in $want; do check "$svc: $w may invoke" "$w@" "$members"; done
  check_not "$svc: not public (no allUsers)" 'allUsers' "$members"
done
keys=0; for sa in sop-orders sop-inventory sop-payments sop-saga sop-trigger sop-gateway sop-client sop-build; do
  n=$(gcloud iam service-accounts keys list --iam-account "$sa@$P.iam.gserviceaccount.com" --managed-by=user --format='value(name)' 2>/dev/null | grep -c .); keys=$((keys+n)); done
check "no user-managed service-account keys exist" '^0$' "$keys"

section "11. Operability"
pol=$(gcloud monitoring policies list --project "$P" --format='value(displayName)')
check "saga-failure alert exists" 'saga execution FAILED' "$pol"
check "API 5xx alert exists" 'API 5xx' "$pol"
check "dashboard exists" 'Serverless orders platform' "$(gcloud monitoring dashboards list --project "$P" --format='value(displayName)')"

say '```'; echo >> "$OUT"; echo "**Result: $PASS passed, $FAIL failed.**" >> "$OUT"
echo; [ "$FAIL" = 0 ] && ok "$PASS/$((PASS+FAIL)) checks passed" || warn "$FAIL failed, $PASS passed"
exit "$FAIL"
