#!/usr/bin/env bash
# Delete everything this repo created, end to end.
#   ./scripts/down.sh            destroy the platform (keeps the tiny shared Terraform state bucket)
#   ./scripts/down.sh --purge    also delete this repo's Terraform state (and the bucket if now empty)
source "$(dirname "$0")/lib.sh"
need gcloud; need terraform
PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1

log "Project $PROJECT_ID — destroying everything managed by this repo"
tf_init
TF_VAR_image="$(cat "$ROOT/.last-image" 2>/dev/null || echo "")"; export TF_VAR_image
# a workflow created with deletion protection (older state) must be unprotected before it can be destroyed
$TF apply -input=false -auto-approve -target=google_workflows_workflow.saga >/dev/null 2>&1 || true
log "1/2 Terraform destroy (gateway, trigger, workflow, Cloud Run, Firestore database incl. data, topic, registry, bucket)"
$TF destroy -input=false -auto-approve
ok "platform destroyed"
rm -f "$ROOT/.last-image"; rm -rf "$ROOT/.test-tmp"

if [ "$PURGE" = 1 ]; then
  log "2/2 Purging this repo's Terraform state"
  gcloud storage rm -r "gs://$STATE_BUCKET/orders-platform/" --quiet >/dev/null 2>&1 || true
  if [ -z "$(gcloud storage ls "gs://$STATE_BUCKET/" 2>/dev/null)" ]; then
    gcloud storage rm -r "gs://$STATE_BUCKET" --quiet >/dev/null 2>&1 || true; ok "state prefix and (now empty) bucket removed"
  else ok "state prefix removed; bucket kept because other stacks still use it"; fi
else log "2/2 Kept state bucket gs://$STATE_BUCKET (a few KB; --purge removes it)"; fi

log "Anything billable left?"
echo "  Cloud Run (orders/inventory/payments): $(gcloud run services list --project "$PROJECT_ID" --format='value(name)' 2>/dev/null | grep -cxE 'orders|inventory|payments' || true)"
echo "  Workflows:          $(gcloud workflows list --location "$REGION" --project "$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
echo "  API gateways:       $(gcloud api-gateway gateways list --project "$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
echo "  Eventarc triggers:  $(gcloud eventarc triggers list --location "$REGION" --project "$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
echo "  Firestore DBs (orders-*): $(gcloud firestore databases list --project "$PROJECT_ID" --format='value(name)' 2>/dev/null | grep -c '/orders-' || true)"
log "DONE"
