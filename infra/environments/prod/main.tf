provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  required_services = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "sts.googleapis.com",
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "networking" {
  source = "../../modules/networking"

  project_id = var.project_id
  region     = var.region
  name       = var.name

  depends_on = [google_project_service.required]
}

module "iam" {
  source = "../../modules/iam"

  project_id = var.project_id

  depends_on = [google_project_service.required]
}

module "gke" {
  source = "../../modules/gke"

  project_id                 = var.project_id
  zone                       = var.zone
  name                       = var.name
  network_id                 = module.networking.network_id
  subnetwork_id              = module.networking.subnetwork_id
  node_service_account_email = module.iam.node_service_account_email
  admin_cidr                 = var.admin_cidr

  depends_on = [
    module.networking,
    module.iam,
  ]
}
