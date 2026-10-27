variable "project_id" {
  type = string
}

resource "google_service_account" "gke_nodes" {
  project      = var.project_id
  account_id   = "platform-gke-nodes"
  display_name = "Python platform GKE nodes"
}

resource "google_project_iam_member" "gke_nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

output "node_service_account_email" {
  value = google_service_account.gke_nodes.email
}
