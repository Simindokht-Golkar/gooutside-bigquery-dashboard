-- =====================================================================
-- GoOutside – Phase 5: Market concentration and targets (Dustin)
-- HHI = sum of squared market shares (%). HHI >= 2,500 = concentrated
-- (US DOJ & FTC Horizontal Merger Guidelines, 2010)
-- =====================================================================

-- 5.2 Concentration per country: active retailers, top-1, top-3, HHI
WITH retailer_sales AS (
  SELECT country, retailer_name, SUM(revenue) AS revenue
  FROM `gooutside-512908.GoOutside.v_sales_full`
  GROUP BY country, retailer_name
),
shares AS (
  SELECT
    country, retailer_name, revenue,
    revenue / SUM(revenue) OVER (PARTITION BY country) * 100 AS share_pct,
    ROW_NUMBER() OVER (PARTITION BY country ORDER BY revenue DESC) AS rank_in_country
  FROM retailer_sales
)
SELECT
  country,
  COUNT(*) AS active_retailers,
  ROUND(SUM(revenue) / 1000000, 1) AS country_revenue_m,
  ROUND(MAX(share_pct), 1) AS top1_share_pct,
  ROUND(SUM(IF(rank_in_country <= 3, share_pct, 0)), 1) AS top3_share_pct,
  ROUND(SUM(share_pct * share_pct)) AS hhi,
  CASE WHEN SUM(share_pct * share_pct) >= 2500 THEN 'Concentrated (big players)' ELSE 'Competitive' END AS market_type
FROM shares
GROUP BY country
ORDER BY hhi DESC;

-- 5.3 Targets per country (baseline = 2017, latest full year), saved as a view
CREATE OR REPLACE VIEW `gooutside-512908.GoOutside.v_dustin_markets` AS
WITH retailer_sales AS (
  SELECT country, retailer_name, SUM(revenue) AS revenue
  FROM `gooutside-512908.GoOutside.v_sales_full`
  GROUP BY country, retailer_name
),
concentration AS (
  SELECT country, SUM(POW(revenue / total * 100, 2)) AS hhi
  FROM (
    SELECT country, revenue, SUM(revenue) OVER (PARTITION BY country) AS total
    FROM retailer_sales
  )
  GROUP BY country
),
baseline_2017 AS (
  SELECT
    country,
    COUNT(DISTINCT retailer_code) AS retailers_2017,
    SUM(revenue) AS revenue_2017
  FROM `gooutside-512908.GoOutside.v_sales_full`
  WHERE order_year = 2017
  GROUP BY country
)
SELECT
  b.country,
  ROUND(c.hhi) AS hhi,
  IF(c.hhi >= 2500, 'Concentrated (big players)', 'Competitive') AS market_type,
  b.retailers_2017,
  ROUND(b.revenue_2017 / 1000000, 1) AS revenue_2017_m,
  ROUND(b.revenue_2017 / b.retailers_2017 / 1000000, 2) AS revenue_per_retailer_m,
  -- Concentrated: +10% sales per retailer
  IF(c.hhi >= 2500, ROUND(b.revenue_2017 / b.retailers_2017 * 1.10 / 1000000, 2), NULL) AS target_revenue_per_retailer_m,
  -- Competitive: +15% retailers, rounded up
  IF(c.hhi < 2500, CAST(CEIL(b.retailers_2017 * 1.15) AS INT64), NULL) AS target_retailers,
  IF(c.hhi < 2500, CAST(CEIL(b.retailers_2017 * 1.15) AS INT64) - b.retailers_2017, NULL) AS new_retailers_needed
FROM baseline_2017 AS b
JOIN concentration AS c USING (country);

-- 5.5 Retailer lookup view
CREATE OR REPLACE VIEW `gooutside-512908.GoOutside.v_retailer_share` AS
WITH retailer_sales AS (
  SELECT
    country, retailer_name, retailer_type,
    SUM(revenue) AS revenue,
    SUM(profit) AS profit,
    COUNT(*) AS order_lines
  FROM `gooutside-512908.GoOutside.v_sales_full`
  GROUP BY country, retailer_name, retailer_type
)
SELECT
  retailer_name, country, retailer_type,
  ROUND(revenue / 1000000, 2) AS revenue_m,
  ROUND(profit / 1000000, 2) AS profit_m,
  order_lines,
  ROUND(revenue / SUM(revenue) OVER (PARTITION BY country) * 100, 1) AS market_share_pct,
  RANK() OVER (PARTITION BY country ORDER BY revenue DESC) AS rank_in_country,
  COUNT(*) OVER (PARTITION BY country) AS retailers_in_country
FROM retailer_sales;

-- 5.6 Pareto: 51 of 289 retailers (18%) generate 80% of revenue
CREATE OR REPLACE VIEW `gooutside-512908.GoOutside.v_pareto` AS
WITH retailer_revenue AS (
  SELECT retailer_name, country, SUM(revenue) AS revenue
  FROM `gooutside-512908.GoOutside.v_sales_full`
  GROUP BY retailer_name, country
)
SELECT
  ROW_NUMBER() OVER (ORDER BY revenue DESC) AS retailer_rank,
  retailer_name,
  country,
  ROUND(revenue / 1000000, 2) AS revenue_m,
  ROUND(revenue / SUM(revenue) OVER () * 100, 2) AS share_pct,
  ROUND(SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER () * 100, 1) AS cumulative_share_pct,
  ROUND(ROW_NUMBER() OVER (ORDER BY revenue DESC) / COUNT(*) OVER () * 100, 1) AS pct_of_retailers
FROM retailer_revenue;
