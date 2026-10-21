# ATHLTH conversation stadium artwork

The direct-message conversation header is a **photograph-only** asset:
`ATHLTH/Assets.xcassets/ConversationStadiumHero.imageset/stadium.jpg`.
All chat controls, avatars, buttons, names and messages remain native SwiftUI.

## Source, licensing and distribution

- Source: https://pxhere.com/en/photo/1038422
- Source media: https://c.pxhere.com/photos/33/7b/athletic_field_stadium_playground_sunset-1038422.jpg!d
- License: **CC0 Public Domain**, as declared by PxHere on the source page.
- Use: can be redistributed, cropped, modified and bundled with the app.
- Asset pipeline: `scripts/prepare_conversation_stadium_hero.py` downloads the photo in CI, crops it to a broad scenic aspect ratio (no stretching), preserves real source pixels and saves an optimized progressive RGB JPEG. The image is committed into the active GitHub branch by the `bundle-conversation-stadium-hero.yml` workflow.
- Fallback: before the licensed source is successfully bundled, the asset uses an existing ATHLTH running-track photograph so builds continue to have an offline header.

The selected chat mockup is **not** stored as a background image. It includes private conversation information, user identity and native UI, and its screenshot resolution is not sufficient as a standalone Retina asset.

If the downstream provider or license changes, replace the photograph through the asset pipeline and re-verify provenance before public release.
