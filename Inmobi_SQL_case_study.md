# **Programmatic Yield Investigation: InMobi SDK Revenue Leak**

### **A SQL data-investigation case study**

**Stakeholders:** VP of Demand, Publisher Success, SDK Engineering, Finance

---

## **The incident**

Over the last 30 days (2026-05-08 → 2026-06-06), InMobi's iOS SDK v8.2.0, newly rolled out across our largest Tier-1 global gaming publishers, has driven a \~25% drop in overall Net Revenue (blended eCPM).

What makes this alarming is what hasn't moved:

* Bid Rate (share of auctions advertisers are willing to bid on) is steady.  
* Win Rate (share of auctions our platform wins) is steady.

Demand is healthy and we are still winning auctions. The revenue is leaking somewhere after the auction is won. Finance wants a number, the VP of Demand wants to know if it's a demand problem (it may not be), and SDK Engineering wants to know whether to roll back v8.2.0 or ship a hotfix, and they need evidence, not a hunch.

The v8.2.0 rollout was not instantaneous: it began ramping on 2026-05-20 and grew to the majority of iOS traffic over the following two weeks. Treat that date as your natural "before/after" hinge, but don't assume it's the whole story, adoption is gradual and confounds exist in this data.

Your job: find where the money is leaking, prove the mechanism with data, size the impact in dollars, and make a shippable recommendation.

## **The tasks**

**Task 1: Establish the baseline and confirm the paradox**

Techniques: multi-table joins, conditional aggregation, date bucketing.

Build a daily funnel-health table for the full 30-day window with one row per day and these columns: Bid Rate, Win Rate, Render Rate, Billable Rate, and eCPM. Then add a 7-day moving average of eCPM (window function) to smooth the trend.

Deliverable: a result set (and a sentence of interpretation) that demonstrates the core paradox — that Bid Rate and Win Rate are flat while eCPM declines — and pinpoints roughly when the decline begins. This is you confirming the problem is real and is downstream of the auction.

**Task 2: Decompose the eCPM drop: is this a price problem or a fill problem?**

Techniques: CTEs, window functions (LAG/period comparison), conditional aggregation.

eCPM can fall for two fundamentally different reasons: we're getting paid less per billable impression (a price problem → likely demand-side), or a smaller share of our impressions are billable at all (a fill/leak problem → likely supply/SDK-side). Decompose blended eCPM into these two multiplicative components and compare the pre-rollout vs post-rollout periods.

Deliverable: a clear quantification of how much of the eCPM drop is attributable to price-per-billable-impression versus billable rate. Your conclusion here should redirect the investigation away from one of the two prime suspects.

**Task 3: Isolate the leak by cohort (the core of the investigation)**

Techniques: advanced joins, window functions (ranking), CASE WHEN, NULL handling.

Reconstruct the post-win conversion funnel — render → (viewable / completion, as appropriate to buyer billing\_type) → billable — and compute the billable-rate change (pre vs post) for every cohort defined by sdk\_version × os × os\_version × ad\_format. Use a window function to rank cohorts by the severity of their billable-rate decline, and surface the worst offenders.

Critically: control for confounds. The blended traffic mix shifts over the window. Before you blame any cohort, show whether the decline survives when you hold geography (and other mix variables) constant — i.e. prove the leak is a within-cohort regression, not an artifact of the traffic mix changing. Also build an explicit control comparison (e.g. the same SDK version on the OS that is not affected) to show the problem is specific, not universal.

Deliverable: the specific cohort(s) where billable rate collapses, with the confounds ruled out and a clean control group that stays healthy. You should find more than one distinct failure Deliverable: the specific cohort(s) where billable rate collapses, with the confounds ruled out and a clean control group that stays healthy. You should find more than one distinct failure pattern here.

**Task 4: Confirm the mechanism and size the dollar impact**

Techniques: percentile/aggregate window functions, joins to sdk\_events, conditional aggregation, counterfactual math.

For each suspect cohort from Task 3, prove the mechanism:

Compare the render-latency distribution (p50 and p95) against bid\_ttl\_ms, and quantify the share of impressions where the bid effectively expired.

For the viewability/completion-sensitive cohorts, quantify how the relevant signal behaves and tie it to the affected billing\_types.

Corroborate both with the sdk\_events error-code trail (which error codes spike, and in which cohort).

