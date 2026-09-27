# Public edge: API Gateway validates a signed JWT (issued for sop-client), then calls orders-api with its own identity.
resource "google_api_gateway_api" "orders" {
  provider     = google-beta
  project      = var.project_id
  api_id       = "orders-${random_id.db.hex}"
  display_name = "Orders API"
  depends_on   = [google_project_service.apis]
}

resource "google_api_gateway_api_config" "orders" {
  count         = var.image == "" ? 0 : 1
  provider      = google-beta
  project       = var.project_id
  api           = google_api_gateway_api.orders.api_id
  api_config_id = "cfg-${substr(sha1(local.openapi), 0, 8)}"

  openapi_documents {
    document {
      path     = "openapi.yaml"
      contents = base64encode(local.openapi)
    }
  }
  gateway_config {
    backend_config {
      google_service_account = google_service_account.sa["sop-gateway"].email
    }
  }
  lifecycle {
    create_before_destroy = true
  }
}

locals {
  openapi = var.image == "" ? "" : templatefile("${path.module}/../api/openapi.yaml.tftpl", {
    orders_url = local.svc_url["orders"]
    client_sa  = local.sa_email["sop-client"]
    audience   = "sop-orders-api"
  })
}

resource "google_api_gateway_gateway" "orders" {
  count      = var.image == "" ? 0 : 1
  provider   = google-beta
  project    = var.project_id
  region     = var.region
  api_config = google_api_gateway_api_config.orders[0].id
  gateway_id = "orders-${random_id.db.hex}"
  depends_on = [google_project_service.gateway_managed]
}

# The API's managed service only exists once a config is deployed, and must be enabled before the gateway is created.
resource "google_project_service" "gateway_managed" {
  count              = var.image == "" ? 0 : 1
  project            = var.project_id
  service            = google_api_gateway_api.orders.managed_service
  disable_on_destroy = false
  depends_on         = [google_api_gateway_api_config.orders]
}
