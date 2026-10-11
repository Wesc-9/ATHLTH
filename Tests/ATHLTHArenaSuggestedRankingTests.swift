import Foundation
import XCTest
@testable import ATHLTH

final class ATHLTHArenaSuggestedRankingTests: XCTestCase {
    private let roundID = UUID()
    private let initialDate = Date(timeIntervalSince1970: 1_790_000_000)

    private func workout(
        slot: UUID,
        value: Double,
        metric: String,
        round: UUID? = nil,
        user: UUID? = nil,
        routeMatchPercent: Double? = nil
    ) -> ATHLTHArenaWorkoutEvidence {
        ATHLTHArenaWorkoutEvidence(
            id: UUID(),
            seriesID: UUID(),
            roundID: round ?? roundID,
            slotID: slot,
            userID: user ?? UUID(),
            sourceWorkoutID: UUID(),
            source: "iphone",
            activityType: "running",
            startedAt: initialDate,
            endedAt: initialDate.addingTimeInterval(1_500),
            metricType: metric,
            metricValue: value,
            reportedDistanceMeters: 5_000,
            reportedRouteMatchPercent: routeMatchPercent,
            verificationLevel: "participant_reported"
        )
    }

    func testLiveDuelRequiresExplicitRoundSelectionAcrossMultipleRoutes() {
        let first = UUID()
        let second = UUID()
        let routeA = UUID()
        let routeB = UUID()
        let rounds = [
            makeRouteRound(id: first, routeID: routeA),
            makeRouteRound(id: second, routeID: routeB)
        ]

        // Starting from the global Arena shortcut must not silently
        // attach the first route when the athlete never chose a round.
        XCTAssertNil(ATHLTHArenaLiveRoundSelection.linkedRoundID(
            selectedRoundID: nil, selectedRouteID: routeA, rounds: rounds
        ))
        XCTAssertEqual(ATHLTHArenaLiveRoundSelection.linkedRoundID(
            selectedRoundID: second, selectedRouteID: routeB, rounds: rounds
        ), second)
        XCTAssertNil(ATHLTHArenaLiveRoundSelection.linkedRoundID(
            selectedRoundID: second, selectedRouteID: routeA, rounds: rounds
        ))
        XCTAssertNil(ATHLTHArenaLiveRoundSelection.linkedRoundID(
            selectedRoundID: UUID(), selectedRouteID: routeB, rounds: rounds
        ))
    }

    func testNonRouteCompetitionCannotBeLinkedAsRouteDuel() {
        let roundID = UUID()
        let routeID = UUID()
        let distanceRound = ATHLTHArenaRemoteProposal(
            id: roundID,
            seriesID: UUID(),
            proposedBy: nil,
            template: .fastestDistance,
            title: "5 km",
            rules: "Fastest time",
            position: 0,
            targetDistanceMeters: 5_000,
            routeSnapshot: nil
        )
        XCTAssertNil(ATHLTHArenaLiveRoundSelection.linkedRoundID(
            selectedRoundID: roundID,
            selectedRouteID: routeID,
            rounds: [distanceRound]
        ))
    }

    private func makeRouteRound(id: UUID, routeID: UUID) -> ATHLTHArenaRemoteProposal {
        ATHLTHArenaRemoteProposal(
            id: id,
            seriesID: UUID(),
            proposedBy: nil,
            template: .fastestRoute,
            title: "Course",
            rules: "Same route for everyone",
            position: 0,
            targetDistanceMeters: 5_000,
            routeSnapshot: ChallengeRouteSnapshot(
                routeID: routeID,
                title: "Course",
                distanceKilometers: 5,
                coordinates: [
                    RouteCoordinate(latitude: 63.43, longitude: 10.4, altitude: nil, sequence: 0),
                    RouteCoordinate(latitude: 63.44, longitude: 10.41, altitude: nil, sequence: 1)
                ]
            )
        )
    }

