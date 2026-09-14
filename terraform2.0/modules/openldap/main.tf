resource "aws_security_group" "openldap" {
  name        = "${var.name_prefix}-openldap-sg"
  description = "Private OpenLDAP access"
  vpc_id      = var.vpc_id

  ingress {
    description     = "LDAP from authorized clients"
    from_port       = var.ldap_port
    to_port         = var.ldap_port
    protocol        = "tcp"
    security_groups = var.client_security_group_ids
  }

  dynamic "ingress" {
    for_each = [9100, 9256]
    content {
      description = "Monitoring exporter from within the VPC"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    }
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

resource "aws_network_interface" "openldap" {
  subnet_id       = var.subnet_id
  security_groups = [aws_security_group.openldap.id]

  tags = {
    Name = "${var.name_prefix}-openldap-network-interface"
  }
}

resource "aws_instance" "openldap" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = templatefile("${path.module}/setup.sh", {
    ldap_domain         = var.ldap_domain
    ldap_organization   = var.ldap_organization
    ldap_admin_password = var.ldap_admin_password
    ldap_port           = var.ldap_port
  })
  user_data_replace_on_change = true

  primary_network_interface {
    network_interface_id = aws_network_interface.openldap.id
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.storage_gb
    encrypted   = true
  }

  tags = {
    Name = "${var.name_prefix}-openldap-instance"
  }
}
