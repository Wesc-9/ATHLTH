# ATHLTH conversation stadium artwork

The ATHLTH one-to-one chat header uses **only a standalone stadium photograph** from
`ATHLTH/Assets.xcassets/ConversationStadiumHero.imageset/stadium.jpg`.
All names, profile photos, buttons and message text remain native SwiftUI.

## Licensed image

- **Photographer:** Heber Vazquez
- **Photo:** [Stands by Running Track at Stadium](https://www.pexels.com/photo/stands-by-running-track-at-stadium-19753619/)
- **License:** [Pexels License](https://www.pexels.com/license/) (free commercial use; photographer attribution not required).
- **Source resolution used:** **3000 × 2250** pixels (download verified in GitHub Actions).
- **Bundled result:** **2880 × 1620** progressive RGB JPEG, ~834 KB.
- **Changes:** Wide panoramic crop, light contrast adjustment and optimized JPEG for the ATHLTH chat hero.

The `scripts/prepare_conversation_stadium_hero.py` script downloads the original
from Pexels, verifies source dimensions and writes the optimized image. The
`.github/workflows/bundle-conversation-stadium-hero.yml` workflow commits it
directly to the active GitHub branch, so the photo ships **offline in the app**
instead of loading at runtime. The asset must not be replaced with a thumbnail
or an upscaled preview.

## Privacy and rendering

Do **not** bundle the selected chat mockup. It contains a private contact
identity, chat history and text rendered at screenshot resolution. Only the
separate licensed stadium photograph is raster; all chat UI stays native.
