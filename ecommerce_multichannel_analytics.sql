-- ============================================================
-- E-COMMERCE MULTI-CHANNEL ANALYTICS
-- MySQL Portfolio Project
--
-- Purpose
--   Build a staging-to-analytics workflow for web, mobile, and
--   partner-channel sales, then support business analysis,
--   query optimization, persisted summaries, and role-based access.
--
-- Execution notes
--   1. Run Section 1 to create the database and staging tables.
--   2. Import the five project source files into the staging tables.
--   3. Continue with Sections 2-7 in order.
--   4. Replace password placeholders with secure credentials only
--      in a local or protected environment. Never commit real secrets.
-- ============================================================


-- ============================================================
-- 1. DATABASE AND STAGING SETUP
-- ============================================================

-- Create the project database.
CREATE DATABASE IF NOT EXISTS ecommerce_analytics;
USE ecommerce_analytics;

-- Expected source-to-staging mapping:
--   web_sales.csv      -> stg_web_sales
--   mobile_sales.csv   -> stg_mobile_sales
--   partners.csv       -> stg_partners
--   partner_sales.csv  -> stg_partner_sales
--   products.csv       -> stg_products
--
-- The CSV import itself is performed outside this script using DBeaver.

-- Create staging tables.
CREATE TABLE stg_web_sales (
    txn_id INT,
    sale_date DATE,
    channel VARCHAR(20),
    product_id INT,
    qty INT,
    amount DECIMAL(10,2)
);

CREATE TABLE stg_mobile_sales (
    txn_id INT,
    sale_date DATE,
    channel VARCHAR(20),
    product_id INT,
    qty INT,
    amount DECIMAL(10,2)
);

CREATE TABLE stg_partners (
    partner_id INT,
    partner_name VARCHAR(100),
    partner_url VARCHAR(200)
);

CREATE TABLE stg_partner_sales (
    txn_id INT,
    sale_date DATE,
    channel VARCHAR(20),
    partner_id INT,
    product_id INT,
    qty INT,
    amount DECIMAL(10,2)
);

CREATE TABLE stg_products (
    product_id INT,
    product_category VARCHAR(50),
    cost_rate DECIMAL(4,2)
);

-- ============================================================
-- 2. STAGING VALIDATION AND DATA QUALITY CHECKS
-- ============================================================

-- Verify imported row counts and inspect sample records.
SELECT * FROM stg_web_sales LIMIT 10;
SELECT COUNT(*) AS total_rows FROM stg_web_sales;

SELECT * FROM stg_mobile_sales LIMIT 10;
SELECT COUNT(*) AS total_rows FROM stg_mobile_sales;

SELECT * FROM stg_partners LIMIT 10;
SELECT COUNT(*) AS total_rows FROM stg_partners;

SELECT * FROM stg_partner_sales LIMIT 10;
SELECT COUNT(*) AS total_rows FROM stg_partner_sales;

SELECT * FROM stg_products LIMIT 10;
SELECT COUNT(*) AS total_rows FROM stg_products;

-- Profile sales staging tables for missing values, duplicate transaction IDs,
-- invalid quantities, and negative sales amounts.

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT txn_id) AS unique_transactions,
    SUM(txn_id IS NULL) AS null_txn_ids,
    SUM(sale_date IS NULL) AS null_dates,
    SUM(channel IS NULL) AS null_channels,
    SUM(product_id IS NULL) AS null_product_ids,
    SUM(qty IS NULL) AS null_quantities,
    SUM(amount IS NULL) AS null_amounts,
    SUM(qty <= 0) AS invalid_quantities,
    SUM(amount < 0) AS negative_amounts
FROM stg_web_sales;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT txn_id) AS unique_transactions,
    SUM(txn_id IS NULL) AS null_txn_ids,
    SUM(sale_date IS NULL) AS null_dates,
    SUM(channel IS NULL) AS null_channels,
    SUM(product_id IS NULL) AS null_product_ids,
    SUM(qty IS NULL) AS null_quantities,
    SUM(amount IS NULL) AS null_amounts,
    SUM(qty <= 0) AS invalid_quantities,
    SUM(amount < 0) AS negative_amounts
FROM stg_mobile_sales;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT txn_id) AS unique_transactions,
    COUNT(DISTINCT partner_id) AS unique_partners,
    SUM(txn_id IS NULL) AS null_txn_ids,
    SUM(sale_date IS NULL) AS null_dates,
    SUM(channel IS NULL) AS null_channels,
    SUM(partner_id IS NULL) AS null_partner_ids,
    SUM(product_id IS NULL) AS null_product_ids,
    SUM(qty IS NULL) AS null_quantities,
    SUM(amount IS NULL) AS null_amounts,
    SUM(qty <= 0) AS invalid_quantities,
    SUM(amount < 0) AS negative_amounts
