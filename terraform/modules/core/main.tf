resource "aws_instance" "defguard_core" {
  ami           = var.ami
  instance_type = var.instance_type

  user_data = templatefile("${path.module}/setup.sh", {
    db_address             = var.db_details.address
    db_password            = var.db_details.password
    db_username            = var.db_details.username
    db_name                = var.db_details.name
    db_port                = var.db_details.port
    core_url               = var.core_url
    proxy_address          = var.proxy_address
    proxy_grpc_port        = var.proxy_grpc_port
    proxy_url              = var.proxy_url
    grpc_port              = var.grpc_port
    gateway_secret         = var.gateway_secret
    vpn_networks           = var.vpn_networks
    package_version        = var.package_version
    arch                   = var.arch
    http_port              = var.http_port
    default_admin_password = var.default_admin_password
    cookie_insecure        = var.cookie_insecure
    log_level              = var.log_level
  })
  user_data_replace_on_change = true

  network_interface {
    network_interface_id = var.network_interface_id
    device_index         = 0
  }

  tags = {
    Name = "defguard-core-instance"
  }
}

