# Round watch presentation
Forerunner 965 is the provisional development target. The screen uses the
smaller physical display dimension, a circular safe area and measured
text width, with smaller fonts and truncation for long exercise labels.
The existing state controller is the only source of recording/progress.
- Ready: title, step count, explicit physical start.
- Endurance: outer ring for current interval progress, large remaining time
  or distance, step index, actual pulse and pace, prescribed target label.
- Free workout: elapsed active time, actual pulse, distance and pace.
- Secondary metrics: pulse, distance, pace (elapsed time for strength).
- Pause and save confirmation: clear status; no silent finish.
- Saved: retained measured final time/distance/average HR after successful
  FIT save. Missing values stay unavailable.
- UP switches pages; DOWN advances open/acknowledged steps, otherwise
  switches pages; START pauses/resumes; BACK opens finish confirmation.
No extra phone cards. Watch-specific rendering is required because
Connect IQ cannot execute SwiftUI. No new recipe builder or fake measurements.
The native SDK simulator, fonts, physical key mapping, round display fit,
GPS/sensor behavior and save acknowledgement are not yet validated.
