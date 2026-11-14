-- ============================================================================
-- Скрипт 1: Створення бази даних та підключення розширень для AWS RDS
-- ============================================================================

-- Примітка: В Amazon RDS база даних зазвичай створюється при ініціалізації
-- інстансу (через параметр DBName у Terraform чи консолі).
-- Якщо підключення виконано під користувачем postgres до системної БД:

CREATE DATABASE opendata_db
    WITH 
    OWNER = dbadmin
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.UTF-8'
    LC_CTYPE = 'en_US.UTF-8'
    TEMPLATE = template0;

\connect opendata_db

-- Підключення розширень для роботи з AWS S3
-- Розширення aws_s3 та aws_commons доступні «з коробки» в Amazon RDS для PostgreSQL
-- і дозволяють імпортувати дані безпосередньо з S3 через команду SELECT aws_s3.table_import_from_s3(...)
CREATE EXTENSION IF NOT EXISTS aws_commons;
CREATE EXTENSION IF NOT EXISTS aws_s3;

-- Додаткові корисні розширення (для генерації UUID тощо при потребі)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

COMMENT ON DATABASE opendata_db IS 'База даних для відкритих даних України (data.gov.ua / Prozorro)';

