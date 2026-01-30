

vault policy write siem-manager-pol siem-manager-policy.hcl

vault auth enable approle

vault write auth/approle/role/siem-creator \
    secret_id_ttl=365d \
    token_num_uses=0 \
    token_ttl=30m \
    token_max_ttl=30m \
    policies="siem-manager-pol,default"

# get role ID
vault read auth/approle/role/siem-creator/role-id

# get Secret ID
vault write -f auth/approle/role/siem-creator/secret-id

vault write auth/approle/login role_id="<ROLE_ID>" secret_id="<SECRET_ID>"