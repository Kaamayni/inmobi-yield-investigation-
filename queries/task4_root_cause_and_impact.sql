-- ============================================================================
-- TASK 4 — Confirm the mechanisms and size the impact
-- ----------------------------------------------------------------------------
-- Goal: prove WHY each cohort fails, corroborate with independent telemetry,
--       then quantify the loss with a counterfactual (recover to the healthy
--       v8.1.0 baseline).
-- Technique: percentile window function, multi-table joins (incl. buyers),
--            conditional aggregation, error-code corroboration, counterfactual.
-- Findings:
--   4A  iOS17 rewarded_video: render p50 443ms -> 2544ms vs ~1830ms TTL;
--       96.9% of won bids EXPIRE before billing (latency/TTL regression).
--   4B  iOS interstitial: only VIEWABLE-billed buyers break (0.706 -> 0.016);
--       render/complete buyers unaffected. The viewability signal collapses to
--       ~1.6% => OM SDK (OMID) measurement break.
--   4C  Error trail corroborates: RENDER_TIMEOUT for cohort A, OMID_NOT_REGISTERED
--       for cohort B -- two different mechanisms, two different error codes.
--   4D  Counterfactual: affected cohorts lost ~96-98% of their billable revenue.
--       (Absolute $ is small because this is a ~2.2k-row sample; present the
--        RELATIVE loss and a per-impression unit, then scale by production volume.)
-- Tested on PostgreSQL 16.
-- ============================================================================

-- 4A: latency distribution vs bid TTL, iOS-17 rewarded_video, by SDK version
WITH c AS (
  SELECT r.sdk_version, i.render_latency_ms, b.bid_ttl_ms,
         (i.render_latency_ms > b.bid_ttl_ms) AS expired
  FROM impressions i
  JOIN ad_requests r USING (request_id)
  JOIN bids b ON i.winning_bid_id = b.bid_id
  WHERE i.rendered AND r.request_ts >= TIMESTAMP '2026-05-20'
    AND r.os='iOS' AND split_part(r.os_version,'.',1)='17' AND r.ad_format='rewarded_video'
)
SELECT sdk_version, COUNT(*) AS n,
  ROUND(percentile_cont(0.50) WITHIN GROUP (ORDER BY render_latency_ms)::numeric,0) AS p50,
  ROUND(percentile_cont(0.95) WITHIN GROUP (ORDER BY render_latency_ms)::numeric,0) AS p95,
  ROUND(AVG(bid_ttl_ms)::numeric,0) AS avg_ttl,
  ROUND(AVG(CASE WHEN expired THEN 1.0 ELSE 0 END)::numeric,3) AS expired_share
FROM c GROUP BY sdk_version ORDER BY sdk_version;

-- 4B: interstitial iOS billable rate split by buyer billing_type, by SDK version
WITH c AS (
  SELECT y.billing_type, r.sdk_version, i.billable, (i.viewable IS TRUE) AS was_viewable
  FROM impressions i
  JOIN ad_requests r USING (request_id)
  JOIN bids b ON i.winning_bid_id = b.bid_id
  JOIN buyers y ON b.buyer_id = y.buyer_id
  WHERE i.rendered AND r.request_ts >= TIMESTAMP '2026-05-20'
    AND r.os='iOS' AND r.ad_format='interstitial'
)
SELECT billing_type,
  ROUND((1.0*SUM(CASE WHEN sdk_version='8.1.0' AND billable THEN 1 ELSE 0 END)
      /NULLIF(SUM(CASE WHEN sdk_version='8.1.0' THEN 1 ELSE 0 END),0))::numeric,3) AS br_v81,
  ROUND((1.0*SUM(CASE WHEN sdk_version='8.2.0' AND billable THEN 1 ELSE 0 END)
      /NULLIF(SUM(CASE WHEN sdk_version='8.2.0' THEN 1 ELSE 0 END),0))::numeric,3) AS br_v82,
  ROUND((1.0*SUM(CASE WHEN sdk_version='8.2.0' AND was_viewable THEN 1 ELSE 0 END)
      /NULLIF(SUM(CASE WHEN sdk_version='8.2.0' THEN 1 ELSE 0 END),0))::numeric,3) AS viewable_rate_v82
FROM c GROUP BY billing_type ORDER BY billing_type;

-- 4C: error-code trail by cohort (independent corroboration)
SELECT
  CASE WHEN r.ad_format='rewarded_video' AND split_part(r.os_version,'.',1)='17' THEN 'iOS17_rewarded_video'
       WHEN r.ad_format='interstitial' THEN 'iOS_interstitial' ELSE 'other_iOS' END AS cohort,
  e.error_code, COUNT(*) AS n
FROM sdk_events e
JOIN ad_requests r USING (request_id)
WHERE r.os='iOS' AND r.sdk_version='8.2.0' AND r.request_ts >= TIMESTAMP '2026-05-20'
  AND e.error_code IS NOT NULL
GROUP BY 1,2 ORDER BY 1, n DESC;

-- 4D: dollar impact -- counterfactual recovery to the v8.1.0 baseline
WITH labeled AS (
  SELECT
    CASE
      WHEN r.os='iOS' AND split_part(r.os_version,'.',1)='17' AND r.ad_format='rewarded_video'
        THEN 'A: iOS17 rewarded_video (latency/TTL)'
      WHEN r.os='iOS' AND r.ad_format='interstitial' AND y.billing_type='viewable'
        THEN 'B: iOS interstitial, viewable buyers (OMID)'
    END AS cohort,
    r.sdk_version, i.billable, COALESCE(i.revenue_usd,0) AS rev
  FROM impressions i
  JOIN ad_requests r USING (request_id)
  JOIN bids b ON i.winning_bid_id=b.bid_id
  JOIN buyers y ON b.buyer_id=y.buyer_id
  WHERE i.rendered AND r.request_ts >= TIMESTAMP '2026-05-20'
),
agg AS (
  SELECT cohort,
    SUM(CASE WHEN sdk_version='8.2.0' THEN 1 ELSE 0 END) AS rendered_v82,
    SUM(CASE WHEN sdk_version='8.2.0' AND billable THEN 1 ELSE 0 END) AS billable_v82,
    1.0*SUM(CASE WHEN sdk_version='8.1.0' AND billable THEN 1 ELSE 0 END)
       /NULLIF(SUM(CASE WHEN sdk_version='8.1.0' THEN 1 ELSE 0 END),0) AS baseline_br,
    SUM(CASE WHEN sdk_version='8.1.0' AND billable THEN rev ELSE 0 END)
       /NULLIF(SUM(CASE WHEN sdk_version='8.1.0' AND billable THEN 1 ELSE 0 END),0) AS price_per_billable_v81
  FROM labeled WHERE cohort IS NOT NULL GROUP BY cohort
)
SELECT cohort, rendered_v82, billable_v82,
  ROUND(baseline_br::numeric,3) AS baseline_br,
  GREATEST(0, ROUND((baseline_br*rendered_v82 - billable_v82)::numeric,0)) AS lost_billable_imps,
  ROUND((GREATEST(0, baseline_br*rendered_v82 - billable_v82) * price_per_billable_v81)::numeric,4) AS lost_revenue_usd
FROM agg ORDER BY cohort;
