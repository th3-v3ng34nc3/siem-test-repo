provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "enable_apis" {
  for_each = toset([
    "pubsub.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com"
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# Create Pub/Sub topic
resource "google_pubsub_topic" "topic" {
  name = var.pubsub_topic_name

  depends_on = [
    google_project_service.enable_apis["pubsub.googleapis.com"]
  ]
}

# Create Pub/Sub subscription
resource "google_pubsub_subscription" "subscription" {
  name  = var.subscription_name
  topic = google_pubsub_topic.topic.name

  ack_deadline_seconds         = var.ack_deadline_seconds
  retain_acked_messages        = var.retain_acked_messages
  message_retention_duration   = var.message_retention_duration
  enable_message_ordering      = var.enable_message_ordering
  enable_exactly_once_delivery = var.enable_exactly_once_delivery

  expiration_policy {
    ttl = var.expiration_policy_ttl
  }

  depends_on = [
    google_pubsub_topic.topic
  ]
}

# Create service account
resource "google_service_account" "reader_sa" {
  account_id   = var.service_account_id
  display_name = "Service account to read Pub/Sub messages"

  depends_on = [
    google_project_service.enable_apis["iam.googleapis.com"]
  ]
}


# Give Pub/Sub subscriber role to service account
resource "google_project_iam_member" "pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.reader_sa.email}"
}

# Create sink to export audit logs to Pub/Sub

locals {
  projects_sorted = sort(var.projects)

  # Build each predicate as a list item:
  # ["resource.labels.project_id=\"p1\"", "resource.labels.project_id=\"p2\""]
  project_predicates = formatlist(
    "resource.labels.project_id=\"%s\"",
    local.projects_sorted
  )

  # Join predicates with OR -> "resource.labels.project_id=\"p1\" OR resource.labels.project_id=\"p2\""
  project_clause = join(" OR ", local.project_predicates)

  # Use concat() to assemble ["(", "<clause>", ")"] then join to a string
  filter = join("", concat(["("], [local.project_clause], [")"]))
}


resource "google_logging_organization_sink" "audit_sink" {
  name             = var.sink_name
  org_id           = var.org_id
  destination      = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.topic.name}"
  include_children = true

  filter = local.filter
  depends_on = [
    google_project_service.enable_apis["logging.googleapis.com"]
  ]
}

# resource "google_logging_project_sink" "audit_sink" {
#   name                   = var.sink_name
#   destination            = "pubsub.googleapis.com/projects/${var.project_id}/topics/${google_pubsub_topic.topic.name}"
#   unique_writer_identity = true

#   depends_on = [
#     google_project_service.enable_apis["logging.googleapis.com"]
#   ]
# }

# Allow the sink writer to publish to Pub/Sub
resource "google_pubsub_topic_iam_member" "allow_sink_publish" {
  topic  = google_pubsub_topic.topic.name
  role   = "roles/pubsub.publisher"
  member = google_logging_organization_sink.audit_sink.writer_identity

  depends_on = [
    google_logging_organization_sink.audit_sink
  ]
}
