-- ============================================================================
-- TASK 1 — Establish the baseline and confirm the paradox
-- ----------------------------------------------------------------------------
-- Goal: build a daily funnel-health table (bid rate, win rate, render rate,
--       billable rate, eCPM + 7-day moving average) to prove that the top of
--       the funnel is healthy while revenue declines.
-- Technique: CTEs at three different grains, conditional aggregation, window
--            function (trailing moving average).
-- Finding: bid rate (~0.82) and win rate (~0.85) stay flat all month, while
--          eCPM and billable rate decline in the back half (post May-20 rollout).
--          => the leak is DOWNSTREAM of winning the auction.
-- Tested on PostgreSQL 16.
-- ============================================================================

WITH bid_daily AS (                              -- grain: one row per BID
    SELECT date_trunc('day', r.request_ts)::date AS d,
           AVG(CASE WHEN b.did_bid = 1 THEN 1.0 ELSE 0 END) AS bid_rate
    FROM bids b
    JOIN ad_requests r USING (request_id)
    GROUP BY 1
),
auction_daily AS (                               -- grain: one row per AUCTION OPPORTUNITY
    SELECT date_trunc('day', r.request_ts)::date AS d,
           AVG(CASE WHEN w.won = 1 THEN 1.0 ELSE 0 END) AS win_rate
    FROM ad_requests r
    LEFT JOIN (
        SELECT request_id, MAX(is_winner) AS won
        FROM bids
        GROUP BY request_id
    ) w USING (request_id)
    GROUP BY 1
),
imp_daily AS (                                   -- grain: one row per IMPRESSION
    SELECT date_trunc('day', r.request_ts)::date AS d,
           AVG(CASE WHEN i.rendered THEN 1.0 ELSE 0 END) AS render_rate,
           AVG(CASE WHEN i.billable THEN 1.0 ELSE 0 END)
               FILTER (WHERE i.rendered) AS billable_rate,
           SUM(COALESCE(i.revenue_usd, 0))
               / NULLIF(COUNT(*) FILTER (WHERE i.rendered), 0) * 1000 AS ecpm
    FROM impressions i
    JOIN ad_requests r USING (request_id)
    GROUP BY 1
),
daily AS (                                       -- join the three grains on the day key
    SELECT b.d, b.bid_rate, a.win_rate,
           i.render_rate, i.billable_rate, i.ecpm
    FROM bid_daily b
    JOIN auction_daily a USING (d)
    JOIN imp_daily i USING (d)
)
SELECT d,
       ROUND(bid_rate::numeric, 3)      AS bid_rate,
       ROUND(win_rate::numeric, 3)      AS win_rate,
       ROUND(render_rate::numeric, 3)   AS render_rate,
       ROUND(billable_rate::numeric, 3) AS billable_rate,
       ROUND(ecpm::numeric, 3)          AS ecpm,
       ROUND(AVG(ecpm) OVER (ORDER BY d
             ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)::numeric, 3) AS ecpm_7d_avg
FROM daily
ORDER BY d;
