variable "account_id" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "github_client_id" {
  type = string
}

variable "github_client_secret" {
  type      = string
  sensitive = true
}
