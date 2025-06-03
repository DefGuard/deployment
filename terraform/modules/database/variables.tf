variable "subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for the database instance"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the database instance will be created"
}

variable "allocated_storage" {
  type        = number
  description = "Allocated storage for the database instance in GB"
}

variable "db_details" {
  description = "Details of the database connection"
  type = object({
    name     = string
    username = string
    password = string
    port     = number
  })
}

variable "sg_ids" {
  type        = list(string)
  description = "List of security group IDs to be associated with the database instance"
}
