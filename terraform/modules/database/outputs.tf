output "db_address" {
  value = aws_db_instance.defguard_core_db.address
  sensitive = true
}
