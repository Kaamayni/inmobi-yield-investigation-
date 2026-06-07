-- ============================================================
--  PART 01 of N — schema + dimension tables
--  Run this FIRST. Then run parts 02, 03, ... in order.
-- ============================================================

DROP TABLE IF EXISTS sdk_events;
DROP TABLE IF EXISTS impressions;
DROP TABLE IF EXISTS bids;
DROP TABLE IF EXISTS ad_requests;
DROP TABLE IF EXISTS buyers;
DROP TABLE IF EXISTS publishers;

CREATE TABLE publishers (
  publisher_id   INTEGER PRIMARY KEY,
  publisher_name VARCHAR, tier VARCHAR, region VARCHAR
);
CREATE TABLE buyers (
  buyer_id INTEGER PRIMARY KEY, buyer_name VARCHAR, billing_type VARCHAR
);
CREATE TABLE ad_requests (
  request_id VARCHAR PRIMARY KEY, request_ts TIMESTAMP, publisher_id INTEGER,
  app_id VARCHAR, sdk_version VARCHAR, os VARCHAR, os_version VARCHAR,
  device_model VARCHAR, country VARCHAR, ad_format VARCHAR, placement_id VARCHAR
);
CREATE TABLE bids (
  bid_id VARCHAR PRIMARY KEY, request_id VARCHAR, buyer_id INTEGER,
  bid_cpm DOUBLE PRECISION, did_bid INTEGER, is_winner INTEGER,
  cleared_price DOUBLE PRECISION, bid_ttl_ms INTEGER
);
CREATE TABLE impressions (
  impression_id VARCHAR PRIMARY KEY, request_id VARCHAR, winning_bid_id VARCHAR,
  render_start_ts TIMESTAMP, render_complete_ts TIMESTAMP, render_latency_ms INTEGER,
  rendered BOOLEAN, viewable BOOLEAN, video_completed BOOLEAN,
  billable BOOLEAN, revenue_usd DOUBLE PRECISION
);
CREATE TABLE sdk_events (
  event_id VARCHAR PRIMARY KEY, request_id VARCHAR, event_type VARCHAR,
  error_code VARCHAR, latency_ms INTEGER, event_ts TIMESTAMP
);

INSERT INTO publishers (publisher_id, publisher_name, tier, region) VALUES
(1, 'GG Studios', 'Tier-1', 'NA'),
(2, 'PixelForge', 'Tier-1', 'EU'),
(3, 'Nova Games', 'Tier-1', 'APAC'),
(4, 'Casual King', 'Tier-1', 'NA'),
(5, 'Indie Bay', 'Tier-2', 'EU'),
(6, 'ArcadeNow', 'Tier-2', 'APAC');
INSERT INTO buyers (buyer_id, buyer_name, billing_type) VALUES
(1, 'BrandReach', 'viewable'),
(2, 'PerformIQ', 'render'),
(3, 'VideoMax', 'complete'),
(4, 'AdsGlobal', 'render'),
(5, 'ViewFirst', 'viewable'),
(6, 'GameAds', 'complete'),
(7, 'MediaPlus', 'render'),
(8, 'PrimeBid', 'viewable');
