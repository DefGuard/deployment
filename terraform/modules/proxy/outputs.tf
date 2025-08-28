output "proxy_private_address" {
  description = "The private IP address of the Defguard Proxy instance"
  value       = aws_instance.defguard_proxy.private_ip
}

output "instance_id" {
  description = "The ID of the Proxy instance"
  value       = aws_instance.defguard_proxy.id
}
