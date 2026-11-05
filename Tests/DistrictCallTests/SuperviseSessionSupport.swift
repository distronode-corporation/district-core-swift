import DistrictCall

extension SuperviseSession {
    /// An engine event from the CURRENT engine of `leg`, stamped with the session's own
    /// generation, which is what the app does for the engine it last built. A test of a
    /// stale engine sends ``SuperviseEvent/engine(_:generation:_:)`` with the old number.
    @discardableResult
    mutating func handle(_ leg: SuperviseLeg, _ event: CallEngineEvent) -> [SuperviseCommand] {
        handle(.engine(leg, generation: state.generation, event))
    }
}
