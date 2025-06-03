variable "aws_access_key" {
  description = "AWS access key"
  type        = string
}

variable "aws_secret_key" {
  description = "AWS secret key"
  type        = string
}

variable "core_url" {
  description = "URL at which Defguard core web UI will be available"
  type        = string
}

variable "core_grpc_port" {
  description = "Port for gRPC communication with Defguard gateways"
  type        = number
  default     = 50055
}

variable "core_http_port" {
  description = "HTTP server port (Web UI)"
  type        = number
  default     = 8000
}

variable "core_cookie_insecure" {
  description = "Enable it if you want to use HTTP"
  type        = bool
  default     = false
}

variable "proxy_url" {
  description = "URL at which Defguard proxy (enrollment service) will be available"
  type        = string
}

variable "proxy_grpc_port" {
  description = "Port for gRPC communication with Defguard core"
  type        = number
  default     = 50051
}

variable "proxy_http_port" {
  description = "HTTP server port"
  type        = number
  default     = 8000
}

variable "vpn_networks" {
  description = "List of VPN networks to be created"
  type = list(object({
    id      = number
    name    = string
    address = string
    port    = number
    nat     = bool
  }))
}

variable "db_name" {
  description = "Name of the PostgreSQL database to create"
  type        = string
  default     = "defguard"
}

variable "db_port" {
  description = "Port for the PostgreSQL database"
  type        = number
  default     = 5432
}

variable "db_username" {
  description = "Username for the PostgreSQL database"
  type        = string
  default     = "defguard"
}

variable "db_password" {
  description = "Password for the PostgreSQL database"
  type        = string
}

variable "default_admin_password" {
  description = "Default password for the admin user"
  type        = string
  default     = "pass123"
}

