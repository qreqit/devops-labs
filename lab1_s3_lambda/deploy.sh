#!/usr/bin/env bash
# Скрипт автоматичного розгортання через Terraform або AWS CLI
set -e

echo "============================================================"
echo " Розгортання S3 Event Router Lambda Функції"
echo "============================================================"

# Перевірка наявності необхідних утиліт
command -v terraform >/dev/null 2>&1 || { echo "Terraform не знайдено!"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "AWS CLI не знайдено!"; exit 1; }

echo "1. Запуск unit-тестів..."
python3 test_lambda.py

echo ""
echo "2. Ініціалізація та застосування Terraform..."
terraform init
terraform apply -auto-approve

echo ""
echo "============================================================"
echo " Розгортання успішно завершено!"
echo " Щоб перевірити роботу, запустіть: ./test_s3_flow.sh"
echo "============================================================"

