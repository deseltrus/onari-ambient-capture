import Foundation

/// Block B, half two: turn a stream of samples into the switch chain.
///
/// Pure logic, no AppKit, no clock of its own — every input is passed in. That
/// is what makes it testable without a Mac session and what let this ship
/// before the probe was wired up.
///
/// Rules, all three load-bearing for the demo:
///   1. A sample identical to the current board is NOT a switch (polling would
///      otherwise emit 150 events per minute of sitting still).
///   2. The first sample of a session emits a switch from the null origin,
///      exactly as `fixtures/events-sample.jsonl` opens.
///   3. `dwell_ms_from` is how long the PREVIOUS board was held. It is the
///      signal the consolidation leans on for "seen in context, never noted" —
///      a 25-second dwell on a LinkedIn profile with no note is the whole demo
///      beat, so this number must be real, not a placeholder.
public final class SwitchChain {
    public private(set) var seq: Int = 0
    public private(set) var current: SurfaceSample?
    private var currentSince: Date?

    /// Samples shorter than this never become their own board. Alt-tabbing
    /// through three windows to reach the fourth should not litter the graph.
    public let minimumDwell: TimeInterval

    private var pending: (sample: SurfaceSample, since: Date)?

    public init(minimumDwell: TimeInterval = 0.75) {
        self.minimumDwell = minimumDwell
    }

    /// Feed one observation. Returns a switch event when the surface actually
    /// changed and settled, nil otherwise.
    public func observe(_ sample: SurfaceSample?, at now: Date) -> SwitchEvent? {
        guard let sample else { return nil }

        // Same board as the one we are on: nothing to do, and cancel any
        // pending candidate (the user came back before it settled).
        if let current, current.boardID == sample.boardID {
            pending = nil
            return nil
        }

        // A different board than the pending candidate: restart the timer.
        if let pending, pending.sample.boardID != sample.boardID {
            self.pending = (sample, now)
            return nil
        }

        // First sighting of this candidate.
        if pending == nil {
            pending = (sample, now)
            // The very first board of a session commits immediately: there is
            // no previous surface to protect from flicker, and waiting would
            // drop the opening event of the demo.
            if current == nil {
                return commit(sample, at: now)
            }
            return nil
        }

        // The candidate has been held long enough. Commit it.
        if let pending, now.timeIntervalSince(pending.since) >= minimumDwell {
            return commit(pending.sample, at: now)
        }

        return nil
    }

    private func commit(_ sample: SurfaceSample, at now: Date) -> SwitchEvent {
        seq += 1

        let from: SurfaceRef
        var dwell: Int?
        if let current {
            from = SurfaceRef(app: current.app, title: current.title, boardID: current.boardID)
            if let since = currentSince {
                dwell = max(0, Int(now.timeIntervalSince(since) * 1000.0))
            }
        } else {
            from = .origin
            dwell = nil
        }

        let event = SwitchEvent(
            t: Contract.stamp(now),
            seq: seq,
            from: from,
            to: SurfaceRef(app: sample.app, title: sample.title, boardID: sample.boardID),
            dwellMsFrom: dwell
        )

        current = sample
        currentSince = now
        pending = nil
        return event
    }

    /// The board a note should bind to right now. Notes attach to the
    /// COMMITTED board, never to a pending candidate — a note spoken during a
    /// half-second flick belongs to the surface you were actually working in.
    public var noteTarget: SurfaceSample? { current }
}
