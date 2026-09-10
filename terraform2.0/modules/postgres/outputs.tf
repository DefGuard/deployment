output "security_group_id" {
  description = "Security group ID attached to PostgreSQL"
  value       = aws_security_group.postgres.id
}

output "private_address" {
  description = "Private IP address of PostgreSQL"
  value       = aws_network_interface.postgres.private_ip
}

output "instance_id" {
  description = "EC2 instance ID of PostgreSQL"
  value       = aws_instance.postgres.id
}

output "db_details" {
  description = "Database connection details in the shape expected by the Core module"
  sensitive   = true
  value = {
    name     = var.db_name
    username = var.db_username
    password = var.db_password
    port     = var.db_port
    address  = aws_network_interface.postgres.private_ip
  }
}
