# 
# Core configuration
#

core_url               = "https://defguard.example.com"
core_grpc_port         = 50055
core_http_port         = 8000
core_cookie_insecure   = false
default_admin_password = "pass123"

# 
# Proxy configuration
#

proxy_url       = "https://proxy.example.com"
proxy_grpc_port = 50051
proxy_http_port = 8000

# 
# VPN configuration
#

# vpn_networks = [{
#   id      = 1
#   name    = "vpn1"
#   address = "10.10.10.1/24"
#   port    = 51820
#   nat     = true
# }]

#
# Database settings
#

db_name     = "defguard"
db_username = "defguard"
db_port     = 5432
db_password = "defguard"
