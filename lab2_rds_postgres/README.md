# Лабораторна робота: Розгортання СКБД PostgreSQL в AWS та імпорт даних з S3 (data.gov.ua)

Цей проєкт містить повний набір матеріалів для виконання лабораторної роботи:
1. Створення керованого екземпляра **Amazon RDS** для СКБД **PostgreSQL** (або на базі **Amazon EC2**).
2. Створення реляційної бази даних з двома таблицями, оптимізованими для імпорту відкритих даних України з порталу [data.gov.ua](https://data.gov.ua) через **AWS S3 bucket**.
3. SQL-скрипти DDL (створення таблиць, індекси, ключі, обмеження), скрипти імпорту даних та аналітичні запити.

---

## 📊 Обраний набір відкритих даних

- **Джерело**: Єдиний державний веб-портал відкритих даних [data.gov.ua](https://data.gov.ua/dataset) (набори даних системи електронних закупівель **Prozorro** та ЄДРПОУ замовників).
- **Зв'язок між таблицями**: Реляційний зв'язок один-до-багатьох ($1:N$). Один замовник (організація) може проводити багато закупівель (тендерів).

### Таблиця 1: `organizations` (Головна таблиця — Організації-замовники)
| Стовпець | Тип даних | Опис / Обмеження |
| :--- | :--- | :--- |
| `edrpou` | `VARCHAR(10)` | **PRIMARY KEY**. Код за ЄДРПОУ (8 цифр для юросіб або 10 для ФОП) |
| `legal_name` | `VARCHAR(500)` | `NOT NULL`. Повна офіційна назва юридичної особи |
| `short_name` | `VARCHAR(250)` | Скорочене найменування організації |
| `org_type` | `VARCHAR(150)` | Тип / організаційно-правова форма (ЗВО, ОМС, КНП тощо) |
| `region` | `VARCHAR(100)` | `NOT NULL`. Область України |
| `city` | `VARCHAR(100)` | `NOT NULL`. Населений пункт реєстрації |
| `postal_code` | `VARCHAR(10)` | Поштовий індекс |
| `address` | `TEXT` | Повна юридична та фактична адреса |
| `email` | `VARCHAR(150)` | Офіційний e-mail |
| `phone` | `VARCHAR(50)` | Контактний телефон |
| `created_at` | `TIMESTAMPTZ` | Час запису в базу даних (`DEFAULT CURRENT_TIMESTAMP`) |

### Таблиця 2: `tenders` (Підлегла таблиця — Публічні закупівлі)
| Стовпець | Тип даних | Опис / Обмеження |
| :--- | :--- | :--- |
| `tender_id` | `VARCHAR(50)` | **PRIMARY KEY**. Унікальний номер закупівлі (наприклад, `UA-2026-09-15-001001-a`) |
| `title` | `TEXT` | `NOT NULL`. Назва предмета закупівлі |
| `description` | `TEXT` | Детальний опис закупівлі та технічні характеристики |
| `procuring_entity_edrpou` | `VARCHAR(10)` | **FOREIGN KEY** $\rightarrow$ `organizations(edrpou)`. Код ЄДРПОУ замовника |
| `expected_value` | `NUMERIC(15, 2)`| `NOT NULL`, `CHECK (expected_value >= 0)`. Очікувана вартість у гривнях |
| `currency` | `VARCHAR(3)` | Валюта (`DEFAULT 'UAH'`) |
| `procedure_type` | `VARCHAR(150)` | `NOT NULL`. Вид процедури закупівлі |
| `status` | `VARCHAR(50)` | `NOT NULL`. Статус закупівлі (`active.tendering`, `complete`, `cancelled`) |
| `start_date` | `TIMESTAMPTZ` | `NOT NULL`. Дата та час початку подання пропозицій |
| `end_date` | `TIMESTAMPTZ` | `NOT NULL`, `CHECK (end_date >= start_date)`. Дата завершення подання |
| `created_at` | `TIMESTAMPTZ` | Час внесення запису (`DEFAULT CURRENT_TIMESTAMP`) |

---

## 🗂 Структура файлів проєкту

```text
lab2_rds_postgres/
├── sql/
│   ├── 01_create_database.sql   # Створення БД opendata_db та розширень aws_s3, aws_commons
│   ├── 02_create_tables.sql     # DDL-скрипт створення таблиць organizations і tenders
│   ├── 03_import_from_s3.sql    # Скрипти імпорту з S3 (через розширення aws_s3 та \copy)
│   └── 04_analytical_queries.sql# Запити для перевірки та аналітики імпортованих даних
├── data/
│   ├── organizations.csv        # Зразок даних реєстру організацій (data.gov.ua)
│   └── tenders.csv              # Зразок відкритих даних закупівель (data.gov.ua)
├── main.tf                      # Terraform-конфігурація RDS PostgreSQL та IAM-ролі S3
├── variables.tf                 # Змінні Terraform (регіон, параметри БД, бакет)
├── outputs.tf                   # Вихідні параметри (endpoint, connection string)
├── upload_to_s3.sh              # Скрипт автоматичного завантаження даних у S3
├── deploy_rds.sh                # Скрипт автоматичного створення RDS через Terraform
├── .gitignore                   # Ігнорування службових файлів Terraform
└── README.md                    # Цей посібник та інструкція
```

---

## 🚀 Варіанти створення СКБД у хмарі AWS

### Спосіб 1: Amazon RDS для PostgreSQL (Рекомендований AWS-підхід)

Amazon RDS — це повністю керований сервіс реляційних баз даних (DBaaS), що бере на себе адміністрування, патчінг, автоматичні бекапи та масштабування.

#### Автоматичне розгортання через Terraform:
```bash
./deploy_rds.sh
```
Або покроково:
```bash
terraform init
terraform apply -auto-approve
```
*Terraform створить інстанс `db.t3.micro` (Free Tier), відкриє порт 5432 у Security Group та створить IAM-роль для імпорту з S3.*

#### Ручне створення через AWS Management Console (для скріншотів у звіт):
1. Відкрийте сервіс **Amazon RDS** $\rightarrow$ **Databases** $\rightarrow$ **Create database**.
2. Оберіть **Standard create** та двигун **PostgreSQL** (версія `16.x` або `15.x`).
3. У блоці **Templates** виберіть **Free Tier** (щоб уникнути зайвих витрат).
4. Налаштування інстансу:
   - **DB instance identifier**: `opendata-postgres`
   - **Master username**: `dbadmin`
   - **Master password**: встановіть надійний пароль (наприклад: `SecurePass2026!`)
5. **Instance configuration**: `db.t3.micro` або `db.t4g.micro`.
6. **Storage**: `General Purpose SSD (gp3)`, 20 GiB, вимкніть Storage autoscaling для навчальної бази.
7. **Connectivity**:
   - **Public access**: `Yes` (для підключення з ПК чи середовища розробки).
   - **VPC security group**: створіть нову групу з правилом Inbound Rule: `TCP`, Port `5432`, Source `Anywhere-IPv4` (або `My IP`).
8. **Additional configuration**:
   - **Initial database name**: `opendata_db`
9. Натисніть **Create database** (ініціалізація триває 5-10 хвилин).
10. Скопіюйте отриманий **Endpoint** з панелі RDS.

---

### Спосіб 2: PostgreSQL на базі Amazon EC2 (Альтернатива)

Якщо завдання вимагає підняти PostgreSQL на власній віртуальній машині (IaaS):
1. Запустіть EC2 інстанс (`t2.micro` / `t3.micro`, Ubuntu 24.04 LTS).
2. У Security Group відкрийте порти `22` (SSH) та `5432` (PostgreSQL).
3. Підключіться через SSH та встановіть PostgreSQL:
   ```bash
   sudo apt update
   sudo apt install -y postgresql postgresql-contrib awscli
   ```
4. Налаштуйте доступ:
   Відредагуйте `/etc/postgresql/16/main/postgresql.conf`:
   ```text
   listen_addresses = '*'
   ```
   Додайте рядок у `/etc/postgresql/16/main/pg_hba.conf`:
   ```text
   host  all  all  0.0.0.0/0  scram-sha-256
   ```
   Перезавантажте службу:
   ```bash
   sudo systemctl restart postgresql
   ```

---

## 📥 Завантаження файлів у S3 та імпорт у базу даних

### Крок 1: Завантаження CSV-файлів у S3 bucket
Виконайте скрипт:
```bash
./upload_to_s3.sh
```
Файли опиняться у вашому бакеті:
- `s3://demo-api-bucket-loving-ox/data/organizations.csv`
- `s3://demo-api-bucket-loving-ox/data/tenders.csv`

---

### Крок 2: Створення структури таблиць у PostgreSQL
Підключіться до створеної бази даних через `psql` (або DBeaver / pgAdmin):
```bash
psql -h <RDS_ENDPOINT> -p 5432 -U dbadmin -d opendata_db
```
Виконайте скрипт створення таблиць:
```sql
\i sql/02_create_tables.sql
```

---

### Крок 3: Імпорт даних з S3 bucket

#### Варіант А: Безпосередньо в RDS через функцію `aws_s3.table_import_from_s3`
Підключіть розширення:
```sql
CREATE EXTENSION IF NOT EXISTS aws_commons;
CREATE EXTENSION IF NOT EXISTS aws_s3;
```
Виконайте імпорт головної таблиці:
```sql
SELECT aws_s3.table_import_from_s3(
    'organizations',
    'edrpou,legal_name,short_name,org_type,region,city,postal_code,address,email,phone',
    '(format csv, header true, delimiter '','', encoding ''utf-8'')',
    aws_commons.create_s3_uri('demo-api-bucket-loving-ox', 'data/organizations.csv', 'us-east-1')
);
```
Виконайте імпорт підлеглої таблиці:
```sql
SELECT aws_s3.table_import_from_s3(
    'tenders',
    'tender_id,title,description,procuring_entity_edrpou,expected_value,currency,procedure_type,status,start_date,end_date',
    '(format csv, header true, delimiter '','', encoding ''utf-8'')',
    aws_commons.create_s3_uri('demo-api-bucket-loving-ox', 'data/tenders.csv', 'us-east-1')
);
```

#### Варіант Б: Потоковий імпорт через AWS CLI та команду `\copy`
```bash
aws s3 cp s3://demo-api-bucket-loving-ox/data/organizations.csv - | \
psql -h <RDS_ENDPOINT> -U dbadmin -d opendata_db -c \
"\copy organizations (edrpou, legal_name, short_name, org_type, region, city, postal_code, address, email, phone) FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER ',');"

aws s3 cp s3://demo-api-bucket-loving-ox/data/tenders.csv - | \
psql -h <RDS_ENDPOINT> -U dbadmin -d opendata_db -c \
"\copy tenders (tender_id, title, description, procuring_entity_edrpou, expected_value, currency, procedure_type, status, start_date, end_date) FROM STDIN WITH (FORMAT csv, HEADER true, DELIMITER ',');"
```

---

## 📈 Перевірка результатів та аналітичні SQL-запити

Після імпорту запустіть файл перевірки [sql/04_analytical_queries.sql](file:///home/greqit/Documents/хмарні/lab2_rds_postgres/sql/04_analytical_queries.sql):

```sql
-- 1. Перевірка кількості імпортованих записів:
SELECT 'organizations' AS table_name, COUNT(*) FROM organizations
UNION ALL
SELECT 'tenders' AS table_name, COUNT(*) FROM tenders;

-- 2. Топ замовників за сумою оголошених закупівель:
SELECT 
    o.short_name,
    o.city,
    COUNT(t.tender_id) AS tenders_count,
    SUM(t.expected_value) AS total_budget_uah
FROM organizations o
LEFT JOIN tenders t ON o.edrpou = t.procuring_entity_edrpou
GROUP BY o.short_name, o.city
ORDER BY total_budget_uah DESC;
```

