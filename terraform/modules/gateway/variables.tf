variable "ami" {
  description = "AMI ID for the instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for the instance"
  type        = string
  default     = "t3.micro"
}

variable "gateway_port" {
  description = "Port to be used by the VPN"
  type        = number
  default     = 50051
}

variable "gateway_secret" {
  description = "Secret key for the Defguard Gateway"
  type        = string
}

variable "network_id" {
  description = "ID of the VPN network"
  type        = number
}

variable "core_address" {
  description = "Internal address of the Defguard instance"
  type        = string
}

variable "core_grpc_port" {
  description = "Port to be used to communicate with Defguard Core"
  type        = number
}

variable "network_interface_id" {
  description = "Network interface ID for the instance"
  type        = string
}

variable "package_version" {
  description = "Version of the Defguard Gateway package to be installed"
  type        = string
}

variable "arch" {
  description = "Architecture of the Defguard Gateway package to be installed"
  type        = string
}

variable "nat" {
  description = "Enable masquerading"
  type        = bool
  default     = true
}

variable "log_level" {
  description = "Log level for Defguard Gateway. Possible values: trace, debug, info, warn, error"
  type        = string
  default     = "info"
}
