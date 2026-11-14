-- ============================================================================
-- Скрипт 3: Імпорт даних з AWS S3 bucket у створені таблиці
-- ============================================================================

-- ВАЖЛИВО: Оскільки між таблицями діє обмеження зовнішнього ключа (Foreign Key),
-- спочатку ОБОВ'ЯЗКОВО імпортуються дані в головну таблицю (organizations),
-- а потім — у підлеглу таблицю (tenders).

-- ----------------------------------------------------------------------------
-- ВАРІАНТ А: Прямий імпорт в Amazon RDS за допомогою розширення aws_s3
-- (Найбільш ефективний спосіб безпосередньо з хмари без передачі на клієнт)
-- ----------------------------------------------------------------------------

-- 1. Імпорт організацій із CSV-файлу в бакеті S3
SELECT aws_s3.table_import_from_s3(
    'organizations',
    'edrpou,legal_name,short_name,org_type,region,city,postal_code,address,email,phone',
    '(format csv, header true, delimiter '','', encoding ''utf-8'')',
    aws_commons.create_s3_uri(
        'demo-api-bucket-loving-ox',          -- Назва вашого S3 бакету
        'data/organizations.csv',             -- Шлях до файлу в S3
        'us-east-1'                           -- Регіон S3 бакету
    )
);

-- 2. Імпорт тендерів із CSV-файлу в бакеті S3
SELECT aws_s3.table_import_from_s3(
    'tenders',
    'tender_id,title,description,procuring_entity_edrpou,expected_value,currency,procedure_type,status,start_date,end_date',
    '(format csv, header true, delimiter '','', encoding ''utf-8'')',
    aws_commons.create_s3_uri(
        'demo-api-bucket-loving-ox',          -- Назва вашого S3 бакету
        'data/tenders.csv',                   -- Шлях до файлу в S3
        'us-east-1'                           -- Регіон S3 бакету
    )
);


-- ----------------------------------------------------------------------------
-- ВАРІАНТ Б: Імпорт через стандартну команду PostgreSQL \copy
-- (Працює як для Amazon RDS, так і для PostgreSQL на базі Amazon EC2)
-- ----------------------------------------------------------------------------

-- Крок 1 в терміналі (завантаження з S3 на клієнтську машину або EC2):
--   aws s3 cp s3://demo-api-bucket-loving-ox/data/organizations.csv ./organizations.csv
--   aws s3 cp s3://demo-api-bucket-loving-ox/data/tenders.csv ./tenders.csv

-- Крок 2 в psql:
\copy organizations (edrpou, legal_name, short_name, org_type, region, city, postal_code, address, email, phone) FROM 'data/organizations.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',', ENCODING 'UTF8');

\copy tenders (tender_id, title, description, procuring_entity_edrpou, expected_value, currency, procedure_type, status, start_date, end_date) FROM 'data/tenders.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',', ENCODING 'UTF8');


-- ----------------------------------------------------------------------------
-- ВАРІАНТ В: Потоковий імпорт без проміжних локальних файлів (через pipe)
-- ----------------------------------------------------------------------------
-- aws s3 cp s3://demo-api-bucket-loving-ox/data/organizations.csv - | psql -h <rds-endpoint> -U dbadmin -d opendata_db -c "\copy organizations (edrpou, legal_name, short_name, org_type, region, city, postal_code, address, email, phone) FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER ',');"
-- aws s3 cp s3://demo-api-bucket-loving-ox/data/tenders.csv - | psql -h <rds-endpoint> -U dbadmin -d opendata_db -c "\copy tenders (tender_id, title, description, procuring_entity_edrpou, expected_value, currency, procedure_type, status, start_date, end_date) FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER ',');"

