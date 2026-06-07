-- ============================================================================
-- TASK 3 — Isolate the leak by cohort (the core of the investigation)
-- ----------------------------------------------------------------------------
-- Goal: find WHICH impressions fail to bill. Because v8.2.0 barely existed
--       before the rollout, compare SDK versions SIDE-BY-SIDE within the same
--       (post-rollout) window instead of pre-vs-post -- this holds time, OS
--       version and format constant so the only difference is the SDK version.
-- Technique: conditional-aggregation pivot (version -> columns), window
--            function (RANK), messy-data handling (split_part on os_version),
--            volume filter to suppress noise.
-- Finding: TWO distinct iOS v8.2.0 failures --
--   (1) iOS 17.x rewarded_video: billable rate 0.855 -> 0.031 (catastrophic)
--   (2) iOS interstitial (all versions): partial drop (different signature)
--   Android is flat (clean control); iOS 18 rewarded_video is flat
--   (=> bug is version-specific). Collapse survives within every geo band.
-- Tested on PostgreSQL 16.
-- ============================================================================

-- 3A: version-vs-version billable rate by cohort, POST period, ranked by drop
WITH post AS (
  SELECT r.os,
         split_part(r.os_version, '.', 1) AS os_major,   -- '17.1.2' -> '17'
         r.ad_format, r.sdk_version, i.billable
  FROM impressions i
  JOIN ad_requests r USING (request_id)
  WHERE i.rendered
    AND r.request_ts >= TIMESTAMP '2026-05-20'
),
cohort AS (
  SELECT os, os_major, ad_format,
    SUM(CASE WHEN sdk_version='8.1.0' THEN 1 ELSE 0 END) AS n_v81,
    SUM(CASE WHEN sdk_version='8.2.0' THEN 1 ELSE 0 END) AS n_v82,
    1.0*SUM(CASE WHEN sdk_version='8.1.0' AND billable THEN 1 ELSE 0 END)
        /NULLIF(SUM(CASE WHEN sdk_version='8.1.0' THEN 1 ELSE 0 END),0) AS br_v81,
    1.0*SUM(CASE WHEN sdk_version='8.2.0' AND billable THEN 1 ELSE 0 END)
        /NULLIF(SUM(CASE WHEN sdk_version='8.2.0' THEN 1 ELSE 0 END),0) AS br_v82
  FROM post
  GROUP BY os, os_major, ad_format
)
SELECT os, os_major, ad_format, n_v81, n_v82,
  ROUND(br_v81::numeric, 3) AS br_v81,
  ROUND(br_v82::numeric, 3) AS br_v82,
  ROUND((br_v82 - br_v81)::numeric, 3) AS delta,
  RANK() OVER (ORDER BY (br_v82 - br_v81)) AS worst_rank
FROM cohort
WHERE n_v81 >= 15 AND n_v82 >= 15          -- drop thin cohorts where rates are noise
ORDER BY delta
LIMIT 12;

-- 3B: does the iOS-17 rewarded_video collapse survive holding geo constant?
WITH post AS (
  SELECT CASE WHEN r.country IN ('IN','ID','BR') THEN 'low_ecpm_geo' ELSE 'high_ecpm_geo' END AS geo_band,
         r.sdk_version, i.billable
  FROM impressions i
  JOIN ad_requests r USING (request_id)
  WHERE i.rendered AND r.request_ts >= TIMESTAMP '2026-05-20'
    AND r.os='iOS' AND split_part(r.os_version,'.',1)='17' AND r.ad_format='rewarded_video'
    AND r.country IS NOT NULL
)
SELECT geo_band,
  ROUND((1.0*SUM(CASE WHEN sdk_version='8.1.0' AND billable THEN 1 ELSE 0 END)
      /NULLIF(SUM(CASE WHEN sdk_version='8.1.0' THEN 1 ELSE 0 END),0))::numeric,3) AS br_v81,
  ROUND((1.0*SUM(CASE WHEN sdk_version='8.2.0' AND billable THEN 1 ELSE 0 END)
      /NULLIF(SUM(CASE WHEN sdk_version='8.2.0' THEN 1 ELSE 0 END),0))::numeric,3) AS br_v82
FROM post
GROUP BY geo_band
ORDER BY geo_band;
