package com.wesc9.athlth.training

/**
 * Platform-independent timer calculations. Times are elapsedRealtime-style
 * monotonic milliseconds. This runner does not record to Health Connect,
 * persist a workout, or claim to support background recording yet.
 */
data class Segment(
    val id: String,
    val label: String,
    val kind: Kind,
    val durationSeconds: Int?,
    val heartRateZone: Int? = null
) {
    enum class Kind { WARMUP, WORK, RECOVERY, COOLDOWN, STRENGTH }
    init {
        require(id.isNotBlank())
        require(durationSeconds == null || durationSeconds > 0)
        require(heartRateZone == null || heartRateZone in 1..5)
    }
}

data class TimelineSnapshot(
    val index: Int,
    val remainingMs: Long?,
    val running: Boolean,
    val finished: Boolean,
    val completedCount: Int
)

class WorkoutTimeline(val segments: List<Segment>) {
    init { require(segments.isNotEmpty()) }

    var snapshot = TimelineSnapshot(0, segments[0].durationSeconds?.times(1000L),
        false, false, 0)
        private set

    private var lastTick: Long? = null

    fun start(nowMs: Long) {
        if (snapshot.finished || snapshot.running) return
        lastTick = nowMs
        snapshot = snapshot.copy(running = true)
    }

    fun pause() {
        if (!snapshot.running) return
        lastTick = null
        snapshot = snapshot.copy(running = false)
    }

    fun advance(nowMs: Long) {
        if (snapshot.finished) return
        advanceInternal()
        lastTick = if (snapshot.running) nowMs else null
    }

    fun tick(nowMs: Long) {
        if (!snapshot.running || snapshot.finished) return
        val previous = lastTick ?: nowMs
        var elapsed = (nowMs - previous).coerceAtLeast(0L)
        lastTick = nowMs
        while (!snapshot.finished && elapsed > 0) {
            val remaining = snapshot.remainingMs ?: return
            if (elapsed < remaining) {
                snapshot = snapshot.copy(remainingMs = remaining - elapsed)
                elapsed = 0
            } else {
                elapsed -= remaining
                advanceInternal()
                // Don't automatically advance past manual strength sets.
                if (snapshot.remainingMs == null) return
            }
        }
    }

    private fun advanceInternal() {
        val nextIndex = snapshot.index + 1
        snapshot = if (nextIndex == segments.size) {
            TimelineSnapshot(snapshot.index, 0, false, true, segments.size)
        } else {
            TimelineSnapshot(
                nextIndex,
                segments[nextIndex].durationSeconds?.times(1000L),
                snapshot.running,
                false,
                nextIndex
            )
        }
    }
}

object SampleWorkouts {
    fun runningFourByFour(): List<Segment> {
        val segments = mutableListOf(
            Segment("warmup", "Oppvarming", Segment.Kind.WARMUP, 600, 2)
        )
        repeat(4) { index ->
            segments += Segment("run-${index+1}", "Drag ${index+1} av 4",
                Segment.Kind.WORK, 240, 4)
            if (index < 3) segments += Segment("rest-${index+1}",
                "Aktiv joggepause", Segment.Kind.RECOVERY, 120, 2)
        }
        segments += Segment("cooldown", "Nedjogging", Segment.Kind.COOLDOWN, 300, 1)
        return segments
    }
    fun strength(): List<Segment> =
        (1..3).map { n ->
            Segment("bench-$n", "Benkpress – sett $n av 3 (velg egen vekt)",
                Segment.Kind.STRENGTH, null)
        }
}
