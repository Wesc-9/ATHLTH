---
name: react-bits
description: Use to evaluate, install, adapt, or audit animated React/Next.js components from React Bits for ATHLTH web pages, including text effects, interactions, cards, microinteractions, and decorative backgrounds. Not applicable to native SwiftUI or watchOS.
---

# React Bits component skill

Official source: https://github.com/DavidHDev/react-bits
Library: https://reactbits.dev/
License: MIT + Commons Clause; check the repository's current license and any included third-party notices before copying components.

## Workflow

1. Read AGENTS.md and confirm the requested target is an actual React/Next.js browser UI. Do not introduce React components into native SwiftUI/iOS/watchOS.
2. Review available components and pick the smallest effect that meets the user's brief. Prioritize a distinctive, consistent ATHLTH premium design rather than a collection of demos.
3. Inspect the selected component's **Code** and **Installation** sections, its JS/TS and CSS/Tailwind variants, dependencies, and browser/runtime assumptions. Match the existing project stack.
4. Use the official documented shadcn registry or jsrepo CLI when appropriate, or bring in only the required component files. Example command from React Bits docs: `npx shadcn@latest add @react-bits/SplitText-TS-TW` (only for the matching TypeScript/Tailwind setup). Never run a blanket installation or overwrite local project files.
5. Customize colors, typography, easing, spacing and responsiveness to fit ATHLTH. Maintain stable touch interactions, keyboard support, accessible labeling, reduced-motion behavior, and legible content.
6. Limit costly canvas/WebGL/shader effects on mobile; provide sensible fallbacks. Clean up event listeners, animation instances, timers and render loops on unmount.
7. Audit licensing and preserve required copyright/third-party notices when reusing source. React Bits' Commons Clause means it must not be treated as unrestricted MIT alone.
8. Run available type-check, lint, build and visual/mobile checks. Do not publish or deploy without an explicit request.

## Integrations

Use **gsap** for custom orchestrated timelines, and **lenis** for a justified site-wide smooth-scroll requirement. Avoid stacking duplicate scroll engines or effects that compete for the same DOM transforms.

## Scope

This skill is an implementation guide. It does not install React Bits, copy its components, or change the running website unless a separate concrete implementation task is requested.
