# Offline coach prototype
Current development manifest targets both Forerunner 570 sizes and requires
Connect IQ 6.0.3 / AudioOutput. The earlier 965 target is temporarily excluded
from this audio-capable build, not declared permanently incompatible with ATHLTH.
Install espeak-ng and ffmpeg locally, run python3 tools/build_voice_pack.py
from ATHLTHGarmin, then build with monkeyc for fr57042mm or fr57047mm.
The generator produces explicitly developer-only Norwegian/English speech
assets and the resource lookup. These must be generated before SDK build.
No paid voice API or network access is used. Do not ship the developer pack
as the user's chosen ATHLTH voice. Actual production voice licensing,
synthesis, transfer and playback still need verification.
V4 wraps v1/v2/v3 recipe and carries a bounded offline coach projection.
Old builds reject v4 rather than ignore coach. Existing configurations
with unsupported features reject before launch; no silent replacement.
Local start, pause/resume, save, set and rest cues and 1–10 countdowns
for selected timed interval/rest transitions are staged. Busy playback
drops a cue rather than replay stale numbers. No dynamic numeric report,
custom rules, music duck/resume, route/ghost coach, or full parity yet.
The current controller still requires a short-lived prepare message before
launch; watch-only selection and persistent synced workout library are
separate pending requirements. No production live launch is enabled.
Actual Monkey C SDK compilation, resource namespace validation, sound route,
headphones, cue timing and phone-off testing are outstanding.
Official API: https://developer.garmin.com/connect-iq/api-docs/Toybox/Audio/Output.html
