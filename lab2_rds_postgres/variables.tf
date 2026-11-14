variable "aws_region" {
  description = "Регіон AWS"
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Назва створюваної бази даних PostgreSQL"
  type        = string
  default     = "opendata_db"
}

variable "db_username" {
  description = "Ім'я головного адміністратора БД (Master Username)"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Пароль головного адміністратора БД"
  type        = string
  default     = "SecurePass2026!"
  sensitive   = true
}

variable "db_instance_class" {
  description = "Клас інстансу RDS (db.t3.micro або db.t4g.micro підходять для AWS Free Tier)"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Обсяг виділеного дискового сховища (в гігабайтах)"
  type        = number
  default     = 20
}

variable "s3_bucket_name" {
  description = "Назва S3 бакету для імпорту файлів"
  type        = string
  default     = "demo-api-bucket-loving-ox"
}

