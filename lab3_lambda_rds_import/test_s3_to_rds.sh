#!/usr/bin/env bash
# Тестування завантаження файлу з дублікатами в S3
set -e

BUCKET_NAME="${1:-demo-api-bucket-loving-ox}"

echo "============================================================"
echo " Тестування S3 Trigger + Lambda + RDS Дедуплікація"
echo " Бакет: s3://$BUCKET_NAME"
echo "============================================================"

echo "1. Завантаження файлу з дублікатами у вхідну папку input/ ..."
aws s3 cp data/organizations_with_duplicates.csv "s3://$BUCKET_NAME/input/organizations_batch1.csv"

echo ""
echo "2. Очікування спрацювання тригера та виконання Lambda (5 секунд)..."
sleep 5

echo ""
echo "3. Вміст папок S3:"
echo "[Вхідна папка - input/]:"
aws s3 ls "s3://$BUCKET_NAME/input/" || true

echo ""
echo "[Папка оброблених - processed/]:"
aws s3 ls "s3://$BUCKET_NAME/processed/" || true

echo ""
echo "4. Перегляд останніх логів CloudWatch:"
aws logs tail /aws/lambda/s3_to_rds_postgres_importer --region us-east-1 --since 3m 2>/dev/null || echo "Логи ще генеруються або функцію не запущено."

echo "============================================================"
echo " Тест завершено!"
echo "============================================================"

