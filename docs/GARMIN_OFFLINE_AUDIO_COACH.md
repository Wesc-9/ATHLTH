# Offline Audio Coach — acceptance requirement

ATHLTH must deliver the chosen Audio Coach without a phone or internet on
compatible watches, using the same authored Coach configuration, rules,
units, language and voice selection as Apple Watch. No Garmin-only templates
or additional phone dashboard cards. An online phone renderer is optional,
not a prerequisite for watch-only workouts.

## Verified platform boundary (2026-11-24)
Garmin Toybox.Audio.Output is available from Connect IQ API 6.0.3, requires
AudioOutput permission, and supports watch apps and bundled OGG/Opus or WAV
resources as well as dynamic audio sources. The official supported-device
list includes Forerunner 570, 970, 170 Music, Venu 4 and several fenix 8/9
models. The previous provisional fr965 target is NOT on that Audio list.
Garmin's native voice prompts and music capability alone are not evidence
that a third-party watch app can play its own speech.
ActivityPrompts intercepts native prompts for data fields; it is not a
general text-to-speech API for our watch app. Attention offers tones and
vibration, which are a non-speech fallback, not Audio Coach parity.

## Design and release gates
- Resolve compatible device and firmware, actual headphone playback,
  AudioOutput permission and voice-pack availability before declaring ready.
- Transfer the existing WatchAudioCoachConfiguration and its effective
  trigger rules with the canonical workout. No duplicate user configuration.
- Compile a bounded offline execution plan and voice pack before start.
  Use pre-generated clips or tested local audio composition for dynamic
  numerical values. Preserve selected voice/language; if unavailable,
  surface that limitation and require explicit fallback selection.
- Run trigger evaluation on the watch against recorded time, distance,
  fresh pulse and workout/interval/set state. No network-dependent trigger
  decisions or assumed sensor samples. Versioned parity fixtures should
  match shared ATHLTH rules; local runtime port is platform-specific.
- Test countdown timing, interval and rest boundaries, time/distance reports,
  heart-rate alerts, motivation, and end summaries; expand to route/Ghost
  only when the required offline data and logic exist.
- One cue owner per active session; never double-speak when phone reconnects.
  Verify music interruption and resumption with Garmin's actual audio
  routing; do not promise automatic Spotify resume before physical tests.
- Test with phone powered off and Wi-Fi unavailable, paired headphones,
  a full 4x4 workout and strength rests, pause/resume, missing measurements,
  stale cues, low battery and lost headphone connection. Require confirmed
  audible speech, not merely a successful API call.
- Older unsupported models keep the shared workout UI, with explicit
  capability reporting and optional local vibration/tones. Do not label
  this as full spoken offline Audio Coach.

This is a design requirement only: no audio code or voice assets have been
enabled, and no compatible device or SDK build has been validated.

Sources:
https://developer.garmin.com/connect-iq/api-docs/Toybox/Audio.html
https://developer.garmin.com/connect-iq/api-docs/Toybox/Audio/Output.html
https://developer.garmin.com/connect-iq/articles/core-topics/Resources.html
https://developer.garmin.com/connect-iq/api-docs/Toybox/ActivityPrompts.html
https://developer.garmin.com/connect-iq/api-docs/Toybox/Attention.html
