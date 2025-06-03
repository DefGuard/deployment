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
  description = "Secret key for the Defguard gateway"
  type        = string
}

variable "network_id" {
  description = "ID of the VPN network"
  type        = number
}

variable "defguard_core_address" {
  description = "Internal address of the Defguard instance"
  type        = string
}

variable "defguard_core_grpc_port" {
  description = "Port to be used to communicate with Defguard core"
  type        = number
}

variable "network_interface_id" {
  description = "Network interface ID for the instance"
  type        = string
}

variable "package_version" {
  description = "Version of the Defguard gateway package to be installed"
  type        = string
}

variable "arch" {
  description = "Architecture of the Defguard gateway package to be installed"
  type        = string
}

variable "nat" {
  description = "Enable masquerading"
  type        = bool
  default     = true
}
