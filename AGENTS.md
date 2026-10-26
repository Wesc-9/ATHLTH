# ATHLTH development conventions (Codex + Claude Code)

## Scope and safety
- Follow the user's explicit scope. Implement only requested changes; do not refactor unrelated screens or flows.
- **No ATHLTH-specific visual system is approved yet.** Do not invent, freeze, or enforce a new palette, typography, component library, hero treatment, or visual direction. For UI tasks, preserve existing behavior and use only design choices explicitly agreed for that task.
- Maintain existing app behavior for iPhone and Apple Watch. Avoid duplicating workouts, losing active sessions, changing saved plans, or leaking personal health data.
- Treat SwiftUI/Swift Testing/Concurrency skills as review guidance, not a mandate to migrate frameworks, raise toolchain requirements, or alter deployment targets.
- Check `project.yml` before selecting APIs: currently Swift 6.0, iOS 18.0 and watchOS 11.0 minimum. Verify live config before each change. APIs introduced later require an available SDK and availability guards; do not blindly adopt upstream iOS 26/27 or Swift 6.2+ recommendations.
- Existing tests use XCTest. Keep them working; Swift Testing may be used for appropriate new tests only when supported by the project toolchain. UI tests remain XCTest.
- No additional runtime dependencies, telemetry services, new network endpoints, or permissions without a specific justification and user approval.
- Don't upload builds or run TestFlight without explicit instruction. Don't claim a build/test was run unless it actually ran.

## Workflow
1. Read relevant source files and existing tests; check actual branch and change scope.
2. Use `swiftui-pro` on SwiftUI work, `swift-concurrency-pro` on async code, `swift-testing-pro` on tests, `ios-code-audit` for broad risk reviews, `observability` for logs/crashes, `healthkit` for HealthKit, and `ios-simulator-skill` for simulator checks (when macOS prerequisites exist).
3. Make the smallest reversible code change. Prefer existing app services and Xcode build workflows.
4. Test impacted modules, app navigation and Watch synchronization if relevant. Never silently mark checks as passed.
5. Report changed files, checks performed, checks blocked, and outstanding risks.

## Project references
- `project.yml` – platforms and toolchain
- `Tests/` – existing regression tests
- `.github/workflows/` – current CI and TestFlight flows
- `Shared/WatchTransferModels.swift` and `ATHLTHWatchExtension/` – watch data contract
- `ATHLTH/Diagnostics/` – existing performance and diagnostic signals
- `docs/development/agent-skills.md` – installed skills, sources and local setup

These rules are implementation safeguards, **not** a decision on ATHLTH visual design.
