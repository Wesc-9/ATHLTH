# Project-local agent skills

Skills here are for **Codex and Claude Code in a local checkout** of ATHLTH. They do not become app frameworks, and GitHub alone cannot execute local simulator automation.

## Discovery

- Codex: `.agents/skills/<skill-name>/SKILL.md`
- Claude Code: `.claude/skills/<skill-name>/SKILL.md`
- Both: repository-root `AGENTS.md`; Claude also reads `CLAUDE.md`.

Installed upstream skills (copied with their references/scripts, including source licenses) are:
- `swiftui-pro` — https://github.com/twostraws/SwiftUI-Agent-Skill
- `swift-concurrency-pro` — https://github.com/twostraws/Swift-Concurrency-Agent-Skill
- `swift-testing-pro` — https://github.com/twostraws/Swift-Testing-Agent-Skill
- `ios-simulator-skill` — https://github.com/conorluddy/ios-simulator-skill
- `ios-code-audit` — https://github.com/jazzychad/ios-code-audit
- `observability` — https://github.com/n0an/Observability-Agent-Skill
- `healthkit` — https://github.com/dpearson2699/swift-ios-skills/tree/main/skills/healthkit (PolyForm Perimeter license, retain LICENSE and check upstream terms before redistribution)

Local `athlth-workflow` provides **engineering safeguards only**; design decisions remain open.

## Important overrides
- Follow the actual `project.yml` minimum versions, installed SDK and existing XCTest suites instead of auto-upgrading to newer Swift/OS targets.
- Do not add a runtime package merely because a skill mentions one.
- Do not trigger TestFlight automatically.
- Do not treat aesthetic examples inside SwiftUI skills as ATHLTH design decisions.
- Code-audit review only writes `CODE_AUDIT.md` when requested, not a drive-by code rewrite.
- Observability is advisory: no remote telemetry/export of sensitive health information without approval.

## Simulator prerequisites
On the developer Mac: full Xcode and simulator runtimes; Python 3.12+ and `idb` for advanced simulator interactions. Skill contains local scripts, but this GitHub change cannot install these tools onto a Mac or run its simulator. From the repository root:
```sh
bash .agents/skills/ios-simulator-skill/scripts/sim_health_check.sh
```
For Python helpers, use `python3 .agents/skills/ios-simulator-skill/scripts/<script-name>.py --help`.

## Validation
Run `python3 scripts/verify_agent_skills.py` to check both skill trees, front matter, licenses and required simulator scripts.
Run the normal Xcode and existing GitHub CI workflows separately for app behavior. New skills by themselves do not change app targets.