FROM stg_partner_sales;

-- Profile product metadata and validate cost-rate assumptions.
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT product_id) AS unique_products,
    SUM(product_id IS NULL) AS null_product_ids,
    SUM(product_category IS NULL) AS null_categories,
    SUM(cost_rate IS NULL) AS null_cost_rates,
    SUM(cost_rate <= 0 OR cost_rate >= 1) AS invalid_cost_rates
FROM stg_products;

-- Inspect channel labels before standardization.

SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT txn_id) AS unique_transactions
FROM stg_web_sales;

SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT txn_id) AS unique_transactions
FROM stg_mobile_sales;

SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT txn_id) AS unique_transactions
FROM stg_partner_sales;

SELECT DISTINCT channel FROM stg_web_sales;
SELECT DISTINCT channel FROM stg_mobile_sales;
SELECT DISTINCT channel FROM stg_partner_sales;

-- Check for duplicate transaction IDs across all three sales sources.
SELECT
    txn_id,
    COUNT(*) AS occurrences
FROM (
    SELECT txn_id FROM stg_web_sales
    UNION ALL
    SELECT txn_id FROM stg_mobile_sales
    UNION ALL
    SELECT txn_id FROM stg_partner_sales
) AS all_transactions
GROUP BY txn_id
HAVING COUNT(*) > 1;

-- Verify the supplemental partner-sales distribution.
SELECT
    partner_id,
    COUNT(*) AS transactions
FROM stg_partner_sales
GROUP BY partner_id
ORDER BY partner_id;

-- ============================================================
-- 3. ANALYTICAL MODEL: DIMENSIONS AND FACT TABLE
-- ============================================================

-- Create dimension tables.

CREATE TABLE DimProduct (
    product_id INT PRIMARY KEY,
    product_category VARCHAR(50) NOT NULL,
    cost_rate DECIMAL(4,2) NOT NULL
);

INSERT INTO DimProduct (
    product_id,
    product_category,
    cost_rate
)
SELECT
    product_id,
    TRIM(product_category),
    cost_rate
FROM stg_products;

SELECT * FROM DimProduct;

CREATE TABLE DimPartner (
    partner_id INT PRIMARY KEY,
    partner_name VARCHAR(100) NOT NULL,
    partner_url VARCHAR(200)
);

INSERT INTO DimPartner (
    partner_id,
    partner_name,
    partner_url
)
SELECT
    partner_id,
    TRIM(partner_name),
    TRIM(partner_url)
FROM stg_partners;

SELECT * FROM DimPartner;

-- Confirm that every sales product exists in DimProduct before loading FactSales.
SELECT DISTINCT s.product_id
FROM (
    SELECT product_id FROM stg_web_sales
    UNION
    SELECT product_id FROM stg_mobile_sales
    UNION
    SELECT product_id FROM stg_partner_sales
) s
LEFT JOIN DimProduct dp
    ON s.product_id = dp.product_id
WHERE dp.product_id IS NULL;

-- Create and load the unified fact table.

CREATE TABLE FactSales (
    txn_id INT PRIMARY KEY,
    sale_date DATE NOT NULL,
    channel VARCHAR(20) NOT NULL,
    partner_id INT NULL,
    product_id INT NOT NULL,
    qty INT NOT NULL,
    revenue DECIMAL(10,2) NOT NULL,
    estimated_cost DECIMAL(10,2) NOT NULL,
    profit DECIMAL(10,2) NOT NULL,
    CONSTRAINT fk_factsales_partner
        FOREIGN KEY (partner_id) REFERENCES DimPartner(partner_id),
    CONSTRAINT fk_factsales_product
        FOREIGN KEY (product_id) REFERENCES DimProduct(product_id)
);

INSERT INTO FactSales (
    txn_id,
    sale_date,
    channel,
    partner_id,
    product_id,
    qty,
    revenue,
    estimated_cost,
    profit
)
SELECT
    s.txn_id,
    s.sale_date,
    LOWER(TRIM(s.channel)),
    NULL,
    s.product_id,
    s.qty,
    s.amount,
    ROUND(s.amount * dp.cost_rate, 2),
    ROUND(s.amount - ROUND(s.amount * dp.cost_rate, 2), 2)
FROM stg_web_sales s
JOIN DimProduct dp
    ON s.product_id = dp.product_id
