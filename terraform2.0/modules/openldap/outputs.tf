output "security_group_id" {
  description = "Security group ID attached to OpenLDAP"
  value       = aws_security_group.openldap.id
}

output "private_address" {
  description = "Private IP address of OpenLDAP"
  value       = aws_network_interface.openldap.private_ip
}

output "instance_id" {
  description = "EC2 instance ID of OpenLDAP"
  value       = aws_instance.openldap.id
}

output "ldap_details" {
  description = "Connection details for the plain LDAP service"
  sensitive   = true
  value = {
    address  = aws_network_interface.openldap.private_ip
    port     = var.ldap_port
    domain   = var.ldap_domain
    base_dn  = "${join(",", [for part in split(".", var.ldap_domain) : "dc=${part}"])}"
    admin_dn = "cn=admin,${join(",", [for part in split(".", var.ldap_domain) : "dc=${part}"])}"
  }
}
