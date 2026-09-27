# One image, three services (SERVICE selects the app). Separate services = separate identities and IAM boundaries.
locals {
  services = {
    orders    = { sa = "sop-orders", app = "app.orders:app" }
    inventory = { sa = "sop-inventory", app = "app.inventory:app" }
    payments  = { sa = "sop-payments", app = "app.payments:app" }
  }
}

resource "google_cloud_run_v2_service" "svc" {
  for_each            = var.image == "" ? {} : local.services
  project             = var.project_id
  name                = each.key
  location            = var.region
  deletion_protection = false

  template {
    service_account = local.sa_email[each.value.sa]
    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }
    containers {
      image   = var.image
      command = ["gunicorn"]
      args    = ["--bind=:8080", "--workers=1", "--threads=8", "--timeout=30", each.value.app]
      env {
        name  = "FIRESTORE_DB"
        value = google_firestore_database.db.name
      }
      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }
      env {
        name  = "TOPIC"
        value = google_pubsub_topic.order_events.id
      }
      resources {
        limits = { cpu = "1", memory = "512Mi" }
      }
    }
  }
  depends_on = [google_project_iam_member.datastore, google_pubsub_topic_iam_member.orders_publish]
}

locals {
  svc_url = { for k, v in google_cloud_run_v2_service.svc : k => v.uri }
}

# who may call what: no allUsers anywhere
locals {
  invokers = var.image == "" ? {} : {
    orders-gateway = { svc = "orders", sa = "sop-gateway" }
    orders-saga    = { svc = "orders", sa = "sop-saga" }
    inventory-saga = { svc = "inventory", sa = "sop-saga" }
    payments-saga  = { svc = "payments", sa = "sop-saga" }
  }
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = local.invokers
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.svc[each.value.svc].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.sa_email[each.value.sa]}"
}
