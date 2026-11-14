-- ============================================================================
-- Лабораторна робота №3: Збережувані процедури для дедуплікації даних (Спосіб 2)
-- ============================================================================
-- Дані процедури реалізують другий спосіб виконання завдання:
-- 1. Дані через команду COPY записуються у тимчасову таблицю (temp_organizations / temp_tenders)
-- 2. Процедура виконує перевірку, усуває дублікати всередині файлу (DISTINCT ON)
--    та вставляє дані в основну таблицю з механізмом ON CONFLICT (UPSERT або SKIP)
-- ============================================================================

-- 1. Збережувана процедура для дедуплікації та вставки організацій
CREATE OR REPLACE PROCEDURE sync_organizations_from_staging(
    IN p_mode VARCHAR DEFAULT 'UPDATE' -- 'UPDATE' (оновлювати наявні) або 'IGNORE' (пропускати дублікати)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_staging INT := 0;
    v_inserted INT := 0;
    v_updated INT := 0;
BEGIN
    -- Перевірка чи існує тимчасова таблиця
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = 'temp_organizations'
    ) THEN
        RAISE EXCEPTION 'Тимчасова таблиця temp_organizations не знайдена!';
    END IF;

    SELECT COUNT(*) INTO v_total_staging FROM temp_organizations;
    RAISE NOTICE 'Отримано записів у тимчасовій таблиці temp_organizations: %', v_total_staging;

    IF p_mode = 'UPDATE' THEN
        -- Варіант А: Оновлювати поля існуючих записів (UPSERT)
        WITH upsert_res AS (
            INSERT INTO organizations (
                edrpou, legal_name, short_name, org_type, 
                region, city, postal_code, address, email, phone
            )
            SELECT DISTINCT ON (TRIM(edrpou))
                TRIM(edrpou),
                TRIM(legal_name),
                NULLIF(TRIM(short_name), ''),
                NULLIF(TRIM(org_type), ''),
                TRIM(region),
                TRIM(city),
                NULLIF(TRIM(postal_code), ''),
                NULLIF(TRIM(address), ''),
                NULLIF(TRIM(email), ''),
                NULLIF(TRIM(phone), '')
            FROM temp_organizations
            WHERE edrpou IS NOT NULL AND TRIM(edrpou) <> ''
            ORDER BY TRIM(edrpou)
            ON CONFLICT (edrpou) DO UPDATE SET
                legal_name  = EXCLUDED.legal_name,
                short_name  = COALESCE(EXCLUDED.short_name, organizations.short_name),
                org_type    = COALESCE(EXCLUDED.org_type, organizations.org_type),
                region      = EXCLUDED.region,
                city        = EXCLUDED.city,
                postal_code = COALESCE(EXCLUDED.postal_code, organizations.postal_code),
                address     = COALESCE(EXCLUDED.address, organizations.address),
                email       = COALESCE(EXCLUDED.email, organizations.email),
                phone       = COALESCE(EXCLUDED.phone, organizations.phone)
            RETURNING (xmax = 0) AS is_insert
        )
        SELECT 
            COUNT(*) FILTER (WHERE is_insert),
            COUNT(*) FILTER (WHERE NOT is_insert)
        INTO v_inserted, v_updated
        FROM upsert_res;
    ELSE
        -- Варіант Б: Ігнорувати дублікати (DO NOTHING)
        WITH insert_res AS (
            INSERT INTO organizations (
                edrpou, legal_name, short_name, org_type, 
                region, city, postal_code, address, email, phone
            )
            SELECT DISTINCT ON (TRIM(edrpou))
                TRIM(edrpou),
                TRIM(legal_name),
                NULLIF(TRIM(short_name), ''),
                NULLIF(TRIM(org_type), ''),
                TRIM(region),
                TRIM(city),
                NULLIF(TRIM(postal_code), ''),
                NULLIF(TRIM(address), ''),
                NULLIF(TRIM(email), ''),
                NULLIF(TRIM(phone), '')
            FROM temp_organizations
            WHERE edrpou IS NOT NULL AND TRIM(edrpou) <> ''
            ORDER BY TRIM(edrpou)
            ON CONFLICT (edrpou) DO NOTHING
            RETURNING 1
        )
        SELECT COUNT(*) INTO v_inserted FROM insert_res;
        v_updated := v_total_staging - v_inserted;
    END IF;

    RAISE NOTICE 'Успішно завершено: нових вставлено = %, дублікатів опрацьовано = %', v_inserted, v_updated;
END;
$$;


-- 2. Збережувана процедура для дедуплікації та вставки тендерів
CREATE OR REPLACE PROCEDURE sync_tenders_from_staging(
    IN p_mode VARCHAR DEFAULT 'UPDATE'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_staging INT := 0;
    v_inserted INT := 0;
    v_updated INT := 0;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = 'temp_tenders'
    ) THEN
        RAISE EXCEPTION 'Тимчасова таблиця temp_tenders не знайдена!';
    END IF;

    SELECT COUNT(*) INTO v_total_staging FROM temp_tenders;
    RAISE NOTICE 'Отримано записів у тимчасовій таблиці temp_tenders: %', v_total_staging;

    IF p_mode = 'UPDATE' THEN
        WITH upsert_res AS (
            INSERT INTO tenders (
                tender_id, title, description, procuring_entity_edrpou, 
                expected_value, currency, procedure_type, status, start_date, end_date
            )
            SELECT DISTINCT ON (TRIM(tender_id))
                TRIM(tender_id),
                TRIM(title),
                NULLIF(TRIM(description), ''),
                TRIM(procuring_entity_edrpou),
                expected_value,
                COALESCE(NULLIF(TRIM(currency), ''), 'UAH'),
                TRIM(procedure_type),
                TRIM(status),
                start_date,
                end_date
            FROM temp_tenders
            WHERE tender_id IS NOT NULL AND TRIM(tender_id) <> ''
            ORDER BY TRIM(tender_id)
            ON CONFLICT (tender_id) DO UPDATE SET
                title          = EXCLUDED.title,
                description    = COALESCE(EXCLUDED.description, tenders.description),
                expected_value = EXCLUDED.expected_value,
                status         = EXCLUDED.status,
                end_date       = EXCLUDED.end_date
            RETURNING (xmax = 0) AS is_insert
        )
        SELECT 
            COUNT(*) FILTER (WHERE is_insert),
            COUNT(*) FILTER (WHERE NOT is_insert)
        INTO v_inserted, v_updated
        FROM upsert_res;
    ELSE
        WITH insert_res AS (
            INSERT INTO tenders (
                tender_id, title, description, procuring_entity_edrpou, 
                expected_value, currency, procedure_type, status, start_date, end_date
            )
            SELECT DISTINCT ON (TRIM(tender_id))
                TRIM(tender_id),
                TRIM(title),
                NULLIF(TRIM(description), ''),
                TRIM(procuring_entity_edrpou),
                expected_value,
                COALESCE(NULLIF(TRIM(currency), ''), 'UAH'),
                TRIM(procedure_type),
                TRIM(status),
                start_date,
                end_date
            FROM temp_tenders
            WHERE tender_id IS NOT NULL AND TRIM(tender_id) <> ''
            ORDER BY TRIM(tender_id)
            ON CONFLICT (tender_id) DO NOTHING
            RETURNING 1
        )
        SELECT COUNT(*) INTO v_inserted FROM insert_res;
        v_updated := v_total_staging - v_inserted;
    END IF;

    RAISE NOTICE 'Успішно завершено: нових тендерів = %, дублікатів = %', v_inserted, v_updated;
END;
$$;

