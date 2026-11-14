-- ============================================================================
-- Скрипт 4: Перевірка та аналітичні запити до імпортованих даних
-- ============================================================================

-- 1. Перевірка кількості записів у таблицях
SELECT 'organizations' AS table_name, COUNT(*) AS total_rows FROM organizations
UNION ALL
SELECT 'tenders' AS table_name, COUNT(*) AS total_rows FROM tenders;

-- 2. Перегляд списку замовників та кількості оголошених ними тендерів (JOIN + GROUP BY)
SELECT 
    o.edrpou,
    o.short_name,
    o.city,
    COUNT(t.tender_id) AS tenders_count,
    COALESCE(SUM(t.expected_value), 0.00) AS total_budget_uah
FROM organizations o
LEFT JOIN tenders t ON o.edrpou = t.procuring_entity_edrpou
GROUP BY o.edrpou, o.short_name, o.city
ORDER BY total_budget_uah DESC;

-- 3. Топ-3 найдорожчих закупівель з інформацією про замовника
SELECT 
    t.tender_id,
    t.title,
    t.expected_value,
    t.status,
    o.legal_name AS procuring_entity,
    o.region
FROM tenders t
JOIN organizations o ON t.procuring_entity_edrpou = o.edrpou
ORDER BY t.expected_value DESC
LIMIT 3;

-- 4. Статистика закупівель за регіонами України
SELECT 
    o.region,
    COUNT(t.tender_id) AS total_tenders,
    SUM(t.expected_value) AS region_total_budget,
    ROUND(AVG(t.expected_value), 2) AS avg_tender_budget
FROM organizations o
JOIN tenders t ON o.edrpou = t.procuring_entity_edrpou
GROUP BY o.region
ORDER BY region_total_budget DESC;

