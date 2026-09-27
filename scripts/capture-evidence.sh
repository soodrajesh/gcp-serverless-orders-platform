#!/usr/bin/env bash
# Re-captures docs/evidence/*.txt from the LIVE platform (run after up.sh).
# Render: python3 docs/diagrams/termshot.py "<title>" docs/evidence/<f>.txt docs/img/<f>.png
source "$(dirname "$0")/lib.sh"; set +e
E="$ROOT/docs/evidence"; TMP="$ROOT/.test-tmp"; mkdir -p "$E" "$TMP"; P="$PROJECT_ID"
out() { $TF output -raw "$1"; }
GW="$(out gateway_host)"; INV="$(out inventory_url)"; PAY="$(out payments_url)"; CLIENT="$(out client_sa)"
OPT="$(gcloud auth print-identity-token 2>/dev/null | tail -1)"
jwt() { local now; now=$(date +%s)
  python3 -c "import json; print(json.dumps({'iss':'$CLIENT','sub':'$CLIENT','aud':'${1:-sop-orders-api}','iat':$now,'exp':$now+3000}))" > "$TMP/c.json"
  gcloud iam service-accounts sign-jwt "$TMP/c.json" "$TMP/c.jwt" --iam-account="$CLIENT" --project "$P" >/dev/null 2>&1; cat "$TMP/c.jwt"; }
show() { echo "\$ $1"; shift; "$@" 2>&1; echo; }
J="$(jwt)"; RUN=$(date +%s)

{ echo "# API Gateway: who gets in (host $GW)"; echo
  echo "\$ curl -i .../orders/x                                    # no token"
  curl -s -i -m 20 "https://$GW/orders/x" | tr -d '\r' | sed -n '1p;$p'; echo; echo
  echo "\$ curl .../orders/x -H 'Authorization: Bearer <Google ID token of the operator>'"
  curl -s -m 20 -w ' [HTTP %{http_code}]\n' "https://$GW/orders/x" -H "Authorization: Bearer $OPT"; echo
  echo "\$ curl .../orders/x -H 'Authorization: Bearer <JWT signed by sop-client, aud=other-audience>'"
  curl -s -m 20 -w ' [HTTP %{http_code}]\n' "https://$GW/orders/x" -H "Authorization: Bearer $(jwt other-audience)"; echo
  echo "\$ curl .../internal/orders/x -H 'Authorization: Bearer <valid client JWT>'   # not in the OpenAPI spec"
  curl -s -m 20 -o /dev/null -w '[HTTP %{http_code}]\n' "https://$GW/internal/orders/x" -H "Authorization: Bearer $J"; echo
  ORD="$(out orders_url)"
  echo "\$ curl -X POST <orders-api Cloud Run URL>/orders            # bypassing the gateway"
  curl -s -m 20 -o /dev/null -w '[HTTP %{http_code}]\n' -X POST "$ORD/orders"
} > "$E/edge-auth.txt"

mk() { curl -s -m 30 -X POST "https://$GW/orders" -H "Authorization: Bearer $(jwt)" -H "Idempotency-Key: $1" -H 'Content-Type: application/json' -d "$2"; }
poll() { for _ in $(seq 1 40); do r=$(curl -s -m 20 "https://$GW/orders/$1" -H "Authorization: Bearer $(jwt)"); grep -q '"PENDING"' <<<"$r" || break; sleep 2; done
  python3 -c "import sys,json; d=json.loads(sys.argv[1]); print(json.dumps({k:d[k] for k in ('order_id','sku','qty','amount','customer','status','reason') if k in d}))" "$r"; }
curl -s -X PUT "$INV/stock/DEMO" -H "Authorization: Bearer $OPT" -H 'Content-Type: application/json' -d '{"qty": 10}' >/dev/null
{ echo "# Three orders through the saga (stock DEMO = 10)"; echo
  echo "\$ POST /orders  {sku: DEMO, qty: 2, amount: 50, customer: ana}"; A=$(mk "ev-a-$RUN" '{"sku":"DEMO","qty":2,"amount":50,"customer":"ana"}'); echo "$A"; AID=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['order_id'])" "$A")
  echo "\$ GET /orders/\$id  (polled until the saga finishes)"; poll "$AID"; echo
  echo "\$ POST /orders  {sku: DEMO, qty: 3, amount: 5000, customer: ana}   # over the 1000 limit"; B=$(mk "ev-b-$RUN" '{"sku":"DEMO","qty":3,"amount":5000,"customer":"ana"}'); echo "$B"; BID=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['order_id'])" "$B")
  echo "\$ GET /orders/\$id"; poll "$BID"
  echo "\$ stock DEMO after both (10 - 2 = 8; the declined order's 3 units were released):"; curl -s "$INV/stock/DEMO" -H "Authorization: Bearer $OPT"; echo; echo
  echo "\$ POST /orders  {sku: DEMO, qty: 999, amount: 10, customer: ana}"; C=$(mk "ev-c-$RUN" '{"sku":"DEMO","qty":999,"amount":10,"customer":"ana"}'); echo "$C"; CID=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['order_id'])" "$C")
  echo "\$ GET /orders/\$id"; poll "$CID"
  echo "\$ POST the first order again with the same Idempotency-Key"; mk "ev-a-$RUN" '{"sku":"DEMO","qty":2,"amount":50,"customer":"ana"}' | python3 -c "import sys,json; d=json.load(sys.stdin); print('same order id returned:', d['order_id']=='$AID', '| status', d['status'])"
} > "$E/order-lifecycle.txt"

{ echo "\$ gcloud workflows executions list order-saga --limit 5   # STATE per run ('result' is only shown by describe)"
  gcloud workflows executions list order-saga --location "$REGION" --project "$P" --limit 5 --format='table(name.basename():label=EXECUTION,state,duration)' 2>&1; echo
  echo "\$ for every execution: gcloud workflows executions describe <id> --format='value(result)' | sort | uniq -c   # the saga's own verdicts"
  gcloud workflows executions list order-saga --location "$REGION" --project "$P" --limit 1000 --format='value(name.basename())' \
    | xargs -P 8 -I{} gcloud workflows executions describe {} --workflow order-saga --location "$REGION" --project "$P" --format='value(result)' 2>&1 | sort | uniq -c | sort -rn; echo
  echo "\$ executions by state"; gcloud workflows executions list order-saga --location "$REGION" --project "$P" --limit 1000 --format='value(state)' | sort | uniq -c
} > "$E/saga-executions.txt"

"$ROOT/scripts/stress.sh" 120 60 > "$E/stress.txt" 2>&1

{ show "gcloud run services list" gcloud run services list --project "$P" --format='table(metadata.name:label=SERVICE,status.url:label=URL)'
  show "gcloud api-gateway gateways list" gcloud api-gateway gateways list --location "$REGION" --project "$P" --format='table(name.basename():label=GATEWAY,defaultHostname,state)'
  show "gcloud workflows describe order-saga" gcloud workflows describe order-saga --location "$REGION" --project "$P" --format='yaml(name.basename(),state,serviceAccount.basename())'
  show "gcloud eventarc triggers list" gcloud eventarc triggers list --location "$REGION" --project "$P" --format='table(name.basename():label=TRIGGER,destination.workflow.basename():label=WORKFLOW,transport.pubsub.topic.basename():label=TOPIC)'
} > "$E/topology.txt"
ok "evidence written to docs/evidence/"
