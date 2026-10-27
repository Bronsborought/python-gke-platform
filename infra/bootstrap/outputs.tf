output "state_bucket_name" {
  description = "Bucket used to store Terraform state."
  value       = google_storage_bucket.terraform_state.name
}
