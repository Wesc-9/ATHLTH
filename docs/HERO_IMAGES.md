# Replacing the five tab hero images

Work on `release/v1.4.2`. The recommended upload size is **2400 × 1200 pixels (width × height)** for all five images. Use landscape JPG, sRGB, exported at approximately 90–95% quality. Avoid enlarging a small source image merely to reach this size. Keep the high-resolution original separately.

| Tab | Upload path |
| --- | --- |
| Home | `ATHLTH/Assets.xcassets/HomeHero.imageset/HomeHero.jpg` |
| Train | `ATHLTH/Assets.xcassets/TrainHero.imageset/TrainHero.jpg` |
| Progress | `ATHLTH/Assets.xcassets/ProgressHero.imageset/ProgressHero.jpg` |
| Recovery | `ATHLTH/Assets.xcassets/RecoveryHero.imageset/RecoveryHero.jpg` |
| Community | `ATHLTH/Assets.xcassets/CommunityHero.imageset/CommunityHero.jpg` |

On GitHub, open the appropriate folder on `release/v1.4.2`, choose **Add file → Upload files**, upload the JPG using the exact filename above, and commit to this branch. Keep `Contents.json` in each folder. The build and TestFlight workflows automatically connect the uploaded JPG to the image set before compiling. To run a check, use **Actions → Build ATHLTH → Run workflow**, selecting `release/v1.4.2`. An upload alone does not update an already installed app.

For local Xcode work, drag each JPG into its matching image set in Assets.xcassets, or run `bash scripts/optimize_hero_assets.sh` on macOS before building.

The current tab hero is 214 points tall with a 24-point content overlap. Its width follows the screen. Images use aspect-fill with slight zoom and focal offsets, so no single aspect ratio can display every pixel on every iPhone and iPad. 2:1 is the recommended iPhone composition, not a promise of zero cropping. Keep faces/important details within the central 60% of the image, preferably right of center; leave the left side quiet for app text. Keep the upper area clear of key details for the status bar and the bottom clear for the fade. Do not bake text into the image.

The workflows cap tab artwork at 2400 pixels on its longest edge to control decoded image memory. Uploading a 6000-pixel image does not increase the delivered resolution. A sharp 2400 × 1200 image is about 11 MiB when decoded as RGBA, before rendering overhead.

Only these five tab images were removed. Profile, onboarding, icons and other artwork are retained. Progress now uses ProgressHero like the other tabs, rather than a code-drawn illustration. Until a replacement is uploaded, the tab displays a neutral gradient with its normal title and subtitle.
