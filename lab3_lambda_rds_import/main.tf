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

# Посилання на існуючий S3 bucket
data "aws_s3_bucket" "target_bucket" {
  bucket = var.s3_bucket_name
}

# IAM роль для виконання Lambda функції
resource "aws_iam_role" "lambda_rds_role" {
  name = "s3_to_rds_importer_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# IAM політика (доступ до S3 та CloudWatch Logs)
resource "aws_iam_role_policy" "lambda_rds_policy" {
  name = "s3_to_rds_importer_policy"
  role = aws_iam_role.lambda_rds_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${data.aws_s3_bucket.target_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda функція для імпорту в PostgreSQL
resource "aws_lambda_function" "s3_to_rds" {
  filename         = "${path.module}/lambda.zip"
  function_name    = "s3_to_rds_postgres_importer"
  role             = aws_iam_role.lambda_rds_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256
  source_code_hash = filebase64sha256("${path.module}/lambda.zip")

  environment {
    variables = {
      DB_HOST              = var.db_host
      DB_PORT              = tostring(var.db_port)
      DB_NAME              = var.db_name
      DB_USER              = var.db_username
      DB_PASSWORD          = var.db_password
      DEDUP_MODE           = var.dedup_mode
      USE_STORED_PROCEDURE = var.use_stored_procedure
      INPUT_PREFIX         = "input/"
      PROCESSED_PREFIX     = "processed/"
      ERROR_PREFIX         = "error/"
    }
  }
}

# Дозвіл S3 викликати Lambda
resource "aws_lambda_permission" "allow_s3_import" {
  statement_id  = "AllowExecutionFromS3ForRDSImport"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_to_rds.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = data.aws_s3_bucket.target_bucket.arn
}

# Тригер S3 Event Notification
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = data.aws_s3_bucket.target_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_to_rds.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
  }

  depends_on = [aws_lambda_permission.allow_s3_import]
}

