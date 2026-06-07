# InMobi Programmatic Yield Investigation

**A SQL-driven product investigation: diagnosing a 25% ad-revenue leak in a mobile SDK.**

This is a self-directed case study in the style of a Principal Product Data Scientist / Monetization PM at an ad-tech company. It starts from a realistic incident, uses SQL to find the root cause through ~20,000 rows of programmatic auction data, and ends in a decision memo a VP could act on.

---

## The incident

Over 30 days, Net Revenue (eCPM) on a mobile ad platform's largest Tier-1 gaming publishers dropped **~25%**. The strange part: **bid rate and win rate were completely flat** — advertisers were still bidding, and the platform was still winning auctions. The money was leaking *after* the auction was won.

## How I approached it

I reconstructed the post-auction funnel — *win → render → measure → bill* — and worked down it stage by stage, ruling out confounds at each step.

| # | Question | Method | Finding |
|---|---|---|---|
| 1 | Is the leak real, and where? | Daily funnel metrics + 7-day moving average (CTEs, window functions) | Bid/win rates flat; eCPM and billable-rate decline → leak is **post-win** |
| 2 | Price problem or fill problem? | Decomposed eCPM = billable_rate × price (conditional aggregation, `LAG`) | An apparent price drop was a **geo mix-shift artifact**, not demand → demand hypothesis closed |
| 3 | Which inventory is failing? | Cohort isolation by SDK × OS × version × format, version-vs-version (pivot, `RANK`) | **Two distinct iOS v8.2.0 failures**; Android + v8.1.0 healthy (clean control) |
| 4 | Why, and how much? | Latency percentiles vs bid TTL, `billing_type` split, error-code corroboration, counterfactual | Mechanisms confirmed; affected cohorts lost **~96–98%** of billable revenue |
| 5 | What do we do? | Decision memo | Server-side mitigation now + targeted hotfix; **not** a client rollback |

## The two root causes

1. **Render-latency regression (iOS 17.x, rewarded video):** median render time jumped ~440ms → ~2,540ms, exceeding the ~1,830ms bid time-to-live, so **97% of won bids expired before billing.** Corroborated by `RENDER_TIMEOUT` telemetry.
2. **Viewability-measurement break (iOS, interstitial):** the Open Measurement (OMID) library stopped registering, so buyers who pay only on *viewable* impressions stopped paying entirely — while render- and completion-billed buyers were unaffected. Corroborated by `OMID_NOT_REGISTERED` telemetry.

## Why it stayed hidden

Every monitored metric — bid rate, win rate, **render rate** — stayed green, because the ads *did* win and *did* render. The failure lived in the unmonitored gap between "rendered" and "billed." The proposed guardrail — **win-to-billable conversion, segmented by SDK version** — sits exactly there and would have caught both bugs within 48 hours.

## What's in this repo

- **[`inmobi_SQL_case_study.md`](inmobi_SQL_case_study.md)** — the full scenario, investigation tasks, and the decision memo (start here)
- **[`data/`](data/)** — the dataset as SQL (`part_01` … `part_11`); run in order (see [`data/00_README.md`](data/00_README.md))
- **[`queries/`](queries/)** — one annotated SQL file per task

## Run it yourself

Built and tested on PostgreSQL (Supabase). Load `data/part_01_of_11.sql` first (it creates the schema), then `part_02` through `part_11` in order, then run any file in `queries/`.

## Skills demonstrated

CTEs · window functions (`LAG`, `RANK`, moving averages) · conditional aggregation (`CASE WHEN`, `FILTER`) · multi-table joins · percentile distributions · confound control · hypothesis-driven investigation · translating data into a business decision.

---

*Dataset is synthetic, generated to model a realistic ad-tech incident. Not affiliated with any company.*
