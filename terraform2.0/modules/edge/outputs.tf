output "edge_private_address" {
  description = "Private IP address of Defguard Edge instance"
  value       = aws_instance.defguard_edge.private_ip
}

output "instance_id" {
  description = "ID of Defguard Edge instance"
  value       = aws_instance.defguard_edge.id
}
