variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "GKE zone within the selected region."
  type        = string
  default     = "europe-west1-b"
}

variable "name" {
  description = "Prefix for infrastructure resource names."
  type        = string
  default     = "python-platform"
}

variable "admin_cidr" {
  description = "Developer public IPv4 address with a /32 prefix."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && endswith(var.admin_cidr, "/32")
    error_message = "Use one public IPv4 address in the form x.x.x.x/32."
  }
}
