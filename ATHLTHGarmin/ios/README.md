# Optional iOS native bridge
Source-only, excluded from the production XcodeGen targets intentionally.
Uses the official ConnectIQ Objective-C SDK API signatures. For a private
test target link the official package, include this .h/.m and register
athlth-connectiq as a unique callback scheme, configure Bluetooth usage
description and required Garmin Connect URL queries from official docs.
Initialize once and route the user-initiated device selection callback to
devicesFromSelectionURL, then explicitly select the returned device.
Do not bind this adapter to live-start availability until the account-scoped
device association, app install check, physical confirmation, launch
reservation, command delivery and acknowledgement have been verified.
The bridge checks device characteristics, installed app and current device
status; it supplies raw events to ATHLTHGarminLiveHandshake, not a new workout.
A production integration must retain session identity on app suspension and
disconnect and cannot release recording ownership merely on a timeout.
No SDK binary or signing credentials are committed.
