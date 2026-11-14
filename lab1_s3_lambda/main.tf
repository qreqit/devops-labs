terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Посилання на створений раніше S3 bucket
data "aws_s3_bucket" "target_bucket" {
  bucket = var.bucket_name
}

# Пакування вихідного коду функції у zip-архів
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

# IAM роль для виконання Lambda функції
resource "aws_iam_role" "lambda_exec_role" {
  name = "s3_file_processor_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# IAM політика з дозволами на S3 (читання, запис, видалення) та CloudWatch Logs
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "s3_file_processor_policy"
  role = aws_iam_role.lambda_exec_role.id

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

# Lambda функція
resource "aws_lambda_function" "s3_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "s3_file_pattern_processor"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      INPUT_PREFIX     = var.input_prefix
      PROCESSED_PREFIX = var.processed_prefix
      IGNORED_PREFIX   = var.ignored_prefix
      CSV_PATTERN      = var.csv_pattern
      JSON_PATTERN     = var.json_pattern
    }
  }
}

# Дозвіл для S3 викликати Lambda функцію
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = data.aws_s3_bucket.target_bucket.arn
}

# Налаштування S3 Event Notification на подію створення файлу у папці input/
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = data.aws_s3_bucket.target_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.input_prefix
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

