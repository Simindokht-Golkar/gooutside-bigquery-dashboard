-- =====================================================================
-- GoOutside – Phase 3: Analysis
-- Profit = Quantity × (Unit sale price − Unit cost)  (actual, realised profit)
-- Margin = SUM(profit) ÷ SUM(revenue)                 (weighted)
-- =====================================================================

-- 3.1 Revenue, cost, profit and margin per year
SELECT
  EXTRACT(YEAR FROM s.Date) AS year,
  ROUND(SUM(s.Quantity * s.`Unit sale price`) / 1000000, 1) AS revenue_m,
  ROUND(SUM(s.Quantity * p.`Unit cost`) / 1000000, 1) AS cost_m,
  ROUND(SUM(s.Quantity * (s.`Unit sale price` - p.`Unit cost`)) / 1000000, 1) AS profit_m,
  ROUND(SUM(s.Quantity * (s.`Unit sale price` - p.`Unit cost`))
        / SUM(s.Quantity * s.`Unit sale price`) * 100, 1) AS margin_pct,
  ROUND(SUM(s.Quantity * (s.`Unit price` - s.`Unit sale price`)) / 1000000, 1) AS discount_cost_m
FROM `gooutside-512908.GoOutside.daily_sales` AS s
JOIN `gooutside-512908.GoOutside.products` AS p
  ON s.`Product number` = p.`Product number`
GROUP BY year
ORDER BY year;

-- 3.2 Sales channels (Sarah) – Part A: performance per order method
WITH channel AS (
  SELECT
    m.`Order method type` AS order_method,
    SUM(s.Quantity * s.`Unit sale price`) AS revenue,
    SUM(s.Quantity * (s.`Unit sale price` - p.`Unit cost`)) AS profit,
    COUNT(*) AS sales_rows,
    COUNT(DISTINCT s.`Retailer code`) AS retailers_served,
    COUNTIF(s.`Unit sale price` < s.`Unit price`) AS discounted_rows,
    SUM(s.Quantity * (s.`Unit price` - s.`Unit sale price`)) AS discount_cost
  FROM `gooutside-512908.GoOutside.daily_sales` AS s
  JOIN `gooutside-512908.GoOutside.products` AS p ON s.`Product number` = p.`Product number`
  JOIN `gooutside-512908.GoOutside.methods` AS m ON s.`Order method code` = m.`Order method code`
  GROUP BY order_method
)
SELECT
  order_method,
  ROUND(revenue / 1000000, 1) AS revenue_m,
  ROUND(revenue / SUM(revenue) OVER () * 100, 1) AS share_pct,
  sales_rows,
  ROUND(revenue / sales_rows) AS avg_revenue_per_row,
  ROUND(profit / revenue * 100, 1) AS margin_pct,
  retailers_served,
  ROUND(discounted_rows / sales_rows * 100, 1) AS pct_rows_discounted,
  ROUND(discount_cost / 1000000, 2) AS discount_cost_m
FROM channel
ORDER BY revenue DESC;

-- 3.2 Part B: share of revenue per method, per year (the channel shift to Web)
WITH yearly AS (
  SELECT
    EXTRACT(YEAR FROM s.Date) AS year,
    m.`Order method type` AS order_method,
    SUM(s.Quantity * s.`Unit sale price`) AS revenue
  FROM `gooutside-512908.GoOutside.daily_sales` AS s
  JOIN `gooutside-512908.GoOutside.methods` AS m ON s.`Order method code` = m.`Order method code`
  GROUP BY year, order_method
)
SELECT
  year, order_method,
  ROUND(revenue / 1000000, 1) AS revenue_m,
  ROUND(revenue / SUM(revenue) OVER (PARTITION BY year) * 100, 1) AS share_of_year_pct
FROM yearly
ORDER BY order_method, year;

-- 3.3 Sales drivers – product lines (change the grouping column for types or brands)
SELECT
  p.`Product line` AS product_line,
  COUNT(DISTINCT p.`Product number`) AS products_sold,
  SUM(s.Quantity) AS units_sold,
  ROUND(SUM(s.Quantity * s.`Unit sale price`) / 1000000, 1) AS revenue_m,
  ROUND(SUM(s.Quantity * s.`Unit sale price`)
        / SUM(SUM(s.Quantity * s.`Unit sale price`)) OVER () * 100, 1) AS share_pct,
  ROUND(SUM(s.Quantity * (s.`Unit sale price` - p.`Unit cost`)) / 1000000, 1) AS profit_m,
  ROUND(SUM(s.Quantity * (s.`Unit sale price` - p.`Unit cost`))
        / SUM(s.Quantity * s.`Unit sale price`) * 100, 1) AS margin_pct
