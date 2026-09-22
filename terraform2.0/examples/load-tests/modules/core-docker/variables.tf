variable "ami" {
  type = string
}
variable "image" {
  description = "Defguard Core container image. Pin this to the image under test."
  type        = string
}
variable "instance_type" {
  type    = string
  default = "m7i.xlarge"
}
variable "db_details" {
  sensitive = true
  type = object({
    name     = string
    username = string
    password = string
    port     = number
    address  = string
  })
}
variable "grpc_port" {
  type    = number
  default = 50055
}
variable "http_port" {
  type    = number
  default = 8000
}
variable "gateway_address" {
  type = string
}
variable "gateway_grpc_port" {
  type    = number
  default = 50066
}
variable "edge_address" {
  type = string
}
variable "edge_grpc_port" {
  type    = number
  default = 50051
}
variable "cookie_insecure" {
  type = bool
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
