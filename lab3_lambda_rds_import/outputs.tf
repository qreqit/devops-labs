output "lambda_function_name" {
  description = "Назва Lambda функції імпорту"
  value       = aws_lambda_function.s3_to_rds.function_name
}

output "lambda_function_arn" {
  description = "ARN Lambda функції"
  value       = aws_lambda_function.s3_to_rds.arn
}

output "s3_bucket" {
  description = "S3 bucket"
  value       = data.aws_s3_bucket.target_bucket.id
}

