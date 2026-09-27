# 08 · Troubleshooting — problems actually hit while building this

| # | Symptom | Cause | Fix |
|---|---|---|---|
| O1 | Terraform: *Enable Project Service … cloud.goog … not found* | The API Gateway managed service exists only after an API config is deployed | Enable it *after* the config, before the gateway (`depends_on`) |
| O2 | `Cannot convert to service config … mapping values are not allowed here` | An OpenAPI `summary` containing `: ` | Quote it |
| O3 | Workflows: *Unterminated expression … wrap with single quotes* | `${…}` in a plain scalar with `: `, or unquoted inside a flow mapping | Single-quote the expression |
| O4 | Workflows: *unexpected entry 'retry'* | `retry` nested inside the call | Make it a sibling of `try` / `except` |
| O5 | `/healthz` returned Google's 404 page | Cloud Run reserves `/healthz` at its frontend | Use `/health` |
| O6 | Gateway returned `401 Jwt issuer is not configured` for a valid Google ID token | ID tokens have `iss: accounts.google.com`, not the SA | Sign a JWT *as* the SA with `signJwt` ([ADR 0002](../adr/0002-signed-jwt-at-the-gateway.md)) |
| O7 | Every negative auth test passed while the valid request also failed | "Wrong audience → 401" passed because *everything* was 401 | Always assert the positive case, and assert the rejection *reason* |
| O8 | Wrong audience gave 403, not 401 | The gateway distinguishes bad audience (403) from bad token (401) | Assert what the system does |
| O9 | 3 sagas crashed under a 40-way burst | Firestore contention → HTTP 500 on `reserve`, no retry there | See [runbook 05](05-incident-response.md) |
| O10 | Re-running `up.sh` rebuilt the gateway (~10 min) every time | Phase 1 ran with an empty image, destroying the count-gated phase-2 resources | Phase 1 reuses `.last-image` |
| O11 | `terraform destroy`: *cannot destroy workflow without deletion_protection=false* | Workflows default to protected | `deletion_protection = false`; `down.sh` unprotects first |
| O12 | `bq`/`gcloud` output formats used in assertions drifted | Text formats are not contracts | Assert exit codes and parsed JSON |
