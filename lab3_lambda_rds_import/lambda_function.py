"""
AWS Lambda функція для автоматичної вставки даних у PostgreSQL (Amazon RDS)
при спрацюванні тригера S3 з уникненням дублікатів (Deduplication / UPSERT).

Підтримує два драйвери підключення:
- psycopg2 (psycopg2-binary)
- pg8000 (чистий Python)

Методика уникнення дублікатів:
1. Завантаження у тимчасову таблицю (temp_*) через команду COPY.
2. Вставка в основну таблицю за допомогою INSERT ... ON CONFLICT DO UPDATE
   (або виклик збережуваної процедури sync_*_from_staging).
3. Використання DISTINCT ON для усунення дублікатів навіть у межах одного вхідного файлу.
"""

import io
import os
import re
import csv
import logging
import urllib.parse
from datetime import datetime
try:
    import boto3
    s3_client = boto3.client("s3")
except ImportError:
    s3_client = None

# Налаштування логування
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Параметри підключення до бази даних (змінні оточення)
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "opendata_db")
DB_USER = os.environ.get("DB_USER", "dbadmin")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "SecurePass2026!")

# Префікси папок S3
INPUT_PREFIX = os.environ.get("INPUT_PREFIX", "input/").strip()
PROCESSED_PREFIX = os.environ.get("PROCESSED_PREFIX", "processed/").strip()
ERROR_PREFIX = os.environ.get("ERROR_PREFIX", "error/").strip()

if not INPUT_PREFIX.endswith("/"):
    INPUT_PREFIX += "/"
if not PROCESSED_PREFIX.endswith("/"):
    PROCESSED_PREFIX += "/"
if not ERROR_PREFIX.endswith("/"):
    ERROR_PREFIX += "/"

# Режим дедуплікації: 'UPDATE' (UPSERT — оновлювати існуючі дані) або 'IGNORE' (пропускати дублікати)
DEDUP_MODE = os.environ.get("DEDUP_MODE", "UPDATE").upper()

# Чи викликати збережувану процедуру замість прямого SQL
USE_STORED_PROCEDURE = os.environ.get("USE_STORED_PROCEDURE", "true").lower() == "true"


def get_db_connection():
    """
    Встановлює з'єднання з базою даних PostgreSQL.
    Автоматично визначає наявний драйвер: psycopg2 або pg8000.
    """
    try:
        import psycopg2
        logger.info("Підключення до PostgreSQL через psycopg2 (%s:%s/%s)", DB_HOST, DB_PORT, DB_NAME)
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            connect_timeout=10
        )
        return conn, "psycopg2"
    except ImportError:
        pass

    try:
        import pg8000.native
        logger.info("Підключення до PostgreSQL через pg8000 (%s:%s/%s)", DB_HOST, DB_PORT, DB_NAME)
        conn = pg8000.native.Connection(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            timeout=10
        )
        return conn, "pg8000"
    except ImportError:
        pass

    raise RuntimeError("Не знайдено жодного драйвера PostgreSQL (psycopg2 або pg8000).")


def detect_target_table(header_line: str, filename: str) -> str:
    """
    Визначає цільову таблицю (organizations або tenders)
    за назвою файлу або списком колонок у заголовку CSV.
    """
    lower_name = filename.lower()
    lower_header = header_line.lower()

    if "tender" in lower_name or "tender_id" in lower_header:
        return "tenders"
    if "organization" in lower_name or "edrpou" in lower_header or "org" in lower_name:
        return "organizations"

    # За замовчуванням для першої таблиці
    if "edrpou" in lower_header:
        return "organizations"

    raise ValueError(f"Неможливо визначити цільову таблицю для файлу '{filename}' із заголовком '{header_line}'")


