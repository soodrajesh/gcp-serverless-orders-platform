resource "google_firestore_database" "db" {
  project                 = var.project_id
  name                    = "orders-${random_id.db.hex}"
  location_id             = var.region
  type                    = "FIRESTORE_NATIVE"
  delete_protection_state = "DELETE_PROTECTION_DISABLED"
  deletion_policy         = "DELETE"
  depends_on              = [google_project_service.apis]
}

resource "google_pubsub_topic" "order_events" {
  project    = var.project_id
  name       = "order-events"
  depends_on = [google_project_service.apis]
}

resource "google_pubsub_topic_iam_member" "orders_publish" {
  project = var.project_id
  topic   = google_pubsub_topic.order_events.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${local.sa_email["sop-orders"]}"
}
