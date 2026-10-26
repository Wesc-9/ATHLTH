#!/usr/bin/env python3
"""Read-only, dependency-free manifest checks for Codex + Claude project skills."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SKILLS = ("swiftui-pro", "swift-concurrency-pro", "swift-testing-pro",
          "ios-simulator-skill", "ios-code-audit", "observability", "healthkit", "athlth-workflow")
REQUIRED_SIM = ("SKILL.md", "scripts/sim_health_check.sh", "scripts/build_and_test.py",
                "scripts/screen_mapper.py", "scripts/navigator.py", "scripts/log_monitor.py")
errors = []
for agent in (".agents", ".claude"):
    for name in SKILLS:
        directory = ROOT / agent / "skills" / name
        manifest = directory / "SKILL.md"
        if not manifest.is_file():
            errors.append(f"missing: {manifest.relative_to(ROOT)}")
            continue
        txt = manifest.read_text(encoding="utf-8")
        if not txt.startswith("---\n") or not re.search(r"(?m)^name:[ \t]*" + re.escape(name) + r"[ \t]*$", txt):
            errors.append(f"invalid metadata/name: {manifest.relative_to(ROOT)}")
        if name != "athlth-workflow" and not (directory / "UPSTREAM_LICENSE").is_file():
            errors.append(f"missing license: {directory.relative_to(ROOT)}")
        if name == "ios-simulator-skill":
            for path in REQUIRED_SIM:
                if not (directory / path).is_file():
                    errors.append(f"missing simulator component: {agent}/{name}/{path}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print(f"OK: {len(SKILLS)} skills registered for each agent (Codex + Claude Code).")
