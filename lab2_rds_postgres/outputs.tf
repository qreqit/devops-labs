output "rds_endpoint" {
  description = "Хост/Endpoint для підключення до PostgreSQL"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_address" {
  description = "DNS адреса бази даних (без порту)"
  value       = aws_db_instance.postgres.address
}

output "rds_port" {
  description = "Порт PostgreSQL"
  value       = aws_db_instance.postgres.port
}

output "database_name" {
  description = "Назва бази даних"
  value       = aws_db_instance.postgres.db_name
}

output "database_username" {
  description = "Ім'я адміністратора"
  value       = aws_db_instance.postgres.username
}

output "connection_string" {
  description = "Команда для підключення через psql"
  value       = "psql -h ${aws_db_instance.postgres.address} -p ${aws_db_instance.postgres.port} -U ${aws_db_instance.postgres.username} -d ${aws_db_instance.postgres.db_name}"
}

