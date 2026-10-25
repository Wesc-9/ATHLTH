---
name: lenis
description: Use for smooth scrolling, scroll experience audits, scroll-trigger synchronization, and Lenis integrations in browser-based ATHLTH websites or React projects. Never replace native scrolling in SwiftUI, iOS, or watchOS.
---

# Lenis smooth-scroll skill

Official source: https://github.com/darkroomengineering/lenis
Documentation: https://lenis.dev/

## When to choose Lenis

Use when the user specifically requests premium/smooth website scrolling, parallax scroll synchronization, or an interaction requiring coordinated scroll animation. Do not install it by default on static or non-scrolling views, nor for native apps. Preserve natural browser behavior wherever possible.

## Implementation checklist

1. Read AGENTS.md and inspect the web framework, dependencies, routing, existing scroll handlers, and layout before changing anything.
2. If appropriate for a web project, install `lenis`; use the official React integration (`lenis/react`) if suitable and supported by the project's version. Import `lenis/dist/lenis.css` according to the official setup instructions.
3. Initialize a single Lenis instance at the correct page/app boundary. Dispose of it on unmount/route teardown. Avoid competing Lenis instances and duplicate animation frames.
4. For standalone Lenis, `autoRaf: true` is a simple option. If paired with GSAP ScrollTrigger, use a single controlled RAF, attach `lenis.on('scroll', ScrollTrigger.update)`, and drive `lenis.raf(time * 1000)` from `gsap.ticker`. Read the official GSAP integration example before implementing.
5. Preserve anchor-link navigation, back/forward restoration, focus scrolling, keyboard and touch input, sticky elements, nested scroll containers, dialogs, and mobile overflow.
6. Respect `prefers-reduced-motion`; fall back to native scrolling if smoothing causes discomfort or breaks accessibility. Do not hijack wheel/touch gestures without a user-facing benefit.
7. Validate the actual interaction on mobile and desktop, under dynamic height changes, with both JS enabled and disabled if applicable. Run available checks. Do not deploy without explicit authorization.

## ATHLTH direction

Scrolling should feel controlled and effortless, never floaty or sluggish. Prioritize UX and performance over effects. Integrate with the **gsap** skill for synchronized scroll animations; React Bits effects should not interfere with page-level scrolling.

A skill is instruction only; it does not install Lenis into the application.