UNION ALL
SELECT
    s.txn_id,
    s.sale_date,
    LOWER(TRIM(s.channel)),
    NULL,
    s.product_id,
    s.qty,
    s.amount,
    ROUND(s.amount * dp.cost_rate, 2),
    ROUND(s.amount - ROUND(s.amount * dp.cost_rate, 2), 2)
FROM stg_mobile_sales s
JOIN DimProduct dp
    ON s.product_id = dp.product_id
UNION ALL
SELECT
    s.txn_id,
    s.sale_date,
    LOWER(TRIM(s.channel)),
    s.partner_id,
    s.product_id,
    s.qty,
    s.amount,
    ROUND(s.amount * dp.cost_rate, 2),
    ROUND(s.amount - ROUND(s.amount * dp.cost_rate, 2), 2)
FROM stg_partner_sales s
JOIN DimProduct dp
    ON s.product_id = dp.product_id;

-- Validate the unified analytical table.

SELECT * FROM FactSales;
SELECT COUNT(*) FROM FactSales;

SELECT
    (SELECT COUNT(*) FROM stg_web_sales)
  + (SELECT COUNT(*) FROM stg_mobile_sales)
  + (SELECT COUNT(*) FROM stg_partner_sales)
    AS source_transactions,
    (SELECT COUNT(*) FROM FactSales)
    AS fact_transactions;

SELECT
    channel,
    COUNT(*) AS transactions,
    SUM(qty) AS quantity_sold,
    ROUND(SUM(revenue), 2) AS revenue
FROM FactSales
GROUP BY channel
ORDER BY channel;

SELECT
    COUNT(*) AS total_transactions,
    SUM(qty) AS total_quantity,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(SUM(estimated_cost), 2) AS total_estimated_cost,
    ROUND(SUM(profit), 2) AS total_profit
FROM FactSales;

-- Confirm that partner_id is populated only for partner-channel transactions.

SELECT
    channel,
    COUNT(*) AS transactions,
    COUNT(partner_id) AS transactions_with_partner
FROM FactSales
GROUP BY channel;

-- ============================================================
-- 4. BUSINESS ANALYTICS
-- ============================================================

-- Analysis 1: Revenue by channel.
SELECT
    channel,
    COUNT(*) AS total_transactions,
    SUM(qty) AS total_quantity,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(SUM(profit), 2) AS total_profit
FROM FactSales
GROUP BY channel
ORDER BY total_revenue DESC;

-- Analysis 2: Monthly revenue trend.
SELECT
    DATE_FORMAT(sale_date, '%Y-%m') AS sales_month,
    COUNT(*) AS total_transactions,
    SUM(qty) AS total_quantity,
    ROUND(SUM(revenue), 2) AS monthly_revenue,
    ROUND(SUM(profit), 2) AS monthly_profit
FROM FactSales
GROUP BY DATE_FORMAT(sale_date, '%Y-%m')
ORDER BY sales_month;

-- Analysis 3: Month-over-month revenue growth using CTEs and LAG().
WITH MonthlyRevenue AS (
    SELECT
        DATE_FORMAT(sale_date, '%Y-%m') AS sales_month,
        ROUND(SUM(revenue), 2) AS monthly_revenue
    FROM FactSales
    GROUP BY DATE_FORMAT(sale_date, '%Y-%m')
),
RevenueComparison AS (
    SELECT
        sales_month,
        monthly_revenue,
        LAG(monthly_revenue) OVER (ORDER BY sales_month) AS previous_month_revenue
    FROM MonthlyRevenue
)
SELECT
    sales_month,
    monthly_revenue,
    previous_month_revenue,
    ROUND(
        ((monthly_revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0)) * 100,
        2
    ) AS growth_rate_percent
FROM RevenueComparison
ORDER BY sales_month;

-- Analysis 4: Compare product-category revenue across channels.
SELECT
    dp.product_category,
    ROUND(SUM(CASE WHEN fs.channel = 'web' THEN fs.revenue ELSE 0 END), 2) AS web_revenue,
    ROUND(SUM(CASE WHEN fs.channel = 'mobile' THEN fs.revenue ELSE 0 END), 2) AS mobile_revenue,
    ROUND(SUM(CASE WHEN fs.channel = 'partner' THEN fs.revenue ELSE 0 END), 2) AS partner_revenue,
    ROUND(SUM(fs.revenue), 2) AS total_revenue
FROM FactSales fs
JOIN DimProduct dp ON fs.product_id = dp.product_id
GROUP BY dp.product_category
ORDER BY total_revenue DESC;

-- Analysis 5: Channel performance and revenue contribution.

