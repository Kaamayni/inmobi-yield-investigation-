# Dataset — load order

The dataset is split into 11 SQL files because the full insert is too large for some SQL editors to run in one go.

**Run them in order:**

1. `part_01_of_11.sql` — **run this first.** It creates all six tables and loads the dimension tables (publishers, buyers).
2. `part_02_of_11.sql` … `part_11_of_11.sql` — the data inserts. Run sequentially.

Tested on PostgreSQL 16+ (also runs on DuckDB and recent SQLite).

**Verify the load** with:

```sql
SELECT 'ad_requests' AS t, count(*) FROM ad_requests
UNION ALL SELECT 'bids', count(*) FROM bids
UNION ALL SELECT 'impressions', count(*) FROM impressions
UNION ALL SELECT 'sdk_events', count(*) FROM sdk_events
UNION ALL SELECT 'publishers', count(*) FROM publishers
UNION ALL SELECT 'buyers', count(*) FROM buyers;
```

Expected: ad_requests 2600 · bids 7766 · impressions 2230 · sdk_events 6976 · publishers 6 · buyers 8.
