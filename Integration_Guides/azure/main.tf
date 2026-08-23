data "azurerm_client_config" "current" {}

resource "random_string" "random" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_resource_group" "resourcegroup" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_eventhub_namespace" "eventhubnamespace" {
  name                          = local.event_hub_namespace_name
  location                      = var.location
  resource_group_name           = azurerm_resource_group.resourcegroup.name
  sku                           = var.event_hub_namespace_sku
  capacity                      = var.event_hub_namespace_capacity
  auto_inflate_enabled          = var.event_hub_namespace_autoinflate
  public_network_access_enabled = true
}

resource "azurerm_eventhub" "akcdreventhub" {
  name              = local.event_hub_name
  namespace_id      = azurerm_eventhub_namespace.eventhubnamespace.id
  partition_count   = var.event_hub_partition_count
  message_retention = var.event_hub_message_retention
}

resource "azurerm_eventhub_authorization_rule" "logstash" {
  name                = "${local.authorization_rule_name}-listen"
  namespace_name      = azurerm_eventhub_namespace.eventhubnamespace.name
  eventhub_name       = azurerm_eventhub.akcdreventhub.name
  resource_group_name = azurerm_resource_group.resourcegroup.name
  listen              = true
  send                = false
  manage              = false
}

resource "azurerm_eventhub_authorization_rule" "ak-sender" {
  name                = "${local.authorization_rule_name}-ak-sender"
  namespace_name      = azurerm_eventhub_namespace.eventhubnamespace.name
  eventhub_name       = azurerm_eventhub.akcdreventhub.name
  resource_group_name = azurerm_resource_group.resourcegroup.name
  listen              = false
  send                = true
  manage              = false
}

resource "azurerm_eventhub_namespace_authorization_rule" "activity_logs" {
  name                = "${local.authorization_rule_name}-activity_logs"
  namespace_name      = azurerm_eventhub_namespace.eventhubnamespace.name
  resource_group_name = azurerm_resource_group.resourcegroup.name
  listen              = false
  send                = true
  manage              = false
}

resource "azurerm_monitor_diagnostic_setting" "diagnostics" {
  name                           = azurerm_eventhub_namespace.eventhubnamespace.name
  target_resource_id             = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  eventhub_name                  = azurerm_eventhub.akcdreventhub.name
  eventhub_authorization_rule_id = azurerm_eventhub_namespace_authorization_rule.activity_logs.id
  dynamic "enabled_log" {
    for_each = [
      "Administrative",
      "Security",
      "ServiceHealth",
      "Alert",
      "Recommendation",
      "Policy",
      "Autoscale",
      "ResourceHealth"
    ]
    content {
      category = enabled_log.value
    }
  }
}
