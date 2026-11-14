output "lambda_function_name" {
  description = "Назва розгорнутої Lambda функції"
  value       = aws_lambda_function.s3_processor.function_name
}

output "lambda_function_arn" {
  description = "ARN Lambda функції"
  value       = aws_lambda_function.s3_processor.arn
}

output "s3_bucket_name" {
  description = "Назва S3 bucket"
  value       = data.aws_s3_bucket.target_bucket.id
}

output "input_folder" {
  description = "Вхідна папка для завантаження файлів"
  value       = var.input_prefix
}

output "processed_folder" {
  description = "Папка для успішно валідованих файлів із таймстампом"
  value       = var.processed_prefix
}

output "ignored_folder" {
  description = "Папка для ігнорованих файлів"
  value       = var.ignored_prefix
}

