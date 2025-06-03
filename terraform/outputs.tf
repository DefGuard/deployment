output "defguard_core_private_address" {
  description = "The IP address of the Defguard core instance in the internal network"
  value       = aws_network_interface.defguard_core_network_interface.private_ip
}

output "defguard_core_public_address" {
  description = "The public IP address of the Defguard core instance"
  value       = aws_eip.defguard_core_endpoint.public_ip
}

output "defguard_proxy_public_address" {
  description = "The public IP address of the Defguard proxy instance"
  value       = aws_eip.defguard_proxy_endpoint.public_ip
}

output "defguard_proxy_private_address" {
  description = "The private IP address of the Defguard proxy instance"
  value       = aws_network_interface.defguard_proxy_network_interface.private_ip
}

output "defguard_gateway_public_addresses" {
  description = "The public IP addresses of the Defguard gateway instances"
  value       = [for gw in aws_eip.defguard_gateway_endpoint : gw.public_ip]
}

output "defguard_gateway_private_addresses" {
  description = "The private IP addresses of the Defguard gateway instances"
  value       = [for gw in aws_network_interface.defguard_gateway_network_interface : gw.private_ip]
}
