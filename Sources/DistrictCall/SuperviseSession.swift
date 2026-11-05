import DistrictModel

/// Live supervision of one call: listen in, take over, hand back.
/// `idle → requestingListen → joiningListen → listening → requestingTakeover →
/// joiningTakeover → takenOver`, back to `idle` on stop or hand back, and `over` when the
/// call itself ends.
///
/// ⛔ A PURE REDUCER WITH NO CLOCK, NO TASK AND NO ACTOR, like ``SoftphoneSession``: every
/// transition is a synchronous function of a state and an event, tested on Linux with no
/// media server. The app runs the commands: it calls the two routes, builds one engine
/// per leg, and on iOS keeps CallKit in step.
///
/// ⛔ THE WEBSITE'S ORDER, ENFORCED HERE RATHER THAN IN TWO VIEW MODELS
/// (`useLiveDashboard.ts`, `takeoverAction`): the takeover credential is fetched WHILE
/// STILL LISTENING, so a refusal leaves the person listening; only a grant leaves the
/// listen room, and the coach room is joined after it. A coach room that cannot be
/// joined leaves NO half-joined leg: the person is out of the call and told why.
///
/// ⛔ HAND BACK IS LEAVING THE ROOM. The coach token cannot rewrite its own metadata to
/// drop back to whisper, and the assistant resumes when the last coach leaves, so
/// ``SuperviseEvent/stopPressed`` is both Stop listening and Hand back.
///
/// ⚠️ NOT TERMINAL ON STOP, unlike ``SoftphoneSession``: a person may stop listening and
/// listen again, each time on a fresh engine. Only ``SupervisePhase/over`` is terminal.
public struct SuperviseSession: Sendable, Equatable {
    public private(set) var state: SuperviseState

    public init(callId: String, role: WorkspaceRole?) {
        state = SuperviseState(callId: callId, role: role)
    }

    /// Apply one event and return what the app must do, in order.
    @discardableResult
    public mutating func handle(_ event: SuperviseEvent) -> [SuperviseCommand] {
        let outcome = Self.reduce(state, event)
        state = outcome.state
        return outcome.commands
    }

    typealias Outcome = (state: SuperviseState, commands: [SuperviseCommand])

    /// The reducer. Pure, total, and the only place a phase changes.
    public static func reduce(_ state: SuperviseState, _ event: SuperviseEvent) -> (
        state: SuperviseState, commands: [SuperviseCommand]
    ) {
        if state.phase == .over {
            return (state, [])
        }
        switch event {
        case .whisperSent:
            var next = state
            next.receipt = nil
            return (next, [])
        case let .whisperReceipt(receipt):
            var next = state
            next.receipt = receipt
            return (next, [])
        case .callEnded:
            return end(state, at: .over, problem: nil, report: state.phase != .idle)
        case let .engine(leg, event):
            // ⛔ AN EVENT FROM A LEG THAT IS NOT THE CURRENT ONE IS DROPPED. See ``SuperviseLeg``.
            guard leg == state.leg else { return (state, []) }
            return reduceEngine(state, event)
        case .speakerToggled:
            return toggleSpeaker(state)
        default:
            return reducePress(state, event)
        }
    }

