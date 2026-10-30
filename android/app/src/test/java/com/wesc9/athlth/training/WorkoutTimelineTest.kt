package com.wesc9.athlth.training

import org.junit.Assert.*
import org.junit.Test

class WorkoutTimelineTest {
    @Test fun fourByFourHasAllIntervalsAndExactlyThreeRecoveries() {
        val stages = SampleWorkouts.runningFourByFour()
        assertEquals(4, stages.count { it.kind == Segment.Kind.WORK })
        assertEquals(3, stages.count { it.kind == Segment.Kind.RECOVERY })
        assertEquals(9, stages.size)
    }

    @Test fun preservesProgressThroughPauseAndResume() {
        val runner = WorkoutTimeline(listOf(
            Segment("a", "Warmup", Segment.Kind.WARMUP, 10),
            Segment("b", "Main", Segment.Kind.WORK, 20)
        ))
        runner.start(1_000L)
        runner.tick(6_000L)
        assertEquals(5000L, runner.snapshot.remainingMs)
        runner.pause()
        runner.tick(100_000L)
        assertEquals(5000L, runner.snapshot.remainingMs)
        runner.start(100_000L)
        runner.tick(107_000L)
        assertEquals(1, runner.snapshot.index)
        assertEquals(18000L, runner.snapshot.remainingMs)
    }

    @Test fun neverAutoAdvancesManualStrengthSets() {
        val stages = listOf(
            Segment("one", "Set", Segment.Kind.STRENGTH, null),
            Segment("two", "Set", Segment.Kind.STRENGTH, null)
        )
        val runner = WorkoutTimeline(stages)
        runner.start(100)
        runner.tick(999999)
        assertEquals(0, runner.snapshot.index)
        runner.advance(999999)
        assertEquals(1, runner.snapshot.index)
        runner.advance(1000000)
        assertTrue(runner.snapshot.finished)
    }

    @Test fun largeTickCompletesOnlyOnce() {
        val runner = WorkoutTimeline(listOf(
            Segment("a", "Warmup", Segment.Kind.WARMUP, 2),
            Segment("b", "Run", Segment.Kind.WORK, 2)
        ))
        runner.start(0)
        runner.tick(10_000)
        assertTrue(runner.snapshot.finished)
        assertEquals(2, runner.snapshot.completedCount)
        runner.tick(20_000)
        assertEquals(2, runner.snapshot.completedCount)
    }
}
