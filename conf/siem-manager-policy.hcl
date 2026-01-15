# Permission to enable/disable/list secret engines under the /siem/ prefix
path "sys/mounts/siem/*" {
  capabilities = ["create", "read", "update", "list"]
}

# Permission to list all mounts (required for UI and CLI navigation)
path "sys/mounts" {
  capabilities = ["read", "list"]
}

# Permission to create and update secrets (KV V2 uses the /data/ subpath)
path "siem/+/data/*" {
  capabilities = ["create", "update", "read", "list"]
}

# Permission to manage secret metadata (required for certain KV V2 operations)
path "siem/+/metadata/*" {
  capabilities = ["create", "update", "read", "list" ]
}

# Permission to enable, disable, and configure Auth Methods (backends)
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Permission to list enabled Auth Methods (required for UI/CLI)
path "sys/auth" {
  capabilities = ["read", "list"]
}

# Permission to create, update, and delete ACL Policies
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Permission to manage roles within any auth backend
# Example: auth/approle/role/my-role or auth/oidc/role/manager
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}