SELECT
    channel,
    COUNT(*) AS total_transactions,
    SUM(qty) AS total_quantity,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND(AVG(revenue), 2) AS avg_transaction_value,
    ROUND(SUM(revenue) / SUM(qty), 2) AS revenue_per_unit,
    ROUND(
        SUM(revenue) /
        SUM(SUM(revenue)) OVER () * 100,
        2
    ) AS revenue_share_percent
FROM FactSales
GROUP BY channel
ORDER BY total_revenue DESC;

-- Analysis 6: Top-performing products.

SELECT
    fs.product_id,
    dp.product_category,
    COUNT(*) AS total_transactions,
    SUM(fs.qty) AS units_sold,
    ROUND(SUM(fs.revenue), 2) AS total_revenue,
    ROUND(SUM(fs.profit), 2) AS total_profit,
    ROUND(AVG(fs.revenue), 2) AS avg_transaction_value
FROM FactSales fs
JOIN DimProduct dp
    ON fs.product_id = dp.product_id
GROUP BY
    fs.product_id,
    dp.product_category
ORDER BY total_revenue DESC;

-- Analysis 7: Partner performance.

SELECT
    dp.partner_id,
    dp.partner_name,
    COUNT(fs.txn_id) AS total_transactions,
    SUM(fs.qty) AS units_sold,
    ROUND(SUM(fs.revenue), 2) AS total_revenue,
    ROUND(SUM(fs.profit), 2) AS total_profit,
    ROUND(AVG(fs.revenue), 2) AS avg_transaction_value
FROM FactSales fs
JOIN DimPartner dp
    ON fs.partner_id = dp.partner_id
WHERE fs.channel = 'partner'
GROUP BY
    dp.partner_id,
    dp.partner_name
ORDER BY total_revenue DESC;

-- Analysis 8: Sales performance by day of week.

SELECT
    DAYNAME(sale_date) AS day_of_week,
    WEEKDAY(sale_date) AS day_number,
    COUNT(*) AS total_transactions,
    SUM(qty) AS total_quantity,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(AVG(revenue), 2) AS avg_transaction_value
FROM FactSales
GROUP BY
    DAYNAME(sale_date),
    WEEKDAY(sale_date)
ORDER BY day_number;

-- Analysis 9: Product category profitability.

SELECT
    dp.product_category,
    COUNT(*) AS total_transactions,
    SUM(fs.qty) AS units_sold,
    ROUND(SUM(fs.revenue), 2) AS total_revenue,
    ROUND(SUM(fs.estimated_cost), 2) AS total_estimated_cost,
    ROUND(SUM(fs.profit), 2) AS total_profit,
    ROUND(
        SUM(fs.profit) / NULLIF(SUM(fs.revenue), 0) * 100,
        2
    ) AS profit_margin_percent
FROM FactSales fs
JOIN DimProduct dp
    ON fs.product_id = dp.product_id
GROUP BY dp.product_category
ORDER BY total_profit DESC;

-- ============================================================
-- 5. QUERY OPTIMIZATION
-- ============================================================

-- Inspect the execution plan before adding an index.
EXPLAIN
SELECT
    DATE_FORMAT(sale_date, '%Y-%m') AS sales_month,
    ROUND(SUM(revenue), 2) AS monthly_revenue
FROM FactSales
WHERE channel = 'web'
  AND sale_date BETWEEN '2025-01-01' AND '2025-06-30'
GROUP BY DATE_FORMAT(sale_date, '%Y-%m')
ORDER BY sales_month;

-- Create a composite index that supports filtering by channel and date range.
CREATE INDEX idx_factsales_channel_date
ON FactSales (channel, sale_date);

-- Re-run the identical EXPLAIN statement after index creation.

EXPLAIN
SELECT
    DATE_FORMAT(sale_date, '%Y-%m') AS sales_month,
    ROUND(SUM(revenue), 2) AS monthly_revenue
FROM FactSales
WHERE channel = 'web'
  AND sale_date BETWEEN '2025-01-01' AND '2025-06-30'
GROUP BY DATE_FORMAT(sale_date, '%Y-%m')
ORDER BY sales_month;

SHOW INDEX FROM FactSales;

-- ============================================================
-- 6. PERSISTED MONTHLY SUMMARY
--    MySQL materialized-view-style alternative
-- ============================================================

CREATE TABLE MonthlyChannelSummary (
    month_start DATE NOT NULL,
    channel VARCHAR(20) NOT NULL,
    total_transactions INT NOT NULL,
    total_quantity INT NOT NULL,
    total_revenue DECIMAL(12,2) NOT NULL,
    total_profit DECIMAL(12,2) NOT NULL,
    PRIMARY KEY (month_start, channel)
);

