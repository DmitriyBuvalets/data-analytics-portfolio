

WITH
-- 1. KEITARO BASE (Smart GEO Logic) Визначаємо країну для всіх записів один раз
keitaro_with_geo AS (
  SELECT *,
    CASE
      WHEN ts = 'Broker MX' OR campaign_group = 'Finance MX' OR LOWER(country) = 'mx' THEN 'mx'
      WHEN ts = 'Broker CO' OR campaign_group = 'Finance CO' OR LOWER(country) = 'co' THEN 'co'
      WHEN ts = 'Broker ES' OR campaign_group = 'Finance ES' OR LOWER(country) = 'es' THEN 'es'
      WHEN ts = 'Broker RO' OR campaign_group = 'Finance RO' OR LOWER(country) = 'ro' THEN 'ro'
      WHEN ts = 'Broker PH' OR campaign_group = 'Finance PH' OR LOWER(country) = 'ph' THEN 'ph'
      WHEN ts = 'Broker VN' OR campaign_group = 'Finance VN' OR LOWER(country) = 'vn' THEN 'vn'
      ELSE LOWER(country)
    END AS final_country
  FROM `decent-tape-413511.task.mock_export_keitaro`
),
/**********************************************************************/
-- 2. CRM (Leads)
leads AS (
  SELECT
    CAST(affid AS STRING) AS partner_id,
    LOWER(country) AS country,
    COUNTIF(action = 'registration') AS registrations,
    COUNTIF(action IN ('registration','login')) AS all_leads
  FROM `decent-tape-413511.task.lead_params`
  WHERE LOWER(country) IN ('mx','co','es','ro','ph','vn')
  GROUP BY 1,2
),
/**********************************************************************/
-- 3. KEITARO (Sales, Revenue)
keitaro AS (
  SELECT
    CAST(sub_id_5 AS STRING) AS partner_id,
    final_country AS country,
    COUNT(*) AS sales,
    SUM(revenue) AS revenue
  FROM keitaro_with_geo
  WHERE 
      sub_id_4 = 'CPA'
      AND status = 'sale'
  GROUP BY 1,2
),
/**********************************************************************/
-- 4. AFFISE (Cost)
affise_cost AS (
  SELECT
    CONCAT(CAST(partner_id AS STRING), '_', CAST(affiliates_params5 AS STRING)) AS partner_id,
    country,
    SUM(revenue) AS cost_cpa
  FROM `decent-tape-413511.task.mock_export_affise`
  WHERE 
      status = 1
  GROUP BY 1,2
),
/**********************************************************************/
-- 5. АТРИБУЦІЯ (Last UTM Source) останнє джерело перед продажем або подією
attribution_lookup AS (
  SELECT
    lead_id,
    crm_id,
    affid,
    utm_source,
    ROW_NUMBER() OVER (PARTITION BY lead_id ORDER BY PARSE_TIMESTAMP('%d-%m-%Y %H:%M:%S', TRIM(created_at)) DESC) as rn
  FROM `decent-tape-413511.task.lead_params`
  WHERE 
      utm_source IN ('CPA','google','facebook','tiktok','bigo','bing','zalo')
),
/**********************************************************************/
-- 6. Retention Revenue
retention_revenue AS (
  SELECT 
    CAST(attr.affid AS STRING) AS partner_id,
    k.final_country AS country,
    SUM(k.revenue) AS retention_revenue
  FROM keitaro_with_geo k

  JOIN attribution_lookup attr
    ON k.sub_id_7 = attr.crm_id

  WHERE 
    k.sub_id_4 IN ('sms','email','push','trafficback','push-pwa')
    AND k.status = 'sale'
    AND attr.rn = 1
    AND attr.utm_source = 'CPA'
  GROUP BY 1, 2
),
/**********************************************************************/
-- 7. Retention costs (Email + SMS)
retention_cost AS (
  SELECT
    CAST(l.affid AS STRING) AS partner_id,
    l.country AS country,

    -- Email Cost
    SUM(IF(s.action = 'email', 1, 0) * COALESCE(er.cost_usd, 0)) AS cost_email,

    -- SMS Cost (UAH to USD, статична заглушка 0.025, що відповідає курсу 40 грн/usd 'Assumption')
    SUM(IF(s.action = 'sms', 1, 0) * (COALESCE(sr.cost_uah, 0) * 0.025)) AS cost_sms 

  FROM `decent-tape-413511.task.scenario_log` s

  JOIN `decent-tape-413511.task.lead_params` l 
    ON s.subid = l.crm_id

  LEFT JOIN `decent-tape-413511.task.email_rates` er 
    ON DATE(PARSE_DATE('%d-%m-%Y', TRIM(s.date))) >= er.dt_from 
    AND DATE(PARSE_DATE('%d-%m-%Y', TRIM(s.date))) < er.dt_to

  LEFT JOIN `decent-tape-413511.task.sms_rates` sr 
    ON l.country = sr.country 
    AND DATE(PARSE_DATE('%d-%m-%Y', TRIM(s.date))) >= sr.dt_from 
    AND DATE(PARSE_DATE('%d-%m-%Y', TRIM(s.date))) < sr.dt_to

  WHERE s.action IN ('email', 'sms')
  GROUP BY 1, 2
),
/***************************************************************/
-- 8. Adsense
adsense AS (
  SELECT
    CAST(aff_id AS STRING) AS partner_id,
    LOWER(country) AS country,
    SUM(total_revenue) AS adsense_revenue
  FROM `decent-tape-413511.task.mock_export_ga4_adsense`
  WHERE 
      event_name = 'ad_impression'
  GROUP BY 1,2
)
/***************************************************************/
-- 9. Final Calculations
SELECT
  l.partner_id AS Partner_ID,

  -- Leads Data
  l.registrations AS Registrations,
  l.all_leads AS Leads,
  SAFE_DIVIDE(l.registrations, l.all_leads) * 100 AS Unique_Percent,

  --  EPL (Earnings Per Lead)
  SAFE_DIVIDE(IFNULL(k.revenue, 0), l.all_leads) AS EPL_Primary,
  SAFE_DIVIDE(
    (IFNULL(k.revenue, 0) + IFNULL(r.retention_revenue, 0) + IFNULL(ad.adsense_revenue, 0)),
    l.all_leads
  ) AS EPL_Total,

  --  NEW USER CPA
  IFNULL(k.sales, 0) AS Sales,
  SAFE_DIVIDE(k.sales, l.all_leads) * 100 AS CR_Percent,
  IFNULL(k.revenue, 0) AS Revenue,
  IFNULL(a.cost_cpa, 0) AS Cost_CPA,
  (IFNULL(k.revenue, 0) - IFNULL(a.cost_cpa, 0)) AS Profit,

  SAFE_DIVIDE((IFNULL(k.revenue, 0) - IFNULL(a.cost_cpa, 0)), NULLIF(a.cost_cpa, 0)) * 100 AS ROMI_New_User,

  -- Retention
  IFNULL(r.retention_revenue, 0) AS Retention_Revenue,
  (IFNULL(rc.cost_email, 0) + IFNULL(rc.cost_sms, 0)) AS Retention_Cost,
  (IFNULL(r.retention_revenue, 0) - (IFNULL(rc.cost_email, 0) + IFNULL(rc.cost_sms, 0))) AS Retention_Profit,

  SAFE_DIVIDE((IFNULL(r.retention_revenue, 0) - (IFNULL(rc.cost_email, 0) + IFNULL(rc.cost_sms, 0))), NULLIF((IFNULL(rc.cost_email, 0) + IFNULL(rc.cost_sms, 0)), 0)) * 100 AS ROMI_Retention,

  -- Retention Cost Breakdown
  IFNULL(rc.cost_email, 0) AS Cost_Email,
  IFNULL(rc.cost_sms, 0) AS Cost_SMS,

  -- Adsense
  IFNULL(ad.adsense_revenue, 0) AS Adsense_Revenue,

  -- Totals
  (IFNULL(k.revenue, 0) + IFNULL(r.retention_revenue, 0) + IFNULL(ad.adsense_revenue, 0)) AS Revenue_TOT,
  
  (IFNULL(a.cost_cpa, 0) + IFNULL(rc.cost_email, 0) + IFNULL(rc.cost_sms, 0)) AS Cost_TOT,
  
  ((IFNULL(k.revenue, 0) + IFNULL(r.retention_revenue, 0) + IFNULL(ad.adsense_revenue, 0))- (IFNULL(a.cost_cpa, 0) + IFNULL(rc.cost_email, 0) + IFNULL(rc.cost_sms, 0))) AS Profit_TOT,

  -- Margins
  -- GPM% = (Profit TOT / Revenue TOT) * 100
  SAFE_DIVIDE(
    ((IFNULL(k.revenue, 0) + IFNULL(r.retention_revenue, 0) + IFNULL(ad.adsense_revenue, 0))
      - (IFNULL(a.cost_cpa, 0) + IFNULL(rc.cost_email, 0) + IFNULL(rc.cost_sms, 0))),
    NULLIF((IFNULL(k.revenue, 0) + IFNULL(r.retention_revenue, 0) + IFNULL(ad.adsense_revenue, 0)), 0)) * 100 AS GPM_Percent,

  -- ROMI% TOT = (Profit TOT / Cost TOT) * 100
  SAFE_DIVIDE(
    ((IFNULL(k.revenue, 0) + IFNULL(r.retention_revenue, 0) + IFNULL(ad.adsense_revenue, 0))
      - (IFNULL(a.cost_cpa, 0) + IFNULL(rc.cost_email, 0) + IFNULL(rc.cost_sms, 0))),
      NULLIF((IFNULL(a.cost_cpa, 0) + IFNULL(rc.cost_email, 0) + IFNULL(rc.cost_sms, 0)), 0)) * 100 AS ROMI_TOT,

  l.country -- країна

FROM leads l

LEFT JOIN keitaro k
  ON CAST(l.partner_id AS STRING) = CAST(k.partner_id AS STRING)
 AND CAST(l.country AS STRING)  = CAST(k.country AS STRING)

LEFT JOIN affise_cost a
  ON CAST(l.partner_id AS STRING) = CAST(a.partner_id AS STRING)
 AND CAST(l.country AS STRING)  = CAST(a.country AS STRING)

LEFT JOIN retention_revenue r
  ON CAST(l.partner_id AS STRING) = CAST(r.partner_id AS STRING)
 AND CAST(l.country AS STRING) = CAST(r.country AS STRING)

LEFT JOIN retention_cost rc
  ON CAST(l.partner_id AS STRING) = CAST(rc.partner_id AS STRING)
 AND CAST(l.country AS STRING) = CAST(rc.country AS STRING)

LEFT JOIN adsense ad
  ON CAST(l.partner_id AS STRING) = CAST(ad.partner_id AS STRING)
 AND CAST(l.country AS STRING) = CAST(ad.country AS STRING)

ORDER BY 1 DESC
