# GoOutside – Data decision log

Facts, checks and decisions from building the GoOutside data warehouse in BigQuery, kept for the presentation and the data dictionary. One section per roadmap step.

---

## 0. Setup and data loading

| Item | Fact |
|---|---|
| Platform | BigQuery sandbox (free, no billing) |
| Project / dataset | `gooutside-512908` / `GoOutside` (dataset name is case-sensitive) |
| Data location | europe-west1 |
| Tables | `daily_sales`, `products`, `retailers`, `methods` |
| Rename | `GoOutside_methods` was renamed to `methods` so all four tables follow one naming pattern |
| Table expiry | Sandbox tables expire after 60 days (daily_sales expires 26 Dec 2026); keep the original CSVs |
| Saved queries | One saved query per phase (e.g. `Phase 1 – Data quality`, `Phase 2 – Exploration`). Saved queries do not save edits automatically: click Save again after changes |

**Upload check – row counts match the CSV files, so nothing was lost:**

| Table | Rows | Columns |
|---|---|---|
| daily_sales | 149,257 | 7 |
| products | 274 | 8 |
| retailers | 562 | 4 |
| methods | 12 | 2 |

**Schema findings**
- BigQuery auto-detected the `dd/mm/yyyy` dates correctly and stored `Date` as a real DATE type (e.g. 2015-01-15), so no conversion is needed.
- Column names kept their spaces (e.g. `Retailer code`), so in SQL they must be written in backticks: `` `Retailer code` ``.
- Codes and quantities are INTEGER, prices are FLOAT.

**Data model (star schema)**
- Fact table: `daily_sales`. Dimension tables: `retailers`, `products`, `methods`.
- retailers → daily_sales: one-to-many (key `Retailer code`)
- products → daily_sales: one-to-many (key `Product number`)
- methods → daily_sales: one-to-many (key `Order method code`)
- retailers ↔ products: many-to-many, resolved through `daily_sales`
- One row of `daily_sales` = one retailer × product × order method × day. There is no order ID.

---

## 1.1 Are the keys unique? – PASSED

| Table | Total rows | Distinct codes |
|---|---|---|
| retailers | 562 | 562 |
| products | 274 | 274 |
| methods | 12 | 12 |

**Meaning:** every code appears once, so each is a valid primary key. Joins to `daily_sales` will not double any sales rows.

---

## 1.2 Orphan codes in daily_sales? – PASSED

| Check (LEFT JOIN … WHERE key IS NULL) | Orphan rows |
|---|---|
| Sales without a matching retailer | 0 |
| Sales without a matching product | 0 |
| Sales without a matching order method | 0 |

**Meaning:** every one of the 149,257 sales links to a known retailer, product and order method. Joining the tables loses no data.

---

## 1.3 What is actually used in the sales?

| Dimension | In table | Appears in sales | Never used |
|---|---|---|---|
| Retailers | 562 | 289 | 273 (49%) |
| Products | 274 | 244 | 30 |
| Order methods | 12 | 7 | 5 (codes 8–12, all "Other") |

**Decisions**
- **Dustin's analysis counts only active retailers** (those with at least one sale). Counting from the full retailer list would make every market look about twice as large as it is.
- **Order methods 8–12 are left out of charts** (never used, all labelled "Other"). Listed as a data-cleanup item.
- The 30 unsold products are an open question for the product team (new, discontinued, or no demand).

---

## 1.4 Duplicate rows – decision: KEEP

**Statement for the presentation / data dictionary:**

> The data contains 802 exact duplicate rows (0.5% of rows, 0.09% of revenue). Since same-day repeat orders are common in the data (12,665 cases with different quantities), the duplicates are spread across 194 days and 55 retailers, and there is no order ID to prove otherwise, they were kept as genuine orders. Removing them would not change any finding.

**Evidence**

| Check | Result |
|---|---|
| Exact duplicate groups (all 7 columns identical) | 780 (761 × twice, 17 × 3 times, 1 × 4, 1 × 5) |
| Extra rows (copies beyond the first) | 802 |
| Share of rows | 802 ÷ 149,257 = 0.54% |
| Revenue of the extra rows | 1,173,410 |
| Share of revenue | 1,173,410 ÷ 1,251,508,640 = 0.09% |
| Same retailer + product + method + day with different quantities | 12,665 groups (real same-day repeat orders are normal) |
| Spread | 194 different days, 55 retailers, all years 2015–2018 (no sign of a single import error) |
| Median quantity | 7 in duplicates vs 44 in all rows (small orders repeat by chance more easily) |

**Method used (reusable):** (1) Are such duplicates possible in real life? (2) Do they cluster like an error or spread like real events? (3) Does the decision change any result? (4) In a real job, confirm with the data owner.

---

## 1.5 The three prices – decision: revenue = Quantity × Unit sale price

| Price column | Table | Meaning (confirmed by the checks below) |
|---|---|---|
| `Unit price` | daily_sales | Normal (list) price on the day of the sale |
| `Unit sale price` | daily_sales | Price the customer actually paid (after discount) |
| `Unit price` | products | Regular retail price per product (one value, confirmed by the instructor). For products whose price changed, it lies between the old and new price (close to the average) and was never actually charged |

**Part A – Unit price vs Unit sale price (daily_sales)**

| Check | Result |
|---|---|
| Discounted rows (sale price < unit price) | 37,707 (25.3%) |
| Full-price rows (sale price = unit price) | 111,550 |
| Rows with sale price above unit price | 0 |
| Value given away as discounts | 66,472,820 (about 5% of revenue at full price) |

**Meaning:** about 1 in 4 sales is discounted, and the sale price is never higher than the unit price. This confirms that `Unit price` is the normal price and `Unit sale price` is what was paid.

**Part B – sales Unit price vs products Unit price**

| Check | Result |
|---|---|
| Rows where the two prices differ | 93,984 (63%) |
| Sales price higher than catalogue | 47,308 |
| Sales price lower than catalogue | 46,676 |
| Products with one stable price for all 3.5 years | 164 – catalogue price always matches |
| Products whose price changed (usually once, most often in 2017) | 80 – catalogue price never matches any sales row |
| Same product with two different unit prices on the same day | 0 |

**Example – TrailChef Canteen (product 2110):** sold at 12.53 from 2015 to 2017 and at 14.89 in 2018. The products table says 12.92, which is between the two and was never charged.

**Meaning:** the 63% of differing rows all belong to the 80 products that had a price change. For each of them, the products table holds one reference value between the old and new price (in all 80 cases it lies inside the range of real prices, close to the average). The daily_sales `Unit price` is the price that applied on the day.

**Three kinds of profit (confirmed with the instructor)**

| Profit type | Formula | Answers | Use |
|---|---|---|---|
| 1. Actual (realised) profit | Quantity × (daily_sales `Unit sale price` − `Unit cost`) | How much money did we really make? | **All profit KPIs**, the dashboard and Sarah's numbers |
| 2. Profit at full price | Quantity × (daily_sales `Unit price` − `Unit cost`) | What would we have made without discounts? (type 2 − type 1 = cost of discounts, 66.5 M) | Extra insight for Sarah |
| 3. Margin at regular price, per unit | products `Unit price` − `Unit cost` | How profitable is a product by design, per unit? | Product comparison and pricing |

Instructor's confirmation: "For the dashboard, if we want actual realized profit, then your approach [Unit sale price − Unit cost] is the correct one." Her own suggestion (Unit price − Unit cost) is the margin at regular price (type 3).

