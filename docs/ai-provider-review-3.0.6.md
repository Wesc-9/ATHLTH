# AI provider review — 3.0.6

Client source review, not a deployed service or GDPR compliance certification.

| Feature | Current client implementation |
| --- | --- |
| Private health insight, ordinary Coach, history queries | Local Apple Foundation Models / deterministic rules; no Groq fallback in these paths |
| Chat workout/plan drafts, structural plan review, shared workout drafts | Local rules, library references and explicit review; some old entry points still use external planning |
| Competition Coach | Local rules over existing server-supported catalog; no prompt sent to AI |
| Equipment scanner | On-device Apple Vision; explicit equipment confirmation, library matching; no AI upload |
| Prestige trophy inscription | Approved generic local wording, existing local cache; no external AI request |
| Daily recommendation | Rules, admin-only local wording pilot |
| Live fixed audio cues | Shared deterministic engine |
| General plan generation / strength generation / legacy adaptation | Existing external Groq endpoints, explicit known-health guards only; free text, goal metadata and plan notes can still contain sensitive information |
| Experimental push-to-talk / realtime conversation | Existing external audio services; voice itself can contain sensitive information |
| Azure speech | Separate speech service; review provider consent, payload and privacy policy |
| Private Cloud Compute / Watch generative Coach | Disabled until access, entitlement and deployment are verified |

Backend endpoints remain available to older clients; no server deployment or deletion was performed. Other backend/admin generation functions (exercise drafts, weekly challenges and cover art) require separate caller and payload verification. This is not an exhaustive proof of absence of external health transfers.

Release gate: compile and run iPhone/iPad/Watch regression tests; test local Apple availability and Norwegian quality, catalog ID checks, offline/fallback behavior, account switching, VoiceOver, and audio timing. Verify current provider contracts, data minimization, retention, consent, legal basis, disclosure and legacy endpoint protections before public launch.
