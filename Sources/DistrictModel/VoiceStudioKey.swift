import Foundation

/// The persona PATCH keys the Voice Studio owns.
///
/// ⛔ A SAVE NAMES ONLY THE KEYS THAT CHANGED, so a teammate's save of a key this screen never
/// touched is not undone. ⛔ ``modelId`` AND ``engineMix`` TRAVEL TOGETHER: the route reads a
/// mix only beside the engine id it belongs to.
public enum VoiceStudioKey: String, CaseIterable, Sendable {
    case modelId
    case voice
    case engineMix
    case preemptiveTts
    case temperature
    case bilingual
    case voiceStyle
}