    func testFastestRunUsesBestTimeAndNeverLongestTime() {
        let a = UUID()
        let b = UUID()
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: .fastest5K,
            roundID: roundID,
            evidence: [
                workout(slot: a, value: 1_400, metric: "elapsed_seconds"),
                workout(slot: a, value: 1_200, metric: "elapsed_seconds"),
                workout(slot: b, value: 1_250, metric: "elapsed_seconds")
            ]
        )
        XCTAssertEqual(standings.map(\.slotID), [a, b])
        XCTAssertEqual(standings.first?.result, 1_200)
    }

    func testDistanceSumsAndExcludesUnrelatedMetric() {
        let a = UUID()
        let b = UUID()
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: .mostDistance,
            roundID: roundID,
            evidence: [
                workout(slot: a, value: 2_000, metric: "distance_meters"),
                workout(slot: a, value: 4_000, metric: "distance_meters"),
                workout(slot: b, value: 4_500, metric: "distance_meters"),
                workout(slot: b, value: 1_400, metric: "elapsed_seconds")
            ]
        )
        XCTAssertEqual(standings.map(\.slotID), [a, b])
        XCTAssertEqual(standings.first?.result, 6_000)
    }

    func testCountUsesNumberOfSharedWorkouts() {
        let a = UUID()
        let b = UUID()
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: .mostWorkouts,
            roundID: roundID,
            evidence: [
                workout(slot: a, value: 1, metric: "completed_workout"),
                workout(slot: a, value: 1, metric: "completed_workout"),
                workout(slot: b, value: 1, metric: "completed_workout")
            ]
        )
        XCTAssertEqual(standings.first?.result, 2)
    }

    func testEqualTimesRequireExplicitGroupResolution() {
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: .fastest1K,
            roundID: roundID,
            evidence: [
                workout(slot: UUID(), value: 280, metric: "elapsed_seconds"),
                workout(slot: UUID(), value: 280, metric: "elapsed_seconds")
            ]
        )
        XCTAssertTrue(ATHLTHArenaSuggestedRanking.hasTieAtTop(standings))
    }

    func testSuggestedWinnerNeedsEvidenceFromEveryAthlete() {
        let a = UUID()
        let b = UUID()
        let suggestion = ATHLTHArenaSuggestedRanking.eligibleSuggestion(
            template: .fastest5K,
            scoring: .winner,
            roundID: roundID,
            requiredSlots: [a, b],
            evidence: [workout(slot: a, value: 1_300, metric: "elapsed_seconds")]
        )
        XCTAssertNil(suggestion)
    }

    func testCompleteUnequalResultsProduceWinnerSuggestion() {
        let a = UUID()
        let b = UUID()
        let suggestion = ATHLTHArenaSuggestedRanking.eligibleSuggestion(
            template: .fastest5K,
            scoring: .winner,
            roundID: roundID,
            requiredSlots: [a, b],
            evidence: [
                workout(slot: a, value: 1_300, metric: "elapsed_seconds"),
                workout(slot: b, value: 1_250, metric: "elapsed_seconds")
            ]
        )
        XCTAssertEqual(suggestion, [b])
    }

    func testEqualTimesNeverProduceAutomaticSuggestion() {
        let a = UUID()
        let b = UUID()
        let suggestion = ATHLTHArenaSuggestedRanking.eligibleSuggestion(
            template: .fastest1K,
            scoring: .winner,
            roundID: roundID,
            requiredSlots: [a, b],
            evidence: [
                workout(slot: a, value: 250, metric: "elapsed_seconds"),
                workout(slot: b, value: 250, metric: "elapsed_seconds")
            ]
        )
        XCTAssertNil(suggestion)
    }

    func testPodiumTieAtThirdPlaceRequiresManualReview() {
        let slots = (0..<4).map { _ in UUID() }
        let evidence = zip(slots, [10_000.0, 9_000, 8_000, 8_000])
            .map { slot, distance in
                workout(slot: slot, value: distance, metric: "distance_meters")
            }
        let suggestion = ATHLTHArenaSuggestedRanking.eligibleSuggestion(
            template: .mostDistance,
            scoring: .podium,
            roundID: roundID,
            requiredSlots: slots,
            evidence: evidence
        )
        XCTAssertNil(suggestion)
    }

    func testRouteRankingRequiresReportedGPSMatchForSameRound() {
        let qualified = UUID()
        let unqualified = UUID()
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: .fastestRoute,
            roundID: roundID,
            evidence: [
                workout(slot: qualified, value: 1_220, metric: "elapsed_seconds",
                        routeMatchPercent: 96),
                workout(slot: unqualified, value: 900, metric: "elapsed_seconds"),
                workout(slot: unqualified, value: 920, metric: "elapsed_seconds",
                        routeMatchPercent: 89.9),
                workout(slot: unqualified, value: 910, metric: "elapsed_seconds",
                        round: UUID(), routeMatchPercent: 98)
            ]
        )
        XCTAssertEqual(standings.map(\.slotID), [qualified])
        XCTAssertEqual(standings.first?.result, 1_220)
    }

    func testRouteRankingOnlySuggestsWinnerWhenBothHaveMatchingGPSReports() {
        let a = UUID()
        let b = UUID()
        let evidence = [
            workout(slot: a, value: 1_500, metric: "elapsed_seconds",
                    routeMatchPercent: 94),
            workout(slot: b, value: 1_350, metric: "elapsed_seconds")
        ]
        XCTAssertNil(ATHLTHArenaSuggestedRanking.eligibleSuggestion(
            template: .fastestRoute,
            scoring: .winner,
            roundID: roundID,
            requiredSlots: [a, b],
            evidence: evidence
        ))
        let completed = evidence + [
            workout(slot: b, value: 1_420, metric: "elapsed_seconds",
                    routeMatchPercent: 91)
        ]
        XCTAssertEqual(ATHLTHArenaSuggestedRanking.eligibleSuggestion(
            template: .fastestRoute,
            scoring: .winner,
            roundID: roundID,
            requiredSlots: [a, b],
            evidence: completed
        ), [b])
    }

    func testRivalTargetUsesOnlyOtherParticipantsValidRouteReports() {
        let me = UUID()
        let other = UUID()
        let anotherRound = UUID()
        let report: [ATHLTHArenaWorkoutEvidence] = [
            workout(slot: UUID(), value: 500, metric: "elapsed_seconds",
                    user: me, routeMatchPercent: 98),
            workout(slot: UUID(), value: 900, metric: "elapsed_seconds",
                    user: other, routeMatchPercent: 92),
            workout(slot: UUID(), value: 400, metric: "elapsed_seconds",
                    round: anotherRound, user: other, routeMatchPercent: 99),
            workout(slot: UUID(), value: 200, metric: "elapsed_seconds",
                    user: other),
            workout(slot: UUID(), value: 600, metric: "elapsed_seconds",
                    user: other, routeMatchPercent: 75),
            workout(slot: UUID(), value: 1, metric: "completed_workout",
                    user: other, routeMatchPercent: 95)
        ]
        XCTAssertEqual(
            ATHLTHArenaSuggestedRanking.fastestSharedRivalTime(
                roundID: roundID,
                currentUserID: me,
                evidence: report
            ),
            900
        )
    }

    func testRivalTargetMissingEvidenceDoesNotInventGhostTime() {
        XCTAssertNil(
            ATHLTHArenaSuggestedRanking.fastestSharedRivalTime(
                roundID: roundID,
                currentUserID: UUID(),
                evidence: []
            )
        )
    }

    func testFinishedLiveDuelResultMatchesReportedWinner() {
        let sender = UUID()
        let recipient = UUID()
        let candidate = ATHLTHArenaLiveDuelReview.candidate(
            senderID: sender,
            recipientID: recipient,
            senderSeconds: 1_500,
            recipientSeconds: 1_450,
            reportedWinnerID: recipient,
            isFinished: true
        )
        XCTAssertEqual(candidate?.winnerID, recipient)
        XCTAssertEqual(candidate?.marginSeconds, 50)
    }

    func testLiveDuelRequiresBothTimesAndCompletedRace() {
        let a = UUID(), b = UUID()
        XCTAssertNil(ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: nil,
            recipientSeconds: 1_500, reportedWinnerID: b, isFinished: true
        ))
        XCTAssertNil(ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: 1_400,
            recipientSeconds: 1_500, reportedWinnerID: a, isFinished: false
        ))
        XCTAssertNil(ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: .infinity,
            recipientSeconds: 1_500, reportedWinnerID: b, isFinished: true
        ))
    }

    func testLiveDuelDisagreementNeverSuggestsWinner() {
        let a = UUID(), b = UUID()
        XCTAssertNil(ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: 1_400,
            recipientSeconds: 1_500, reportedWinnerID: b, isFinished: true
        ))
    }

    func testTiedLiveDuelHasNoAutomaticWinner() {
        let a = UUID(), b = UUID()
        let candidate = ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: 1_500.0,
            recipientSeconds: 1_500.3, reportedWinnerID: nil, isFinished: true
        )
        XCTAssertNotNil(candidate)
        XCTAssertNil(candidate?.winnerID)
        XCTAssertNil(ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b, senderSeconds: 1_500.0,
            recipientSeconds: 1_500.3, reportedWinnerID: a, isFinished: true
        ))
    }

    func testLiveDuelDraftRespectsWinnerAndPodiumScoring() {
        let sender = UUID(), recipient = UUID()
        let senderSlot = UUID(), recipientSlot = UUID()
        let candidate = ATHLTHArenaLiveDuelReview.candidate(
            senderID: sender,
            recipientID: recipient,
            senderSeconds: 1_600,
            recipientSeconds: 1_550,
            reportedWinnerID: recipient,
            isFinished: true
        )
        let result = try? XCTUnwrap(candidate)
        XCTAssertNotNil(result)
        if let result {
            XCTAssertEqual(
                ATHLTHArenaLiveDuelReview.proposedSlots(
                    candidate: result,
                    senderID: sender,
                    recipientID: recipient,
                    senderSlotID: senderSlot,
                    recipientSlotID: recipientSlot,
                    scoring: .winner
                ),
                [recipientSlot]
            )
            XCTAssertEqual(
                ATHLTHArenaLiveDuelReview.proposedSlots(
                    candidate: result,
                    senderID: sender,
                    recipientID: recipient,
                    senderSlotID: senderSlot,
                    recipientSlotID: recipientSlot,
                    scoring: .podium
                ),
                [recipientSlot, senderSlot]
            )
        }
    }

    func testTiedLiveDuelNeverCreatesPrefilledRanking() {
        let a = UUID(), b = UUID()
        let candidate = ATHLTHArenaLiveDuelReview.candidate(
            senderID: a, recipientID: b,
            senderSeconds: 2_000, recipientSeconds: 2_000.2,
            reportedWinnerID: nil, isFinished: true
        )
        XCTAssertNotNil(candidate)
        if let candidate {
            XCTAssertNil(
                ATHLTHArenaLiveDuelReview.proposedSlots(
                    candidate: candidate,
                    senderID: a, recipientID: b,
                    senderSlotID: UUID(), recipientSlotID: UUID(),
                    scoring: .winner
                )
            )
        }
    }

    func testArenaLiveDuelHighlightsUsePeakLeadAndCount() {
        let telemetry = ATHLTHArenaLiveDuelReview.highlights(
            senderPeakLeadMeters: 84.2,
            recipientPeakLeadMeters: 131.5,
            leadChangeCount: 4
        )
        XCTAssertEqual(telemetry?.peakLeadMeters, 131.5)
        XCTAssertEqual(telemetry?.leadChanges, 4)
    }

    func testArenaLiveDuelHighlightsRejectInvalidTelemetry() {
        XCTAssertNil(ATHLTHArenaLiveDuelReview.highlights(
            senderPeakLeadMeters: .infinity,
            recipientPeakLeadMeters: 10,
            leadChangeCount: 2
        ))
        XCTAssertNil(ATHLTHArenaLiveDuelReview.highlights(
            senderPeakLeadMeters: -2,
            recipientPeakLeadMeters: 12,
            leadChangeCount: 3
        ))
        XCTAssertNil(ATHLTHArenaLiveDuelReview.highlights(
            senderPeakLeadMeters: 100,
            recipientPeakLeadMeters: 80,
            leadChangeCount: -1
        ))
    }

    func testLiveGhostCanRejoinCountdownOrRaceAfterInvitationExpires() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expired = now.addingTimeInterval(-3_600)
        XCTAssertTrue(ATHLTHArenaLinkedRaceAccess.canOpen(
            roomStatus: .countdown, expiresAt: expired, now: now
        ))
        XCTAssertTrue(ATHLTHArenaLinkedRaceAccess.canOpen(
            roomStatus: .racing, expiresAt: expired, now: now
        ))
    }

    func testExpiredUnstartedLiveGhostCannotOpenLobby() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expired = now.addingTimeInterval(-1)
        let future = now.addingTimeInterval(600)
        XCTAssertFalse(ATHLTHArenaLinkedRaceAccess.canOpen(
            roomStatus: nil, expiresAt: expired, now: now
        ))
        XCTAssertFalse(ATHLTHArenaLinkedRaceAccess.canOpen(
            roomStatus: .lobby, expiresAt: expired, now: now
        ))
        XCTAssertTrue(ATHLTHArenaLinkedRaceAccess.canOpen(
            roomStatus: nil, expiresAt: future, now: now
        ))
    }

    func testFinishedAndCancelledLiveGhostNeverRestartWorkout() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let future = now.addingTimeInterval(600)
        XCTAssertFalse(ATHLTHArenaLinkedRaceAccess.canOpen(
            roomStatus: .finished, expiresAt: future, now: now
        ))
        XCTAssertFalse(ATHLTHArenaLinkedRaceAccess.canOpen(
            roomStatus: .cancelled, expiresAt: future, now: now
        ))
    }

    func testArenaHistoricalDuelsKeepFinishedAndCancelledResults() {
        let future = Date().addingTimeInterval(3600)
        XCTAssertTrue(ATHLTHArenaLiveDuelBrowsing.isHistorical(
            roomStatus: .finished, expiresAt: future
        ))
        XCTAssertTrue(ATHLTHArenaLiveDuelBrowsing.isHistorical(
            roomStatus: .cancelled, expiresAt: future
        ))
    }

    func testArenaActiveDuelSurvivesInvitationExpiry() {
        let expired = Date().addingTimeInterval(-3600)
        XCTAssertFalse(ATHLTHArenaLiveDuelBrowsing.isHistorical(
            roomStatus: .racing, expiresAt: expired
        ))
        XCTAssertFalse(ATHLTHArenaLiveDuelBrowsing.isHistorical(
            roomStatus: .countdown, expiresAt: expired
        ))
    }

    func testArenaUnstartedExpiredDuelMovesToHistory() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(ATHLTHArenaLiveDuelBrowsing.isHistorical(
            roomStatus: .lobby,
            expiresAt: now.addingTimeInterval(-1),
            now: now
        ))
        XCTAssertTrue(ATHLTHArenaLiveDuelBrowsing.isHistorical(
            roomStatus: nil,
            expiresAt: now,
            now: now
        ))
        XCTAssertFalse(ATHLTHArenaLiveDuelBrowsing.isHistorical(
            roomStatus: .lobby,
            expiresAt: now.addingTimeInterval(1),
            now: now
        ))
    }

    private func rivalryChallenge(
        id: UUID = UUID(),
        roundID: UUID,
        sender: UUID,
        recipient: UUID,
        status: GhostFriendRaceStatus = .accepted,
        sourceKind: String? = "planned_route"
    ) -> GhostFriendRaceChallengeRecord {
        GhostFriendRaceChallengeRecord(
            id: id,
            senderID: sender,
            recipientID: recipient,
            title: "Test duel",
            referenceDurationSeconds: 1_600,
            distanceMeters: 5_000,
            routePoints: [],
            privacyTrimmed: true,
            sourceKind: sourceKind,
            arenaRoundID: roundID,
            status: status,
            createdAt: initialDate,
            respondedAt: initialDate,
            expiresAt: initialDate.addingTimeInterval(86_400)
        )
    }

    private func rivalryRoom(
        challengeID: UUID,
        winnerID: UUID?,
        status: LiveGhostRaceRoomStatus = .finished,
        finishOffset: TimeInterval = 1_600
    ) -> LiveGhostRaceRoomRecord {
        LiveGhostRaceRoomRecord(
            challengeID: challengeID,
            status: status,
            countdownStartedAt: initialDate,
            startsAt: initialDate.addingTimeInterval(5),
            finishedAt: initialDate.addingTimeInterval(finishOffset),
            winnerID: winnerID,
            senderMaxLeadMeters: 45,
            recipientMaxLeadMeters: 20,
            leadChangeCount: 2,
            lastLeaderID: winnerID,
            createdAt: initialDate,
            updatedAt: initialDate.addingTimeInterval(1_600)
        )
    }

    private func rivalryParticipant(
        challengeID: UUID, userID: UUID, seconds: Double?
    ) -> LiveGhostRaceParticipantRecord {
        LiveGhostRaceParticipantRecord(
            challengeID: challengeID,
            userID: userID,
            ready: true,
            deviceType: "iphone",
            joinedAt: initialDate,
            readyAt: initialDate,
            finishedAt: seconds == nil ? nil
                : initialDate.addingTimeInterval(seconds!),
            elapsedSeconds: seconds,
            updatedAt: initialDate.addingTimeInterval(1_800)
        )
    }

    func testRivalryCountsOnlyFinishedValidLinkedResults() {
        let me = UUID(), opponent = UUID(), stranger = UUID()
        let won = UUID(), lost = UUID(), tied = UUID(), unverified = UUID()
        let otherRound = UUID(), other = UUID(), racing = UUID()
        let races = [
            rivalryChallenge(id: won, roundID: roundID, sender: me, recipient: opponent),
            rivalryChallenge(id: lost, roundID: roundID, sender: me, recipient: opponent),
            rivalryChallenge(id: tied, roundID: roundID, sender: me, recipient: opponent),
            rivalryChallenge(id: unverified, roundID: roundID, sender: me, recipient: opponent),
            rivalryChallenge(id: other, roundID: otherRound, sender: me, recipient: opponent),
            rivalryChallenge(id: racing, roundID: roundID, sender: stranger, recipient: opponent)
        ]
        let rooms = [
            rivalryRoom(challengeID: won, winnerID: me),
            rivalryRoom(challengeID: lost, winnerID: opponent),
            rivalryRoom(challengeID: tied, winnerID: nil),
            rivalryRoom(challengeID: unverified, winnerID: me),
            rivalryRoom(challengeID: other, winnerID: me),
            rivalryRoom(challengeID: racing, winnerID: stranger)
        ]
        let times: [LiveGhostRaceParticipantRecord] = [
            rivalryParticipant(challengeID: won, userID: me, seconds: 1_400),
            rivalryParticipant(challengeID: won, userID: opponent, seconds: 1_600),
            rivalryParticipant(challengeID: lost, userID: me, seconds: 1_700),
            rivalryParticipant(challengeID: lost, userID: opponent, seconds: 1_500),
            rivalryParticipant(challengeID: tied, userID: me, seconds: 1_600),
            rivalryParticipant(challengeID: tied, userID: opponent, seconds: 1_600.2),
            rivalryParticipant(challengeID: unverified, userID: me, seconds: 1_300),
            rivalryParticipant(challengeID: unverified, userID: opponent, seconds: nil),
            rivalryParticipant(challengeID: other, userID: me, seconds: 1_400),
            rivalryParticipant(challengeID: other, userID: opponent, seconds: 1_600),
            rivalryParticipant(challengeID: racing, userID: stranger, seconds: 1_400),
            rivalryParticipant(challengeID: racing, userID: opponent, seconds: 1_600)
        ]
        let record = ATHLTHArenaRivalrySummary.calculate(
            challenges: races + [races[0]],
            rooms: rooms,
            participants: times,
            eligibleRoundIDs: [roundID],
            currentUserID: me
        )
        XCTAssertEqual(record.wins, 1)
        XCTAssertEqual(record.losses, 1)
        XCTAssertEqual(record.ties, 1)
        XCTAssertEqual(record.excluded, 1)
        XCTAssertEqual(record.finishedCount, 3)
    }

    func testRivalryExcludesFinishedRaceWithMismatchedServerWinner() {
        let me = UUID(), opponent = UUID(), challengeID = UUID()
        let summary = ATHLTHArenaRivalrySummary.calculate(
            challenges: [
                rivalryChallenge(id: challengeID, roundID: roundID,
                                 sender: me, recipient: opponent)
            ],
            rooms: [rivalryRoom(challengeID: challengeID, winnerID: opponent)],
            participants: [
                rivalryParticipant(challengeID: challengeID, userID: me, seconds: 1_300),
                rivalryParticipant(challengeID: challengeID, userID: opponent, seconds: 1_500)
            ],
            eligibleRoundIDs: [roundID],
            currentUserID: me
        )
        XCTAssertEqual(summary.finishedCount, 0)
        XCTAssertEqual(summary.excluded, 1)
    }

    func testLiveRouteTrendUsesOnlyLastTwoValidSameRoundAttempts() {
        let me = UUID(), other = UUID(), earlier = UUID(), latest = UUID()
        let foreign = UUID(), foreignRound = UUID()
        let runs = [
            rivalryChallenge(id: earlier, roundID: roundID, sender: me, recipient: other),
            rivalryChallenge(id: latest, roundID: roundID, sender: me, recipient: other),
            rivalryChallenge(id: foreign, roundID: foreignRound, sender: me, recipient: other)
        ]
        let rooms = [
            rivalryRoom(challengeID: earlier, winnerID: me, finishOffset: 1_600),
            rivalryRoom(challengeID: latest, winnerID: me, finishOffset: 2_500),
            rivalryRoom(challengeID: foreign, winnerID: me, finishOffset: 3_000)
        ]
        let attempts = [
            rivalryParticipant(challengeID: earlier, userID: me, seconds: 1_600),
            rivalryParticipant(challengeID: earlier, userID: other, seconds: 1_750),
            rivalryParticipant(challengeID: latest, userID: me, seconds: 1_450),
            rivalryParticipant(challengeID: latest, userID: other, seconds: 1_590),
            rivalryParticipant(challengeID: foreign, userID: me, seconds: 700),
            rivalryParticipant(challengeID: foreign, userID: other, seconds: 950)
        ]
        let trends = ATHLTHArenaLiveTimeTrend.summaries(
            challenges: runs + [runs[0]],
            rooms: rooms,
            participants: attempts,
            eligibleRoundIDs: [roundID],
            currentUserID: me
        )
        XCTAssertEqual(trends.count, 1)
        XCTAssertEqual(trends.first?.roundID, roundID)
        XCTAssertEqual(trends.first?.attempts, 2)
        XCTAssertEqual(trends.first?.previousSeconds, 1_600)
        XCTAssertEqual(trends.first?.latestSeconds, 1_450)
        XCTAssertEqual(trends.first?.improvementSeconds, 150)
    }

    func testLiveRouteTrendRejectsMissingDisputedOrOtherOriginRace() {
        let me = UUID(), other = UUID()
        let past = UUID(), missing = UUID(), disputed = UUID(), otherOrigin = UUID()
        let races = [
            rivalryChallenge(id: past, roundID: roundID, sender: me, recipient: other),
            rivalryChallenge(id: missing, roundID: roundID, sender: me, recipient: other),
            rivalryChallenge(id: disputed, roundID: roundID, sender: me, recipient: other),
            rivalryChallenge(id: otherOrigin, roundID: roundID, sender: me,
                             recipient: other, sourceKind: "previous_workout")
        ]
        let rooms = [
            rivalryRoom(challengeID: past, winnerID: me),
            rivalryRoom(challengeID: missing, winnerID: me, finishOffset: 2_000),
            rivalryRoom(challengeID: disputed, winnerID: other, finishOffset: 3_000),
            rivalryRoom(challengeID: otherOrigin, winnerID: me, finishOffset: 4_000)
        ]
        let attempts = [
            rivalryParticipant(challengeID: past, userID: me, seconds: 1_400),
            rivalryParticipant(challengeID: past, userID: other, seconds: 1_500),
            rivalryParticipant(challengeID: missing, userID: me, seconds: 1_300),
            rivalryParticipant(challengeID: missing, userID: other, seconds: nil),
            rivalryParticipant(challengeID: disputed, userID: me, seconds: 1_200),
            rivalryParticipant(challengeID: disputed, userID: other, seconds: 1_600),
            rivalryParticipant(challengeID: otherOrigin, userID: me, seconds: 1_100),
            rivalryParticipant(challengeID: otherOrigin, userID: other, seconds: 1_400)
        ]
        XCTAssertTrue(ATHLTHArenaLiveTimeTrend.summaries(
            challenges: races,
            rooms: rooms,
            participants: attempts,
            eligibleRoundIDs: [roundID],
            currentUserID: me
        ).isEmpty)
    }

    func testLiveRouteTrendCanReportSlowerSecondAttemptWithoutAwardingPoints() {
        let me = UUID(), other = UUID(), first = UUID(), next = UUID()
        let changes = ATHLTHArenaLiveTimeTrend.summaries(
            challenges: [
                rivalryChallenge(id: first, roundID: roundID, sender: me, recipient: other),
                rivalryChallenge(id: next, roundID: roundID, sender: me, recipient: other)
            ],
            rooms: [
                rivalryRoom(challengeID: first, winnerID: me, finishOffset: 1_600),
                rivalryRoom(challengeID: next, winnerID: me, finishOffset: 2_500)
            ],
            participants: [
                rivalryParticipant(challengeID: first, userID: me, seconds: 1_200),
                rivalryParticipant(challengeID: first, userID: other, seconds: 1_500),
                rivalryParticipant(challengeID: next, userID: me, seconds: 1_280),
                rivalryParticipant(challengeID: next, userID: other, seconds: 1_500)
            ],
            eligibleRoundIDs: [roundID],
            currentUserID: me
        )
        XCTAssertEqual(changes.first?.improvementSeconds, -80)
    }

    private func roundResult(
        roundID: UUID,
        status: String
    ) -> ATHLTHArenaRoundResult {
        ATHLTHArenaRoundResult(
            id: UUID(),
            seriesID: UUID(),
            roundID: roundID,
            proposedBy: UUID(),
            rankedSlots: [UUID()],
            evidenceNote: "Participant-reviewed",
            status: status,
            createdAt: initialDate
        )
    }

    func testRoundProgressCountsOnlyApprovedAndPendingUniqueRounds() {
        let first = UUID(), second = UUID(), third = UUID(), fourth = UUID()
        let progress = ATHLTHArenaRoundProgress.summarize(
            roundIDs: [first, second, third, fourth, first],
            results: [
                roundResult(roundID: first, status: "rejected"),
                roundResult(roundID: first, status: "approved"),
                roundResult(roundID: first, status: "approved"),
                roundResult(roundID: second, status: "pending"),
                roundResult(roundID: third, status: "expired"),
                roundResult(roundID: UUID(), status: "approved")
            ]
        )
        XCTAssertEqual(progress.total, 4)
        XCTAssertEqual(progress.approved, 1)
        XCTAssertEqual(progress.pending, 1)
        XCTAssertEqual(progress.unresolved, 2)
        XCTAssertEqual(progress.approvedFraction, 0.25, accuracy: 0.0001)
    }

    func testApprovedRoundOverridesOldPendingResult() {
        let round = UUID()
        let progress = ATHLTHArenaRoundProgress.summarize(
            roundIDs: [round],
            results: [
                roundResult(roundID: round, status: "pending"),
                roundResult(roundID: round, status: "approved")
            ]
        )
        XCTAssertEqual(progress.approved, 1)
        XCTAssertEqual(progress.pending, 0)
    }

    func testEmptyRoundProgressNeverDividesByZero() {
        let progress = ATHLTHArenaRoundProgress.summarize(
            roundIDs: [],
            results: [roundResult(roundID: UUID(), status: "approved")]
        )
        XCTAssertEqual(progress.total, 0)
        XCTAssertEqual(progress.unresolved, 0)
        XCTAssertEqual(progress.approvedFraction, 0)
    }

    func testArenaTeamsSumOnlyApprovedPointsAndKeepDeletedSlots() {
        let seriesID = UUID()
        let slots = (0..<4).map { _ in UUID() }
        let members = slots.enumerated().map { index, slot in
            ATHLTHArenaRemoteMember(
                slotID: slot,
                seriesID: seriesID,
                userID: index == 3 ? nil : UUID(),
                response: index == 3 ? "deleted" : "accepted",
                points: Double(index + 1),
                createdAt: initialDate
            )
        }
        let lineup = slots.enumerated().map { index, slot in
            ATHLTHArenaTeamAssignment(
                slotID: slot,
                seriesID: seriesID,
                teamIndex: index < 2 ? 1 : 2
            )
        }
        let standings = ATHLTHArenaTeamStandings.calculate(
            members: members, assignments: lineup
        )
        XCTAssertEqual(standings.count, 2)
        XCTAssertEqual(standings[0].points, 3)
        XCTAssertEqual(standings[1].points, 7)
        XCTAssertEqual(standings[1].athleteCount, 2)
    }

    func testArenaTeamsIgnoreDuplicateOrForeignSlots() {
        let seriesID = UUID()
        let slot = UUID()
        let athlete = ATHLTHArenaRemoteMember(
            slotID: slot,
            seriesID: seriesID,
            userID: UUID(),
            response: "accepted",
            points: 5,
            createdAt: initialDate
        )
        let roster = [
            ATHLTHArenaTeamAssignment(
                slotID: slot, seriesID: seriesID, teamIndex: 1
            ),
            ATHLTHArenaTeamAssignment(
                slotID: slot, seriesID: seriesID, teamIndex: 2
            ),
            ATHLTHArenaTeamAssignment(
                slotID: UUID(), seriesID: seriesID, teamIndex: 2
            )
        ]
        let totals = ATHLTHArenaTeamStandings.calculate(
            members: [athlete], assignments: roster
        )
        XCTAssertEqual(totals.map(\.points).reduce(0,+), 5)
        XCTAssertEqual(totals.map(\.athleteCount).reduce(0,+), 1)
        XCTAssertTrue(ATHLTHArenaTeamStandings.calculate(
            members: [athlete], assignments: []
        ).isEmpty)
    }

    func testAutoTeamDistributionBalancesFourAndFiveAcceptedMembers() throws {
        let seriesID = UUID()
        let athletes = (0..<5).map { index in
            ATHLTHArenaRemoteMember(
                slotID: UUID(),
                seriesID: seriesID,
                userID: UUID(),
                response: "accepted",
                points: Double(index * 2),
                createdAt: initialDate
            )
        }
        for count in [4, 5] {
            let chosen = Array(athletes.prefix(count))
            let assignments = try XCTUnwrap(
                ATHLTHArenaTeamBalancer.suggestedAssignments(members: chosen)
            )
            XCTAssertEqual(assignments.count, count)
            XCTAssertEqual(Set(assignments.keys), Set(chosen.map(\.slotID)))
            XCTAssertEqual(assignments.values.filter { $0 == 1 }.count,
                           (count + 1) / 2)
            XCTAssertEqual(assignments.values.filter { $0 == 2 }.count,
                           count / 2)
            // Same members in a different order produce the same draft.
            XCTAssertEqual(
                assignments,
                ATHLTHArenaTeamBalancer.suggestedAssignments(
                    members: Array(chosen.reversed())
                )
            )
        }
    }

    func testAutoTeamDistributionNeverAssignsUnacceptedOrForeignAthletes() {
        let seriesID = UUID()
        let accepted = (0..<4).map { _ in
            ATHLTHArenaRemoteMember(
                slotID: UUID(), seriesID: seriesID, userID: UUID(),
                response: "accepted", points: 0, createdAt: initialDate
            )
        }
        XCTAssertNil(ATHLTHArenaTeamBalancer.suggestedAssignments(
            members: Array(accepted.prefix(3))
        ))
        let invited = ATHLTHArenaRemoteMember(
            slotID: UUID(), seriesID: seriesID, userID: UUID(),
            response: "invited", points: 0, createdAt: initialDate
        )
        XCTAssertNil(ATHLTHArenaTeamBalancer.suggestedAssignments(
            members: Array(accepted.prefix(3)) + [invited]
        ))
        let foreign = ATHLTHArenaRemoteMember(
            slotID: UUID(), seriesID: UUID(), userID: UUID(),
            response: "accepted", points: 0, createdAt: initialDate
        )
        XCTAssertNil(ATHLTHArenaTeamBalancer.suggestedAssignments(
            members: Array(accepted.prefix(3)) + [foreign]
        ))
        XCTAssertNil(ATHLTHArenaTeamBalancer.suggestedAssignments(
            members: accepted + [accepted[0]]
        ))
    }

    func testRelayLineupRequiresEqualTeamsAndUniqueStages() {
        let first = [UUID(), UUID()]
        let second = [UUID(), UUID()]
        let route = UUID()
        let order = Dictionary(uniqueKeysWithValues: zip(
            first + second, [1, 2, 1, 2]
        ))
        XCTAssertTrue(ATHLTHArenaRelayPlanning.isValid(
            firstTeam: first, secondTeam: second,
            legOrders: order, routeRoundID: route,
            availableRouteRoundIDs: [route]
        ))
        XCTAssertFalse(ATHLTHArenaRelayPlanning.isValid(
            firstTeam: first, secondTeam: [second[0]],
            legOrders: order, routeRoundID: route,
            availableRouteRoundIDs: [route]
        ))
        XCTAssertFalse(ATHLTHArenaRelayPlanning.isValid(
            firstTeam: first, secondTeam: [first[0], second[1]],
            legOrders: order, routeRoundID: route,
            availableRouteRoundIDs: [route]
        ))
        XCTAssertFalse(ATHLTHArenaRelayPlanning.isValid(
            firstTeam: first, secondTeam: second,
            legOrders: order, routeRoundID: UUID(),
            availableRouteRoundIDs: [route]
        ))
    }

    func testRelayLineupRejectsDuplicateOrMissingStageNumbers() {
        let first = [UUID(), UUID()]
        let second = [UUID(), UUID()]
        let route = UUID()
        let duplicate = Dictionary(uniqueKeysWithValues: zip(
            first + second, [1, 1, 1, 2]
        ))
        XCTAssertFalse(ATHLTHArenaRelayPlanning.isValid(
            firstTeam: first, secondTeam: second,
            legOrders: duplicate, routeRoundID: route,
            availableRouteRoundIDs: [route]
        ))
        let missing = [first[0]: 1, first[1]: 2, second[0]: 1]
        XCTAssertFalse(ATHLTHArenaRelayPlanning.isValid(
            firstTeam: first, secondTeam: second,
            legOrders: missing, routeRoundID: route,
            availableRouteRoundIDs: [route]
        ))
    }

    func testRelayGPSCandidateSelectionRequiresSameParticipantAndFrozenRoute() {
        let slot = UUID()
        let round = UUID()
        let candidate = ATHLTHArenaRelayGPSCandidate(
            id: UUID(),
            slotID: slot,
            routeRoundID: round,
            startedAt: Date(),
            elapsedSeconds: 1_650,
            routeMatchPercent: 96
        )
        XCTAssertTrue(candidate.canPrefill(
            for: slot, routeRoundID: round, reportWindowOpen: true
        ))
        XCTAssertFalse(candidate.canPrefill(
            for: UUID(), routeRoundID: round, reportWindowOpen: true
        ))
        XCTAssertFalse(candidate.canPrefill(
            for: slot, routeRoundID: UUID(), reportWindowOpen: true
        ))
        XCTAssertFalse(candidate.canPrefill(
            for: slot, routeRoundID: round, reportWindowOpen: false
        ))
    }

    func testRelayGPSCandidateSelectionRejectsStaleOrInvalidResult() {
        let slot = UUID()
        let round = UUID()
        for (duration, match) in [
            (Double.infinity, 98.0),
            (8.0, 96.0),
            (1_650.0, Double.nan),
            (1_650.0, 82.0),
            (1_650.0, 105.0)
        ] {
            let candidate = ATHLTHArenaRelayGPSCandidate(
                id: UUID(),
                slotID: slot,
                routeRoundID: round,
                startedAt: Date(),
                elapsedSeconds: duration,
                routeMatchPercent: match
            )
            XCTAssertFalse(candidate.canPrefill(
                for: slot, routeRoundID: round, reportWindowOpen: true
            ))
        }
    }

    func testRelayOwnGPSSuggestionRequiresAgreedRouteMatch() {
        XCTAssertTrue(ATHLTHArenaRelayGPSMatch.qualifies(
            routeLengthMeters: 7_500,
            coveredMeters: 7_460,
            elapsedSeconds: 2_100,
            routeMatchPercent: 96,
            startGapMeters: 22,
            endGapMeters: 39
        ))
        XCTAssertFalse(ATHLTHArenaRelayGPSMatch.qualifies(
            routeLengthMeters: 7_500,
            coveredMeters: 7_460,
            elapsedSeconds: 2_100,
            routeMatchPercent: 89,
            startGapMeters: 22,
            endGapMeters: 39
        ))
        XCTAssertFalse(ATHLTHArenaRelayGPSMatch.qualifies(
            routeLengthMeters: 7_500,
            coveredMeters: 6_000,
            elapsedSeconds: 2_100,
            routeMatchPercent: 98,
            startGapMeters: 22,
            endGapMeters: 39
        ))
    }

    func testRelayOwnGPSSuggestionRejectsInvalidAndWrongEndpoints() {
        XCTAssertFalse(ATHLTHArenaRelayGPSMatch.qualifies(
            routeLengthMeters: 5_000,
            coveredMeters: 5_000,
            elapsedSeconds: .infinity,
            routeMatchPercent: 99,
            startGapMeters: 10,
            endGapMeters: 10
        ))
        XCTAssertFalse(ATHLTHArenaRelayGPSMatch.qualifies(
            routeLengthMeters: 5_000,
            coveredMeters: 5_000,
            elapsedSeconds: 1_800,
            routeMatchPercent: .nan,
            startGapMeters: 10,
            endGapMeters: 10
        ))
        XCTAssertFalse(ATHLTHArenaRelayGPSMatch.qualifies(
            routeLengthMeters: 5_000,
            coveredMeters: 5_000,
            elapsedSeconds: 1_800,
            routeMatchPercent: 99,
            startGapMeters: 250,
            endGapMeters: 10
        ))
        XCTAssertFalse(ATHLTHArenaRelayGPSMatch.qualifies(
            routeLengthMeters: 5_000,
            coveredMeters: 5_000,
            elapsedSeconds: 8,
            routeMatchPercent: 99,
            startGapMeters: 10,
            endGapMeters: 10
        ))
    }

    func testCustomRoundsDoNotInferUnsupportedResults() {
        let standings = ATHLTHArenaSuggestedRanking.standings(
            template: .custom,
            roundID: roundID,
            evidence: [workout(slot: UUID(), value: 3_000, metric: "distance_meters")]
        )
        XCTAssertTrue(standings.isEmpty)
    }
}
