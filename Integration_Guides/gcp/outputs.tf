output "project_id" {
  value = var.project_id
}

output "topic" {
  value = google_pubsub_topic.topic.name
}

output "subscription" {
  value = google_pubsub_subscription.subscription.name
}

output "serviceAccount_email" {
  value = google_service_account.reader_sa.email
}