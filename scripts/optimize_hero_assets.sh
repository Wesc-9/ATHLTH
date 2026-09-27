#!/bin/bash
set -euo pipefail

# Connect manually uploaded tab artwork before compiling the asset catalogue.
# Empty image sets are intentional until replacement JPGs have been uploaded.
python3 - <<'PY_ASSETS'
import json
from pathlib import Path
for name in ("HomeHero", "TrainHero", "ProgressHero", "RecoveryHero", "CommunityHero"):
    folder = Path("ATHLTH/Assets.xcassets") / (name + ".imageset")
    image = {"idiom": "universal"}
    if (folder / (name + ".jpg")).is_file():
        image["filename"] = name + ".jpg"
    (folder / "Contents.json").write_text(json.dumps({
        "images": [image], "info": {"author": "xcode", "version": 1}
    }, indent=2) + "\n")
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

# Full-screen onboarding needs more vertical resolution than the 190 pt
# dashboard heroes. These limits still exceed what current iPhone/iPad
# displays need at Retina scale while dramatically reducing decoded memory.
resize_if_needed   "ATHLTH/Assets.xcassets/OnboardingHero.imageset/ATHLTH_hero_4x_3764x6688.png"   3200

for file in   "ATHLTH/Assets.xcassets/HomeHero.imageset/HomeHero.jpg"   "ATHLTH/Assets.xcassets/TrainHero.imageset/TrainHero.jpg"   "ATHLTH/Assets.xcassets/RecoveryHero.imageset/RecoveryHero.jpg"   "ATHLTH/Assets.xcassets/ProgressHero.imageset/ProgressHero.jpg"   "ATHLTH/Assets.xcassets/CommunityHero.imageset/CommunityHero.jpg"   "ATHLTH/Assets.xcassets/ProfileHero.imageset/ProfileHero.jpg"   "ATHLTH/Assets.xcassets/StrengthPostWorkoutHero.imageset/StrengthPostWorkoutHero.jpg"
do
  resize_if_needed "$file" 2400
done
