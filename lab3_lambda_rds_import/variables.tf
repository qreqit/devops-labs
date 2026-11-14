variable "aws_region" {
  description = "Регіон AWS"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Назва S3 бакету"
  type        = string
  default     = "demo-api-bucket-loving-ox"
}

variable "db_host" {
  description = "Хост (Endpoint) Amazon RDS PostgreSQL"
  type        = string
  default     = "localhost"
}

variable "db_port" {
  description = "Порт PostgreSQL"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Назва бази даних"
  type        = string
  default     = "opendata_db"
}

variable "db_username" {
  description = "Користувач бази даних"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Пароль до бази даних"
  type        = string
  default     = "SecurePass2026!"
  sensitive   = true
}

variable "dedup_mode" {
  description = "Режим дедуплікації: UPDATE (UPSERT) або IGNORE (DO NOTHING)"
  type        = string
  default     = "UPDATE"
}

variable "use_stored_procedure" {
  description = "Використовувати збережувану процедуру для вставки"
  type        = string
  default     = "true"
}

