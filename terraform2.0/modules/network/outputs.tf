output "core_network_interface_id" {
  description = "Network interface ID for the Core instance"
  value       = aws_network_interface.core.id
}

output "gateway_network_interface_id" {
  description = "Network interface ID for the Gateway instance"
  value       = aws_network_interface.gateway.id
}

output "edge_network_interface_id" {
  description = "Network interface ID for the Edge instance"
  value       = aws_network_interface.edge.id
}

output "core_private_ip" {
  description = "Private IP of the Core network interface"
  value       = aws_network_interface.core.private_ip
}

output "gateway_private_ip" {
  description = "Private IP of the Gateway network interface (used as Core's adoption target)"
  value       = aws_network_interface.gateway.private_ip
}

output "edge_private_ip" {
  description = "Private IP of the Edge network interface (used as Core's adoption target)"
  value       = aws_network_interface.edge.private_ip
}

output "gateway_public_ip" {
  description = "Public EIP of the Gateway (WireGuard endpoint for clients)"
  value       = aws_eip.gateway.public_ip
}

output "edge_public_ip" {
  description = "Public EIP of the Edge (enrollment / client HTTPS)"
  value       = aws_eip.edge.public_ip
}

output "db_details" {
  description = "Database connection details, in the shape the Core module expects"
  sensitive   = true
  value = {
    name     = var.db_name
    username = var.db_username
    password = var.db_password
    port     = var.db_port
    address  = aws_db_instance.core.address
  }
}
