-- ============================================================================
-- Довідковий DDL: Таблиці бази даних opendata_db
-- ============================================================================

CREATE TABLE IF NOT EXISTS organizations (
    edrpou          VARCHAR(10) PRIMARY KEY,
    legal_name      VARCHAR(500) NOT NULL,
    short_name      VARCHAR(250),
    org_type        VARCHAR(150),
    region          VARCHAR(100) NOT NULL,
    city            VARCHAR(100) NOT NULL,
    postal_code     VARCHAR(10),
    address         TEXT,
    email           VARCHAR(150),
    phone           VARCHAR(50),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tenders (
    tender_id               VARCHAR(50) PRIMARY KEY,
    title                   TEXT NOT NULL,
    description             TEXT,
    procuring_entity_edrpou VARCHAR(10) NOT NULL REFERENCES organizations(edrpou) ON UPDATE CASCADE ON DELETE RESTRICT,
    expected_value          NUMERIC(15, 2) NOT NULL CHECK (expected_value >= 0),
    currency                VARCHAR(3) DEFAULT 'UAH',
    procedure_type          VARCHAR(150) NOT NULL,
    status                  VARCHAR(50) NOT NULL,
    start_date              TIMESTAMP WITH TIME ZONE NOT NULL,
    end_date                TIMESTAMP WITH TIME ZONE NOT NULL CHECK (end_date >= start_date),
    created_at              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_organizations_region ON organizations (region);
CREATE INDEX IF NOT EXISTS idx_tenders_procuring_entity ON tenders (procuring_entity_edrpou);