**Decisions**
- **Revenue = Quantity × Unit sale price** (what the customer actually paid, on the day of the sale).
- **The profit KPI uses actual profit (type 1)**, because the brief defines profit as sales revenues minus costs, and only this version includes discounts and the zero-price losses. The instructor's sample does the same in its `sales_losses` tab (unit margin = sale price − cost).
- **The products `Unit price` is the regular retail price.** It is used for the margin at regular price per product (type 3), not for revenue or the profit KPI. Caveat: for the 80 products with a price change, this price was never actually charged.
- **Profit is an estimate:** `Unit cost` exists only once per product, while prices (and probably costs) changed over time. State this once in the presentation.
- Possible extras for Sarah: cost of discounts (type 2 − type 1), discount value by order method or retailer, list of the 80 products with a price change.

---

## 1.6 Sales at price 0 and below cost – decision: KEEP, report separately to Finance

**The question:** did GoOutside sell anything for less than it cost? How often, and how much money was lost?

**Logic:** for each sale row, compare `Unit sale price` (daily_sales) with `Unit cost` (products). Loss per row = Quantity × (sale price − cost), negative when the sale price is below cost. A sale price of 0 is the extreme case (product given away).

**Main result**

| Check | Result |
|---|---|
| Rows sold at price 0 | 524 |
| Rows sold below `Unit cost` (includes the 524 zero-price rows) | 613 |
| …of which sold above 0 but below cost | 89 |
| Total loss on these rows | −1,057,340 |
| Loss compared with total profit (527.7 M) | about 0.2% |

**Q1 – How much of the loss comes from free products?**

| Loss type | Rows | Loss | Share of loss |
|---|---|---|---|
| Given away (price 0) | 524 | −971,406 | 91.9% |
| Sold below cost (price > 0) | 89 | −85,934 | 8.1% |

**Q2 – Which products lose the most?** (18 products in total; grouped by product name)

| Product | Loss rows | Of which free | Loss | Type |
|---|---|---|---|---|
| Blue Steel Max Putter | 62 | 43 | −362,442 | Mixed |
| TrailChef Cook Set | 57 | 48 | −276,520 | Mixed |
| Seeker Mini | 13 | 13 | −147,400 | Given away |
| TrailChef Deluxe Cook Set | 10 | 10 | −66,361 | Given away |
| Firefly Mapreader | 44 | 44 | −52,342 | Given away |
| Blue Steel Putter | 26 | 26 | −40,088 | Given away |
| Course Pro Umbrella | 91 | 91 | −26,193 | Given away |
| Hibernator Camp Cot | 49 | 17 | −23,895 | Mixed |
| Firefly Rechargeable Battery | 18 | 18 | −12,030 | Given away |
| Firefly Climbing Lamp | 19 | 0 | −11,081 | Sold below cost |
| Course Pro Golf and Tee Set | 70 | 70 | −9,536 | Given away |
| BugShield Extreme | 29 | 29 | −7,737 | Given away |
| Aloe Relief | 24 | 24 | −6,588 | Given away |
| Sun Shelter 30 | 38 | 38 | −5,763 | Given away |
| BugShield Spray | 19 | 19 | −4,635 | Given away |
| BugShield Lotion Lite | 26 | 26 | −2,359 | Given away |
| Seeker Extreme | 10 | 0 | −1,896 | Sold below cost |
| Sun Shelter 15 | 8 | 8 | −476 | Given away |

- Number of rows and money tell different stories: Course Pro Umbrella has the most loss rows (91) but a small loss (cheap product); Blue Steel Max Putter has fewer rows but the biggest loss. For Finance, sort by money.
- Two kinds of loss: **given away** (all loss rows free, looks like promotions or gifts) and **sold below cost** (Firefly Climbing Lamp, Seeker Extreme: never free, but sold below cost, which looks like a pricing or discount-approval problem). Three products are mixed.

**Q3 – Is it spread out or concentrated?**

| Check | Result |
|---|---|
| Retailers involved | 56 |
| Products involved | 18 |
| Loss rows per year | 2015: 100 · 2016: 119 · 2017: 229 · 2018: 165 |
| Loss rows per order method (raw count) | Web 420 · Telephone 99 · E-mail 48 · Sales visit 32 · Mail 11 · Fax 2 · Special 1 |

**Meaning:** spread across many retailers, products, all years and all channels → a regular business practice (promotions, gifts or discounts), not a one-time data error.

**Q3 extra – fair comparison by order method (loss rows ÷ all rows of that method)**

| Order method | All rows | Loss rows | Loss rate (rows) | Loss | Loss as % of method revenue |
|---|---|---|---|---|---|
| Mail | 929 | 11 | **1.18%** | −32,701 | 0.16% |
| Sales visit | 3,661 | 32 | 0.87% | −61,327 | 0.09% |
| Telephone | 12,404 | 99 | 0.80% | −125,119 | 0.08% |
| Fax | 280 | 2 | 0.71% | −1,705 | 0.06% |
| E-mail | 7,388 | 48 | 0.65% | −54,829 | 0.06% |
| Web | 124,225 | 420 | **0.34%** | −763,659 | 0.08% |
| Special | 370 | 1 | 0.27% | −18,000 | **0.40%** |

