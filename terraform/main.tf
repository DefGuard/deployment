locals {
  region = "eu-north-1"
  azs    = ["eu-north-1a", "eu-north-1b"]
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_ami_ids" "ubuntu" {
  owners = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-22.04-amd64-server-*"]
  }
}

provider "aws" {
  region     = local.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "random_password" "gateway_secret" {
  length  = 64
  special = false
}

module "defguard_core_db" {
  source     = "./modules/database"
  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id
  sg_ids     = [aws_security_group.defguard_db_sg.id]
  db_details = {
    name     = var.db_name
    username = var.db_username
    password = var.db_password
    port     = var.db_port
  }

  allocated_storage = 20
}

module "defguard_core" {
  source               = "./modules/core"
  core_url             = var.core_url
  proxy_address        = module.defguard_proxy.proxy_private_address
  proxy_grpc_port      = var.proxy_grpc_port
  proxy_url            = var.proxy_url
  grpc_port            = var.core_grpc_port
  gateway_secret       = random_password.gateway_secret.result
  network_interface_id = aws_network_interface.defguard_core_network_interface.id
  http_port            = var.core_http_port
  cookie_insecure      = var.core_cookie_insecure
  vpn_networks = [for network in var.vpn_networks : {
    id       = network.id
    name     = network.name
    address  = network.address
    port     = network.port
    endpoint = aws_eip.defguard_gateway_endpoint[network.id - 1].public_ip
  }]
  db_details = {
    name     = var.db_name
    username = var.db_username
    password = var.db_password
    port     = var.db_port
    address  = module.defguard_core_db.db_address
  }
  # instance_type = "t3.micro"
  ami = data.aws_ami_ids.ubuntu.ids[0]

  # Version of the Defguard core package
  package_version = "1.3.2-alpha2"

  # Supported values: "x86_64", "aarch64"
  arch = "x86_64"
}

module "defguard_proxy" {
  source               = "./modules/proxy"
  grpc_port            = var.proxy_grpc_port
  http_port            = var.proxy_http_port
  proxy_url            = var.proxy_url
  network_interface_id = aws_network_interface.defguard_proxy_network_interface.id
  # instance_type = "t3.micro"
  ami = data.aws_ami_ids.ubuntu.ids[0]

  # Version of the Defguard proxy package
  package_version = "1.2.0"

  # Supported values: "x86_64", "aarch64"
  arch = "x86_64"
}

module "defguard_gateway" {
  count                   = length(var.vpn_networks)
  source                  = "./modules/gateway"
  gateway_secret          = random_password.gateway_secret.result
  network_id              = var.vpn_networks[count.index].id
  network_interface_id    = aws_network_interface.defguard_gateway_network_interface[count.index].id
  defguard_core_address   = aws_network_interface.defguard_core_network_interface.private_ip
  defguard_core_grpc_port = var.core_grpc_port
  nat                     = var.vpn_networks[count.index].nat
  # instance_type = "t3.micro"
  ami = data.aws_ami_ids.ubuntu.ids[0]

  # Version of the Defguard gateway package
  package_version = "1.3.0"

  # Supported values: "x86_64", "aarch64"
  arch = "x86_64"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "defguard"
  cidr = "10.0.0.0/16"

  azs             = local.azs
  private_subnets = ["10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.1.0/24"]

  enable_dns_hostnames = true

  tags = {
    Name = "defguard-vpc"
  }
}

#
# Core network configuration
#

resource "aws_eip" "defguard_core_endpoint" {
  domain = "vpc"
}

resource "aws_eip_association" "defguard_core_endpoint_association" {
  network_interface_id = aws_network_interface.defguard_core_network_interface.id
  allocation_id        = aws_eip.defguard_core_endpoint.id
}

resource "aws_security_group" "defguard_core_sg" {
  name        = "defguard-core-sg"
  description = "Core access"
  vpc_id      = module.vpc.vpc_id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access to the Defguard core web UI
  ingress {
    from_port = var.core_http_port
    to_port   = var.core_http_port
    protocol  = "tcp"
    # allow access from every eip of the Defguard gateways
    cidr_blocks = [
      for eip in aws_eip.defguard_gateway_endpoint : "${eip.public_ip}/32"
    ]
  }

  # Internal communication with Defguard gateways
  ingress {
    from_port = var.core_grpc_port
    to_port   = var.core_grpc_port
    protocol  = "tcp"
    security_groups = [
      for sg in aws_security_group.defguard_gateway_sg : sg.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface" "defguard_core_network_interface" {
  subnet_id       = module.vpc.public_subnets[0]
  security_groups = [aws_security_group.defguard_core_sg.id]

  tags = {
    Name = "defguard-core-network-interface"
  }
}

# 
# Gateway network configuration
# 

resource "aws_eip" "defguard_gateway_endpoint" {
  count  = length(var.vpn_networks)
  domain = "vpc"
}

resource "aws_eip_association" "defguard_gateway_endpoint_association" {
  count                = length(var.vpn_networks)
  network_interface_id = aws_network_interface.defguard_gateway_network_interface[count.index].id
  allocation_id        = aws_eip.defguard_gateway_endpoint[count.index].id
}

resource "aws_security_group" "defguard_gateway_sg" {
  count       = length(var.vpn_networks)
  name        = "defguard-gateway-sg-${count.index}"
  description = "Gateway access"
  vpc_id      = module.vpc.vpc_id

  # VPN traffic coming from connected clients
  ingress {
    from_port   = var.vpn_networks[count.index].port
    to_port     = var.vpn_networks[count.index].port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface" "defguard_gateway_network_interface" {
  count           = length(var.vpn_networks)
  subnet_id       = module.vpc.public_subnets[0]
  security_groups = [aws_security_group.defguard_gateway_sg[count.index].id]

  tags = {
    Name = "defguard-gateway-network-interface-${count.index}"
  }
}

# 
# Proxy network configuration
#

resource "aws_eip" "defguard_proxy_endpoint" {
  domain = "vpc"
}

resource "aws_eip_association" "defguard_proxy_endpoint_association" {
  network_interface_id = aws_network_interface.defguard_proxy_network_interface.id
  allocation_id        = aws_eip.defguard_proxy_endpoint.id
}

resource "aws_security_group" "defguard_proxy_sg" {
  name        = "defguard-proxy-sg"
  description = "Proxy access"
  vpc_id      = module.vpc.vpc_id

  # Internal communication with Defguard core
  ingress {
    from_port       = var.proxy_grpc_port
    to_port         = var.proxy_grpc_port
    protocol        = "tcp"
    security_groups = [aws_security_group.defguard_core_sg.id]
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access to the proxy service
  ingress {
    from_port   = var.proxy_http_port
    to_port     = var.proxy_http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface" "defguard_proxy_network_interface" {
  subnet_id       = module.vpc.public_subnets[0]
  security_groups = [aws_security_group.defguard_proxy_sg.id]

  tags = {
    Name = "defguard-proxy-network-interface"
  }
}

#
# Database network configuration
#

resource "aws_security_group" "defguard_db_sg" {
  name        = "defguard-db-sg"
  description = "Access to the database"
  vpc_id      = module.vpc.vpc_id

  # Allow access from the Defguard core instance
  ingress {
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.defguard_core_sg.id]
  }

  tags = {
    Name = "defguard-db-sg"
  }
}
