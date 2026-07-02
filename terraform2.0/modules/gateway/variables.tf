variable "ami" {
  description = "AMI ID for the instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for the instance"
  type        = string
  default     = "t3.micro"
}

variable "grpc_port" {
  description = "Port the Defguard Gateway gRPC server listens on (Core dials this)"
  type        = number
  default     = 50066
}

variable "network_interface_id" {
  description = "Network interface ID for the instance"
  type        = string
}

variable "package_version" {
  description = "Version of the Defguard Gateway package to install (e.g. \"2.0.1\"). Leave empty to install the latest version available in the APT repository."
  type        = string
  default     = ""
}

variable "nat" {
  description = "Enable masquerading"
  type        = bool
  default     = true
}

variable "key_name" {
  description = "Name of an existing EC2 key pair to attach (for SSH/tunnel access). Leave null to launch without a key."
  type        = string
  default     = null
}

variable "log_level" {
  description = "Log level for Defguard Gateway. Possible values: trace, debug, info, warn, error"
  type        = string
  default     = "info"
}