**Meaning:** the raw count suggested Web is the problem (420 rows), but that only reflects its size. Relative to its volume, **Web has one of the lowest loss rates (0.34%)**, while the manual channels (Mail 1.18%, Sales visit 0.87%, Telephone 0.80%) give away or underprice products 2–3 times as often. Special has only one loss row, but it was a large one (−18,000, 0.4% of that channel's revenue). Lesson: always compare rates, not raw counts, when groups have very different sizes.

**Decisions**
- **Keep the rows in all totals** (they are real transactions that cost money).
- **Show them separately in Sarah's sheet** as a loss summary (by product, loss type and order method), with the detailed rows below.
- **Use the loss rate per channel in Sarah's channel analysis** (manual channels lose relatively more).
- **Open questions for the business:** why are products sold at 0 (promotion, sample, data-entry error)? Who approves sales below cost (Firefly Climbing Lamp, Seeker Extreme)?

---

## 2.1 Temporal scope – decision: compare years on the same period (1 Jan – 20 Jul)

**Overall range**

| Check | Result |
|---|---|
| First sale | 12 Jan 2015 |
| Last sale | 20 Jul 2018 |
| Calendar days covered | 1,285 (about 3.5 years) |
| Days with sales | 439 (about 1 in 3 calendar days) |

**Per year**

| Year | First sale | Last sale | Sales days | Sales rows | Complete? |
|---|---|---|---|---|---|
| 2015 | 12 Jan | 17 Dec | 122 | 26,936 | Yes |
| 2016 | 10 Jan | 23 Dec | 123 | 40,689 | Yes |
| 2017 | 9 Jan | 22 Dec | 123 | 51,326 | Yes |
| 2018 | 8 Jan | **20 Jul** | 71 | 30,306 | **No – about 7 months only** |

**Sales-day pattern:** sales are recorded on about 123 days per year, almost only on weekdays (Mon–Thu 86–87 days each, Fri 65, Sun 24, Sat 3). Sales days come in blocks of consecutive days, separated by gaps of about 2–3 weeks (most common gaps: 1 day, then 17 and 24 days). So the data looks like periodic order cycles, not continuous daily trading. For trend charts, use months or quarters, not days.

**Fair comparison – same period every year (1 Jan – 20 Jul)**

| Year | Sales days | Sales rows | Revenue (Jan – 20 Jul) | Growth vs previous year |
|---|---|---|---|---|
| 2015 | 68 | 14,259 | 135.2 M | – |
| 2016 | 71 | 21,751 | 174.2 M | +28.9% |
| 2017 | 71 | 27,593 | 220.0 M | +26.3% |
| 2018 | 71 | 30,306 | 285.5 M | **+29.8%** |

**Meaning:** comparing the full 2018 total (285.5 M) with full-year 2017 (401.4 M) would wrongly suggest a decline. On the same period, 2018 is the strongest year so far, with growth of about 26–30% every year.

**Decisions**
- **Year-over-year comparisons use the same period (1 Jan – 20 Jul)**, or full years 2015–2017 only.
- **2018 is labelled as "Jan – Jul 2018" (partial year)** in every chart and table.
- **Time charts use month or quarter**, because sales days come in blocks with gaps.

---

## 2.2 Retailer landscape – decision: report listed vs active retailers side by side

**Overview:** 562 retailers listed in 21 countries and 8 store types; 289 (51%) are active (at least one sale). All 21 countries have at least one active retailer.

**Part A – per country**

| Country | Listed | Active | % active |
|---|---|---|---|
| United States | 104 | 54 | 52% |
| Japan | 49 | 22 | 45% |
| United Kingdom | 38 | 21 | 55% |
| France | 43 | 20 | 47% |
| China | 28 | 18 | 64% |
| Canada | 34 | 17 | 50% |
| Germany | 38 | 15 | 39% |
| Austria | 18 | 13 | 72% |
| Brazil | 16 | 11 | 69% |
| Spain | 14 | 10 | 71% |
| Finland | 15 | 10 | 67% |
| Italy | 22 | 10 | 45% |
| Belgium | 13 | 9 | 69% |
| Singapore | 20 | 9 | 45% |
| Netherlands | 19 | 9 | 47% |
| Mexico | 10 | 8 | 80% |
| Korea | 13 | 8 | 62% |
| Sweden | 17 | 7 | 41% |
| Denmark | 12 | 7 | 58% |
| Switzerland | 26 | 6 | **23%** |
| Australia | 13 | 5 | 38% |

**Part B – per store type**

| Store type | Listed | Active | % active |
|---|---|---|---|
| Eyewear Store | 31 | 24 | 77% |
| Department Store | 50 | 38 | 76% |
| Sports Store | 124 | 78 | 63% |
| Outdoors Shop | 164 | 91 | 55% |
| Golf Shop | 72 | 33 | 46% |
| Warehouse Store | 46 | 13 | 28% |
| Direct Marketing | 45 | 12 | 27% |
| **Equipment Rental Store** | **30** | **0** | **0%** |

**Meaning**
- **No Equipment Rental Store has ever bought anything (0 of 30).** A whole store type is registered but inactive: an untapped segment, a different buying route, or outdated entries.
- Warehouse Stores and Direct Marketing convert poorly (about 1 in 4 active); Eyewear and Department Stores convert best (about 3 in 4).
- **Switzerland has only 6 of 26 retailers active (23%)**, which explains why its market looks so concentrated (largest retailer about 87% of sales).
- The US has the most retailers, both listed (104) and active (54).

**Decisions**
- **Dustin's sheet shows listed and active retailers side by side** per country and store type.
- **For competitive markets, "+15% retailers" can also be reached by activating listed but inactive retailers**, which is cheaper than finding new partners. Point for the presentation.
- **Open questions for Dustin:** why are Equipment Rental Stores inactive? Are the inactive entries still real partners or outdated records?

---

## 3.1 Sales performance by year – decision: weighted margin, actual profit

**Revenue, cost, profit and margin per year** (actual profit = Quantity × (Unit sale price − Unit cost); margin = total profit ÷ total revenue, weighted)

| Year | Revenue (M) | Cost (M) | Profit (M) | Margin |
|---|---|---|---|---|
| 2015 | 242.3 | 139.3 | 103.0 | 42.5% |
| 2016 | 322.3 | 188.0 | 134.3 | 41.7% |
| 2017 | 401.4 | 232.3 | 169.0 | 42.1% |
| 2018 (Jan – 20 Jul) | 285.5 | 164.2 | 121.4 | 42.5% |
| **Total** | **1,251.5** | **723.8** | **527.7** | **42.2%** |

**Cost of discounts per year** (profit at full price − actual profit = Quantity × (Unit price − Unit sale price))

| Year | Actual profit (M) | Profit at full price (M) | Discount cost (M) | Discounts as % of full-price revenue |
|---|---|---|---|---|
| 2015 | 103.0 | 118.1 | 15.1 | 5.9% |
| 2016 | 134.3 | 151.7 | 17.4 | 5.1% |
| 2017 | 169.0 | 187.6 | 18.6 | 4.4% |
| 2018 (Jan – 20 Jul) | 121.4 | 136.8 | 15.4 | 5.1% |

**Meaning**
- **Revenue grows about 26–30% per year (same-period comparison, see 2.1), while the margin stays stable at about 42%.** GoOutside grows by selling more volume, not by changing prices or costs: healthy growth that is not bought with discounts.
- **Discounts fell from 5.9% (2015) to 4.4% (2017) but rose again to 5.1% in 2018.** In 7 months of 2018 discounts already reached 15.4 M, close to the full 2017 value (18.6 M). Flag for Sarah.
- Total discount cost over the whole period: 66.5 M.

**Decisions**
- **Margin is always weighted: SUM(profit) ÷ SUM(revenue)**, never an average of row margins (improvement over the instructor's sample, where small orders counted as much as large ones).
- **Show actual profit and discount cost side by side in Sarah's sheet** (profit types 1 and 2).
- **Margin at regular price per product (type 3) is used in 3.3**, because it describes a product, not a year.

---

## 3.2 Sales channels (Sarah) – decision: judge channels on trend, order value, reach and discounts, not margin alone

**Part A – performance per order method (all years)**

| Method | Revenue (M) | Share | Sales rows | Avg revenue per row | Margin | Retailers served | % rows discounted | Discount cost (M) |
|---|---|---|---|---|---|---|---|---|
| Web | 909.6 | 72.7% | 124,225 | 7,322 | 42.2% | 289 | 18.9% | 43.05 |
| Telephone | 157.9 | 12.6% | 12,404 | 12,729 | 42.1% | 93 | 52.1% | 11.55 |
| E-mail | 87.9 | 7.0% | 7,388 | 11,898 | 43.2% | 38 | 47.3% | 5.68 |
| Sales visit | 68.0 | 5.4% | 3,661 | 18,563 | 40.9% | 49 | 85.7% | 4.22 |
| Mail | 20.8 | 1.7% | 929 | 22,349 | 43.4% | 23 | 93.8% | 1.55 |
| Special | 4.5 | 0.4% | 370 | 12,202 | 40.7% | 7 | 53.0% | 0.33 |
| Fax | 2.9 | 0.2% | 280 | 10,284 | 41.7% | 19 | 25.4% | 0.09 |

**Part B – share of revenue per year**

| Method | 2015 | 2016 | 2017 | 2018 (Jan–Jul) | Pattern |
|---|---|---|---|---|---|
| Web | 36.6% | 67.7% | 87.8% | 87.7% | Dominant |
| Telephone | 34.1% | 17.1% | 3.4% | 2.3% | Collapsed |
| E-mail | 21.5% | 7.3% | 1.6% | 2.1% | Collapsed |
| Sales visit | 3.3% | 4.1% | 6.3% | 7.5% | Growing |
| Mail | 3.8% | 2.6% | 0.8% | 0.0% | Gone |
| Special | 0.5% | 1.0% | 0.0% | – | Gone |
| Fax | 0.2% | 0.2% | 0.2% | 0.3% | Always tiny, stable |

**Meaning**
- **Channel shift:** customers moved from Telephone and E-mail to Web between 2015 and 2017. This is a shift, not lost business (total revenue grew 26–30% per year).
- **Margins are almost equal (41–43%)**, so margin alone cannot tell Sarah which channel to cut. The useful columns are trend, average order value, retailers served, discount frequency and loss rate (1.6).
- **Mail:** 1.7% of revenue, discount on 94% of orders, highest loss rate (1.18%, see 1.6), disappeared by 2018.
- **Telephone and E-mail:** shrinking fast, but Telephone still serves 93 retailers and E-mail 38.
- **Sales visit:** small (5.4%) but growing (3% → 7.5%), with large orders (18.6 k per row), but discounts on 86% of orders.
- **Web:** 73% of revenue, used by all 289 active retailers, discounts on only 19% of orders, lowest loss rate among the big channels.

**Decisions**
- **Sarah's channel tab shows all of these columns plus the yearly trend**, not revenue alone.
- **Personnel cost per channel is not in the data** → the break-even calculator in Sarah's sheet lets her enter it.
- **Presentation framing:** show the product, not a verdict. E.g. "Sarah can see that Mail brings 1.7% of revenue, discounts 94% of orders and has almost disappeared; with the calculator she enters its staff cost and decides."
- Possible observations for the business: Mail, Special and Fax are phase-out candidates; Telephone and E-mail need a managed move to Web; Sales visit discounts should be reviewed.

---

## 3.3 Sales drivers – decision: show revenue AND margin for every product level

**Part A – product lines**

| Product line | Products sold | Units sold | Revenue (M) | Share | Profit (M) | Margin |
|---|---|---|---|---|---|---|
| Personal Accessories | 152 | 6,376,094 | 410.3 | 32.8% | 172.2 | 42.0% |
| Camping Equipment | 41 | 5,030,564 | 334.8 | 26.8% | 124.4 | 37.1% |
| Golf Equipment | 15 | 2,173,517 | 331.8 | 26.5% | 158.0 | 47.6% |
| Mountaineering Equipment | 21 | 3,736,892 | 156.9 | 12.5% | 62.5 | 39.9% |
| Outdoor Protection | 15 | 2,478,880 | 17.7 | 1.4% | 10.6 | 60.1% |

**Part B – top product types**

| Product type | Products | Revenue (M) | Share | Margin |
|---|---|---|---|---|
| Eyewear | 75 | 204.7 | 16.4% | 41.4% |
| Woods | 4 | 148.4 | 11.9% | 46.8% |
| Watches | 47 | 146.5 | 11.7% | 44.3% |
| Irons | 4 | 113.2 | 9.0% | 46.2% |
| Tents | 6 | 101.8 | 8.1% | 31.4% |
| Packs | 6 | 101.6 | 8.1% | 39.7% |
| Sleeping Bags | 7 | 65.7 | 5.2% | 39.4% |
| Putters | 3 | 49.1 | 3.9% | 47.4% |

**Part C – top brands** (26 brands in total)

| Brand | Products | Revenue (M) | Share | Profit (M) | Margin |
|---|---|---|---|---|---|
| Hailstorm | 8 | 261.6 | 20.9% | 121.8 | 46.6% |
| Star | 6 | 101.8 | 8.1% | 32.0 | **31.4%** |
| Epoch | 23 | 96.7 | 7.7% | 42.4 | 43.9% |
| Canyon Mule | 5 | 88.3 | 7.1% | 34.3 | 38.8% |
| Extreme | 11 | 87.3 | 7.0% | 37.4 | 42.8% |
| Relax | 22 | 66.3 | 5.3% | 24.1 | 36.4% |
| Granite | 11 | 61.9 | 4.9% | 26.1 | 42.1% |
| Xray | 11 | 54.0 | 4.3% | 24.3 | 45.1% |

**Part D – per product: actual margin vs margin at regular price (profit type 3)**

Top 5 by revenue:

| Product | Revenue (M) | Actual margin | Regular margin | Regular margin per unit |
|---|---|---|---|---|
| Hailstorm Titanium Woods Set | 56.8 | 45.7% | 49.0% | 622.36 |
| Star Lite (tent) | 46.5 | **28.9%** | **32.5%** | 120.13 |
| TX (watch) | 44.3 | 44.7% | 45.0% | 86.36 |
| Hailstorm Titanium Irons | 44.3 | 45.7% | 49.8% | 461.96 |
| Hailstorm Steel Woods Set | 37.3 | 45.0% | 51.9% | 414.11 |

Largest gap between regular and actual margin (percentage points):

| Product | Revenue (M) | Actual margin | Regular margin | Gap (pts) |
|---|---|---|---|---|
| Seeker Mini | 1.7 | 39.5% | 53.2% | 13.8 |
| Hibernator Pad | 7.5 | 43.8% | 54.4% | 10.6 |
| TrailChef Kettle | 6.4 | 52.5% | 61.6% | 9.1 |
| Course Pro Putter | 23.2 | 49.5% | 58.5% | 9.0 |
| TrailChef Water Bag | 1.8 | 49.3% | 58.0% | 8.7 |

Highest regular margin %: small, cheap products (TrailChef Cup 76.8%, Course Pro Gloves 76.3%, BugShield Lotion Lite 73.1%). Lowest: Granite Hammer 28.9%, Granite Climbing Helmet 29.0%. Revenue and regular margin are almost unrelated (rank correlation about −0.1).

**Meaning**
- **Golf = few expensive products.** 15 products bring almost the same revenue as Camping's 41 (about 153 per item vs about 67), and with a higher margin (47.6% vs 37.1%) Golf earns 34 M more profit than Camping. Golf is the most profitable line.
- **Hailstorm (golf) alone is 20.9% of all revenue** and has a high margin (46.6%).
- **Star (tents) is the number-2 brand by revenue but has the lowest margin of the top brands (31.4%).** Epoch sells less (96.7 M) but earns 10 M more profit. Star Lite is the number-2 product but earns only 28.9%. Candidate for a price or supplier-cost review.
- **Outdoor Protection has the highest margin (60.1%) but only 1.4% of revenue**: cheap, high-margin items.
- **Best sellers are not automatically the most profitable**, so revenue and margin must be shown together.
- **The margin gap shows where discounts or free items cost margin** (Seeker Mini was given away 13 times, see 1.6). Course Pro Putter combines a large gap with large revenue.

**Decisions**
- **Every product view in Sarah's sheet and the dashboard shows revenue and margin side by side.**
- **A product tab for Sarah** with actual margin, regular margin (type 3) and the gap in percentage points.
- **Method for the presentation:** compare revenue with units (average price) and revenue with profit (margin), because one column alone can mislead.

---

## 3.4 Product popularity by country – decision: show product mix per country, including gaps

**Part A – top product line per country** (ROW_NUMBER + QUALIFY)

| Top product line | Countries | Countries (share of that line in the country) |
|---|---|---|
| Golf Equipment | 8 | Belgium 36.5%, Brazil 38.9%, China 46.1%, Japan 39.6%, Mexico 30.7%, Netherlands 36.0%, Singapore 61.9%, Switzerland 42.5% |
| Personal Accessories | 6 | Austria 47.3%, Canada 46.8%, Denmark 100%, France 47.9%, Italy 50.7%, United States 43.1% |
| Camping Equipment | 5 | Australia 35.8%, Germany 30.3%, Korea 37.0%, Spain 26.2%, United Kingdom 35.6% |
| Mountaineering Equipment | 2 | Finland 40.8%, Sweden 44.1% |

**Part B – share of each product line per country (%)** (PIVOT; empty = never bought)

| Country | Camping | Golf | Mountaineering | Outdoor Prot. | Personal Acc. |
|---|---|---|---|---|---|
| Australia | 35.8 | 4.5 | 32.5 | 0.5 | 26.8 |
| Austria | 23.5 | – | 27.8 | 1.4 | 47.3 |
| Belgium | 11.9 | 36.5 | 22.6 | 0.7 | 28.3 |
| Brazil | 37.6 | 38.9 | 0.2 | 2.4 | 21.0 |
| Canada | 26.3 | 23.8 | 1.6 | 1.5 | 46.8 |
| China | 6.9 | 46.1 | 18.4 | – | 28.6 |
| Denmark | – | – | – | – | 100.0 |
| Finland | 25.2 | – | 40.8 | 1.9 | 32.1 |
| France | 29.1 | 15.6 | 6.0 | 1.5 | 47.9 |
| Germany | 30.3 | 28.0 | 12.5 | 2.1 | 27.1 |
| Italy | 33.6 | 14.9 | – | 0.8 | 50.7 |
| Japan | 27.0 | 39.6 | – | 1.2 | 32.2 |
| Korea | 37.0 | 32.4 | 2.9 | 2.1 | 25.6 |
| Mexico | 23.3 | 30.7 | 28.9 | 1.4 | 15.7 |
| Netherlands | 16.0 | 36.0 | 19.9 | 0.7 | 27.5 |
| Singapore | 20.3 | 61.9 | – | 0.9 | 16.9 |
| Spain | 26.2 | 25.0 | 24.1 | 0.3 | 24.5 |
| Sweden | – | 15.8 | 44.1 | 0.3 | 39.9 |
| Switzerland | 27.2 | 42.5 | – | 1.6 | 28.7 |
| United Kingdom | 35.6 | 22.9 | 10.9 | 1.7 | 28.9 |
| United States | 28.7 | 13.5 | 12.8 | 1.8 | 43.1 |
| **All countries** | **26.8** | **26.5** | **12.5** | **1.4** | **32.8** |

**Regional patterns**
- **Asia → Golf:** Singapore 62%, China 46%, Japan 40% (number 1); Korea 32% (number 2).
- **Nordics → Mountaineering:** Sweden 44%, Finland 41% (vs 12.5% overall); the only two countries where it is number 1.
- **North America and Western Europe → Personal Accessories:** USA 43%, Canada 47%, France 48%, Italy 51%, Austria 47%.
- **Outdoor Protection is small everywhere** (never above 2.4%).

**White spaces – product lines never sold in a country**

| Product line | Never sold in |
|---|---|
| Golf Equipment | Austria, Finland, Denmark |
| Mountaineering Equipment | Italy, Japan, Singapore, Switzerland, Denmark |
| Camping Equipment | Sweden, Denmark |
| Outdoor Protection | China |

**Meaning**
- Clear regional preferences support targeted marketing (golf in Asia, mountaineering in the Nordics).
- **Denmark buys only Personal Accessories (100%)** from its 7 active retailers.
- **White spaces are possible growth opportunities for Dustin**, e.g. no mountaineering gear sold in Switzerland or Japan, no golf in Austria. They may also reflect missing retailer types in those countries.

**Decisions**
- **The dashboard gets a country × product line view** (heatmap or stacked bar) with a country filter.
- **Dustin's sheet shows the white spaces** as a list of country × product line combinations with no sales.

---

## 4.1 Flat sales view `v_sales_full` – built and reconciled

**What it is:** a BigQuery view (saved query, no stored data, always current) joining daily_sales + retailers + products + methods. Single source of truth for Sarah's sheet, Dustin's sheet and the Looker Studio dashboard.

**Columns:** order_date, order_year, order_quarter, order_month · retailer_code, retailer_name, retailer_type, country · product_number, product_name, product_line, product_type, brand · order_method · quantity, unit_price, unit_sale_price, unit_cost, regular_price · revenue, cost, profit, discount_value · is_discounted, is_free, is_loss

**Design choices**
- snake_case column names (no backticks needed downstream)
- Names next to codes, so non-SQL users read product and retailer names
- Revenue, cost, profit (actual, type 1) and discount value defined once, in one place
- TRUE/FALSE flags for one-click filtering in Sheets
- Plain JOINs are safe because 1.2 found no orphan codes

**Reconciliation check – PASSED** (view totals match the original tables)

| Check | Value |
|---|---|
| Rows | 149,257 |
| Revenue | 1,251.5 M |
| Profit | 527.7 M |
| Loss rows | 613 |

---

## 4.2 Google Sheets connection – Connected Sheets works

- File: `GoOutside Finance` (Google Sheets), connected live to `v_sales_full` via Data → Data connectors → Connect to BigQuery.
- Scheduled refresh is available on the account (Refresh options → Scheduled refresh) → set to daily.
- The connected tab shows only a 500-row preview; pivot tables, charts and extracts built on it calculate in BigQuery over all 149,257 rows.
- Functions in connected-pivot calculated fields are limited: SUM, COUNT, COUNTUNIQUE, AVERAGE, MIN, MAX work; COUNTA is refused inside formulas (but works as a normal "Summarise by" value).

## 4.3 Sarah's pivot tabs – built so far

**Tab "Sales by channel":** order method × year (revenue, totals, sorted by revenue), colour-scale heatmap, 100% stacked column chart "Share of revenue by order method" (Web 37% → 88%).

**Tab "Channel details":** per order method: revenue, profit, order lines, retailers served, discounts, Margin % = SUM(profit)/SUM(revenue), Discount % = SUM(discount_value)/(SUM(revenue)+SUM(discount_value)), Avg per order line = SUM(revenue)/COUNT(quantity). Totals reconcile with BigQuery: 1,251.5 M revenue, 527.7 M profit, 149,257 order lines, 289 retailers, 42.2% margin, 5.0% discounts.
- Note: Discount % here is value-based (share of full-price revenue given away), not the share of discounted rows used in 3.2.

**Tab "Profit & margin":** product line × year, profit and Margin %, red–white–green colour scale on margins.

**View update – `loss_category` added to `v_sales_full`:** CASE label 'Given away' (sale price = 0) / 'Sold below cost' (sale price < unit cost) / 'Profitable' (all other rows). Order matters: price 0 is also below cost, so 'Given away' is checked first. Defined in the warehouse so Sheets and Looker Studio use the same rule.
- Lesson learned: a quick Sheets calculated column `=IF(is_free, "Given away", "Sold below cost")` labelled all ~148,600 profitable rows as "Sold below cost". Business rules belong in the warehouse, not in each spreadsheet (presentation point).
- Lesson learned: a Sheets calculated column with the same name as a new BigQuery column causes an "alias conflict" loop. Delete or rename the Sheets column first, or give the BigQuery column a different name (that is why it is called `loss_category`).

**Tab "Losses":** pivot filtered to is_loss = TRUE, product × loss_category (Given away / Sold below cost), SUM of profit (= loss) and loss rows, sorted by biggest loss. Reconciles with 1.6: given away −971,406 (524 rows), below cost −85,934 (89 rows), total −1,057,340 (613 rows).

**New findings from the "Profit & margin" tab (revenue per product line and year, M)**

| Product line | 2015 | 2016 | 2017 | 2018 (Jan–Jul) |
|---|---|---|---|---|
| Personal Accessories | 87.4 | 110.2 | 130.2 | 82.5 |
| Camping Equipment | 76.5 | 91.0 | 103.1 | 64.2 |
| Golf Equipment | 69.4 | 79.7 | 102.5 | 80.2 |
| Mountaineering Equipment | – | 35.3 | 63.5 | 58.0 |
| Outdoor Protection | 8.9 | 6.1 | 2.0 | 0.6 |

- **Mountaineering Equipment has no sales in 2015**: first sale 10 Jan 2016. It is a new product line, and it grew fast (2018 Jan–Jul already 58.0 M, close to full-year 2017).
- **Outdoor Protection is shrinking every year** (8.9 → 6.1 → 2.0 → 0.6 M), although it has the highest margin (about 60%). A product line being phased out or losing demand. Question for the business.
- Margins per line are stable over the years; Golf (about 48%) and Outdoor Protection (about 60%) highest, Camping (about 37%) lowest.

**Tab "Profit & margin" charts:** bar chart "Profit by product line" (Grand Total profit) and line chart "Overall margin by year" from a small margin pivot (42.5% / 41.7% / 42.1% / 42.5%). Vertical axis starts at 0 so small variations are not exaggerated (presentation point).

## 4.4 "Start here" KPI page – helper pivot + XLOOKUP

- Helper tab `kpi_data` (hidden): connected pivot, rows order_year with Grand Total; values SUM revenue, SUM profit, COUNTUNIQUE retailer_code, COUNTUNIQUE brand.
- Start page: year dropdown in C4 (All years, 2015–2018); KPI formula in B7, copied to E7: `=XLOOKUP(IF($C$4="All years","Grand Total",VALUE($C$4)), kpi_data!$A:$A, kpi_data!B:B)`.
- Why a helper pivot: normal formulas cannot read the connected tab (500-row preview only); connected pivots write their results into normal cells.

| Year | Total sales | Profit | Active retailers | Brands |
|---|---|---|---|---|
| All years | 1,251.5 M | 527.7 M | 289 | 26 |
| 2015 | 242.3 M | 103.0 M | 265 | 24 |
| 2016 | 322.3 M | 134.3 M | 289 | 26 |
| 2017 | 401.4 M | 169.0 M | 288 | 26 |
| 2018 (Jan–Jul) | 285.5 M | 121.4 M | 288 | 26 |

- Active retailers for "All years" = 289 (each retailer counted once), not the sum of the yearly counts.
- 2015 has 24 brands: the 2 missing brands belong to Mountaineering Equipment, which started in 2016.

## 4.5 Channel break-even calculator – built

- Tab "Channel calculator": per order method, profit of a selectable base year, profit per month, yellow input cell for monthly staff cost, result per month and a Keep / Review decision (conditional formatting green / red).
- Helper pivot `calc_data` (hidden): order_method × order_year, SUM of profit.
- Profit lookup: `=IFERROR(INDEX(calc_data!$A:$F, MATCH($A5, calc_data!$A:$A, 0), MATCH(VALUE($B$3), calc_data!$2:$2, 0)), 0)` (two-way INDEX + MATCH).
- Base year dropdown in B3 (2015–2018, default 2017 = latest full year). Profit per month divides by 12, or by 7 for 2018 (Jan–Jul only).
- Why a base year and not all years: the decision is about today's staff, and channels changed a lot (Telephone profit 35.4 M in 2015 → 5.4 M in 2017 → 2.6 M in Jan–Jul 2018).

**Profit per channel and year (actual profit)**

| Channel | 2015 | 2016 | 2017 | 2018 (Jan–Jul) |
|---|---|---|---|---|
| Web | 36,902,903 | 91,061,296 | 148,738,623 | 106,716,834 |
| Telephone | 35,416,745 | 23,165,732 | 5,399,783 | 2,557,503 |
| E-mail | 22,728,727 | 9,767,591 | 2,682,909 | 2,767,805 |
| Sales visit | 2,958,438 | 5,433,141 | 10,426,973 | 8,949,002 |
| Mail | 4,249,134 | 3,331,718 | 1,412,234 | 20,007 |
| Special | 546,188 | 1,279,645 | 12,376 | – |
| Fax | 225,503 | 290,365 | 340,254 | 344,625 |

- Test case for the demo: 150,000 staff cost per month → Mail (2017) = Review, Telephone (2017) = Keep; switching the base year shows Telephone moving from clearly profitable (2015) towards Review (2018).
- Lessons learned: (1) hidden trailing spaces in typed names made MATCH fail; (2) IFERROR(…, 0) hid the error and made it look like real zeros, so add IFERROR only after a formula works.

## 4.6–4.8 Sarah's sheet – extras

- 4.6 Sparklines: line sparklines of profit 2015–2017 per channel on the calculator (2018 left out because it is a half year). Each sparkline is scaled on its own: it shows direction, not size.
- 4.7 Data dictionary tab: 54 rows in 4 sections (27 view columns, 10 KPIs, 9 known data caveats, guide to all tabs), imported from GoOutside_data_dictionary.csv.
- 4.8 Protection: "Start here" (only C4 editable) and "Channel calculator" (only B3 and D5:D11 editable) protected. Remaining tabs to be protected at the end. Share as Editor, because viewers cannot use dropdowns or input cells. Refreshing connected data needs BigQuery access.

---

## 5.1 Market share per retailer – CHECKED

- Revenue per active retailer and its share of its country's revenue, ranked with RANK() OVER (PARTITION BY country).
- Based on `v_sales_full`, so only active retailers (289) are included automatically.
- Check: shares add up to exactly 100.0% in all 21 countries; retailer counts match 2.2.

## 5.2 Market concentration per country – decision: HHI with threshold 2,500

**Measures:** top-1 share, top-3 share and HHI (sum of squared market shares in %; < 1,500 competitive, 1,500–2,500 moderate, > 2,500 highly concentrated). All years together.

| Country | Active retailers | Revenue (M) | Top 1 | Top 3 | HHI | Market type |
|---|---|---|---|---|---|---|
| Switzerland | 6 | 77.1 | 87.0% | 98.5% | 7,674 | Concentrated |
| Brazil | 11 | 28.9 | 79.3% | 90.7% | 6,380 | Concentrated |
| Singapore | 9 | 35.0 | 70.8% | 95.3% | 5,477 | Concentrated |
| Finland | 10 | 32.3 | 72.0% | 87.1% | 5,352 | Concentrated |
| Spain | 10 | 52.6 | 56.5% | 96.9% | 4,723 | Concentrated |
| Austria | 13 | 29.6 | 61.3% | 92.0% | 4,538 | Concentrated |
| Australia | 5 | 27.6 | 56.5% | 95.2% | 4,329 | Concentrated |
| Denmark | 7 | 5.7 | 56.9% | 92.3% | 4,191 | Concentrated |
| Sweden | 7 | 18.1 | 56.9% | 93.3% | 4,163 | Concentrated |
| Korea | 8 | 96.2 | 58.8% | 89.0% | 4,040 | Concentrated |
| China | 18 | 58.4 | 51.7% | 88.5% | 3,723 | Concentrated |
| Italy | 10 | 22.8 | 54.2% | 78.7% | 3,361 | Concentrated |
| Belgium | 9 | 33.1 | 42.5% | 85.5% | 3,257 | Concentrated |
| Mexico | 8 | 62.3 | 46.7% | 85.8% | 3,120 | Concentrated |
| Canada | 17 | 83.7 | 52.2% | 71.1% | 3,069 | Concentrated |
| Japan | 22 | 63.8 | 43.7% | 74.2% | 2,468 | Competitive (moderate, borderline) |
| Netherlands | 9 | 60.7 | 29.1% | 78.9% | 2,338 | Competitive (moderate) |
| France | 20 | 53.3 | 42.0% | 67.5% | 2,292 | Competitive (moderate) |
| United Kingdom | 21 | 107.7 | 36.7% | 71.6% | 2,148 | Competitive (moderate) |
| Germany | 15 | 105.3 | 27.4% | 73.0% | 1,995 | Competitive (moderate) |
| United States | 54 | 197.2 | 14.5% | 39.4% | 827 | Competitive |

**Meaning**
- 15 of 21 markets are concentrated: in most countries a few retailers carry GoOutside's sales. Only the US is truly competitive (HHI 827).
- The 5 "moderate" markets (UK, Germany, France, Netherlands, Japan; HHI 1,500–2,500) are classified as Competitive because the brief has only two groups. Japan (2,468) is borderline.
- **Small markets look concentrated partly by structure:** with n equal retailers the HHI is 10,000 ÷ n (5 retailers → 2,000 minimum). Concentration in Australia, Switzerland or Denmark partly reflects having few active retailers.
- **Switzerland:** 6 of 26 listed retailers active, the largest holds 87%. Activating listed but inactive retailers could make the market less dependent on one partner.

**Decisions**
- Two groups as in the brief: HHI ≥ 2,500 = Concentrated (big players), otherwise Competitive. HHI, top-1 and top-3 shown next to the label so Dustin sees borderline cases.
- Classification uses all years (stable picture); targets in 5.3 use 2017 as the baseline (latest full year).

**About the HHI and the threshold:** the Herfindahl-Hirschman Index is calculated "by summing the squares of the individual market shares of all the participants" (US DOJ/FTC). It ranges from close to 0 (many tiny firms) to 10,000 (one firm with 100%). It is the standard concentration measure used by competition authorities.

**Thresholds in official guidelines (verified)**

| Source | Unconcentrated | Moderately concentrated | Highly concentrated |
|---|---|---|---|
| US DOJ & FTC, Horizontal Merger Guidelines, 19 Aug 2010 | < 1,500 | 1,500 – 2,500 | > 2,500 ← used in this project |
| US DOJ & FTC, Merger Guidelines, 2023 (Guideline 1, §2.1) | – | – | > 1,800 |
| US DOJ & FTC, Horizontal Merger Guidelines, 1992 | < 1,000 | 1,000 – 1,800 | > 1,800 |
| European Commission, Horizontal Merger Guidelines, 2004 | concerns unlikely below 1,000; 1,000–2,000 with small change; above 2,000 with very small change (a "soft safe harbour", not fixed classes) | | |

**References**
- White & Case client alert summarising the 2010 DOJ/FTC Horizontal Merger Guidelines (issued 19 Aug 2010; < 1,500 / 1,500–2,500 / > 2,500): https://www.whitecase.com/sites/default/files/files/download/publications/alert_ferc_noi_2010_horizontal_merger_guidelines.pdf
- US Department of Justice, 2023 Merger Guidelines, Guideline 1 ("Markets with an HHI greater than 1,800 are highly concentrated"): https://www.justice.gov/atr/merger-guidelines/applying-merger-guidelines/guideline-1
- US Department of Justice, 1992 Horizontal Merger Guidelines, §1.5 (HHI definition; < 1,000 / 1,000–1,800 / > 1,800): https://www.justice.gov/atr/horizontal-merger-guidelines-0
- US Department of Justice, paper on the European Commission's 2004 horizontal merger guidelines (HHI levels 1,000 / 2,000): https://justice.gov/atr/role-market-shares-and-market-concentration-indices-european-commissions-guidelines-assessment

**Choice for this project:** 2,500 (2010 US guidelines), because it gives a clear two-way split matching Dustin's two strategies. With the stricter 2023 threshold (1,800), UK, Germany, France, Netherlands and Japan would also be concentrated and only the US competitive. Merger guidelines judge mergers between competitors; here the HHI is used as a descriptive measure of how GoOutside's sales are spread across its retailers in each country. The threshold can be changed in one place in the query (presentation point).

## 5.3 Targets per country – baseline 2017, saved as view `v_dustin_markets`

- Concentrated (HHI ≥ 2,500): target = 2017 revenue per active retailer × 1.10.
- Competitive (HHI < 2,500): target = CEIL(active retailers 2017 × 1.15) (whole retailers, rounded up).
- Classification uses all years; baseline uses 2017 (latest full year).
- "Sales volume" in the brief is measured as revenue (what Dustin and Finance track); quantity would be an alternative.

| Country | Type | Retailers 2017 | Revenue 2017 (M) | Revenue per retailer (M) | Target |
|---|---|---|---|---|---|
| France | Competitive | 19 | 15.7 | 0.83 | 22 retailers (+3) |
| Germany | Competitive | 15 | 32.5 | 2.17 | 18 retailers (+3) |
| Japan | Competitive | 22 | 19.2 | 0.87 | 26 retailers (+4) |
| Netherlands | Competitive | 9 | 22.1 | 2.46 | 11 retailers (+2) |
| United Kingdom | Competitive | 21 | 33.4 | 1.59 | 25 retailers (+4) |
| United States | Competitive | 54 | 60.5 | 1.12 | 63 retailers (+9) |
| Australia | Concentrated | 5 | 11.5 | 2.30 | 2.53 M per retailer |
| Austria | Concentrated | 13 | 10.8 | 0.83 | 0.91 M per retailer |
| Belgium | Concentrated | 9 | 11.5 | 1.28 | 1.41 M per retailer |
| Brazil | Concentrated | 11 | 9.6 | 0.87 | 0.96 M per retailer |
| Canada | Concentrated | 17 | 24.5 | 1.44 | 1.58 M per retailer |
| China | Concentrated | 18 | 17.6 | 0.98 | 1.08 M per retailer |
| Denmark | Concentrated | 7 | 1.9 | 0.27 | 0.29 M per retailer |
| Finland | Concentrated | 10 | 11.5 | 1.15 | 1.27 M per retailer |
| Italy | Concentrated | 10 | 7.4 | 0.74 | 0.82 M per retailer |
| Korea | Concentrated | 8 | 26.3 | 3.28 | 3.61 M per retailer |
| Mexico | Concentrated | 8 | 23.7 | 2.96 | 3.26 M per retailer |
| Singapore | Concentrated | 9 | 11.8 | 1.31 | 1.44 M per retailer |
| Spain | Concentrated | 10 | 17.7 | 1.77 | 1.94 M per retailer |
| Sweden | Concentrated | 7 | 7.1 | 1.02 | 1.12 M per retailer |
| Switzerland | Concentrated | 6 | 25.1 | 4.18 | 4.60 M per retailer |

**In total:** 25 new active retailers in the 6 competitive markets; about +21.8 M revenue in the 15 concentrated markets (10% of about 218 M in 2017).

**Observations for Dustin:** France had 20 active retailers over all years but 19 in 2017 (part of the target is winning a partner back). Denmark is very small (0.27 M per retailer), so its +10% target is only about 20 k per retailer.

## 5.4 Dustin's sheet "GoOutside – Retail Partnerships" – built

- Connected to `v_dustin_markets` and `v_sales_full` (daily scheduled refresh).
- `markets_data` (hidden): Extract of v_dustin_markets (normal cells, refreshable) plus a Target sentence column: `=IF(C2="Competitive", "Grow from "&D2&" to "&H2&" retailers (+"&I2&")", "Grow revenue per retailer from "&TEXT(F2,"0.00")&" M to "&TEXT(G2,"0.00")&" M")`.
- "Markets": presentation tab built with QUERY + label (readable headers, column order changed), because Extract and pivot headers cannot be renamed.
- "Retailers by country": active retailers per country × store type (COUNTUNIQUE retailer_code), total 289.
- "Revenue by country": revenue per country × year, plus stacked bar chart "Revenue by country".
- Lessons learned: Extract/pivot headers, group labels and "Grand Total" come from the data and cannot be typed over (only value headers like "SUM of revenue" can be renamed); column order of an Extract may differ from the query, so check formula references.

## 5.5 Retailer lookup – built and checked

- BigQuery view `v_retailer_share` (289 rows, one per active retailer): retailer_name, country, retailer_type, revenue_m, profit_m, order_lines, market_share_pct, rank_in_country, retailers_in_country (COUNT(*) OVER (PARTITION BY country)).
- Extract to hidden tab `retailer_data`, sorted by name. All 289 active retailer names are unique, so a name lookup is safe.
- Tab "Retailer lookup": searchable dropdown in C4 (Dropdown from a range `retailer_data!A2:A`), XLOOKUP formulas for country, store type, revenue, profit, order lines, market share and "rank X of Y".
- Check: Armazém do esporte → Brazil, Sports Store, 0.82 M revenue, 0.33 M profit, 120 order lines, 2.8% market share, rank 3 of 11 (matches an independent calculation).

## 5.6 ★ Pareto analysis – 18% of retailers bring 80% of revenue

- Running total with `SUM(revenue) OVER (ORDER BY revenue DESC)` ÷ grand total (`SUM(revenue) OVER ()`).

| Group (ranked by revenue) | Share of retailers | Cumulative share of revenue |
|---|---|---|
| Top 1 – Grand choix (Switzerland), 67.1 M | 0.3% | 5.4% |
| Top 10 | 3.5% | 30.5% |
| Top 29 | 10.0% | 61.9% |
| **Top 51 – up to Arnold's Clubs (Switzerland)** | **17.6%** | **80.0%** |
| Top 58 | 20.1% | 83.8% |
| Bottom half (ranks 145–289) | 50% | 2.9% |

**Meaning**
- Classic 80/20 pattern: 51 key accounts carry the business; the largest single retailer alone brings 5.4% of revenue.
- Long tail: half of the active retailers add less than 3% of revenue. For the "+15% retailers" target in competitive markets, new retailers only matter if they grow beyond this tail.
- Confirms the concentration picture of 5.2 at company level.

**Built:** view `v_pareto` (289 rows) → Extract to tab "Pareto" in Dustin's sheet (sorted by rank) + helper column "80% line" = 80 → combo chart "18% of retailers generate 80% of revenue" (columns = revenue per retailer on the left axis; lines = cumulative share and 80% line on the right axis, 0–100). The cumulative line crosses 80% at rank 51.
- Chart title states the finding (message title), not just "Pareto chart".
- **Where the 80% comes from:** not from the brief; our choice, based on the Pareto principle (80/20 rule), a common rule of thumb in business analysis. Vilfredo Pareto observed in 1906 that about 80% of Italy's land belonged to about 20% of the population; Joseph M. Juran applied the idea to quality management ("the vital few and the trivial many"). It is a rule of thumb, not a law: real splits can be 70/30 or 90/10. We used 80% only as a reading point; the data itself showed 18% → 80%.
- Reference: https://en.wikipedia.org/wiki/Pareto_principle

## 6.1 Data Studio dashboard (Looker Studio was renamed back to Data Studio) – built (3 pages)

- Report "GoOutside – Business dashboard", data source `v_sales_full` (field types detected correctly: country = geo, dates = date).
- Calculated fields: Margin = SUM(profit) / SUM(revenue) (Percent); Active retailers = COUNT_DISTINCT(retailer_code); Countries = COUNT_DISTINCT(country).
- Page 1 done so far: title "GoOutside – Business overview"; 5 KPI scorecards (Revenue 1.25bn, Profit 527.73m, Margin 42.2%, Active retailers 289, Countries 21), styled the same, aligned and distributed. Cosmetics are done immediately for each dashboard element (not postponed).
- Page 1 built: filter row (Year, Country, Order method, Product line dropdowns); line chart "Revenue by month (2018 = Jan–Jul)" (dimension order_date as Month, breakdown order_year, sorted by Month ascending, missing data = line breaks); Google Maps filled map "Revenue by country"; combo chart "Revenue and margin by product line" (revenue bars, margin line on right axis from 0, sorted by revenue: Personal Accessories 410.3 M, Camping 334.8 M, Golf 331.8 M, Mountaineering 156.9 M, Outdoor Protection 17.7 M).
- Lessons learned: sort the month axis by the Month field (not by revenue); "Dimension value colours" only works for text fields (order_year is a date); manual style settings override the theme → customise the theme (palette, component border/radius) and use Style → Reset to apply it.
- Colour convention: Revenue = magenta, Margin = teal.
- Page 1 "Overview" finished: plus top 10 brands table (revenue bars, margin heatmap) and footer note "Data: BigQuery view v_sales_full · refreshed daily · 2018 = Jan–Jul". To fix: brands table shows 26 rows → Rows per page 10, pagination off.
- Page 2 "Order channels" (Sarah) finished: duplicated from page 1; calculated fields Discount % = SUM(discount_value)/(SUM(revenue)+SUM(discount_value)), Loss on sales = SUM(IF(is_loss, profit, 0)), Loss rate = SUM(IF(is_loss, 1, 0))/COUNT(order_date); scorecards Revenue, Profit, Margin, Discount % (5.0%), Loss on sales (−1.06m); 100% stacked column "Share of revenue by order method" (year × method); bar chart "Share of sales below cost, by order method" (Mail 1.18% … Web 0.34%); channel details table (revenue bars, share = percent of total, order lines, retailers served, margin and discount % as heatmaps) matching task 3.2.
- Page 3 "Markets" (Dustin) – plan: second data source v_dustin_markets; scorecards Concentrated markets (15), Competitive markets (6), New retailers needed (25), Revenue uplift target (about 21.8 M); bar chart HHI by country with reference line at 2,500; bar chart active retailers by store type (v_sales_full); market table with conditional formatting by market type; Country filter only.
- Decision: no Year filter on page 3. Dustin's targets need one fixed baseline (2017, latest full year), and v_dustin_markets has one row per country without a year column. Presentation sentence: "Targets use 2017, the latest full year, as the baseline; 2018 is incomplete."
- ★ later (optional): HHI per country and year (view with order_year) to show whether markets become more or less concentrated over time; targets stay on the 2017 baseline.
