terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Отримуємо стандартну VPC
data "aws_vpc" "default" {
  default = true
}

# Отримуємо підмережі стандартної VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group для доступу до PostgreSQL (порт 5432)
resource "aws_security_group" "rds_sg" {
  name        = "opendata-postgres-sg"
  description = "Security group for PostgreSQL RDS instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Для навчальних цілей; у проді краще обмежити своєю IP
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "opendata-postgres-sg"
  }
}

# IAM роль для інтеграції Amazon RDS із S3 (для розширення aws_s3)
resource "aws_iam_role" "rds_s3_role" {
  name = "rds_s3_import_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "rds.amazonaws.com" }
    }]
  })
}

# Політика дозволу читання з S3 для RDS
resource "aws_iam_role_policy" "rds_s3_policy" {
  name = "rds_s3_import_policy"
  role = aws_iam_role.rds_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      }
    ]
  })
}

# Інстанс бази даних Amazon RDS PostgreSQL
resource "aws_db_instance" "postgres" {
  identifier             = "opendata-postgres"
  engine                 = "postgres"
  engine_version         = "16.4"
  instance_class         = var.db_instance_class
  allocated_storage      = var.allocated_storage
  storage_type           = "gp3"
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  port                   = 5432
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = true
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = {
    Name        = "OpenDataPostgreSQL"
    Environment = "Lab2"
  }
}

# Асоціація ролі S3 з RDS інстансом для підтримки розширення aws_s3
resource "aws_db_instance_role_association" "rds_s3_assoc" {
  db_instance_identifier = aws_db_instance.postgres.identifier
  feature_name           = "s3Import"
  role_arn               = aws_iam_role.rds_s3_role.arn
}

