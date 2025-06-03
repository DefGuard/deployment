variable "ami" {
  description = "AMI ID for the instance"
  type        = string
}

variable "instance_type" {
  description = "Instance type for the instance"
  type        = string
  default     = "t3.micro"
}

variable "proxy_url" {
  description = "URL of the Proxy instance"
  type        = string
}

variable "grpc_port" {
  description = "Port to be used to communicate with Defguard core"
  type        = string
}

variable "network_interface_id" {
  description = "Network interface ID for the instance"
  type        = string
}

variable "arch" {
  description = "Architecture of the Defguard proxy package to be installed"
  type        = string
}

variable "package_version" {
  description = "Version of the Defguard proxy package to be installed"
  type        = string
}

variable "http_port" {
  description = "Port to be used to access Defguard core via HTTP"
  type        = number
  default     = 8080
}
