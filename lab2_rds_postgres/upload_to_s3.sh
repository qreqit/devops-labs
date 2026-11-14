#!/usr/bin/env bash
# Завантаження зразків відкритих даних з data.gov.ua у S3 bucket
set -e

BUCKET_NAME="${1:-demo-api-bucket-loving-ox}"

echo "============================================================"
echo " Завантаження даних у S3 bucket: s3://$BUCKET_NAME/data/"
echo "============================================================"

aws s3 cp data/organizations.csv "s3://$BUCKET_NAME/data/organizations.csv"
aws s3 cp data/tenders.csv "s3://$BUCKET_NAME/data/tenders.csv"

echo ""
echo "Вміст папки s3://$BUCKET_NAME/data/:"
aws s3 ls "s3://$BUCKET_NAME/data/"

echo "============================================================"
echo " Дані успішно завантажено в S3!"
echo "============================================================"

