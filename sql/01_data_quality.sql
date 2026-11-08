-- =====================================================================
-- GoOutside – Phase 1: Data quality checks
-- Dataset: gooutside-512908.GoOutside  (replace with your own project)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1.1 Are the keys in each dimension table unique?
-- If total_rows = unique_codes, the column is a valid primary key
-- Result: retailers 562/562, products 274/274, methods 12/12
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT `Retailer code`) AS unique_codes
FROM `gooutside-512908.GoOutside.retailers`;

SELECT COUNT(*) AS total_rows, COUNT(DISTINCT `Product number`) AS unique_codes
FROM `gooutside-512908.GoOutside.products`;

SELECT COUNT(*) AS total_rows, COUNT(DISTINCT `Order method code`) AS unique_codes
FROM `gooutside-512908.GoOutside.methods`;

-- ---------------------------------------------------------------------
-- 1.2 Orphan codes: sales without a matching dimension row
-- Result: 0 / 0 / 0
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS orphan_rows
FROM `gooutside-512908.GoOutside.daily_sales` AS s
LEFT JOIN `gooutside-512908.GoOutside.retailers` AS r
  ON s.`Retailer code` = r.`Retailer code`
WHERE r.`Retailer code` IS NULL;

SELECT COUNT(*) AS orphan_rows
FROM `gooutside-512908.GoOutside.daily_sales` AS s
LEFT JOIN `gooutside-512908.GoOutside.products` AS p
  ON s.`Product number` = p.`Product number`
WHERE p.`Product number` IS NULL;

SELECT COUNT(*) AS orphan_rows
FROM `gooutside-512908.GoOutside.daily_sales` AS s
LEFT JOIN `gooutside-512908.GoOutside.methods` AS m
  ON s.`Order method code` = m.`Order method code`
WHERE m.`Order method code` IS NULL;

-- ---------------------------------------------------------------------
-- 1.3 What is actually used in the sales?
-- Result: 289 of 562 retailers, 244 of 274 products, 7 of 12 methods
-- ---------------------------------------------------------------------
SELECT
  COUNT(DISTINCT `Retailer code`)     AS active_retailers,
  COUNT(DISTINCT `Product number`)    AS sold_products,
  COUNT(DISTINCT `Order method code`) AS used_methods
FROM `gooutside-512908.GoOutside.daily_sales`;

-- ---------------------------------------------------------------------
-- 1.4 Exact duplicate rows
-- Result: 780 duplicate groups, 802 extra rows (0.54% of rows, 0.09% of revenue)
-- Decision: kept as genuine repeat orders (see docs/decision-log.md)
-- ---------------------------------------------------------------------
WITH duplicates AS (
  SELECT
    Quantity, `Unit sale price`,
    COUNT(*) - 1 AS extra_copies
  FROM `gooutside-512908.GoOutside.daily_sales`
  GROUP BY `Retailer code`, `Product number`, `Order method code`,
           Date, Quantity, `Unit price`, `Unit sale price`
  HAVING COUNT(*) > 1
),
totals AS (
  SELECT COUNT(*) AS all_rows, SUM(Quantity * `Unit sale price`) AS all_revenue
  FROM `gooutside-512908.GoOutside.daily_sales`
)
SELECT
  COUNT(*) AS duplicate_groups,
  SUM(d.extra_copies) AS extra_rows,
  ROUND(SUM(d.extra_copies * d.Quantity * d.`Unit sale price`)) AS extra_revenue,
  ROUND(SUM(d.extra_copies) / ANY_VALUE(t.all_rows) * 100, 2) AS pct_rows,
  ROUND(SUM(d.extra_copies * d.Quantity * d.`Unit sale price`) / ANY_VALUE(t.all_revenue) * 100, 3) AS pct_revenue
FROM duplicates AS d
CROSS JOIN totals AS t;

-- Evidence: same retailer + product + method + day with different quantities
-- Result: 12,665 groups -> same-day repeat orders are normal
SELECT COUNT(*) AS repeat_orders_same_day
FROM (
  SELECT `Retailer code`, `Product number`, `Order method code`, Date
  FROM `gooutside-512908.GoOutside.daily_sales`
  GROUP BY 1, 2, 3, 4
  HAVING COUNT(DISTINCT Quantity) > 1
);

