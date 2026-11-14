"""
AWS Lambda функція для автоматичної обробки файлів у S3 bucket.

Функція реагує на подію створення файлу у вхідній папці (input/),
перевіряє назву файлу на відповідність регулярним виразам (шаблонам):
- Шаблон для .csv файлів (за замовчуванням: ^data_\\d{4}\\.csv$)
- Шаблон для .json файлів (за замовчуванням: ^report_\\d{4}\\.json$)

Якщо назва відповідає шаблону:
- файл переміщується у папку оброблених (processed/)
- до назви додається дата і час обробки у форматі yyyymmdd_hhmmss
  (наприклад: data_2024_20261114_143000.csv)

Якщо назва НЕ відповідає шаблону:
- файл переміщується до ігнорованих (ignored/) з оригінальною назвою.
"""

import os
import re
import logging
import urllib.parse
from datetime import datetime

# Налаштування логування для AWS CloudWatch
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Префікси папок у бакеті S3
INPUT_PREFIX = os.environ.get("INPUT_PREFIX", "input/").strip()
PROCESSED_PREFIX = os.environ.get("PROCESSED_PREFIX", "processed/").strip()
IGNORED_PREFIX = os.environ.get("IGNORED_PREFIX", "ignored/").strip()

# Нормалізація префіксів (мають завершуватися слешем)
if not INPUT_PREFIX.endswith("/"):
    INPUT_PREFIX += "/"
if not PROCESSED_PREFIX.endswith("/"):
    PROCESSED_PREFIX += "/"
if not IGNORED_PREFIX.endswith("/"):
    IGNORED_PREFIX += "/"

# Шаблони для перевірки імен файлів:
# 1. Шаблон для .csv файлів (наприклад: data_2024.csv, data_1234.csv)
CSV_PATTERN_STR = os.environ.get("CSV_PATTERN", r"^data_\d{4}\.csv$")
# 2. Шаблон для .json файлів (наприклад: report_2024.json, report_5678.json)
JSON_PATTERN_STR = os.environ.get("JSON_PATTERN", r"^report_\d{4}\.json$")

CSV_PATTERN = re.compile(CSV_PATTERN_STR)
JSON_PATTERN = re.compile(JSON_PATTERN_STR)

# Ініціалізація клієнта S3
try:
    import boto3
    s3_client = boto3.client("s3")
except ImportError:
    # Запасний варіант для локального тестування без встановленого boto3
    s3_client = None


def is_file_matching_pattern(filename: str) -> bool:
    """
    Перевіряє назву файлу на відповідність заданим шаблонам:
    - Якщо розширення .csv, перевіряється шаблон CSV_PATTERN
    - Якщо розширення .json, перевіряється шаблон JSON_PATTERN
    - Всі інші розширення повертають False
    """
    lower_filename = filename.lower()
    if lower_filename.endswith(".csv"):
        matches = bool(CSV_PATTERN.match(filename))
        logger.info("Файл '%s' перевірено за CSV-шаблоном ('%s'): %s", filename, CSV_PATTERN_STR, matches)
        return matches
    elif lower_filename.endswith(".json"):
        matches = bool(JSON_PATTERN.match(filename))
        logger.info("Файл '%s' перевірено за JSON-шаблоном ('%s'): %s", filename, JSON_PATTERN_STR, matches)
        return matches
    else:
        logger.info("Файл '%s' не є .csv або .json файлом", filename)
        return False


def move_s3_object(bucket: str, source_key: str, destination_key: str):
    """
    Переміщує об'єкт в S3 (копіювання на нове місце + видалення оригіналу).
    """
    copy_source = {"Bucket": bucket, "Key": source_key}
    logger.info("Копіювання s3://%s/%s -> s3://%s/%s", bucket, source_key, bucket, destination_key)
    s3_client.copy_object(
        Bucket=bucket,
        CopySource=copy_source,
        Key=destination_key
    )

    logger.info("Видалення оригінального файлу s3://%s/%s", bucket, source_key)
    s3_client.delete_object(
        Bucket=bucket,
        Key=source_key
    )


def process_record(record: dict):
    """
    Обробляє один запис про подію S3.
    """
    s3_info = record.get("s3", {})
    bucket_name = s3_info.get("bucket", {}).get("name")
    raw_key = s3_info.get("object", {}).get("key")

    if not bucket_name or not raw_key:
        logger.warning("Пропущено запис без назви бакету або ключа: %s", record)
        return

    # S3 кодує символи в URL (наприклад, пробіли як '+' або '%20')
    source_key = urllib.parse.unquote_plus(raw_key)

    # Ігноруємо виклики для об'єктів-папок
    if source_key.endswith("/"):
        logger.info("Пропущено папку: %s", source_key)
        return

    # Захист від зациклення: реагуємо ТІЛЬКИ на файли у вхідній папці (input/)
    if not source_key.startswith(INPUT_PREFIX):
        logger.info("Файл '%s' знаходиться поза вхідною папкою '%s'. Ігноруємо.", source_key, INPUT_PREFIX)
        return

    # Отримуємо ім'я файлу (без префіксу папки)
    filename = os.path.basename(source_key)

    # Отримуємо поточний час у форматі yyyymmdd_hhmmss
    now = datetime.now()
    timestamp_str = now.strftime("%Y%m%d_%H%M%S")

    # Перевірка на відповідність шаблонам
    if is_file_matching_pattern(filename):
        # Додаємо дату і час до назви файлу перед розширенням
        name_part, ext_part = os.path.splitext(filename)
        new_filename = f"{name_part}_{timestamp_str}{ext_part}"
        destination_key = f"{PROCESSED_PREFIX}{new_filename}"
        logger.info(
            "Файл '%s' відповідає шаблону! Переміщення до '%s'",
            filename, destination_key
        )
    else:
        # Переміщуємо до ігнорованих зі збереженням назви
        destination_key = f"{IGNORED_PREFIX}{filename}"
        logger.info(
            "Файл '%s' НЕ відповідає шаблону! Переміщення до '%s'",
            filename, destination_key
        )

    # Виконуємо операцію переміщення
    move_s3_object(bucket_name, source_key, destination_key)


def lambda_handler(event, context):
    """
    Головний вхідний обробник AWS Lambda.
    """
    logger.info("Отримано подію S3: %s", event)

    records = event.get("Records", [])
    if not records:
        logger.warning("У події відсутні записи 'Records'")
        return {
            "statusCode": 400,
            "body": "No records found in event"
        }

    for record in records:
        try:
            process_record(record)
        except Exception as e:
            logger.error("Помилка під час обробки запису %s: %s", record, str(e), exc_info=True)
            raise e

    return {
        "statusCode": 200,
        "body": f"Successfully processed {len(records)} record(s)."
    }
