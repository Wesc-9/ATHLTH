---
name: gsap
description: Use for GSAP-powered animations in browser-based ATHLTH projects, including React landing pages, logo motion, hero transitions, SVG, timelines, ScrollTrigger, and interaction design. Do not invoke for native SwiftUI, iOS, or watchOS.
---

# GSAP animation skill

Official source: https://github.com/greensock/gsap
Documentation: https://gsap.com/docs/v3/

## Workflow

1. Read the project-level AGENTS.md and inspect the actual target component, styles, package manager, and runtime. Confirm it is a web UI; GSAP is not the animation framework for native ATHLTH SwiftUI/watchOS.
2. Translate the requested animation into an intentional, premium, restrained motion sequence. Preserve ATHLTH branding and existing functionality.
3. Install only the dependencies required by the approved change (normally `gsap`; for React, use `@gsap/react` and `useGSAP()`).
4. Prefer timelines for linked sequences. Scope selectors to their container, and create cleanup with `useGSAP()` or `gsap.context(...).revert()`; handle route changes and unmounts.
5. Register plugins such as ScrollTrigger explicitly. For scroll effects, ensure refresh and teardown behavior works when content size changes.
6. Prefer transforms and opacity; avoid animating expensive layout properties repeatedly. Limit simultaneous effects and animations on mobile.
7. Honor `prefers-reduced-motion` and ensure the final readable state remains available when animations are off. Avoid layout shifts, flashes, and motion that impairs keyboard/screen-reader access.
8. Test page transitions, touch, resize, scrolling, navigation, and build/lint/type checks. Never publish/deploy or trigger TestFlight without an explicit request.

## Collaboration with other skills

- Use **lenis** for smooth-scrolling requirements, but only when native scrolling is demonstrably insufficient.
- When Lenis and GSAP ScrollTrigger coexist, drive both from one RAF/ticker and synchronize ScrollTrigger with Lenis scroll events; do not create multiple competing RAF loops.
- Use **react-bits** for a relevant existing React component rather than rebuilding it without reason. Avoid layering several visually competing effects.

## ATHLTH visual bar

Aim for understated luxury: precise easing, purposeful depth, polished entrance/exit timing, and clarity over spectacle. Do not add animation simply because a library supports it. Avoid unrelated project changes.

A skill is instruction only; it does not install the GSAP package into the app.
