resource "aws_db_instance" "defguard_core_db" {
  engine = "postgres"
  instance_class = "db.t3.micro"
  username = var.db_details.username
  password = var.db_details.password
  db_name = var.db_details.name
  port = var.db_details.port
  skip_final_snapshot = true
  allocated_storage = var.allocated_storage
  db_subnet_group_name = aws_db_subnet_group.defguard.name
  vpc_security_group_ids = var.sg_ids
  parameter_group_name = aws_db_parameter_group.defguard_db_parameter_group.name
}

resource "aws_db_parameter_group" "defguard_db_parameter_group" {
  name        = "defguard-db-parameter-group"
  family      = "postgres17"

  parameter {
    name = "rds.force_ssl"
    value = "0"
  }
}

resource "aws_db_subnet_group" "defguard" {
  name       = "defguard-db-subnet-group"
  subnet_ids = var.subnet_ids
}
