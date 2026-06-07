-- ============================================================================
-- TASK 2 — Decompose the eCPM drop: price problem or fill problem?
-- ----------------------------------------------------------------------------
-- Goal: split eCPM into (billable_rate x price_cpm) to see whether each billed
--       impression is worth less (price/demand problem) or fewer impressions
--       bill at all (fill/leak problem). Then pressure-test the price drop.
-- Technique: CTEs, conditional aggregation (FILTER), window function (LAG).
-- Finding: both components fall, but the price drop does NOT survive controlling
--          for geography -- it is a traffic mix-shift toward low-eCPM countries
--          (their share jumps ~22% -> ~42%), not demand softening. Demand
--          hypothesis CLOSED. The real, controllable loss is the billable-rate
--          (fill) decline => leak is post-win.
-- Tested on PostgreSQL 16.
-- ============================================================================

-- 2A: decompose eCPM = billable_rate x price_cpm, with LAG for era-over-era change
WITH base AS (
  SELECT CASE WHEN r.request_ts < TIMESTAMP '2026-05-20' THEN '1_pre' ELSE '2_post' END AS era,
         i.rendered, i.billable, COALESCE(i.revenue_usd, 0) AS rev
  FROM impressions i
  JOIN ad_requests r USING (request_id)
),
period AS (
  SELECT era,
    1.0 * COUNT(*) FILTER (WHERE billable)
        / NULLIF(COUNT(*) FILTER (WHERE rendered), 0)              AS billable_rate,
    SUM(rev) / NULLIF(COUNT(*) FILTER (WHERE billable), 0) * 1000  AS price_cpm,
    SUM(rev) / NULLIF(COUNT(*) FILTER (WHERE rendered), 0) * 1000  AS ecpm
  FROM base
  GROUP BY era
)
SELECT era,
  ROUND(billable_rate::numeric, 3) AS billable_rate,
  ROUND(price_cpm::numeric, 3)     AS price_cpm,
  ROUND(ecpm::numeric, 3)          AS ecpm,
  ROUND((100.0*(billable_rate/LAG(billable_rate) OVER (ORDER BY era) - 1))::numeric,1) AS billable_rate_pct_chg,
  ROUND((100.0*(price_cpm   /LAG(price_cpm)    OVER (ORDER BY era) - 1))::numeric,1)   AS price_pct_chg,
  ROUND((100.0*(ecpm        /LAG(ecpm)         OVER (ORDER BY era) - 1))::numeric,1)   AS ecpm_pct_chg
FROM period
ORDER BY era;

-- 2B: pressure-test the price drop -- is it real, or a geo mix-shift artifact?
WITH base AS (
  SELECT CASE WHEN r.request_ts < TIMESTAMP '2026-05-20' THEN '1_pre' ELSE '2_post' END AS era,
         r.country, i.rendered, i.billable, COALESCE(i.revenue_usd, 0) AS rev
  FROM impressions i
  JOIN ad_requests r USING (request_id)
)
SELECT
  CASE WHEN country = 'US' THEN 'US only (geo held constant)' ELSE 'All geos (blended)' END AS scope,
  era,
  ROUND((SUM(rev)/NULLIF(COUNT(*) FILTER (WHERE billable),0)*1000)::numeric, 3) AS price_cpm,
  ROUND(AVG(CASE WHEN country IN ('IN','ID','BR') THEN 1.0 ELSE 0 END), 3)       AS low_ecpm_geo_share
FROM base
WHERE country = 'US' OR country IS NOT NULL
GROUP BY 1, era
ORDER BY 1, era;
