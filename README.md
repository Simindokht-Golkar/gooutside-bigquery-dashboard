# GoOutside – From four CSV files to a data platform

**BigQuery · SQL · Google Sheets (Connected Sheets) · Data Studio (Looker Studio)**

A data warehouse, two self-service spreadsheets and an interactive dashboard for an outdoor-equipment company whose data analyst had left, leaving the sales data locked in four CSV files.

*Project from the WBS CODING SCHOOL Data Analytics bootcamp (November 2026).*

---

## The problem

GoOutside sells camping and outdoor gear through 562 registered retailers in 21 countries. After the data analyst left, nobody could answer questions from the raw data:

| Table | Rows | Content |
|---|---|---|
| `daily_sales` | 149,257 | One row per retailer × product × order method × day |
| `retailers` | 562 | Name, store type, country |
| `products` | 274 | Product line, type, brand, unit cost, unit price |
| `methods` | 12 | Order method (Web, Telephone, E-mail, …) |

## The questions

| Stakeholder | Question |
|---|---|
| **Sarah, Finance Manager** | Which order methods justify the personnel costs they require? Which could be phased out? |
| **Dustin, Head of Retail Partnerships** | Is each market controlled by a few big players or by many similar-sized retailers? Big players → target +10% sales per retailer; competitive → +15% more retailers. |

## KPIs

| Total sales | Profit | Countries | Customers & suppliers |
|---|---|---|---|
| **1.25 bn** (Jan 2015 – Jul 2018) | **527.7 M** (42.2% margin) | **21** | **289** active retailers · **26** brands |

## Architecture

```
4 CSV files ──► BigQuery data warehouse ──► Google Sheets (Sarah · Dustin)
                • data quality checks          Data Studio dashboard (everyone)
                • one central view                   ▲ refreshed daily
                  (v_sales_full)
```

Every tool reads from the same BigQuery views, so every number matches everywhere.

## What I built

**1. BigQuery data warehouse** ([`sql/`](sql))
- Data quality checks: unique keys, orphan records, unused records, duplicates, price consistency, sales below cost ([`01_data_quality.sql`](sql/01_data_quality.sql))
- Exploration and analysis with CTEs, window functions (`OVER`, `LAG`, `RANK`, `ROW_NUMBER`, `QUALIFY`) and `PIVOT` ([`02_exploration.sql`](sql/02_exploration.sql), [`03_analysis.sql`](sql/03_analysis.sql))
- Central flat view `v_sales_full` with revenue, cost, profit, discount and loss flags, reconciled against the source tables ([`04_view_sales_full.sql`](sql/04_view_sales_full.sql))
- Market concentration (Herfindahl-Hirschman Index), targets, retailer lookup and Pareto views ([`05_market_concentration.sql`](sql/05_market_concentration.sql))

**2. Google Sheets for Finance (Sarah)** – Connected Sheets on BigQuery, daily scheduled refresh
- Start page with KPIs and a year dropdown (`XLOOKUP`)
- Sales by channel, channel details, profit & margin, losses (connected pivot tables, heatmaps, charts)
- **Channel break-even calculator**: the data has no personnel costs, so Sarah enters the staff cost per channel and gets *Keep / Review* (`INDEX`/`MATCH`, base-year dropdown, sparklines)
- Data dictionary ([`docs/data_dictionary.csv`](docs/data_dictionary.csv)) and protected ranges

**3. Google Sheets for Retail Partnerships (Dustin)**
- Market table with market type (HHI) and a concrete target per country (`QUERY` with readable labels)
- Active retailers by country and store type, revenue by country
- Retailer lookup (searchable dropdown + `XLOOKUP`)
- Pareto analysis with a combo chart

**4. Data Studio dashboard – 3 pages**
- **Overview** (everyone): KPI scorecards, revenue by month per year, map by country, revenue and margin by product line, top 10 brands
- **Order channels** (Sarah): channel share per year, loss rate per channel, channel details table
- **Markets** (Dustin): concentrated vs competitive markets, HHI by country with the 2,500 threshold, store types, market table with targets
- Shared filters (year, country, order method, product line) across all charts

## Key findings

- **Steady growth:** revenue grew 26–30% per year (same period Jan–Jul compared), with a stable margin of about 42%.
- **Channel shift:** Web grew from 37% to 88% of revenue (2015 → 2018); Telephone and E-mail almost disappeared. Margins are similar across channels (41–43%), but the manual channels (Mail, Sales visit, Telephone) sell below cost 2–3 times as often as Web.
- **Markets:** 15 of 21 markets are concentrated (HHI ≥ 2,500), e.g. Switzerland, where one retailer holds 87%. 6 are competitive (US, UK, Germany, France, Netherlands, Japan). Targets: 25 new retailers in competitive markets, about +21.8 M revenue in concentrated ones.
- **Key accounts:** 18% of retailers (51 of 289) generate 80% of revenue.
- **Product mix:** Golf has the same revenue as Camping with only 15 products and a 10-point higher margin; Asia prefers golf, the Nordic countries mountaineering.

## Data decisions

Every check and decision is documented in [`docs/decision-log.md`](docs/decision-log.md), for example:
- **Active retailers only:** 273 of 562 listed retailers never ordered (including all 30 Equipment Rental Stores).
- **Duplicates kept:** 802 exact duplicates (0.09% of revenue) are kept as genuine repeat orders – there is no order ID and same-day repeat orders are common.
- **Actual profit:** revenue uses the price the customer paid (`Unit sale price`), so discounts and free products are included.
- **Fair year comparison:** 2018 ends on 20 July, so years are compared on the same period.
- **HHI threshold 2,500:** from the US DOJ & FTC Horizontal Merger Guidelines (2010); the stricter 2023 threshold (1,800) is noted as an alternative.

## Live tools

- 📊 Data Studio dashboard: *[add link]*
- 📗 Finance sheet: *[add link]*
- 📘 Retail Partnerships sheet: *[add link]*

## Repository structure

```
├── README.md
├── sql/
│   ├── 01_data_quality.sql
│   ├── 02_exploration.sql
│   ├── 03_analysis.sql
│   ├── 04_view_sales_full.sql
│   └── 05_market_concentration.sql
├── docs/
│   ├── decision-log.md
│   └── data_dictionary.csv
├── presentation/
│   └── GoOutside_opening_presentation.pptx
└── images/            (dashboard and sheet screenshots)
```

## Skills demonstrated

Data warehousing in BigQuery · data quality assessment · SQL (CTEs, joins, window functions, PIVOT, views) · KPI definition · market concentration analysis (HHI) · Pareto analysis · Google Sheets (Connected Sheets, pivot tables, XLOOKUP, INDEX/MATCH, QUERY, data validation, protection) · dashboard design in Data Studio · stakeholder-oriented reporting

---

**Author:** Dr. Simindokht Gol Kar · [LinkedIn](https://www.linkedin.com/in/simindokhtgolkar)