FROM `gooutside-512908.GoOutside.daily_sales` AS s
JOIN `gooutside-512908.GoOutside.products` AS p ON s.`Product number` = p.`Product number`
GROUP BY product_line
ORDER BY revenue_m DESC;

-- 3.3 Part D: per product – actual margin vs margin at regular price, and the gap
SELECT
  p.`Product number`,
  p.Product,
  p.`Product brand` AS brand,
  ROUND(SUM(s.Quantity * s.`Unit sale price`)) AS revenue,
  ROUND(SUM(s.Quantity * (s.`Unit sale price` - p.`Unit cost`))
        / SUM(s.Quantity * s.`Unit sale price`) * 100, 1) AS actual_margin_pct,
  ROUND(ANY_VALUE(p.`Unit price`) - ANY_VALUE(p.`Unit cost`), 2) AS regular_margin_per_unit,
  ROUND((ANY_VALUE(p.`Unit price`) - ANY_VALUE(p.`Unit cost`)) / ANY_VALUE(p.`Unit price`) * 100, 1) AS regular_margin_pct,
  ROUND((ANY_VALUE(p.`Unit price`) - ANY_VALUE(p.`Unit cost`)) / ANY_VALUE(p.`Unit price`) * 100
        - SUM(s.Quantity * (s.`Unit sale price` - p.`Unit cost`)) / SUM(s.Quantity * s.`Unit sale price`) * 100, 1) AS margin_gap_pts
FROM `gooutside-512908.GoOutside.daily_sales` AS s
JOIN `gooutside-512908.GoOutside.products` AS p ON s.`Product number` = p.`Product number`
GROUP BY p.`Product number`, p.Product, brand
ORDER BY revenue DESC;

-- 3.4 Product popularity by country – top product line per country
WITH country_line AS (
  SELECT
    r.Country AS country,
    p.`Product line` AS product_line,
    SUM(s.Quantity * s.`Unit sale price`) AS revenue
  FROM `gooutside-512908.GoOutside.daily_sales` AS s
  JOIN `gooutside-512908.GoOutside.products` AS p ON s.`Product number` = p.`Product number`
  JOIN `gooutside-512908.GoOutside.retailers` AS r ON s.`Retailer code` = r.`Retailer code`
  GROUP BY country, product_line
)
SELECT
  country,
  product_line AS top_product_line,
  ROUND(revenue / 1000000, 1) AS revenue_m,
  ROUND(revenue / SUM(revenue) OVER (PARTITION BY country) * 100, 1) AS share_in_country_pct
FROM country_line
QUALIFY ROW_NUMBER() OVER (PARTITION BY country ORDER BY revenue DESC) = 1
ORDER BY country;

-- 3.4 Part B: share of each product line per country (PIVOT)
WITH country_line AS (
  SELECT
    r.Country AS country,
    p.`Product line` AS product_line,
    SUM(s.Quantity * s.`Unit sale price`) AS revenue
  FROM `gooutside-512908.GoOutside.daily_sales` AS s
  JOIN `gooutside-512908.GoOutside.products` AS p ON s.`Product number` = p.`Product number`
  JOIN `gooutside-512908.GoOutside.retailers` AS r ON s.`Retailer code` = r.`Retailer code`
  GROUP BY country, product_line
),
shares AS (
  SELECT country, product_line,
         ROUND(revenue / SUM(revenue) OVER (PARTITION BY country) * 100, 1) AS share_pct
  FROM country_line
)
SELECT *
FROM shares
PIVOT (
  SUM(share_pct) FOR product_line IN (
    'Camping Equipment' AS camping,
    'Golf Equipment' AS golf,
    'Mountaineering Equipment' AS mountaineering,
    'Outdoor Protection' AS outdoor_protection,
    'Personal Accessories' AS personal_accessories
  )
)
ORDER BY country;
