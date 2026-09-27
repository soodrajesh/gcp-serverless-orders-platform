resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Orders platform alerts"
  type         = "email"
  labels       = { email_address = var.alert_email }
  depends_on   = [google_project_service.apis]
}

resource "google_monitoring_alert_policy" "saga_failed" {
  project      = var.project_id
  display_name = "Orders: saga execution FAILED (unexpected, not a business decline)"
  combiner     = "OR"
  conditions {
    display_name = "any failed workflow execution"
    condition_threshold {
      filter          = "metric.type=\"workflows.googleapis.com/finished_execution_count\" AND resource.type=\"workflows.googleapis.com/Workflow\" AND metric.label.status=\"FAILED\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
  documentation {
    content   = "A saga crashed instead of completing or compensating. Runbook: docs/runbooks/05-incident-response.md"
    mime_type = "text/markdown"
  }
}

resource "google_monitoring_alert_policy" "api_5xx" {
  project      = var.project_id
  display_name = "Orders: API 5xx rate"
  combiner     = "OR"
  conditions {
    display_name = "orders 5xx > 5 in 5 min"
    condition_threshold {
      filter          = "metric.type=\"run.googleapis.com/request_count\" AND resource.type=\"cloud_run_revision\" AND resource.label.service_name=\"orders\" AND metric.label.response_code_class=\"5xx\""
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
}

resource "google_monitoring_dashboard" "main" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "Serverless orders platform"
    mosaicLayout = {
      columns = 12
      tiles = [
        { width = 6, height = 4, widget = { title = "Saga executions by status (5 min)", xyChart = { dataSets = [{ plotType = "STACKED_BAR", timeSeriesQuery = { timeSeriesFilter = { filter = "metric.type=\"workflows.googleapis.com/finished_execution_count\" resource.type=\"workflows.googleapis.com/Workflow\"", aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_SUM", groupByFields = ["metric.label.status"], crossSeriesReducer = "REDUCE_SUM" } } } }] } } },
        { xPos = 6, width = 6, height = 4, widget = { title = "Requests by service (per min)", xyChart = { dataSets = [{ plotType = "LINE", timeSeriesQuery = { timeSeriesFilter = { filter = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\"", aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE", groupByFields = ["resource.label.service_name"], crossSeriesReducer = "REDUCE_SUM" } } } }] } } },
        { yPos = 4, width = 6, height = 4, widget = { title = "Request latency p95 (ms)", xyChart = { dataSets = [{ plotType = "LINE", timeSeriesQuery = { timeSeriesFilter = { filter = "metric.type=\"run.googleapis.com/request_latencies\" resource.type=\"cloud_run_revision\"", aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_PERCENTILE_95", groupByFields = ["resource.label.service_name"], crossSeriesReducer = "REDUCE_MAX" } } } }] } } },
        { xPos = 6, yPos = 4, width = 6, height = 4, widget = { title = "Firestore reads + writes (per min)", xyChart = { dataSets = [{ plotType = "LINE", timeSeriesQuery = { timeSeriesFilter = { filter = "metric.type=\"firestore.googleapis.com/document/write_count\" resource.type=\"firestore_instance\"", aggregation = { alignmentPeriod = "60s", perSeriesAligner = "ALIGN_RATE" } } } }] } } },
      ]
    }
  })
  depends_on = [google_project_service.apis]
}

resource "google_billing_budget" "this" {
  billing_account = var.billing_account_id
  display_name    = "serverless-orders-platform"
  amount {
    specified_amount {
      currency_code = "EUR"
      units         = tostring(var.budget_amount)
    }
  }
  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }
  threshold_rules { threshold_percent = 0.5 }
  threshold_rules { threshold_percent = 1.0 }
  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.email.id]
    disable_default_iam_recipients   = true
  }
  depends_on = [google_project_service.apis]
}
