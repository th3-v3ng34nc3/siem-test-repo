variable "subscription_id" {
  type        = string
  description = "Azure subscription ID."
  sensitive   = true
}

variable "location" {
  type        = string
  default     = "East US"
  description = "Azure location where the resources will be created."
}

variable "resource_group_name" {
  type        = string
  default     = "accuknox-cdr"
  description = "Name of the resource group to be created."
}

variable "event_hub_namespace_prefix" {
  type        = string
  default     = "accuknox-cdr"
  description = "Name of the event hub namespace."
}

variable "event_hub_namespace_sku" {
  type        = string
  default     = "Basic"
  description = "Defines the event hub tier to be used."
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.event_hub_namespace_sku)
    error_message = "Invalid event hub tier. Must be one of `Basic`, `Standard`, `Premium`"
  }
}

variable "event_hub_namespace_capacity" {
  type        = number
  default     = 1
  description = "Capacity / throughput units"
}

variable "event_hub_namespace_autoinflate" {
  type        = bool
  default     = false
  description = "Auto-scale the throughput"
}

variable "event_hub_prefix" {
  type        = string
  default     = "default"
  description = "Name of the event hub."
}

variable "event_hub_partition_count" {
  type        = number
  default     = 1
  description = "Specifies the current number of shards on the Event Hub."
}

variable "event_hub_message_retention" {
  type        = number
  default     = 1
  description = "Specifies the number of days to retain the events for this Event Hub."
}

variable "authorization_rule_name_prefix" {
  type = string
  default = "logstash"
}