INSERT INTO MonthlyChannelSummary (
    month_start,
    channel,
    total_transactions,
    total_quantity,
    total_revenue,
    total_profit
)
SELECT
    DATE_FORMAT(sale_date, '%Y-%m-01'),
    channel,
    COUNT(*),
    SUM(qty),
    ROUND(SUM(revenue), 2),
    ROUND(SUM(profit), 2)
FROM FactSales
GROUP BY DATE_FORMAT(sale_date, '%Y-%m-01'), channel;

SELECT * FROM MonthlyChannelSummary;
SELECT COUNT(*) AS summary_rows FROM MonthlyChannelSummary;
SELECT *
FROM MonthlyChannelSummary
ORDER BY month_start, channel;

-- Two alternative refresh methods are shown for MonthlyChannelSummary.
-- Execute either Option 1 or Option 2 as required.
-- Option 1: Refresh the summary table directly within a transaction.

START TRANSACTION;
DELETE FROM MonthlyChannelSummary
WHERE month_start BETWEEN '1000-01-01' AND '9999-12-31';
INSERT INTO MonthlyChannelSummary
    (month_start, channel, total_transactions,
     total_quantity, total_revenue, total_profit)
SELECT
    DATE_FORMAT(sale_date, '%Y-%m-01'),
    channel,
    COUNT(*),
    SUM(qty),
    ROUND(SUM(revenue), 2),
    ROUND(SUM(profit), 2)
FROM FactSales
GROUP BY
    DATE_FORMAT(sale_date, '%Y-%m-01'),
    channel;
COMMIT;

-- Option 2: Encapsulate the same refresh logic in a stored procedure.
DELIMITER //
DROP PROCEDURE IF EXISTS RefreshMonthlyChannelSummary //
CREATE PROCEDURE RefreshMonthlyChannelSummary()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    START TRANSACTION;
    DELETE FROM MonthlyChannelSummary
    WHERE month_start BETWEEN '1000-01-01' AND '9999-12-31';
    INSERT INTO MonthlyChannelSummary (
        month_start,
        channel,
        total_transactions,
        total_quantity,
        total_revenue,
        total_profit
    )
    SELECT
        DATE_FORMAT(sale_date, '%Y-%m-01'),
        channel,
        COUNT(*),
        SUM(qty),
        ROUND(SUM(revenue), 2),
        ROUND(SUM(profit), 2)
    FROM FactSales
    GROUP BY
        DATE_FORMAT(sale_date, '%Y-%m-01'),
        channel;
    COMMIT;
END //
DELIMITER ;

-- Execute the stored procedure.
CALL RefreshMonthlyChannelSummary();

-- Verify the refreshed summary.
SELECT COUNT(*) AS summary_rows
FROM MonthlyChannelSummary;

SELECT *
FROM MonthlyChannelSummary
ORDER BY month_start, channel;

-- ============================================================
-- 7. ROLE-BASED ACCESS CONTROL
-- ============================================================

-- Remove existing project users and roles if they already exist.
DROP USER IF EXISTS
    'analyst_user'@'localhost',
    'etl_user'@'localhost';

DROP ROLE IF EXISTS
    'analyst_role',
    'etl_role';

-- Create least-privilege roles.
CREATE ROLE 'analyst_role', 'etl_role';

-- Analyst has read-only access to the ecommerce_analytics database.
GRANT SELECT ON ecommerce_analytics.* TO 'analyst_role';

-- ETL role can manipulate project data but is not granted
-- structural/server administration privileges.

GRANT SELECT, INSERT, UPDATE, DELETE
ON ecommerce_analytics.* TO 'etl_role';

-- Create users with placeholder passwords and assign their roles.
CREATE USER 'analyst_user'@'localhost'
IDENTIFIED BY 'YOUR_SECURE_PASSWORD_HERE';

CREATE USER 'etl_user'@'localhost'
IDENTIFIED BY 'YOUR_SECURE_PASSWORD_HERE';

GRANT 'analyst_role'
TO 'analyst_user'@'localhost';

GRANT 'etl_role'
TO 'etl_user'@'localhost';

SET DEFAULT ROLE 'analyst_role'
TO 'analyst_user'@'localhost';

SET DEFAULT ROLE 'etl_role'
TO 'etl_user'@'localhost';

SHOW GRANTS FOR 'analyst_role';
SHOW GRANTS FOR 'etl_role';
SHOW GRANTS FOR 'analyst_user'@'localhost';
SHOW GRANTS FOR 'etl_user'@'localhost';

-- ============================================================
-- END OF SCRIPT
-- ============================================================
