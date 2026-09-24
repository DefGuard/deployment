output "private_address" {
  description = "Private IP address of Prometheus"
  value       = aws_network_interface.prometheus.private_ip
}

output "security_group_id" {
  description = "Security group ID used by Prometheus and Grafana"
  value       = aws_security_group.prometheus.id
}

output "grafana_private_address" {
  description = "Private IP address of Grafana"
  value       = aws_network_interface.prometheus.private_ip
}

output "grafana_admin_password_file" {
  description = "File containing the generated Grafana admin password on the monitoring host"
  value       = "/root/grafana-admin-password"
}
