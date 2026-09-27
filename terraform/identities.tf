# One identity per job to be done.
locals {
  sas = {
    "sop-orders"    = "orders-api: owns order state, publishes OrderCreated"
    "sop-inventory" = "inventory service: stock + reservations"
    "sop-payments"  = "payments service: idempotent charges"
    "sop-saga"      = "Workflows saga runner: may invoke the three services"
    "sop-trigger"   = "Eventarc: starts the saga from Pub/Sub"
    "sop-gateway"   = "API Gateway: may invoke orders-api only"
    "sop-client"    = "Demo API client: its signed JWT is what the gateway accepts"
    "sop-build"     = "Cloud Build"
  }
}

resource "google_service_account" "sa" {
  for_each     = local.sas
  project      = var.project_id
  account_id   = each.key
  display_name = each.value
  depends_on   = [google_project_service.apis]
}

locals {
  sa_email = { for k, v in google_service_account.sa : k => v.email }
}

# Firestore access: only the three data-owning services
resource "google_project_iam_member" "datastore" {
  for_each = toset(["sop-orders", "sop-inventory", "sop-payments"])
  project  = var.project_id
  role     = "roles/datastore.user"
  member   = "serviceAccount:${local.sa_email[each.key]}"
}

resource "google_project_iam_member" "trigger" {
  for_each = toset(["roles/workflows.invoker", "roles/eventarc.eventReceiver"])
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${local.sa_email["sop-trigger"]}"
}

resource "google_project_iam_member" "saga_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.sa_email["sop-saga"]}"
}

# ── build ──
resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "sop"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

resource "google_storage_bucket" "build" {
  project                     = var.project_id
  name                        = "${var.project_id}-sop-build"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_project_iam_member" "build_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.sa_email["sop-build"]}"
}

resource "google_artifact_registry_repository_iam_member" "build_push" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${local.sa_email["sop-build"]}"
}

resource "google_storage_bucket_iam_member" "build_src" {
  bucket = google_storage_bucket.build.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.sa_email["sop-build"]}"
}

# operator may mint tokens as the demo client (what a real API consumer would present)
resource "google_service_account_iam_member" "operator_client" {
  service_account_id = google_service_account.sa["sop-client"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.admin_email}"
}

resource "google_project_iam_member" "operator" {
  for_each = toset(["roles/run.developer", "roles/workflows.viewer"])
  project  = var.project_id
  role     = each.value
  member   = "user:${var.admin_email}"
}
