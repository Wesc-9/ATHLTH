---
name: athlth-workflow
description: Apply ATHLTH-specific release, change-control, regression, iPhone/Watch safety and toolchain checks without defining an ATHLTH visual design. Use for any changes to ATHLTH app or TestFlight workflows.
---

# ATHLTH development workflow

Read repository-root `AGENTS.md` and `project.yml` first. Prefer verified project state over prior assumptions.

1. Confirm requested scope, active branch, existing implementation, and key regression tests.
2. Keep change sets small and reversible. Do not include unrelated redesigns or surprise new packages.
3. For live workouts, verify session identity, persistence, pause/resume, duplicate workout prevention, sync and routing between iPhone and Watch.
4. For HealthKit, check authorization, data provenance, deduplication and explicit user consent before writing or reading health data.
5. For Train navigation, verify active session handling and preservation of user data; never erase planned workouts while resolving visual issues.
6. Use the matching upstream engineering skill for the technology involved. Follow project deployment target and installed Xcode SDK over upstream defaults.
7. Run relevant tests/build checks where a compatible Mac is available; distinguish static review from executed tests.
8. State what changed and what wasn't verified. TestFlight and releases happen only on explicit request.

## Visual design
Visual direction is **not yet approved**. No custom ATHLTH design skill, theme, token scheme, color palette, or component style is imposed by this workflow. Do not reinterpret this process skill as design approval.
