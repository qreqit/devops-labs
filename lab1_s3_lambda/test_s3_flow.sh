#!/usr/bin/env bash
set -e

# Назва S3 bucket (за замовчуванням береться з terraform output або змінної оточення)
BUCKET_NAME="${1:-$(terraform output -raw s3_bucket_name 2>/dev/null || echo 'demo-api-bucket-loving-ox')}"

echo "============================================================"
echo " Тестування S3 Event Trigger + AWS Lambda"
echo " Бакет: s3://$BUCKET_NAME"
echo "============================================================"

# Створюємо тимчасові тестові файли
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

echo "1. Створення тестових файлів..."
# Валідні файли за шаблонами (^data_\d{4}\.csv$ та ^report_\d{4}\.json$)
echo "id,name,amount\n1,Alpha,500" > "$TMP_DIR/data_2025.csv"
echo '{"report_id": 2025, "metric": "growth", "value": 15.4}' > "$TMP_DIR/report_2025.json"

# Невалідні файли
echo "wrong,csv,data" > "$TMP_DIR/sales_summary.csv"
echo '{"settings": "debug"}' > "$TMP_DIR/app_config.json"
echo "Unsupported plain text file" > "$TMP_DIR/readme.txt"

echo "2. Завантаження файлів у вхідну папку s3://$BUCKET_NAME/input/ ..."
aws s3 cp "$TMP_DIR/data_2025.csv" "s3://$BUCKET_NAME/input/data_2025.csv"
aws s3 cp "$TMP_DIR/report_2025.json" "s3://$BUCKET_NAME/input/report_2025.json"
aws s3 cp "$TMP_DIR/sales_summary.csv" "s3://$BUCKET_NAME/input/sales_summary.csv"
aws s3 cp "$TMP_DIR/app_config.json" "s3://$BUCKET_NAME/input/app_config.json"
aws s3 cp "$TMP_DIR/readme.txt" "s3://$BUCKET_NAME/input/readme.txt"

echo ""
echo "3. Очікування виконання Lambda функції (4 секунди)..."
sleep 4

echo ""
echo "4. Результати у бакеті s3://$BUCKET_NAME/ :"
echo "------------------------------------------------------------"
echo "[Вхідна папка - input/ (має бути порожньою)]:"
aws s3 ls "s3://$BUCKET_NAME/input/" || true

echo ""
echo "[Папка оброблених - processed/ (валідовані файли з датою і часом)]:"
aws s3 ls "s3://$BUCKET_NAME/processed/" || true

echo ""
echo "[Папка ігнорованих - ignored/ (файли, що не відповідають шаблонам)]:"
aws s3 ls "s3://$BUCKET_NAME/ignored/" || true

echo "============================================================"
echo " Тест завершено успішно!"
echo "============================================================"

