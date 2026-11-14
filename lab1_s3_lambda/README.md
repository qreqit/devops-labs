# Лабораторна робота: AWS Lambda для фільтрації та маршрутизації файлів у S3

Даний проєкт реалізує безсерверну (Serverless) архітектуру на базі **AWS Lambda** та **Amazon S3**, яка автоматично реагує на завантаження нових файлів у вхідну папку, перевіряє їхні назви на відповідність заданим шаблонам та переміщує у відповідні папки.

---

## 📋 Вимоги та логіка роботи

1. **Реакція на подію**: Lambda-функція тригериться автоматично при появі нового об'єкта у вхідній папці S3 бакету (`input/`).
2. **Шаблони валідації назв файлів**:
   - **CSV-шаблон**: `^data_\d{4}\.csv$`  
     *Приклади валідних назв*: `data_2024.csv`, `data_1234.csv`, `data_0001.csv`
   - **JSON-шаблон**: `^report_\d{4}\.json$`  
     *Приклади валідних назв*: `report_2024.json`, `report_5678.json`, `report_0000.json`
3. **Обробка валідних файлів**:
   - Файл переміщується у папку `processed/`.
   - До назви файлу додається дата та час обробки у форматі `yyyymmdd_hhmmss`:  
     `data_2024.csv` $\rightarrow$ `processed/data_2024_20261114_143000.csv`
4. **Обробка невідповідних файлів**:
   - Файл переміщується у папку `ignored/` зі збереженням оригінального імені:  
     `sales_report.csv` $\rightarrow$ `ignored/sales_report.csv`  
     `config.json` $\rightarrow$ `ignored/config.json`  
     `document.txt` $\rightarrow$ `ignored/document.txt`
5. **Захист від нескінченного циклу (Recursion Guard)**:
   - S3 Event Notification налаштовано виключно на префікс `input/`.
   - Код Lambda перевіряє `key.startswith(INPUT_PREFIX)` та ігнорує виклики для файлів у `processed/` чи `ignored/`.

---

## 🗂 Структура проєкту

```text
├── lambda_function.py      # Вихідний код AWS Lambda функції (Python 3.12, boto3)
├── test_lambda.py          # Набір модульних (unit) тестів (12 тестів)
├── main.tf                 # Terraform конфігурація (IAM, Lambda, S3 Notification)
├── variables.tf            # Змінні Terraform (назва бакету, шаблони, префікси)
├── outputs.tf              # Вихідні параметри після розгортання
├── deploy.sh               # Скрипт автоматичного тестування та деплою
├── test_s3_flow.sh         # Скрипт перевірки роботи безпосередньо в AWS S3
└── README.md               # Документація проєкту
```

---

## 🚀 Способи розгортання

### Варіант 1: Автоматично через Terraform (Рекомендовано)

1. Переконайтеся, що налаштований AWS CLI (`aws configure`) та встановлений Terraform.
2. Запустіть скрипт розгортання:
   ```bash
   ./deploy.sh
   ```
   Або вручну:
   ```bash
   terraform init
   terraform apply -auto-approve
   ```

### Варіант 2: Вручну через AWS Management Console

1. **Створення IAM Ролі**:
   - Перейдіть в **IAM** $\rightarrow$ **Roles** $\rightarrow$ **Create role**.
   - Оберіть **AWS service** $\rightarrow$ **Lambda**.
   - Додайте політику з правами:
     - `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` на ваш бакет: `arn:aws:s3:::<your-bucket>/*`
     - `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` на `arn:aws:logs:*:*:*`
   - Назвіть роль: `s3_file_processor_lambda_role`.

2. **Створення Lambda Функції**:
   - Перейдіть в **AWS Lambda** $\rightarrow$ **Create function**.
   - Назва: `s3_file_pattern_processor`.
   - Runtime: `Python 3.12`.
   - Execution role: оберіть створену роль `s3_file_processor_lambda_role`.
   - Вставте код із файлу `lambda_function.py` та натисніть **Deploy**.

3. **Налаштування тригера S3**:
   - У вкладці функції **Function overview** натисніть **Add trigger**.
   - Оберіть **S3**.
   - Оберіть ваш бакет.
   - Event type: `All object create events` (`s3:ObjectCreated:*`).
   - Prefix: `input/`.
   - Поставте прапорець згоди щодо рекурсії та натисніть **Add**.

---

## 🧪 Тестування

### 1. Локальні Unit-тести
Модульні тести покривають усі сценарії (валідація CSV, JSON, невідповідні формати, інші розширення, URL-encoded ключі, захист від зациклення):
```bash
python3 test_lambda.py
```
Результат:
```text
Ran 12 tests in 0.009s
OK
```

### 2. Інтеграційний тест у реальному S3 бакеті
Скрипт створює та завантажує тестові файли у вхідну папку бакету, очікує обробки та виводить вміст папок `input/`, `processed/` та `ignored/`:
```bash
./test_s3_flow.sh
```

**Очікуваний результат:**
- `input/`: порожня (всі файли переміщено).
- `processed/`:
  - `data_2025_20261114_123039.csv` (додано дату та час `yyyymmdd_hhmmss`)
  - `report_2025_20261114_123040.json` (додано дату та час `yyyymmdd_hhmmss`)
- `ignored/`:
  - `sales_summary.csv` (назва не відповідає `^data_\d{4}\.csv$`)
  - `app_config.json` (назва не відповідає `^report_\d{4}\.json$`)
  - `readme.txt` (розширення не підтримується)

---

## 📊 Моніторинг та логи

Логи обробки кожного файлу можна переглянути через AWS CLI або в AWS CloudWatch:
```bash
aws logs tail /aws/lambda/s3_file_pattern_processor --region us-east-1 --since 10m
```

