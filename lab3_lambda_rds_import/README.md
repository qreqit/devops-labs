# Лабораторна робота: Автоматичний імпорт даних з S3 у PostgreSQL через AWS Lambda з дедуплікацією

Даний проєкт реалізує безсерверний пайплайн завантаження даних (Serverless ELT Pipeline):
1. **S3 Event Trigger**: при завантаженні CSV-файлу у вхідну папку `input/` бакету S3 автоматично викликається **AWS Lambda**.
2. **PostgreSQL Ingestion**: функція зчитує вміст файлу та виконує швидкісну вставку у СКБД **PostgreSQL (Amazon RDS)**.
3. **Механізм дедуплікації**: забезпечено 100% захист від появи дублікатів за первинним ключем (код ЄДРПОУ для організацій, ID тендеру для закупівель).

---

## 🔍 Аналіз можливих способів дедуплікації

Вимоги завдання пропонують розглянути різні підходи до вирішення задачі:

| Спосіб | Принцип роботи | Переваги | Обмеження / Недоліки |
| :--- | :--- | :--- | :--- |
| **1. Тільки SQL команда `COPY`** | Прямий імпорт `COPY organizations FROM STDIN` | Найвища швидкість передачі даних | ❌ **Не підтримує `ON CONFLICT`**. При наявності хоча б одного дубліката весь імпорт переривається фатальною помилкою: `duplicate key value violates unique constraint`. |
| **2. Збережувана процедура + тимчасові таблиці** | 1. `COPY` у `temp_organizations`<br>2. Виклик процедури `sync_organizations_from_staging()`<br>3. `INSERT ... ON CONFLICT` | Швидкість `COPY` + безпечна дедуплікація + інкапсуляція бізнес-логіки в БД | Потребує попереднього створення процедури в базі даних. |
| **3. Наше комплексне рішення (Serverless ELT)** | Поєднання способу 2 із динамічним визначенням типу файлу, переміщенням в S3 та моніторингом метрик | Автоматичне визначення цільової таблиці за схемою, підтримка `psycopg2` / `pg8000`, усунення дублікатів усередині вхідного пакету (`DISTINCT ON`) | Потребує налаштування мережевого доступу між Lambda та RDS. |

---

## ⚙️ Як працює механізм усунення дублікатів

1. **Захист від дублікатів всередині одного файлу**:
   Якщо у завантаженому CSV-файлі один і той самий ЄДРПОУ зустрічається кілька разів (наприклад, стара і нова версія адреси), конструкція `SELECT DISTINCT ON (TRIM(edrpou))` залишає лише один актуальний рядок:
   ```sql
   SELECT DISTINCT ON (TRIM(edrpou))
       TRIM(edrpou), TRIM(legal_name), ...
   FROM temp_organizations
   WHERE edrpou IS NOT NULL AND TRIM(edrpou) <> ''
   ORDER BY TRIM(edrpou)
   ```

2. **Захист від дублікатів з раніше завантаженими даними**:
   Використовується конструкція `ON CONFLICT (edrpou)`:
   - **Режим `UPDATE` (UPSERT)**: якщо організація з таким ЄДРПОУ вже є в базі, її реквізити оновлюються свіжими даними з нового файлу:
     ```sql
     ON CONFLICT (edrpou) DO UPDATE SET
         legal_name  = EXCLUDED.legal_name,
         short_name  = COALESCE(EXCLUDED.short_name, organizations.short_name),
         address     = COALESCE(EXCLUDED.address, organizations.address),
         ...
     ```
   - **Режим `IGNORE` (DO NOTHING)**: якщо запис існує, новий запис просто ігнорується без помилки:
     ```sql
     ON CONFLICT (edrpou) DO NOTHING;
     ```

---

## 🗂 Структура файлів проєкту

```text
lab3_lambda_rds_import/
├── lambda_function.py           # Модифікована Lambda-функція (S3 -> PostgreSQL)
├── test_lambda.py               # Unit-тести логіки дедуплікації та імпорту (5 тестів)
├── package_lambda.sh            # Скрипт збирання lambda.zip разом із psycopg2-binary
├── main.tf                      # Terraform конфігурація Lambda, IAM та S3 тригера
├── variables.tf                 # Змінні (хост БД, користувач, назва бакету, режим)
├── outputs.tf                   # Вихідні параметри Terraform
├── test_s3_to_rds.sh            # Інтеграційний тест файлу з дублікатами в S3
├── .gitignore                   # Ігнорування білдів та стану Terraform
├── sql/
│   ├── 01_stored_procedures.sql # Збережувані процедури sync_*_from_staging (Спосіб 2)
│   └── 02_schema_reference.sql  # Довідкова схема цільових таблиць
└── data/
    ├── organizations_with_duplicates.csv # Тестовий файл з повторюваними ЄДРПОУ
    └── tenders_with_duplicates.csv       # Тестовий файл з повторюваними закупівлями
```

---

## 🚀 Покроковий запуск та тестування

### Крок 1: Створення процедур у базі даних PostgreSQL
Підключіться до вашої бази даних (Amazon RDS або EC2) та виконайте збережувані процедури:
```bash
psql -h <RDS_ENDPOINT> -p 5432 -U dbadmin -d opendata_db -f sql/01_stored_procedures.sql
```

### Крок 2: Пакування Lambda функції із залежностями
Оскільки функція взаємодіє з PostgreSQL, їй необхідний драйвер `psycopg2`. Скрипт автоматично завантажує бінарний сумісний wheel для AWS Lambda (Python 3.12, Linux x86_64) та створює `lambda.zip`:
```bash
./package_lambda.sh
```

### Крок 3: Запуск локальних Unit-тестів
```bash
python3 test_lambda.py
```
Вивід:
```text
Ran 5 tests in 0.008s
OK
```

### Крок 4: Розгортання інфраструктури (Terraform)
Вкажіть endpoint вашого RDS інстансу у `terraform.tfvars` або через змінну оточення:
```bash
terraform init
terraform apply -var="db_host=<RDS_ENDPOINT>" -auto-approve
```

### Крок 5: Тестування дедуплікації в S3
Запустіть тестовий скрипт:
```bash
./test_s3_to_rds.sh
```
Він завантажить файл `data/organizations_with_duplicates.csv`, у якому код ЄДРПОУ `02125266` та `04054346` дублюються по кілька разів.

**Результат:**
1. Файл оброблено без жодної помилки `duplicate key violation`.
2. У таблиці `organizations` кожен ЄДРПОУ збережено рівно в одному екземплярі (`COUNT(*) = 3`).
3. Файл переміщено до `processed/organizations_batch1_YYYYMMDD_HHMMSS.csv`.

