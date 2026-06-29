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
  sensitive   = true
  type = object({
    name     = string
    username = string
    password = string
    port     = number
    address  = string
  })
}

variable "grpc_port" {
  description = "Port the Defguard Core gRPC server listens on"
  type        = number
  default     = 50055
}

variable "http_port" {
  description = "Port to be used to access Defguard Core via HTTP"
  type        = number
  default     = 8000
}

variable "gateway_address" {
  description = "Address Core dials to adopt the gateway. Also reused as the WireGuard location endpoint; if a private address is passed, set the location endpoint in the Core web UI after adoption so external clients can connect."
  type        = string
}

variable "gateway_grpc_port" {
  description = "Port the Defguard Gateway gRPC server listens on"
  type        = number
  default     = 50066
}

variable "edge_address" {
  description = "Address Core dials to adopt the edge. Used only for internal core->edge gRPC, so the private address is preferred."
  type        = string
}

variable "edge_grpc_port" {
  description = "Port the Defguard Edge gRPC server listens on"
  type        = number
  default     = 50051
}

variable "network_interface_id" {
  description = "Network interface ID for the instance"
  type        = string
}

variable "package_version" {
  description = "Version of the Defguard Core package to be installed"
  type        = string
}

variable "arch" {
  description = "Architecture of the Defguard Core package to be installed"
  type        = string
}

variable "cookie_insecure" {
  description = "Whether to use insecure cookies for the Defguard Core"
  type        = bool
}

variable "log_level" {
  description = "Log level for Defguard Core. Possible values: trace, debug, info, warn, error"
  type        = string
  default     = "info"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair to attach (for SSH access). Leave null to launch without a key."
  type        = string
  default     = null
}
