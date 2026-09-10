variable "ami" {
  description = "AMI ID for the Prometheus instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Prometheus"
  type        = string
}

variable "key_name" {
  description = "Existing EC2 key pair"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for Prometheus"
  type        = string
}

variable "gateway_security_group_id" {
  description = "Gateway security group used for SSH and Prometheus access"
  type        = string
}

variable "name_prefix" {
  description = "Resource name prefix"
  type        = string
}

variable "scrape_targets" {
  description = "Private scrape targets grouped by job"
  type        = map(list(string))
}

variable "storage_gb" {
  description = "Encrypted gp3 root-volume size"
  type        = number
  default     = 100
}

variable "scrape_interval" {
  description = "Prometheus scrape interval"
  type        = string
  default     = "5s"
}
