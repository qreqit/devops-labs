variable "aws_region" {
  description = "AWS регіон для розгортання"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Назва S3 bucket, створеного у попередньому завданні"
  type        = string
  default     = "demo-api-bucket-loving-ox"
}

variable "input_prefix" {
  description = "Префікс вхідної папки у бакеті S3"
  type        = string
  default     = "input/"
}

variable "processed_prefix" {
  description = "Префікс папки для оброблених файлів"
  type        = string
  default     = "processed/"
}

variable "ignored_prefix" {
  description = "Префікс папки для ігнорованих файлів"
  type        = string
  default     = "ignored/"
}

variable "csv_pattern" {
  description = "Регулярний вираз для валідації назви .csv файлів"
  type        = string
  default     = "^data_\\d{4}\\.csv$"
}

variable "json_pattern" {
  description = "Регулярний вираз для валідації назви .json файлів"
  type        = string
  default     = "^report_\\d{4}\\.json$"
}

