variable "project_id" {
  description = "The project ID to create resources in"
}
variable "projects" {
  description = "List of project IDs to include in the sink"
  type        = list(string)
}
variable "region" {}

variable "org_id" {
  description = "Organization ID"
  type        = string
}

variable "pubsub_topic_name" {
  default = "accuknox-siem"
}
variable "subscription_name" {
  default = "accuknox-siem-sub"
}
variable "ack_deadline_seconds" {
  default = 10
}
variable "retain_acked_messages" {
  default = false
}
variable "message_retention_duration" {
  default = "604800s" # 7 days
}
variable "enable_message_ordering" {
  default = false
}
variable "expiration_policy_ttl" {
  default = "2678400s" # 31 days
}
variable "enable_exactly_once_delivery" {
  default = true
}
variable "service_account_id" {
  default = "accuknox-cdr-pubsub-reader"
}
variable "sink_name" {
  default = "accuknox-audit-logs-to-pubsub"
}
