resource "aws_instance" "defguard_edge" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = templatefile("${path.module}/setup.sh", {
    image      = var.image
    grpc_port  = var.grpc_port
    http_port  = var.http_port
    https_port = var.https_port
    log_level  = var.log_level
  })
  user_data_replace_on_change = true

  primary_network_interface {
    network_interface_id = var.network_interface_id
  }

  tags = {
    Name = "defguard-load-tests-edge-docker"
  }
}
