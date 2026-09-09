variable "ami" {
  description = "AMI ID for the PostgreSQL instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for PostgreSQL"
  type        = string
}

variable "key_name" {
  description = "Existing EC2 key pair attached to PostgreSQL. Leave null to launch without a key."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC ID for PostgreSQL security group"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR of the VPC, used for SSH tunnelling from the Gateway"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the PostgreSQL network interface"
  type        = string
}

variable "core_security_group_id" {
  description = "Security group attached to Core, allowed to connect to PostgreSQL"
  type        = string
}

variable "enable_ssh" {
  description = "Whether to permit SSH from within the VPC for tunnelling through the Gateway"
  type        = bool
  default     = false
}

variable "name_prefix" {
  description = "Prefix for PostgreSQL resource names"
  type        = string
}

variable "db_name" {
  description = "Database created for Defguard"
  type        = string
}

variable "db_username" {
  description = "Database role created for Defguard"
  type        = string
}

variable "db_password" {
  description = "Password for the Defguard database role"
  type        = string
  sensitive   = true
}

variable "db_port" {
  description = "PostgreSQL TCP port"
  type        = number
  default     = 5432
}

variable "storage_gb" {
  description = "Encrypted gp3 root-volume size for PostgreSQL"
  type        = number
  default     = 100
}
