resource "aws_instance" "defguard_core" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = templatefile("${path.module}/setup.sh", {
    db_address        = var.db_details.address
    db_password       = var.db_details.password
    db_username       = var.db_details.username
    db_name           = var.db_details.name
    db_port           = var.db_details.port
    grpc_port         = var.grpc_port
    http_port         = var.http_port
    gateway_address   = var.gateway_address
    gateway_grpc_port = var.gateway_grpc_port
    edge_address      = var.edge_address
    edge_grpc_port    = var.edge_grpc_port
    package_version   = var.package_version
    cookie_insecure   = var.cookie_insecure
    log_level         = var.log_level
  })
  user_data_replace_on_change = true

  primary_network_interface {
    network_interface_id = var.network_interface_id
  }

  tags = {
    Name = "defguard-core-instance"
  }
}
