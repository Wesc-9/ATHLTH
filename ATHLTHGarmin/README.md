# ATHLTH Connect IQ — initial development project

This is a separate watch application, NOT a second iPhone workout engine.
Initial simulator/device target: Forerunner 965 (fr965), provisional until the
owner confirms the model. No claim of device compatibility beyond the
declared test target. The manifest app UUID is 8fc5f765ab344de2bdca2580f832729b.
Do not change it after deployment; the iOS companion must use the same ID.

Install Garmin Connect IQ SDK and VS Code Monkey C extension after accepting
the SDK terms. Download the fr965 device profile. Generate a private developer
signing key locally (never commit it). Build for fr965 using:
```sh
monkeyc -f monkey.jungle -d fr965 -y /secure/path/developer_key.der -o ATHLTHGarmin.prg
```
Use the simulator first, then sideload the PRG to GARMIN/APPS via USB on the
compatible device. Source code is not a signed or tested PRG.

V1 wire protocol: dictionaries with v=1, kind=prepare/status/cancel, id=UUID.
prepare includes sport and expiry (Unix seconds, 90-second window).
The watch requests a physical confirmation before creating its FIT recording.
START toggles pause/resume; BACK then START attempts to stop and save.
Events contain state and increasing seq, optionally seconds/meters/bpm.
No account identifier, personal API key, or cloud endpoint travels over BLE.

The iOS handshake is staged in ATHLTH/Wearables/ATHLTHGarminLiveProtocol.swift.
Do not enable Garmin in the existing Watch button until the actual official
iOS SDK adapter is linked, device and app identity validated, universal
recording admission reserved, account lifecycle handling implemented,
and recording/terminal acknowledgements tested. Delivery is not a start ACK.
No silent fallback to Apple Watch. On link loss retain an occupied/uncertain
recording slot until confirmed stopped and reconciled; no second capture.
No structured interval/route/strength-set recipe execution yet; reject
rather than flatten such workouts to free recording.
No publishing, health data cloud upload, or fake live readings.
No Garmin-only cards in the phone app. Feed confirmed snapshots and finished
recordings into the existing shared live UI/import paths once validated.

iOS integration reference:
https://github.com/garmin/connectiq-companion-app-sdk-ios
https://developer.garmin.com/connect-iq/articles/core-topics/Mobile_SDK_for_iOS.html
https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityRecording.html
