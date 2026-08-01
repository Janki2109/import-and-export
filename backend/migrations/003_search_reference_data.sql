-- ============================================================
-- ONE BHARAT EXPORT-IMPORT — SEARCH & CALCULATOR REFERENCE DATA
-- Curated reference subset for HS Code / GST / Country / Policy search
-- and Duty/Freight/Landed-Cost calculators. NOT an exhaustive or
-- legally authoritative dataset — for production, replace/extend with
-- licensed government trade data feeds.
-- ============================================================

CREATE TYPE policy_type AS ENUM ('import', 'export');

-- ---------- HS CODES ----------
CREATE TABLE hs_codes (
    id                          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code                        VARCHAR(10) UNIQUE NOT NULL,
    description                 TEXT NOT NULL,
    chapter                     VARCHAR(4) NOT NULL,
    basic_customs_duty_percent  NUMERIC(5,2) NOT NULL DEFAULT 0,
    igst_percent                NUMERIC(5,2) NOT NULL DEFAULT 18,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_hs_codes_code ON hs_codes(code);
CREATE INDEX idx_hs_codes_description ON hs_codes USING gin (to_tsvector('english', description));

-- ---------- GST RATE SLABS ----------
CREATE TABLE gst_rates (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category        VARCHAR(150) NOT NULL,
    rate_percent    NUMERIC(5,2) NOT NULL,
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------- COUNTRIES ----------
CREATE TABLE countries (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(100) UNIQUE NOT NULL,
    iso2            VARCHAR(2) NOT NULL,
    iso3            VARCHAR(3) NOT NULL,
    region          VARCHAR(50) NOT NULL,
    is_restricted   BOOLEAN NOT NULL DEFAULT false,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_countries_name ON countries(name);

-- ---------- IMPORT / EXPORT POLICY NOTES ----------
CREATE TABLE trade_policies (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    country_id      UUID REFERENCES countries(id),
    policy_type     policy_type NOT NULL,
    hs_chapter      VARCHAR(4),
    title           VARCHAR(255) NOT NULL,
    description     TEXT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_trade_policies_country ON trade_policies(country_id);
CREATE INDEX idx_trade_policies_chapter ON trade_policies(hs_chapter);

-- ============================================================
-- SEED DATA
-- ============================================================

INSERT INTO hs_codes (code, description, chapter, basic_customs_duty_percent, igst_percent) VALUES
('0901.21', 'Coffee, roasted, not decaffeinated', '09', 100.00, 5.00),
('1006.30', 'Rice, semi-milled or wholly milled', '10', 70.00, 5.00),
('1512.19', 'Sunflower-seed oil, refined', '15', 12.50, 5.00),
('2401.10', 'Tobacco, unmanufactured, not stemmed/stripped', '24', 30.00, 28.00),
('3004.90', 'Medicaments, for therapeutic use, put up in dosage', '30', 10.00, 12.00),
('3924.10', 'Tableware and kitchenware, of plastics', '39', 10.00, 18.00),
('4202.22', 'Handbags, with outer surface of textile materials', '42', 10.00, 18.00),
('5208.52', 'Cotton fabrics, plain weave, printed', '52', 10.00, 5.00),
('6109.10', 'T-shirts, singlets, of cotton, knitted', '61', 10.00, 5.00),
('6203.42', 'Men''s trousers, of cotton', '62', 10.00, 12.00),
('6403.99', 'Footwear with rubber/plastic/leather soles', '64', 25.00, 18.00),
('7113.19', 'Jewellery of precious metal (gold)', '71', 15.00, 3.00),
('7308.90', 'Structures and parts, of iron or steel', '73', 7.50, 18.00),
('8471.30', 'Portable automatic data processing machines (laptops)', '84', 0.00, 18.00),
('8517.13', 'Smartphones', '85', 20.00, 18.00),
('8536.50', 'Electrical switches, for voltage <= 1000V', '85', 10.00, 18.00),
('8703.23', 'Motor cars, spark-ignition engine 1500-3000cc', '87', 60.00, 28.00),
('9018.90', 'Medical, surgical instruments and appliances', '90', 7.50, 12.00),
('9403.60', 'Wooden furniture', '94', 25.00, 18.00),
('9506.62', 'Inflatable balls (footballs, basketballs)', '95', 10.00, 12.00);

INSERT INTO gst_rates (category, rate_percent, description) VALUES
('Essential food items (unbranded)', 0.00, 'Unbranded cereals, fresh produce, milk'),
('Household necessities', 5.00, 'Edible oil, sugar, spices, tea/coffee, life-saving drugs'),
('Standard goods (slab 1)', 12.00, 'Processed food, mobile phones, business/computer equipment'),
('Standard goods (slab 2)', 18.00, 'Most manufactured goods, electronics, industrial intermediates'),
('Luxury / sin goods', 28.00, 'Automobiles, tobacco, aerated drinks, luxury items');

INSERT INTO countries (name, iso2, iso3, region, is_restricted, notes) VALUES
('United States', 'US', 'USA', 'North America', false, 'Major export destination; FDA/USDA compliance required for food & pharma.'),
('United Arab Emirates', 'AE', 'ARE', 'Middle East', false, 'Free trade hub; re-export gateway for Gulf & African markets.'),
('United Kingdom', 'GB', 'GBR', 'Europe', false, 'India-UK trade agreement in force; CE/UKCA marking may apply.'),
('Germany', 'DE', 'DEU', 'Europe', false, 'EU CE marking and REACH compliance required.'),
('China', 'CN', 'CHN', 'Asia', false, 'Major import source; anti-dumping duties apply on select HS chapters.'),
('Singapore', 'SG', 'SGP', 'Asia', false, 'Free trade hub; ASEAN-India FTA preferential tariffs available.'),
('Saudi Arabia', 'SA', 'SAU', 'Middle East', false, 'SASO conformity certification required for many goods.'),
('Japan', 'JP', 'JPN', 'Asia', false, 'India-Japan CEPA preferential tariffs on eligible HS codes.'),
('Australia', 'AU', 'AUS', 'Oceania', false, 'India-Australia ECTA in force for many product categories.'),
('South Africa', 'ZA', 'ZAF', 'Africa', false, 'Gateway to SACU region; NRCS certification required for electricals.'),
('Bangladesh', 'BD', 'BGD', 'Asia', false, 'SAFTA preferential tariffs; land/sea/border trade routes available.'),
('Nepal', 'NP', 'NPL', 'Asia', false, 'India-Nepal Treaty of Trade; simplified border clearance.'),
('Russia', 'RU', 'RUS', 'Europe', true, 'Payment settlement restrictions due to international sanctions regime — verify banking channel before committing.'),
('Iran', 'IR', 'IRN', 'Middle East', true, 'Trade restricted under international sanctions — most categories require special clearance.'),
('North Korea', 'KP', 'PRK', 'Asia', true, 'UN sanctions in force — trade prohibited for nearly all goods.'),
('Brazil', 'BR', 'BRA', 'South America', false, 'Mercosur-India PTA covers limited tariff lines.'),
('Netherlands', 'NL', 'NLD', 'Europe', false, 'Major EU re-export hub via Rotterdam port.'),
('Vietnam', 'VN', 'VNM', 'Asia', false, 'ASEAN-India FTA preferential tariffs available.'),
('Kenya', 'KE', 'KEN', 'Africa', false, 'Growing East African trade corridor via Mombasa port.'),
('Canada', 'CA', 'CAN', 'North America', false, 'CFIA compliance required for food/agricultural exports.');

INSERT INTO trade_policies (country_id, policy_type, hs_chapter, title, description)
SELECT id, 'export', '09', 'Coffee export documentation', 'Export requires a Coffee Board of India registration certificate along with the standard shipping bill and certificate of origin.'
FROM countries WHERE name = 'United States';

INSERT INTO trade_policies (country_id, policy_type, hs_chapter, title, description)
SELECT id, 'import', '85', 'Electronics BIS compliance', 'Electronic goods imported for resale must carry BIS (Bureau of Indian Standards) certification before customs clearance.'
FROM countries WHERE name = 'China';

INSERT INTO trade_policies (country_id, policy_type, hs_chapter, title, description)
SELECT id, 'export', '61', 'Textile export incentive (RoDTEP)', 'Cotton textile exports are eligible for RoDTEP duty remission — claim via shipping bill at the time of export.'
FROM countries WHERE name = 'Germany';

INSERT INTO trade_policies (country_id, policy_type, hs_chapter, title, description)
SELECT id, 'export', NULL, 'Sanctions restriction', 'Trade with this destination is restricted under active international sanctions. Consult legal/compliance before proceeding with any order.'
FROM countries WHERE is_restricted = true;
