#!/usr/bin/env bash
# Build the whole platform end to end, then prove it works:
#   state bucket -> Firestore/Pub/Sub/IAM/monitoring -> image build -> Cloud Run x3 + Workflows + Eventarc + API Gateway -> seed -> live tests.
# Two Terraform phases: the services, workflow and gateway need the image digest / service URLs.
source "$(dirname "$0")/lib.sh"
PLAN_ONLY=0; SKIP_TESTS=0
for a in "$@"; do case "$a" in --plan) PLAN_ONLY=1;; --skip-tests) SKIP_TESTS=1;; esac; done
need gcloud; need terraform; need curl; need python3

log "Project $PROJECT_ID · $REGION · billing $BILLING_ACCOUNT_ID · admin $ADMIN_EMAIL"
log "1/6 Terraform state bucket"
"$ROOT/scripts/bootstrap.sh" "$PROJECT_ID" "$REGION" >/dev/null && ok "gs://$STATE_BUCKET"
tf_init
[ "$PLAN_ONLY" = 1 ] && { $TF plan -input=false; exit 0; }

log "2/6 Phase 1: Firestore, Pub/Sub, IAM, monitoring, registry"
# Re-runs must not tear down phase-2 resources (gateway = ~10 min to rebuild): keep the previous image during phase 1.
if [ -s "$ROOT/.last-image" ]; then TF_VAR_image="$(cat "$ROOT/.last-image")"; export TF_VAR_image; fi
$TF apply -input=false -auto-approve
out() { $TF output -raw "$1"; }
REPO="$(out artifact_repo)"; BUCKET="$(out build_bucket)"; BUILD_SA="$(out build_sa)"

log "3/6 Build the image (Cloud Build, dedicated least-privilege SA)"
TAG="v$(date +%y%m%d-%H%M%S)"
gcloud builds submit --project "$PROJECT_ID" --region "$REGION" --config cloudbuild.yaml \
  --service-account "projects/$PROJECT_ID/serviceAccounts/$BUILD_SA" \
  --gcs-source-staging-dir "gs://$BUCKET/src" --substitutions "_REPO=$REPO,_TAG=$TAG" .
DIGEST="$(gcloud artifacts docker images describe "$REPO/orders:$TAG" --format='get(image_summary.digest)')"
IMG="$REPO/orders@$DIGEST"; ok "image $IMG"; echo "$IMG" > "$ROOT/.last-image"

log "4/6 Phase 2: Cloud Run x3, Workflows saga, Eventarc trigger, API Gateway (gateway takes a few minutes)"
export TF_VAR_image="$IMG"
$TF apply -input=false -auto-approve
ok "applied"

log "5/6 Seed stock"
INV="$(out inventory_url)"
wait_for "inventory answers" 120 bash -c "curl -fsS -H \"Authorization: Bearer \$(gcloud auth print-identity-token)\" $INV/health"
curl -fsS -X PUT "$INV/stock/WIDGET" -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
  -H 'Content-Type: application/json' -d '{"qty": 1000}' >/dev/null && ok "stock WIDGET = 1000"

if [ "$SKIP_TESTS" = 1 ]; then log "Skipping tests"; else log "6/6 Live test suite"; "$ROOT/scripts/test.sh"; fi
log "DONE — tear down with ./scripts/down.sh"
