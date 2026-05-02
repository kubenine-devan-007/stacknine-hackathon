resource "random_password" "db_master" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.name_prefix}-db-subnet"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${var.name_prefix}-db-subnet"
  }
}

# PostgreSQL 15 — private subnets only; not internet-facing (task §5).
resource "aws_db_instance" "main" {
  identifier                 = "${var.name_prefix}-postgres"
  engine                     = "postgres"
  engine_version             = "15.14"
  instance_class             = "db.t3.micro"
  allocated_storage          = 20
  storage_type               = "gp3"
  db_name                    = "stacknine"
  username                   = "postgres"
  password                   = random_password.db_master.result
  db_subnet_group_name       = aws_db_subnet_group.main.name
  vpc_security_group_ids     = [aws_security_group.rds.id]
  skip_final_snapshot        = true
  publicly_accessible        = false
  storage_encrypted          = true
  multi_az                   = false
  backup_retention_period    = 1
  auto_minor_version_upgrade = true

  tags = {
    Name = "${var.name_prefix}-postgres"
  }
}
