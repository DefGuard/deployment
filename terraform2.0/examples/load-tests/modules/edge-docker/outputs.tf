output "edge_private_address" {
  value = aws_instance.defguard_edge.private_ip
}

output "instance_id" {
  value = aws_instance.defguard_edge.id
}
