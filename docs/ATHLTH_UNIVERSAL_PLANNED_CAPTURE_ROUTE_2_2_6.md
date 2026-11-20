# 2.2.6 — capture routing for planned sports

This change extends the existing universal timeline and launch admission without changing source workout IDs, legacy Codable schemas, HealthKit ownership or recording journals.

- A named unstructured planned activity (cycling, rowing, stairclimber, HIIT, circuit, functional, sports, yoga, mobility, other) can now prepare the matching existing Watch capture kind. Mobility uses other rather than falsely claiming yoga; explicit yoga uses yoga. Meditation still requires a dedicated truthful recording option and is not relabeled as yoga.
- A saved legacy title/category/duration-only non-running session can be projected to one iPhone manual structured timer with its original stable ID, no fabricated sensor data and no saved plan mutation. Its category and activity tag survive preview and execution.
- Structured or mixed plans **never** convert automatically to a single Watch category that would discard blocks. A real multi-sport HealthKit owner with verified activity semantics and transfer schema is still required.
- Legacy running, walking and strength Watch transfers remain supported when their actual activity category agrees with their stored kind.
- Targeted tests check correct Watch kind, unsupported mixed transfers, projected timed categories, immutable source identity and no false distance.
- No additional HealthKit or GPS capture is created and no TestFlight deployment is requested. iPhone/iPad/Watch CI is required before production.