-- ---------------------------------------------------------------------
-- 1.5 The three prices
-- Part A: Unit price vs Unit sale price (25.3% discounted, 0 above price)
-- ---------------------------------------------------------------------
SELECT
  COUNT(*) AS all_rows,
  COUNTIF(`Unit sale price` < `Unit price`) AS discounted_rows,
  COUNTIF(`Unit sale price` = `Unit price`) AS full_price_rows,
  COUNTIF(`Unit sale price` > `Unit price`) AS above_price_rows,
  ROUND(COUNTIF(`Unit sale price` < `Unit price`) / COUNT(*) * 100, 1) AS pct_discounted,
  CAST(ROUND(SUM(Quantity * (`Unit price` - `Unit sale price`))) AS INT64) AS discount_value
FROM `gooutside-512908.GoOutside.daily_sales`;

-- Part B: sales Unit price vs products Unit price (63% of rows differ)
SELECT
  COUNT(*) AS all_rows,
  COUNTIF(s.`Unit price` != p.`Unit price`) AS price_differs,
  COUNTIF(s.`Unit price` > p.`Unit price`) AS sales_price_higher,
  COUNTIF(s.`Unit price` < p.`Unit price`) AS sales_price_lower,
  ROUND(COUNTIF(s.`Unit price` != p.`Unit price`) / COUNT(*) * 100, 1) AS pct_differs
FROM `gooutside-512908.GoOutside.daily_sales` AS s
JOIN `gooutside-512908.GoOutside.products` AS p
  ON s.`Product number` = p.`Product number`;

-- Price history of one product (TrailChef Canteen: 12.53 until 2017, 14.89 in 2018)
SELECT EXTRACT(YEAR FROM Date) AS year, `Unit price`, COUNT(*) AS sales_rows
FROM `gooutside-512908.GoOutside.daily_sales`
WHERE `Product number` = 2110
GROUP BY year, `Unit price`
ORDER BY year;

-- ---------------------------------------------------------------------
-- 1.6 Sales at price 0 and below cost
-- Result: 524 free rows, 613 below cost, total loss -1,057,340
-- ---------------------------------------------------------------------
SELECT
  COUNTIF(s.`Unit sale price` = 0) AS zero_price_rows,
  COUNTIF(s.`Unit sale price` < p.`Unit cost`) AS below_cost_rows,
  ROUND(SUM(CASE WHEN s.`Unit sale price` < p.`Unit cost`
                 THEN s.Quantity * (s.`Unit sale price` - p.`Unit cost`) ELSE 0 END)) AS total_loss
FROM `gooutside-512908.GoOutside.daily_sales` AS s
JOIN `gooutside-512908.GoOutside.products` AS p
  ON s.`Product number` = p.`Product number`;

-- Loss by product
SELECT
  p.Product,
  COUNT(*) AS loss_rows,
  COUNTIF(s.`Unit sale price` = 0) AS free_rows,
  ROUND(SUM(s.Quantity * (s.`Unit sale price` - p.`Unit cost`))) AS total_loss
FROM `gooutside-512908.GoOutside.daily_sales` AS s
JOIN `gooutside-512908.GoOutside.products` AS p
  ON s.`Product number` = p.`Product number`
WHERE s.`Unit sale price` < p.`Unit cost`
GROUP BY p.Product
ORDER BY total_loss;

-- Loss rate per order method (compare rates, not raw counts)
SELECT
  m.`Order method type` AS order_method,
  COUNT(*) AS all_rows,
  COUNTIF(s.`Unit sale price` < p.`Unit cost`) AS loss_rows,
  ROUND(COUNTIF(s.`Unit sale price` < p.`Unit cost`) / COUNT(*) * 100, 2) AS loss_rate_pct
FROM `gooutside-512908.GoOutside.daily_sales` AS s
JOIN `gooutside-512908.GoOutside.products` AS p
  ON s.`Product number` = p.`Product number`
JOIN `gooutside-512908.GoOutside.methods` AS m
  ON s.`Order method code` = m.`Order method code`
GROUP BY order_method
ORDER BY loss_rate_pct DESC;
