undefined
 
/// A prepared Watch card is allowed to configure the shared workout manager
/// only when another card is not already awaiting HealthKit/phone permission.
/// This is a transient preflight lock, not a second recording owner.
enum ATHLTHWatchPreparedLaunchReservationPolicy {
    static func mayBegin(pendingID: UUID?) -> Bool {
        pendingID == nil
    }
}
