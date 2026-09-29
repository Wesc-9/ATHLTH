# ATHLTH primary tab hero images

ATHLTH 1.4.5 uses the same hero height and scroll behavior on all five primary tabs as the Profile view.

## Current mapping

| Primary tab | Asset |
| --- | --- |
| Home | `HomeHero` |
| Train | `TrainHero` |
| Insights | `ProgressHero` |
| Explore | `RecoveryHero` |
| Community | `CommunityHero` |

Explore currently reuses the former Recovery artwork because Recovery is no longer a primary tab. A dedicated `ExploreHero` asset can replace it later without changing the layout.

## Layout baseline

- Hero height: **236 pt**
- Scroll behavior: `ATHLTHPinnedHeroLayout` default behavior, matching Profile
- Sheet overlap: **8 pt**
- No immersive hero transition
- No scroll-fade mask
- Same pinned back-layer behavior as Profile
- Hero artwork extends behind the top safe area
- The rounded content sheet scrolls naturally over the hero

Do not re-enable `immersiveTransition`, `softTransition`, or `scrollFadeTransition` independently on a primary tab. If the primary-tab hero behavior changes in the future, update all five tabs and Profile together unless a deliberate product decision says otherwise.

## Artwork guidance

Recommended source size remains **2400 × 1200 px**, landscape JPG, sRGB, approximately 90–95% quality.

Images use aspect-fill, so keep important subjects away from the extreme edges and leave enough quiet space for the title/subtitle. Do not bake text into the artwork.
