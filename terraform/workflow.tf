resource "google_workflows_workflow" "saga" {
  count               = var.image == "" ? 0 : 1
  project             = var.project_id
  name                = "order-saga"
  region              = var.region
  description         = "Reserve stock -> charge -> confirm, with retries and compensation"
  service_account     = google_service_account.sa["sop-saga"].id
  call_log_level      = "LOG_ERRORS_ONLY"
  deletion_protection = false
  source_contents = templatefile("${path.module}/../workflows/order-saga.yaml", {
    orders_url    = local.svc_url["orders"]
    inventory_url = local.svc_url["inventory"]
    payments_url  = local.svc_url["payments"]
  })
  depends_on = [google_project_service.apis]
}

resource "google_eventarc_trigger" "saga" {
  count           = var.image == "" ? 0 : 1
  project         = var.project_id
  name            = "order-created-to-saga"
  location        = var.region
  service_account = google_service_account.sa["sop-trigger"].email

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }
  transport {
    pubsub {
      topic = google_pubsub_topic.order_events.id
    }
  }
  destination {
    workflow = google_workflows_workflow.saga[0].id
  }
  depends_on = [google_project_iam_member.trigger]
}
