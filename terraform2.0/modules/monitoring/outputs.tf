output "private_address" {
  description = "Private IP address of Prometheus"
  value       = aws_network_interface.prometheus.private_ip
}

output "security_group_id" {
  description = "Security group ID used by Prometheus"
  value       = aws_security_group.prometheus.id
}
