resource "google_service_account" "application" {
  project      = var.project_id
  account_id   = "python-platform-app"
  display_name = "Python platform application"

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket" "application_config" {
  project                     = var.project_id
  name                        = "${var.project_id}-app-config"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  labels = {
    project    = "python-gke-platform"
    managed_by = "terraform"
    purpose    = "application-config"
  }

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket_object" "identity_check" {
  bucket       = google_storage_bucket.application_config.name
  name         = "identity-check.txt"
  content      = "Workload Identity access verified"
  content_type = "text/plain"
}

resource "google_storage_bucket_iam_member" "application_reader" {
  bucket = google_storage_bucket.application_config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.application.email}"
}

resource "google_service_account_iam_member" "application_workload_identity" {
  for_each = toset([
    "platform-staging",
    "platform-production",
  ])

  service_account_id = google_service_account.application.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.value}/python-platform-app]"

  depends_on = [module.gke]
}

output "application_service_account_email" {
  value = google_service_account.application.email
}

output "application_config_bucket" {
  value = google_storage_bucket.application_config.name
}