def import_with_psycopg2(conn, table_name: str, csv_content: str):
    """
    Імпорт даних через psycopg2 з використанням тимчасової таблиці,
    команди COPY та збережуваної процедури / UPSERT для дедуплікації.
    """
    with conn.cursor() as cur:
        # 1. Створюємо тимчасову таблицю без обмежень первинного ключа
        temp_table = f"temp_{table_name}"
        cur.execute(f"DROP TABLE IF EXISTS {temp_table};")
        cur.execute(f"CREATE TEMP TABLE {temp_table} (LIKE {table_name} INCLUDING DEFAULTS) ON COMMIT DROP;")

        # 2. Швидке завантаження потоку CSV через команду COPY
        csv_file = io.StringIO(csv_content)
        # Визначаємо колонки з першого рядка
        first_line = csv_content.splitlines()[0]
        columns = [c.strip().strip('"') for c in first_line.split(",")]
        cols_str = ", ".join(columns)

        copy_sql = f"COPY {temp_table} ({cols_str}) FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER ',');"
        cur.copy_expert(copy_sql, csv_file)

        cur.execute(f"SELECT COUNT(*) FROM {temp_table};")
        staging_count = cur.fetchone()[0]
        logger.info("Завантажено %d рядків у тимчасову таблицю %s", staging_count, temp_table)

        # 3. Дедуплікація та перенесення даних в основну таблицю
        if USE_STORED_PROCEDURE:
            # Спосіб 2: Виклик збережуваної процедури
            proc_name = f"sync_{table_name}_from_staging"
            logger.info("Виклик збережуваної процедури %s(p_mode => '%s')", proc_name, DEDUP_MODE)
            cur.execute(f"CALL {proc_name}(%s);", (DEDUP_MODE,))
            inserted, updated = staging_count, 0 # детальний підсумок у raise notice
        else:
            # Спосіб 3: Прямий SQL UPSERT із дедуплікацією через DISTINCT ON
            inserted, updated = execute_direct_upsert(cur, table_name, temp_table)

        conn.commit()
        return staging_count, inserted, updated


def execute_direct_upsert(cur, table_name: str, temp_table: str):
    """
    Прямий SQL-запит для дедуплікації та вставки через ON CONFLICT.
    """
    if table_name == "organizations":
        sql = """
        WITH upsert_res AS (
            INSERT INTO organizations (
                edrpou, legal_name, short_name, org_type, 
                region, city, postal_code, address, email, phone
            )
            SELECT DISTINCT ON (TRIM(edrpou))
                TRIM(edrpou), TRIM(legal_name), NULLIF(TRIM(short_name), ''), NULLIF(TRIM(org_type), ''),
                TRIM(region), TRIM(city), NULLIF(TRIM(postal_code), ''), NULLIF(TRIM(address), ''),
                NULLIF(TRIM(email), ''), NULLIF(TRIM(phone), '')
            FROM temp_organizations
            WHERE edrpou IS NOT NULL AND TRIM(edrpou) <> ''
            ORDER BY TRIM(edrpou)
            ON CONFLICT (edrpou) DO UPDATE SET
                legal_name  = EXCLUDED.legal_name,
                short_name  = COALESCE(EXCLUDED.short_name, organizations.short_name),
                org_type    = COALESCE(EXCLUDED.org_type, organizations.org_type),
                region      = EXCLUDED.region,
                city        = EXCLUDED.city,
                postal_code = COALESCE(EXCLUDED.postal_code, organizations.postal_code),
                address     = COALESCE(EXCLUDED.address, organizations.address),
                email       = COALESCE(EXCLUDED.email, organizations.email),
                phone       = COALESCE(EXCLUDED.phone, organizations.phone)
            RETURNING (xmax = 0) AS is_insert
        )
        SELECT 
            COUNT(*) FILTER (WHERE is_insert),
            COUNT(*) FILTER (WHERE NOT is_insert)
        FROM upsert_res;
        """
        cur.execute(sql)
        row = cur.fetchone()
        inserted, updated = row[0] or 0, row[1] or 0
        return inserted, updated
    else:
        sql = """
        WITH upsert_res AS (
            INSERT INTO tenders (
                tender_id, title, description, procuring_entity_edrpou, 
                expected_value, currency, procedure_type, status, start_date, end_date
            )
            SELECT DISTINCT ON (TRIM(tender_id))
                TRIM(tender_id), TRIM(title), NULLIF(TRIM(description), ''), TRIM(procuring_entity_edrpou),
                expected_value, COALESCE(NULLIF(TRIM(currency), ''), 'UAH'), TRIM(procedure_type),
                TRIM(status), start_date, end_date
            FROM temp_tenders
            WHERE tender_id IS NOT NULL AND TRIM(tender_id) <> ''
            ORDER BY TRIM(tender_id)
            ON CONFLICT (tender_id) DO UPDATE SET
                title          = EXCLUDED.title,
                description    = COALESCE(EXCLUDED.description, tenders.description),
                expected_value = EXCLUDED.expected_value,
                status         = EXCLUDED.status,
                end_date       = EXCLUDED.end_date
            RETURNING (xmax = 0) AS is_insert
        )
        SELECT 
            COUNT(*) FILTER (WHERE is_insert),
            COUNT(*) FILTER (WHERE NOT is_insert)
        FROM upsert_res;
        """
        cur.execute(sql)
        row = cur.fetchone()
        inserted, updated = row[0] or 0, row[1] or 0
        return inserted, updated


