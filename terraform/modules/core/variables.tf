variable "ami" {
  description = "AMI ID for the instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for the instance"
  type        = string
  default     = "t3.micro"
}

variable "db_details" {
  description = "Details of the database connection"
  type = object({
    name     = string
    username = string
    password = string
    port     = number
    address  = string
  })
}

variable "core_url" {
  description = "URL of the Defguard instance"
  type        = string
}

variable "proxy_address" {
  description = "The IP address of the Defguard Proxy instance"
  type        = string
}

variable "proxy_grpc_port" {
  description = "Port to be used to communicate with Defguard Proxy"
  type        = string
}

variable "proxy_url" {
  description = "The URL of the Defguard Proxy instance where enrollment is performed"
  type        = string
}

variable "grpc_port" {
  description = "Port to be used to communicate with Defguard Core"
  type        = number
}

variable "http_port" {
  description = "Port to be used to access Defguard Core via HTTP"
  type        = number
  default     = 8000
}

variable "gateway_secret" {
  description = "Secret for the Defguard Gateway"
  type        = string
}

variable "network_interface_id" {
  description = "Network interface ID for the instance"
  type        = string
}

variable "vpn_networks" {
  description = "List of VPN networks"
  type = list(object({
    name     = string
    address  = string
    port     = number
    endpoint = string
    id       = number
  }))
}

variable "package_version" {
  description = "Version of the Defguard Core package to be installed"
  type        = string
}

variable "arch" {
  description = "Architecture of the Defguard Core package to be installed"
  type        = string
}

variable "default_admin_password" {
  description = "Default admin password for the Defguard Core"
  type        = string
  default     = "pass123"
}

variable "cookie_insecure" {
  description = "Whether to use insecure cookies for the Defguard Core"
  type        = bool
}

variable "log_level" {
  description = "Log level for Defguard Core. Possible values: debug, info, warn, error"
  type        = string
  default     = "info"
}
