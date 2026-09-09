resource "aws_security_group" "postgres" {
  name        = "${var.name_prefix}-postgres-sg"
  description = "Self-managed PostgreSQL access"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from Core"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [var.core_security_group_id]
  }

  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []
    content {
      description = "SSH from within the VPC"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface" "postgres" {
  subnet_id       = var.subnet_id
  security_groups = [aws_security_group.postgres.id]

  tags = {
    Name = "${var.name_prefix}-postgres-network-interface"
  }
}

resource "aws_instance" "postgres" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = templatefile("${path.module}/setup.sh", {
    db_name     = var.db_name
    db_username = var.db_username
    db_password = var.db_password
    db_port     = var.db_port
    vpc_cidr    = var.vpc_cidr
  })
  user_data_replace_on_change = true

  primary_network_interface {
    network_interface_id = aws_network_interface.postgres.id
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.storage_gb
    encrypted   = true
  }

  tags = {
    Name = "${var.name_prefix}-postgres-instance"
  }
}
