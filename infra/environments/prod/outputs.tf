output "project_id" {
  value = var.project_id
}

output "cluster_name" {
  value = module.gke.cluster_name
}

output "cluster_location" {
  value = module.gke.cluster_location
}

output "nat_ip" {
  value = module.networking.nat_ip
}

output "node_service_account_email" {
  value = module.iam.node_service_account_email
}
