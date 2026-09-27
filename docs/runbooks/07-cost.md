# 07 · Cost

| Item | While running |
|---|---|
| Cloud Run ×3 (`min_instance_count = 0`) | €0 idle; pennies per burst |
| API Gateway | per-call pricing, first 2 M calls/month free |
| Workflows | per step (first 5,000 internal steps free) |
| Firestore (tiny data) | inside the free tier |
| Pub/Sub, Eventarc | ≈ €0 at demo volume |
| Cloud Build, Artifact Registry | cents |

A full build–test–teardown cycle costs well under €1. A Terraform-managed budget (€10 default) emails at 50 % and 100 %. After `down.sh` the cost is €0.
