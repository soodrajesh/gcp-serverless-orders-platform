variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "billing_account_id" {
  type = string
}

variable "budget_amount" {
  type    = number
  default = 10
}

variable "alert_email" {
  type = string
}

variable "admin_email" {
  type = string
}

variable "image" {
  description = "Digest-pinned container image for the three services. Empty = phase 1 (infrastructure only)."
  type        = string
  default     = ""
}
