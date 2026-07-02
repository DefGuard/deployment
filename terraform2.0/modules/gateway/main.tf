resource "aws_instance" "defguard_gateway" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = templatefile("${path.module}/setup.sh", {
    grpc_port       = var.grpc_port
    nat             = var.nat
    package_version = var.package_version
    log_level       = var.log_level
  })
  user_data_replace_on_change = true

  primary_network_interface {
    network_interface_id = var.network_interface_id
  }

  tags = {
    Name = "defguard-gateway-instance"
  }
}
