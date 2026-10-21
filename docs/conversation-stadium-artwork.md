# ATHLTH conversation stadium artwork

The ATHLTH one-to-one chat header uses **only a standalone stadium photograph** from
`ATHLTH/Assets.xcassets/ConversationStadiumHero.imageset/stadium.jpg`.
Names, profile photos, controls and all message text are native SwiftUI.

## Stadium photograph and license

- **Photographer:** Editor5807
- **Original image:** [Sunset at Lake Fairway Athletics Track.JPG](https://commons.wikimedia.org/wiki/File:Sunset_at_Lake_Fairway_Athletics_Track.JPG)
- **License:** [Creative Commons Attribution 3.0 Unported (CC BY 3.0)](https://creativecommons.org/licenses/by/3.0/)
- **Changes:** Resized, cropped to a panoramic composition, light color/contrast adjustment and optimized as progressive JPEG for use in ATHLTH's chat header.
- **Attribution:** Photo © Editor5807, licensed CC BY 3.0; source and license linked above. The app must retain a discoverable photo credit in its conversation UI.

The `scripts/prepare_conversation_stadium_hero.py` pipeline obtains the
original **4592×3056** image and produces a bundled wide image of about
**2880×1620** pixels. It checks the actual input dimensions and explicitly
refuses to upscale small previews. The GitHub workflow
`.github/workflows/bundle-conversation-stadium-hero.yml` commits the optimized
binary directly to the active 1.8.7 branch.

The fallback in the asset is ATHLTH's existing running-track photograph;
it is replaced by the licensed sunset image when the workflow succeeds.

## Privacy and UX

Do **not** ship the design screenshot. It shows a private user identity,
conversation content and text rendered at screenshot resolution.
The photograph is the only raster component; text, buttons, avatar,
sheet, messages and send controls render natively.
