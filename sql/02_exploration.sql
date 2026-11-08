-- =====================================================================
-- GoOutside – Phase 2: Exploration
-- =====================================================================

-- 2.1 Temporal scope: 12 Jan 2015 – 20 Jul 2018, 439 sales days
SELECT
  MIN(Date) AS first_day,
  MAX(Date) AS last_day,
  COUNT(DISTINCT Date) AS sales_days,
  DATE_DIFF(MAX(Date), MIN(Date), DAY) AS days_covered
FROM `gooutside-512908.GoOutside.daily_sales`;

SELECT
  EXTRACT(YEAR FROM Date) AS year,
  MIN(Date) AS first_day,
  MAX(Date) AS last_day,
  COUNT(DISTINCT Date) AS sales_days,
  COUNT(*) AS sales_rows
FROM `gooutside-512908.GoOutside.daily_sales`
GROUP BY year
ORDER BY year;

-- Fair year comparison: same period (1 Jan – 20 Jul) with year-over-year growth
WITH yearly AS (
  SELECT
    EXTRACT(YEAR FROM Date) AS year,
    COUNT(DISTINCT Date) AS sales_days,
    COUNT(*) AS sales_rows,
    SUM(Quantity * `Unit sale price`) AS revenue
  FROM `gooutside-512908.GoOutside.daily_sales`
  WHERE EXTRACT(MONTH FROM Date) < 7
     OR (EXTRACT(MONTH FROM Date) = 7 AND EXTRACT(DAY FROM Date) <= 20)
  GROUP BY year
)
SELECT
  year, sales_days, sales_rows,
  ROUND(revenue / 1000000, 1) AS revenue_million,
  ROUND((revenue - LAG(revenue) OVER (ORDER BY year))
        / LAG(revenue) OVER (ORDER BY year) * 100, 1) AS growth_pct
FROM yearly
ORDER BY year;

-- 2.2 Retailer landscape: listed vs active retailers per country
WITH active AS (
  SELECT DISTINCT `Retailer code`
  FROM `gooutside-512908.GoOutside.daily_sales`
)
SELECT
  r.Country,
  COUNT(*) AS listed_retailers,
  COUNTIF(a.`Retailer code` IS NOT NULL) AS active_retailers,
  ROUND(COUNTIF(a.`Retailer code` IS NOT NULL) / COUNT(*) * 100) AS pct_active
FROM `gooutside-512908.GoOutside.retailers` AS r
LEFT JOIN active AS a ON r.`Retailer code` = a.`Retailer code`
GROUP BY r.Country
ORDER BY active_retailers DESC;

-- ... and per store type (Equipment Rental Stores: 0 of 30 active)
WITH active AS (
  SELECT DISTINCT `Retailer code`
  FROM `gooutside-512908.GoOutside.daily_sales`
)
SELECT
  r.Type AS store_type,
  COUNT(*) AS listed_retailers,
  COUNTIF(a.`Retailer code` IS NOT NULL) AS active_retailers
FROM `gooutside-512908.GoOutside.retailers` AS r
LEFT JOIN active AS a ON r.`Retailer code` = a.`Retailer code`
GROUP BY store_type
ORDER BY active_retailers DESC;
