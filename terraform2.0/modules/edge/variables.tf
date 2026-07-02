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
  description = "Port the Defguard Edge gRPC server listens on (Core dials this)"
  type        = number
  default     = 50051
}

variable "http_port" {
  description = "Port to be used to access the Defguard Edge enrollment server via HTTP"
  type        = number
  default     = 8080
}

variable "https_port" {
  description = "Port the Defguard Edge HTTPS server listens on"
  type        = number
  default     = 443
}

variable "network_interface_id" {
  description = "Network interface ID for the instance"
  type        = string
}

variable "package_version" {
  description = "Version of the Defguard Edge package to install (e.g. \"2.0.1\"). Leave empty to install the latest version available in the APT repository."
  type        = string
  default     = ""
}

variable "log_level" {
  description = "Log level for Defguard Edge. Possible values: trace, debug, info, warn, error"
  type        = string
  default     = "info"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair to attach (for SSH access). Leave null to launch without a key."
  type        = string
  default     = null
}
