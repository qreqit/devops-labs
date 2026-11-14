#!/usr/bin/env bash
# Пакування Lambda функції разом із бібліотекою psycopg2-binary
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
ZIP_FILE="$SCRIPT_DIR/lambda.zip"

echo "============================================================"
echo " Пакування AWS Lambda функції для Lab 3"
echo "============================================================"

# Очищення попереднього білду
rm -rf "$BUILD_DIR" "$ZIP_FILE"
mkdir -p "$BUILD_DIR"

echo "1. Встановлення залежності psycopg2-binary..."
python3 -m pip install --platform manylinux2014_x86_64 --target "$BUILD_DIR" --implementation cp --python-version 3.12 --only-binary=:all: psycopg2-binary

echo "2. Копіювання коду функції..."
cp "$SCRIPT_DIR/lambda_function.py" "$BUILD_DIR/"

echo "3. Створення zip-архіву $ZIP_FILE ..."
cd "$BUILD_DIR"
zip -r9 "$ZIP_FILE" . -x "*.pyc" "__pycache__/*" >/dev/null
cd "$SCRIPT_DIR"

rm -rf "$BUILD_DIR"

echo "============================================================"
echo " Архів успішно створено: $ZIP_FILE ($(du -h "$ZIP_FILE" | cut -f1))"
echo "============================================================"

