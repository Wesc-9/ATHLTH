# Strength prescription parity — initial subset
Version 3 uses the existing WatchStrengthSessionSnapshot exerciseQueue and
setPlans. Preserve exercise index, set number, plan/session/workout identity,
prescribed repetitions, duration, total weight and rest. Wire step UUIDs are
per transfer. Physical DOWN confirms each set; a timed set requires its timer
target first. Rest uses active recording time and advances only after expiry.
The round screen presents set targets, rest and confirmed-set progress.
Confirmation is NOT a measurement of performed reps or actual weight; those
are not imported. Only confirmed set count is reported. No full strength log
is created on iPhone. Unsupported group modes, mixed intervals, resistance,
RPE/RIR, resumed sessions and over-budget prescriptions reject rather than
silently flatten. 32 steps/10KB remain provisional limits. Transport activation,
SDK compilation, tests and real-device verification are still required.
