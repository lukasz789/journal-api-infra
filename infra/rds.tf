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
  security_group_id            = aws_security_group.rds.id
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
