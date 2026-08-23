output "event_hub_primary_connection_string" {
  value       = azurerm_eventhub_authorization_rule.logstash.primary_connection_string
  description = "EventHub primary connection string (listen-only)"
  sensitive   = true
}

output "event_hub_secondary_connection_string" {
  value       = azurerm_eventhub_authorization_rule.logstash.secondary_connection_string
  description = "EventHub secondary connection string (listen-only)"
  sensitive   = true
}

output "ak-sender" {
  value       = azurerm_eventhub_authorization_rule.ak-sender.id
  description = "Event Hub Auth ID"
}

output "logstash" {
    value       = azurerm_eventhub_authorization_rule.logstash.id
  description = "Event Hub Auth ID - logstash"
}

output "even_hub_name" {
  value       = azurerm_eventhub.akcdreventhub.name
  description = "Event Hub Name"
}