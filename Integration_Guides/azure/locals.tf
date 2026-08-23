locals {
    event_hub_namespace_name =  "${var.event_hub_namespace_prefix}-${random_string.random.id}"
    event_hub_name = "${var.event_hub_prefix}-${random_string.random.id}"
    authorization_rule_name = "${var.authorization_rule_name_prefix}-${random_string.random.id}"
}