    /// The person's presses and the two routes' answers.
    private static func reducePress(_ state: SuperviseState, _ event: SuperviseEvent) -> Outcome {
        switch (state.phase, event) {
        case (.idle, .listenPressed) where state.mayListen:
            var next = state
            next.phase = .requestingListen
            next.problem = nil
            return (next, [.requestListen])
        case let (.requestingListen, .listenGranted(url, token)):
            var next = state
            next.phase = .joiningListen
            next.leg = .listen
            next.media = SuperviseState.listenMedia()
            return (next, [.join(.listen, url: url, token: token)])
        case let (.requestingListen, .listenRefused(error)):
            // ⛔ REPORTED: the OS already holds the call the person started.
            return end(state, at: .idle, problem: .listenRefused(error), report: true)
        case (.listening, .takeOverPressed) where state.mayTakeOver:
            var next = state
            next.phase = .requestingTakeover
            next.problem = nil
            return (next, [.requestTakeover])
        case let (.requestingTakeover, .takeoverGranted(url, token)):
            var next = state
            next.phase = .joiningTakeover
            next.leg = .takeover
            var media = SuperviseState.listenMedia()
            media.speakerRequested = state.media.speakerRequested
            next.media = media
            return (next, [.engine(.listen, .disconnect), .join(.takeover, url: url, token: token)])
        case let (.requestingTakeover, .takeoverRefused(error)):
            // ⛔ STILL LISTENING: nothing was torn down, and nothing is.
            var next = state
            next.phase = .listening
            next.problem = .takeoverRefused(error)
            return (next, [])
        case (.takenOver, .muteToggled):
            return (state, [.engine(.takeover, state.media.muteToggleCommand())])
        case (.requestingListen, .stopPressed), (.joiningListen, .stopPressed), (.listening, .stopPressed),
             (.requestingTakeover, .stopPressed), (.joiningTakeover, .stopPressed), (.takenOver, .stopPressed):
            // ⛔ NO REPORT: CallKit performed this ending. A grant that answers after it is
            // absorbed by `idle`, so no engine is built for a person who left.
            return end(state, at: .idle, problem: nil, report: false)
        default:
            // ⚠️ DROPPED RATHER THAN TRAPPED: a late answer or a stale tap against a phase
            // that has moved on is ordinary, and a viewer's Take over is never offered.
            return (state, [])
        }
    }

    private static func reduceEngine(_ state: SuperviseState, _ event: CallEngineEvent) -> Outcome {
        var next = state
        next.media.apply(event)
        switch (state.phase, event) {
        case (.joiningListen, .connected):
            next.phase = .listening
            return (next, [])
        case (.joiningTakeover, .connected):
            next.phase = .takenOver
            // ⛔ THE ONE PLACE THIS SESSION OPENS THE MICROPHONE.
            return (next, [.engine(.takeover, .setMuted(false))])
        case let (.joiningListen, .failed(message)):
            return end(state, at: .idle, problem: .listenFailed(message: message), report: true)
        case let (.joiningListen, .disconnected(reason)):
            return end(state, at: .idle, problem: .listenFailed(message: reason), report: true)
        case let (.joiningTakeover, .failed(message)):
            return end(state, at: .idle, problem: .takeoverJoinFailed(message: message), report: true)
        case let (.joiningTakeover, .disconnected(reason)):
            return end(state, at: .idle, problem: .takeoverJoinFailed(message: reason), report: true)
        case let (.listening, .failed(reason)), let (.requestingTakeover, .failed(reason)),
             let (.listening, .disconnected(reason)), let (.requestingTakeover, .disconnected(reason)):
            return end(state, at: .idle, problem: .listenDropped(reason: reason), report: true)
        case let (.takenOver, .failed(reason)), let (.takenOver, .disconnected(reason)):
            return end(state, at: .idle, problem: .takeoverDropped(reason: reason), report: true)
        case (.listening, .participantLeft), (.requestingTakeover, .participantLeft), (.takenOver, .participantLeft):
            // ⛔ THE ROOM EMPTYING IS THE CALL ENDING: the caller and the assistant are both
            // gone. A leave that still leaves someone (a second supervisor) is not.
            guard next.media.remoteParticipants == 0 else { return (next, []) }
            return end(next, at: .over, problem: nil, report: true)
        default:
            return (next, [])
        }
    }

    private static func toggleSpeaker(_ state: SuperviseState) -> Outcome {
        guard let leg = state.leg else { return (state, []) }
        var next = state
        // ⚠️ Bound before the tuple, for the reason ``SoftphoneSession`` gives.
        let command = next.media.toggleSpeaker()
        return (next, [.engine(leg, command)])
    }

    /// The one exit from a room. ⛔ Exactly one disconnect, for the leg that exists.
    ///
    /// - Parameter report: whether the OS must be told. ⛔ False only for an ending CallKit
    ///   performed itself (``SuperviseEvent/stopPressed``) or one where it holds nothing
    ///   (the call ending while the person was not in it).
    static func end(
        _ state: SuperviseState,
        at phase: SupervisePhase,
        problem: SuperviseProblem?,
        report: Bool
    ) -> Outcome {
        var next = state
        next.phase = phase
        next.problem = problem
        next.leg = nil
        next.media = SuperviseState.listenMedia()
        var commands: [SuperviseCommand] = report ? [.reportCallEnded] : []
        if let leg = state.leg {
            commands.append(.engine(leg, .disconnect))
        }
        return (next, commands)
    }
}
