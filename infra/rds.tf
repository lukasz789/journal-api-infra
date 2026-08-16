# ------------------------------------------------------------------------------
# RDS subnet group
# ------------------------------------------------------------------------------
# RDS can place the database in either of the two private Availability Zones.
resource "aws_db_subnet_group" "rds" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Private subnets available to the Journal API database."
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ------------------------------------------------------------------------------
# RDS security group
# ------------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allows PostgreSQL connections from the EKS cluster."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# EKS attaches its cluster security group to managed node group network interfaces.
# This allows Pods running on those nodes to connect to PostgreSQL on port 5432.
resource "aws_vpc_security_group_ingress_rule" "rds_postgresql" {
  security_group_id = aws_security_group.rds.id
  # could also use aws_security_group.eks_nodes.id (if created), but this is more robust because it will work even if the EKS cluster is recreated.
  # could also restrict it further so that only specific pods can access.
  referenced_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  description                  = "PostgreSQL access from EKS nodes."

  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432

  tags = {
    Name = "${var.project_name}-rds-postgresql-ingress"
  }
}

# ------------------------------------------------------------------------------
# RDS PostgreSQL instance
# ------------------------------------------------------------------------------
# This is a cost-conscious setup: one small Single-AZ instance with the minimum
# gp3 storage. It is suitable for learning, but it does not provide Multi-AZ HA.
resource "aws_db_instance" "postgresql" {
  identifier = "${var.project_name}-postgresql"

  engine         = "postgres"
  engine_version = var.rds_postgres_version
  instance_class = var.rds_instance_class

  db_name  = var.rds_database_name
  username = var.rds_master_username
  port     = 5432

  # a) RDS stores the password in Secrets Manager instead of Terraform state.
  # b) For a larger production setup, consider IAM database authentication so the
  # application can use short-lived tokens instead of a stored password.
  # c) RDS rotates this password every 7 days by default. In the current setup,
  # the Kubernetes Secret and running Pods are updated only during deployment,
  # so the application can keep the old password and lose database access. I
  # accept this limitation because this is a practice project.
  # ---THIS MUST NOT BE LEFT LIKE THIS IN A REAL PRODUCTION CONFIGURATION---
  manage_master_user_password = true

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  # Short backup retention (1 day) and no final snapshot keep this learning setup cheap
  # and easy to destroy, at the cost of a much smaller recovery window.
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  # `false`, just for simplicity in this learning setup. In production, you would typically set this to `true` to automatically apply minor version upgrades.
  auto_minor_version_upgrade = false
  copy_tags_to_snapshot      = true

  tags = {
    Name = "${var.project_name}-postgresql"
  }
}
