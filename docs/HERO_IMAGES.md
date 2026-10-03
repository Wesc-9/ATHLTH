# ATHLTH runtime artwork

The active development baseline is **release/v1.5.7**.

## Tab heroes

Runtime tab heroes live directly in `ATHLTH/Assets.xcassets`:

- `HomeHero.imageset`
- `TrainHero.imageset`
- `RecoveryHero.imageset`
- `ProgressHero.imageset`
- `CommunityHero.imageset`

Use landscape artwork around **2400 × 1200 px** for a 2:1 composition. Keep important subjects inside the central area because SwiftUI uses aspect-fill and different devices crop differently.

The app uses the runtime asset catalog only. High-resolution design masters are intentionally not stored in the application repository.

## Standard goal / club / event artwork

The standard artwork set is:

`GoalSprint`, `GoalWalking`, `GoalMountain`, `GoalProgress`, `GoalRelax`,
`GoalRunning`, `GoalStrength`, `GoalEndurance`, `GoalRecovery`,
`GoalConsistency`, `GoalEvent`, and `GoalAdventure`.

The **Optimize ATHLTH runtime artwork** workflow converts photographic assets to efficient runtime JPEGs and generates small `*Thumbnail` image sets for the artwork picker. Some standard names intentionally fall back to an existing identical runtime hero instead of storing duplicate image bytes.

Do not add raw base64 fragments or large design-master images under `ATHLTH/`. Keep source artwork outside the app repository and upload only the runtime asset.
