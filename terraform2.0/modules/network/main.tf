###########################################################################
# Security groups
###########################################################################

# Core is the control plane and stays entirely private. SSH and the web UI are reachable
# only from within the VPC (hop through the public Gateway, a bastion, or SSM).
resource "aws_security_group" "core" {
  name        = "${var.name_prefix}-core-sg"
  description = "Core access"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ssh_admin_cidr == null ? [] : [1]
    content {
      description = "SSH from within the VPC"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  ingress {
    description = "Web UI from within the VPC / over the VPN"
    from_port   = var.core_http_port
    to_port     = var.core_http_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Gateway exposes only its WireGuard UDP port publicly. gRPC is reachable only from Core.
resource "aws_security_group" "gateway" {
  name        = "${var.name_prefix}-gateway-sg"
  description = "Gateway access"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ssh_admin_cidr == null ? [] : [1]
    content {
      description = "SSH from the admin IP"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ssh_admin_cidr]
    }
  }

  ingress {
    description = "WireGuard VPN traffic from clients"
    from_port   = var.wireguard_port
    to_port     = var.wireguard_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "gRPC from Core (adoption + control stream)"
    from_port       = var.gateway_grpc_port
    to_port         = var.gateway_grpc_port
    protocol        = "tcp"
    security_groups = [aws_security_group.core.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Edge is the only public HTTPS interface. Plain HTTP is VPC-internal; 80 is for ACME.
resource "aws_security_group" "edge" {
  name        = "${var.name_prefix}-edge-sg"
  description = "Edge access"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ssh_admin_cidr == null ? [] : [1]
    content {
      description = "SSH from the admin IP"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.ssh_admin_cidr]
    }
  }

  ingress {
    description = "Public HTTPS (enrollment + client communication)"
    from_port   = var.edge_https_port
    to_port     = var.edge_https_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ACME HTTP-01 challenge for the :443 certificate"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Plain HTTP API, VPC-internal only (pre-TLS testing)"
    from_port   = var.edge_http_port
    to_port     = var.edge_http_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description     = "gRPC from Core (adoption + control stream)"
    from_port       = var.edge_grpc_port
    to_port         = var.edge_grpc_port
    protocol        = "tcp"
    security_groups = [aws_security_group.core.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "Access to the database"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from Core"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.core.id]
  }

  tags = {
    Name = "${var.name_prefix}-db-sg"
  }
}

###########################################################################
# Network interfaces and elastic IPs
###########################################################################

resource "aws_network_interface" "core" {
  subnet_id       = var.core_subnet_id
  security_groups = [aws_security_group.core.id]

  tags = {
    Name = "${var.name_prefix}-core-network-interface"
  }
}

resource "aws_network_interface" "gateway" {
  subnet_id       = coalesce(var.gateway_subnet_id, var.public_subnet_id)
  security_groups = [aws_security_group.gateway.id]

  tags = {
    Name = "${var.name_prefix}-gateway-network-interface"
  }
}

resource "aws_network_interface" "edge" {
  subnet_id       = coalesce(var.edge_subnet_id, var.public_subnet_id)
  security_groups = [aws_security_group.edge.id]

  tags = {
    Name = "${var.name_prefix}-edge-network-interface"
  }
}

# Gateway needs a public IP so external WireGuard clients can reach its UDP port.
resource "aws_eip" "gateway" {
  domain = "vpc"
}

resource "aws_eip_association" "gateway" {
  network_interface_id = aws_network_interface.gateway.id
  allocation_id        = aws_eip.gateway.id
}

# Edge is the public-facing component for enrollment and client communication.
resource "aws_eip" "edge" {
  domain = "vpc"
}

resource "aws_eip_association" "edge" {
  network_interface_id = aws_network_interface.edge.id
  allocation_id        = aws_eip.edge.id
}

###########################################################################
# Database
###########################################################################

resource "aws_db_instance" "core" {
  engine                  = "postgres"
  engine_version          = var.db_engine_version
  instance_class          = var.db_instance_class
  username                = var.db_username
  password                = var.db_password
  db_name                 = var.db_name
  port                    = var.db_port
  skip_final_snapshot     = true
  allocated_storage       = var.db_storage
  db_subnet_group_name    = aws_db_subnet_group.core.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  parameter_group_name    = aws_db_parameter_group.core.name
  storage_encrypted       = true
  backup_retention_period = 7
  deletion_protection     = false
}

resource "aws_db_parameter_group" "core" {
  name   = "${var.name_prefix}-db-parameter-group"
  family = "postgres${var.db_engine_version}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_db_subnet_group" "core" {
  name       = "${var.name_prefix}-db-subnet-group"
  subnet_ids = var.db_subnet_ids
}
