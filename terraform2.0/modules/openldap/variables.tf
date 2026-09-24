variable "ami" {
  description = "AMI ID for the OpenLDAP instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for OpenLDAP"
  type        = string
}

variable "key_name" {
  description = "Existing EC2 key pair attached to OpenLDAP"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC ID for the OpenLDAP security group"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR used for optional SSH access"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the OpenLDAP network interface"
  type        = string
}

variable "client_security_group_ids" {
  description = "Security groups allowed to connect to OpenLDAP"
  type        = list(string)
}

variable "enable_ssh" {
  description = "Whether to permit SSH from within the VPC"
  type        = bool
  default     = false
}

variable "name_prefix" {
  description = "Prefix for OpenLDAP resource names"
  type        = string
}

variable "ldap_domain" {
  description = "OpenLDAP domain, for example example.org"
  type        = string
  default     = "example.com"
}

variable "ldap_organization" {
  description = "OpenLDAP organization name"
  type        = string
  default     = "Defguard Load Tests"
}

variable "ldap_admin_password" {
  description = "Password for the OpenLDAP admin DN"
  type        = string
  sensitive   = true
}

variable "ldap_port" {
  description = "Plain LDAP TCP port"
  type        = number
  default     = 389
}

variable "storage_gb" {
  description = "Encrypted gp3 root-volume size for OpenLDAP"
  type        = number
  default     = 20
}
