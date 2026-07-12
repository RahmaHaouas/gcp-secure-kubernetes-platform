output "gke_node_sa_email" {
  value = google_service_account.gke_node.email
}