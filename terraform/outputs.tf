output "artifact_repo" { value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}" }
output "build_bucket" { value = google_storage_bucket.build.name }
output "build_sa" { value = local.sa_email["sop-build"] }
output "client_sa" { value = local.sa_email["sop-client"] }
output "firestore_db" { value = google_firestore_database.db.name }
output "gateway_host" { value = var.image == "" ? "" : google_api_gateway_gateway.orders[0].default_hostname }
output "orders_url" { value = var.image == "" ? "" : local.svc_url["orders"] }
output "inventory_url" { value = var.image == "" ? "" : local.svc_url["inventory"] }
output "payments_url" { value = var.image == "" ? "" : local.svc_url["payments"] }
