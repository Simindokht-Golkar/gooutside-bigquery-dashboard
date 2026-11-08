-- =====================================================================
-- GoOutside – Central view: one flat sales table for Sheets and Data Studio
-- Reconciliation check: 149,257 rows · 1,251.5 M revenue · 527.7 M profit · 613 loss rows
-- =====================================================================
CREATE OR REPLACE VIEW `gooutside-512908.GoOutside.v_sales_full` AS
SELECT
  -- When
  s.Date AS order_date,
  EXTRACT(YEAR FROM s.Date) AS order_year,
  EXTRACT(QUARTER FROM s.Date) AS order_quarter,
  DATE_TRUNC(s.Date, MONTH) AS order_month,
  -- Who
  s.`Retailer code` AS retailer_code,
  r.`Retailer name` AS retailer_name,
  r.Type AS retailer_type,
  r.Country AS country,
  -- What
  s.`Product number` AS product_number,
  p.Product AS product_name,
  p.`Product line` AS product_line,
  p.`Product type` AS product_type,
  p.`Product brand` AS brand,
  -- How
  m.`Order method type` AS order_method,
  -- Prices and quantity
  s.Quantity AS quantity,
  s.`Unit price` AS unit_price,
  s.`Unit sale price` AS unit_sale_price,
  p.`Unit cost` AS unit_cost,
  p.`Unit price` AS regular_price,
  -- Calculated values
  s.Quantity * s.`Unit sale price` AS revenue,
  s.Quantity * p.`Unit cost` AS cost,
  s.Quantity * (s.`Unit sale price` - p.`Unit cost`) AS profit,
  s.Quantity * (s.`Unit price` - s.`Unit sale price`) AS discount_value,
  -- Flags
  s.`Unit sale price` < s.`Unit price` AS is_discounted,
  s.`Unit sale price` = 0 AS is_free,
  s.`Unit sale price` < p.`Unit cost` AS is_loss,
  -- Label (order matters: price 0 is also below cost)
  CASE
    WHEN s.`Unit sale price` = 0 THEN 'Given away'
    WHEN s.`Unit sale price` < p.`Unit cost` THEN 'Sold below cost'
    ELSE 'Profitable'
  END AS loss_category
FROM `gooutside-512908.GoOutside.daily_sales` AS s
JOIN `gooutside-512908.GoOutside.retailers` AS r ON s.`Retailer code` = r.`Retailer code`
JOIN `gooutside-512908.GoOutside.products` AS p ON s.`Product number` = p.`Product number`
JOIN `gooutside-512908.GoOutside.methods` AS m ON s.`Order method code` = m.`Order method code`;

-- Reconciliation check
SELECT
  COUNT(*) AS rows_in_view,
  ROUND(SUM(revenue) / 1000000, 1) AS revenue_m,
  ROUND(SUM(profit) / 1000000, 1) AS profit_m,
  COUNTIF(is_loss) AS loss_rows
FROM `gooutside-512908.GoOutside.v_sales_full`;
