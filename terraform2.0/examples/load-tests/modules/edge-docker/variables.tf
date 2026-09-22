variable "ami" {
  type = string
}
variable "image" {
  description = "Defguard Edge container image. Pin this to the image under test."
  type        = string
}
variable "instance_type" {
  type    = string
  default = "t3.micro"
}
variable "grpc_port" {
  type    = number
  default = 50051
}
variable "http_port" {
  type    = number
  default = 8080
}
variable "https_port" {
  type    = number
  default = 443
}
variable "log_level" {
  type    = string
  default = "info"
}
variable "network_interface_id" {
  type = string
}
variable "key_name" {
  type    = string
  default = null
}
