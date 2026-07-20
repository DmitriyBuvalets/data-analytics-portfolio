# Marketing & Financial Performance Analytics Pipeline (SQL)

## 📌 Project Overview
This repository contains a comprehensive SQL pipeline designed for Google BigQuery. The script aggregates and transforms fragmented cross-channel marketing data (CRM leads, CPA networks, email/SMS retention campaigns, and AdSense) into a single, unified view. 

The primary business objective of this script is to calculate end-to-end profitability, partner performance, and marketing efficiency metrics across multiple geographic regions.

## 🛠️ Technical Stack & SQL Features
* **Dialect:** Google BigQuery Standard SQL
* **Architecture:** Modular design using 9 Common Table Expressions (CTEs) for readability and easy debugging.
* **Key SQL Concepts Demonstrated:**
  * **Window Functions:** Implemented a last-click attribution model using `ROW_NUMBER() OVER(PARTITION BY...)`.
  * **Data Cleansing & Transformation:** Type casting, string manipulation, and strict date/timestamp parsing (`PARSE_TIMESTAMP`, `PARSE_DATE`).
  * **Robust Error Handling:** Extensive use of `SAFE_DIVIDE`, `IFNULL`, and `COALESCE` to prevent division by zero and handle missing data seamlessly.
  * **Conditional Aggregation:** Utilizing `COUNTIF()` and `IF()` for pivot-like summaries (e.g., separating SMS and Email costs).

## 📊 Business Metrics Calculated
The final query outputs a comprehensive dataset ready for BI tools. Key metrics include:
* **Acquisition:** Registrations, Unique Leads, Conversion Rate (CR%).
* **Efficiency:** Earnings Per Lead (EPL), Cost Per Action (CPA).
* **Retention:** Retention Revenue, Retention Cost (split by Email/SMS), and ROMI Retention.
* **Profitability:** Gross Profit Margin (GPM%), Total Return on Marketing Investment (ROMI), and overall Profit & Revenue combining AdSense, Retention, and Primary Sales.

## 🗄️ Data Sources (Mocked)
1. **Keitaro:** Smart GEO logic, Sales, and Revenue tracking.
2. **CRM:** Lead registrations and user activity.
3. **Affise:** CPA partner costs.
4. **Scenario Logs:** Webhooks/logs for Email & SMS retention actions.
5. **GA4 / AdSense:** Ad impressions and total revenue.
