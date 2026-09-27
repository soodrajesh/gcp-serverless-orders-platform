# 01 · Build & teardown

```bash
gcloud config set project <project>
./scripts/up.sh            # ≈ 20 min: mostly API Gateway (config ≈ 3 min, gateway ≈ 8 min); tests ≈ 4 min
./scripts/up.sh --plan
./scripts/up.sh --skip-tests
./scripts/down.sh          # --purge also removes this repo's state
```
`up.sh` runs Terraform in **two phases**: phase 1 (Firestore, Pub/Sub, IAM, alerts, registry) → Cloud Build (dedicated SA) → phase 2 (three Cloud Run services, Workflows saga, Eventarc trigger, API Gateway) → seed stock → `scripts/test.sh`.

`down.sh` first unprotects the workflow, then destroys everything (the gateway takes ≈ 3 min to delete) and prints what is left (Cloud Run services, workflows, gateways, triggers, Firestore databases named `orders-*`: all should be `0`).
