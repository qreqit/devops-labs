#!/usr/bin/env bash
# Розгортання Amazon RDS PostgreSQL через Terraform
set -e

echo "============================================================"
echo " Розгортання Amazon RDS PostgreSQL для Лабораторної роботи №2"
echo "============================================================"

command -v terraform >/dev/null 2>&1 || { echo "Terraform не встановлено!"; exit 1; }

terraform init
terraform apply -auto-approve

echo ""
echo "============================================================"
echo " Amazon RDS PostgreSQL успішно створено!"
echo " Параметри підключення:"
terraform output
echo "============================================================"

