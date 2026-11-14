-- ============================================================================
-- Скрипт 2: Створення двох взаємопов'язаних таблиць для імпорту з S3
-- Тематика даних: Реєстр організацій-замовників та публічні закупівлі (Prozorro)
-- Джерело структури: data.gov.ua (Єдиний державний реєстр відкритих даних)
-- ============================================================================

-- 1. Видалення таблиць, якщо вони вже існують (для ідемпотентності скрипту)
DROP TABLE IF EXISTS tenders CASCADE;
DROP TABLE IF EXISTS organizations CASCADE;

-- 2. Створення головної таблиці: Організації (Замовники / Юридичні особи)
CREATE TABLE organizations (
    edrpou          VARCHAR(10) PRIMARY KEY,                    -- Код за ЄДРПОУ (8 цифр для юросіб або 10 для ФОП)
    legal_name      VARCHAR(500) NOT NULL,                      -- Повне найменування юридичної особи
    short_name      VARCHAR(250),                               -- Скорочене найменування
    org_type        VARCHAR(150),                               -- Організаційно-правова форма / тип замовника
    region          VARCHAR(100) NOT NULL,                      -- Область розташування
    city            VARCHAR(100) NOT NULL,                      -- Населений пункт
    postal_code     VARCHAR(10),                                -- Поштовий індекс
    address         TEXT,                                       -- Повна поштова адреса
    email           VARCHAR(150),                               -- Офіційна електронна адреса
    phone           VARCHAR(50),                                -- Контактний телефон
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP -- Час запису в базу даних
);

-- Коментарі до таблиці organizations та її колонок
COMMENT ON TABLE organizations IS 'Таблиця організацій-замовників на основі відкритих даних ЄДРПОУ з data.gov.ua';
COMMENT ON COLUMN organizations.edrpou IS 'Код за ЄДРПОУ — унікальний первинний ключ організації';
COMMENT ON COLUMN organizations.legal_name IS 'Офіційна повна назва організації';
COMMENT ON COLUMN organizations.region IS 'Область України';
COMMENT ON COLUMN organizations.city IS 'Місто або селище реєстрації';

-- 3. Створення підлеглої таблиці: Публічні закупівлі (Тендери)
CREATE TABLE tenders (
    tender_id               VARCHAR(50) PRIMARY KEY,            -- Унікальний ідентифікатор закупівлі Prozorro (наприклад: UA-2026-09-15-001001-a)
    title                   TEXT NOT NULL,                      -- Назва предмета закупівлі
    description             TEXT,                               -- Детальний опис закупівлі / технічні вимоги
    procuring_entity_edrpou VARCHAR(10) NOT NULL,               -- Зовнішній ключ: код ЄДРПОУ замовника
    expected_value          NUMERIC(15, 2) NOT NULL,            -- Очікувана вартість закупівлі в гривнях
    currency                VARCHAR(3) DEFAULT 'UAH',           -- Валюта закупівлі (за замовчуванням UAH)
    procedure_type          VARCHAR(150) NOT NULL,              -- Тип процедури закупівлі
    status                  VARCHAR(50) NOT NULL,               -- Поточний статус закупівлі (active, complete, cancelled)
    start_date              TIMESTAMP WITH TIME ZONE NOT NULL,  -- Початок подання тендерних пропозицій
    end_date                TIMESTAMP WITH TIME ZONE NOT NULL,  -- Завершення подання тендерних пропозицій
    created_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Обмеження зовнішнього ключа: зв'язок 1:N між organizations та tenders
    CONSTRAINT fk_tenders_procuring_entity
        FOREIGN KEY (procuring_entity_edrpou)
        REFERENCES organizations (edrpou)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,

    -- Обмеження на невід'ємну вартість закупівлі
    CONSTRAINT chk_positive_expected_value
        CHECK (expected_value >= 0),

    -- Обмеження: дата завершення повинна бути пізнішою за дату початку
    CONSTRAINT chk_tender_dates
        CHECK (end_date >= start_date)
);

-- Коментарі до таблиці tenders та її колонок
COMMENT ON TABLE tenders IS 'Таблиця публічних закупівель (тендерів Prozorro) на основі відкритих даних з data.gov.ua';
COMMENT ON COLUMN tenders.tender_id IS 'Унікальний ідентифікатор закупівлі в електронній системі';
COMMENT ON COLUMN tenders.procuring_entity_edrpou IS 'Код ЄДРПОУ організації-замовника (FK до organizations.edrpou)';
COMMENT ON COLUMN tenders.expected_value IS 'Очікувана вартість предмета закупівлі (UAH)';

-- 4. Створення індексів для оптимізації реляційних зв'язків та пошуку
CREATE INDEX idx_organizations_region ON organizations (region);
CREATE INDEX idx_organizations_city ON organizations (city);
CREATE INDEX idx_tenders_procuring_entity ON tenders (procuring_entity_edrpou);
CREATE INDEX idx_tenders_status ON tenders (status);
CREATE INDEX idx_tenders_dates ON tenders (start_date, end_date);

