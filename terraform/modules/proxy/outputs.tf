output "proxy_private_address" {
  description = "Private IP address of Defguard Proxy instance"
  value       = aws_instance.defguard_proxy.private_ip
}

output "instance_id" {
  description = "ID of Defguard Proxy instance"
  value       = aws_instance.defguard_proxy.id
}
