resource "aws_security_group" "prometheus" {
  name        = "${var.name_prefix}-prometheus-sg"
  description = "Private Prometheus monitoring"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH through the Gateway"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.gateway_security_group_id]
  }

  ingress {
    description     = "Prometheus UI through the Gateway"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [var.gateway_security_group_id]
  }

  ingress {
    description     = "Grafana UI through the Gateway"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [var.gateway_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_network_interface" "prometheus" {
  subnet_id       = var.subnet_id
  security_groups = [aws_security_group.prometheus.id]

  tags = {
    Name = "${var.name_prefix}-prometheus-network-interface"
  }
}

resource "aws_instance" "prometheus" {
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name

  user_data = templatefile("${path.module}/setup.sh", {
    scrape_targets             = var.scrape_targets
    scrape_interval            = var.scrape_interval
    grafana_admin_password_b64 = var.grafana_admin_password == null ? "" : base64encode(var.grafana_admin_password)
    dashboard_files = {
      "node-overview.json" = file("${path.module}/dashboards/node-overview.json")
      "postgresql.json"    = file("${path.module}/dashboards/postgresql.json")
      "prometheus.json"    = file("${path.module}/dashboards/prometheus.json")
      "processes.json"     = file("${path.module}/dashboards/processes.json")
    }
  })
  user_data_replace_on_change = true

  primary_network_interface {
    network_interface_id = aws_network_interface.prometheus.id
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.storage_gb
    encrypted   = true
  }

  tags = {
    Name = "${var.name_prefix}-prometheus-instance"
  }
}