Then quantify the business impact: estimate the dollars lost over the 30 days, and build a counterfactual, how much revenue would have been recovered if each suspect cohort's billable rate had held at its healthy baseline (e.g. the control group's rate). Use COALESCE to handle the NULL revenue rows correctly.

Deliverable: for each root cause: the mechanism, the corroborating telemetry, and a defensible dollar figure with the assumptions stated.

Task 5: Write up

Write an incident brief / decision memo that the stakeholders could act on.

---

## **Summary**

Net Revenue on our largest Tier-1 gaming publishers fell \~23% over 30 days. This is not a demand problem, bid rate and win rate are flat. The loss is entirely post-auction: two independent bugs in iOS SDK v8.2.0 are causing won impressions to render but fail to bill. Recommendation: deploy two server-side mitigations this week to stop the revenue loss immediately, and ship a targeted SDK hotfix (v8.2.1) in the next release, do not attempt a client-side rollback, which would take weeks to propagate and disrupt publishers.

## **What's broken**

Both failures are confined to v8.2.0 on iOS. Android is unaffected; v8.1.0 is unaffected.

1\. Latency regression — iOS 17.x, rewarded video. Median render time jumped from \~440ms to \~2,540ms, exceeding the bid's \~1,830ms time-to-live. 97% of won bids now expire before they can bill — we win the auction, the ad renders too late, and the advertiser owes us nothing. Billable rate on this cohort fell from 86% to 3%. Confirmed by 95 RENDER\_TIMEOUT events. Notably, iOS 18 is not affected — the bug respects an OS-version boundary, pointing to a specific rendering-path change.

2\. Viewability-measurement break — iOS, interstitial. The Open Measurement (OMID) library is failing to register, so the viewability signal collapsed to \~2%. Buyers who pay only on a measured viewable impression have stopped paying entirely (billable rate 71% → 2%); buyers who pay on render or video-completion are unaffected. Confirmed by 166 OMID\_NOT\_REGISTERED events.

**Why it stayed invisible for weeks**

Every health metric the team monitors i.e bid rate, win rate, render rate, stayed green because the ads do win and do render. The failure is in the thin slice between "rendered" and "billed," which no dashboard watched. We were monitoring the top of the funnel while the leak was at the bottom.

## **Impact**

The two affected cohorts lost \~96-98% of the revenue they should have earned, a near-total loss within those slices, diluted at the blended level by healthy Android and v8.1.0 traffic. (Sizing: at an assumed \[N\] affected iOS impressions/day across these publishers and \~$0.0064 lost revenue per affected rendered impression, 30-day exposure ≈ $\[N × 0.0064 × 30\]. Replace \[N\] with the production volume for these placements.) Note: a separate, benign factor, a traffic mix-shift toward lower-eCPM geographies also pressured blended eCPM but is unrelated to the SDK and requires no action.

## **Recommendation & trade-offs**

| Option | Speed to recover | Risk / cost | Verdict |
| :---- | :---- | :---- | :---- |
| Client-side rollback to v8.1.0 | Weeks (publishers must ship app updates; SDK version can't be forced remotely) | High publisher disruption; loses v8.2.0's intended improvements | Reject: too slow for a client SDK, too disruptive |
| Server-side mitigation (now) | Days | Low; reversible | Adopt: stops the bleed immediately |
| Targeted hotfix v8.2.1 | 1-2 release cycles | Medium; eng time | Adopt: the durable fix |

Immediate (server-side, no client release): 

(a) temporarily raise the bid TTL for the iOS-17 rewarded-video slice so slow renders still bill; (b) route viewability-billed demand away from iOS-v8.2.0 interstitial, or fall back to an alternate measurement source, until OMID is fixed.

Durable (v8.2.1 hotfix): fix the iOS-17 rewarded-video render path and the OMID initialization failure.

## **Guardrail**

Instrument a win-to-billable conversion rate — billable impressions ÷ won impressions — segmented by SDK version × OS version × ad format, with an automatic alert whenever a new SDK version's conversion deviates from the incumbent version's baseline on the same cohort. This sits at the exact funnel stage we were blind to, and a version-vs-version comparison would have caught both bugs within 48 hours of rollout.

## **The ask**

* SDK Engineering: root-cause and hotfix the two defects above; cohorts and error codes attached.  
* Data/Infra: stand up the win-to-billable guardrail and alerting.  
* Demand/Partnerships: confirm whether affected viewability buyers need proactive notification.
