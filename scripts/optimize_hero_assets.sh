#!/bin/bash
set -euo pipefail

# Connect manually uploaded tab artwork before compiling the asset catalogue.
# Accept PNG/JPG/JPEG and preserve the filename that was actually uploaded.
# An empty image set remains valid and falls back gracefully until artwork exists.
python3 - <<'PY_ASSETS'
import json
from pathlib import Path

SUPPORTED = {".png", ".jpg", ".jpeg"}

for name in ("HomeHero", "TrainHero", "ProgressHero", "RecoveryHero", "CommunityHero"):
    folder = Path("ATHLTH/Assets.xcassets") / (name + ".imageset")
    image = {"idiom": "universal"}

    candidates = sorted(
        (
            path for path in folder.iterdir()
            if path.is_file()
            and path.name != "Contents.json"
            and path.suffix.lower() in SUPPORTED
        ),
        key=lambda path: (
            path.stem.lower() != name.lower(),
            path.name.lower(),
        ),
    )

    if candidates:
        image["filename"] = candidates[0].name

    (folder / "Contents.json").write_text(
        json.dumps(
            {
                "images": [image],
                "info": {"author": "xcode", "version": 1},
            },
            indent=2,
        )
        + "\n"
    )
PY_ASSETS


resize_if_needed() {
  local file="$1"
  local max_dimension="$2"

  [ -f "$file" ] || return 0

  local width height largest
  width=$(sips -g pixelWidth "$file" | awk '/pixelWidth/ {print $2}')
  height=$(sips -g pixelHeight "$file" | awk '/pixelHeight/ {print $2}')

  if [ "$width" -ge "$height" ]; then
    largest="$width"
  else
    largest="$height"
  fi

  if [ "$largest" -gt "$max_dimension" ]; then
    echo "Optimizing $file: ${width}x${height} -> max ${max_dimension}px"
    sips -Z "$max_dimension" "$file" >/dev/null
  else
    echo "Keeping $file: ${width}x${height}"
  fi
}

# Keep runtime artwork bounded even when a replacement image was uploaded
# directly to an image set. The dedicated asset workflow handles format
# conversion and thumbnails; this build-time guard prevents oversized source
# pixels from reaching the asset compiler.
for folder in \
  "ATHLTH/Assets.xcassets/OnboardingHero.imageset"
do
  while IFS= read -r file; do
    resize_if_needed "$file" 3200
  done < <(
    find "$folder" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
      -print
  )
done

for folder in \
  "ATHLTH/Assets.xcassets/HomeHero.imageset" \
  "ATHLTH/Assets.xcassets/TrainHero.imageset" \
  "ATHLTH/Assets.xcassets/RecoveryHero.imageset" \
  "ATHLTH/Assets.xcassets/ProgressHero.imageset" \
  "ATHLTH/Assets.xcassets/CommunityHero.imageset" \
  "ATHLTH/Assets.xcassets/ProfileHero.imageset" \
  "ATHLTH/Assets.xcassets/StrengthPostWorkoutHero.imageset" \
  "ATHLTH/Assets.xcassets/StrengthQuickStartHero.imageset" \
  ATHLTH/Assets.xcassets/Goal*.imageset
do
  [ -d "$folder" ] || continue
  case "$folder" in
    *Thumbnail.imageset) max_dimension=600 ;;
    *) max_dimension=2400 ;;
  esac

  while IFS= read -r file; do
    resize_if_needed "$file" "$max_dimension"
  done < <(
    find "$folder" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
      -print
  )
done