def move_s3_object(bucket: str, source_key: str, dest_key: str):
    """
    Переміщує об'єкт в S3 (копіювання на нове місце + видалення оригіналу).
    """
    logger.info("Переміщення s3://%s/%s -> s3://%s/%s", bucket, source_key, bucket, dest_key)
    s3_client.copy_object(
        Bucket=bucket,
        CopySource={"Bucket": bucket, "Key": source_key},
        Key=dest_key
    )
    s3_client.delete_object(
        Bucket=bucket,
        Key=source_key
    )


def process_s3_file(bucket_name: str, object_key: str):
    """
    Завантажує файл з S3, розпізнає структуру, вставляє в PostgreSQL з дедуплікацією.
    """
    logger.info("Початок обробки файлу s3://%s/%s", bucket_name, object_key)

    # 1. Завантажуємо файл з S3
    response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
    content_bytes = response["Body"].read()
    csv_content = content_bytes.decode("utf-8")

    lines = csv_content.strip().splitlines()
    if not lines:
        logger.warning("Файл %s порожній!", object_key)
        return

    first_line = lines[0]
    filename = os.path.basename(object_key)

    # 2. Визначаємо цільову таблицю
    table_name = detect_target_table(first_line, filename)
    logger.info("Цільова таблиця для '%s': '%s'", filename, table_name)

    # 3. Підключаємося до бази даних та виконуємо імпорт
    conn, driver_type = get_db_connection()
    try:
        staging_count, inserted, updated = import_with_psycopg2(conn, table_name, csv_content)
        logger.info(
            "Успішно імпортовано у '%s': всього у файлі=%d, нових=%d, дублікатів (оновлено/пропущено)=%d",
            table_name, staging_count, inserted, updated
        )
    finally:
        conn.close()

    # 4. Переміщуємо оброблений файл до папки processed/ із таймстампом
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    name_part, ext_part = os.path.splitext(filename)
    new_filename = f"{name_part}_{timestamp}{ext_part}"
    dest_key = f"{PROCESSED_PREFIX}{new_filename}"

    move_s3_object(bucket_name, object_key, dest_key)
    logger.info("Файл успішно переміщено до '%s'", dest_key)


def lambda_handler(event, context):
    """
    Головна точка входу AWS Lambda при виклику від S3.
    """
    logger.info("Отримано подію S3: %s", event)

    records = event.get("Records", [])
    if not records:
        logger.warning("У події відсутні записи 'Records'")
        return {"statusCode": 400, "body": "No records in event"}

    processed_count = 0
    for record in records:
        s3_info = record.get("s3", {})
        bucket_name = s3_info.get("bucket", {}).get("name")
        raw_key = s3_info.get("object", {}).get("key")

        if not bucket_name or not raw_key:
            continue

        object_key = urllib.parse.unquote_plus(raw_key)

        # Пропускаємо папки
        if object_key.endswith("/"):
            continue

        # Захист від зациклення: обробляємо тільки файли з вхідної папки
        if not object_key.startswith(INPUT_PREFIX):
            logger.info("Пропущено файл поза вхідною папкою: %s", object_key)
            continue

        try:
            process_s3_file(bucket_name, object_key)
            processed_count += 1
        except Exception as e:
            logger.error("Помилка обробки файлу s3://%s/%s: %s", bucket_name, object_key, str(e), exc_info=True)
            # Переміщуємо файл у папку помилок
            try:
                err_filename = os.path.basename(object_key)
                err_dest = f"{ERROR_PREFIX}{err_filename}"
                move_s3_object(bucket_name, object_key, err_dest)
            except Exception as move_err:
                logger.error("Не вдалося перемістити файл до error/: %s", move_err)
            raise e

    return {
        "statusCode": 200,
        "body": f"Successfully processed {processed_count} file(s) into PostgreSQL database."
    }
