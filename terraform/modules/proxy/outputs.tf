output "proxy_private_address" {
  description = "The private IP address of the Defguard proxy instance"
  value       = aws_instance.defguard_proxy.private_ip
}
