# App-wide Garmin coverage and release gates

Private opt-in only. Existing UI, no new dashboard cards.
- iPhone Home: sleep, steps, HRV existing tiles and existing detail charts.
- iPhone Insights: current readiness measurements, health library, sleep stages,
  selected history charts. Apple readiness score still uses Apple baseline.
- iPad root: account lifecycle boundary; editorial Home readiness measurements.
- History: ordinary chronological list; possible cross-source duplicates labelled.
- Fetch: 30-day steps, resting pulse and overnight HRV ranges; one night's sleep
  and stages, current active/basal energy where supplied. Response fields require
  actual Garmin-account verification. No guessed measurements.
- Pending: longer sleep and exercise history, source-specific readiness baselines,
  Home recent activity, calendar, streak, load, progress, PRs, iPad analytics and
  history, running dynamics, routes/FIT and per-metric preference.
- Do not replace HealthKitManager globally: its results feed social sharing,
  external AI, export, backup, and competition. Each downstream recipient needs
  explicit approval and a scoped, provenance-preserving policy.
- Apple Watch live launch, mirroring, sensors, haptics, audio, live HR zones,
  competition recording, widgets and remote control cannot use synced Garmin
  Personal API activity history as if it were a live session. Separate supported
  Garmin SDK/API, hardware tests and authorization required.
- Commercial OAuth remains gated on Garmin developer approval.
