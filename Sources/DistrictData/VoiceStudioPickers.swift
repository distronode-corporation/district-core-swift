import DistrictModel
import Foundation

/// One row of a Studio picker: a value to hold and the words to show for it.
public struct VoiceStudioPickerOption: Equatable, Sendable, Identifiable {
    public let value: String
    public let label: String
    /// The channel badge's text, for a model; nil for a vendor or a location.
    public let channelLabel: String?
    /// The Preview note, for a Preview model.
    public let note: String?

    public var id: String {
        value
    }

    public init(value: String, label: String, channelLabel: String? = nil, note: String? = nil) {
        self.value = value
        self.label = label
        self.channelLabel = channelLabel
        self.note = note
    }

    /// "Gemini 3.8 Flash · Latest": the channel in TEXT as well as in a badge, and a Preview
    /// model's note.
    public var text: String {
        [label, channelLabel, note].compactMap(\.self).joined(separator: " · ")
    }

    /// What a closed picker shows: the held option, or the held value itself when it is not
    /// listed (a stored choice the list no longer carries is still what the workspace runs).
    public static func summary(of options: [VoiceStudioPickerOption], selected: String?) -> String {
        options.first { $0.value == selected }?.text ?? selected ?? ""
    }
}

/// What each leg's pickers offer.
///
/// ⛔ THE WEB'S PICKER RULE: a model is listed when it is `offered` to this account in this
/// region OR it is the one held now (a stored choice must still show as selected). Ear and
/// mouth models are filtered by the persona language (`forLanguage`), or by `forBilingual`
/// while the Studio holds bilingual on. A vendor appears when at least one of its models is
/// listable.
///
/// ⛔ EVERY LIST IS THE SERVICE'S. Nothing here names a model.
public enum VoiceStudioPickers {
    private static let previewChannel = "preview"

    public static func earVendors(
        _ mix: EngineMix,
        bilingual: Bool,
        in studio: VoiceStudioResponse
    ) -> [VoiceStudioPickerOption] {
        vendors(studio.catalog.stt.filter { listable($0, mix: mix, bilingual: bilingual) }.map {
            VoiceStudioPickerOption(value: $0.provider, label: $0.providerLabel)
        })
    }

    public static func earModels(
        _ mix: EngineMix,
        bilingual: Bool,
        in studio: VoiceStudioResponse
    ) -> [VoiceStudioPickerOption] {
        studio.catalog.stt
            .filter { $0.provider == mix.stt.provider && listable($0, mix: mix, bilingual: bilingual) }
            .map { model($0.model, $0.label, $0.channel, $0.channelLabel, studio) }
    }

    public static func brainModels(_ mix: EngineMix, in studio: VoiceStudioResponse) -> [VoiceStudioPickerOption] {
        studio.catalog.llm
            .filter { $0.offered || $0.model == mix.llm.model }
            .map { model($0.model, $0.label, $0.channel, $0.channelLabel, studio) }
    }

    public static func voiceVendors(
        _ mix: EngineMix,
        bilingual: Bool,
        in studio: VoiceStudioResponse
    ) -> [VoiceStudioPickerOption] {
        vendors(studio.catalog.tts.filter { listable($0, mix: mix, bilingual: bilingual) }.map {
            VoiceStudioPickerOption(value: $0.provider, label: $0.providerLabel)
        })
    }

    public static func voiceModels(
        _ mix: EngineMix,
        bilingual: Bool,
        in studio: VoiceStudioResponse
    ) -> [VoiceStudioPickerOption] {
        studio.catalog.tts
            .filter { $0.provider == mix.tts.provider && listable($0, mix: mix, bilingual: bilingual) }
            .map { model($0.model, $0.label, $0.channel, $0.channelLabel, studio) }
    }

    /// The held leg's locations; empty for a vendor endpoint, and for turn-taking.
    public static func locations(
        for leg: VoiceStudioLeg,
        mix: EngineMix,
        in studio: VoiceStudioResponse
    ) -> [VoiceStudioPickerOption] {
        let catalog = studio.catalog
        let locations: [VoiceStudioLocation] = switch leg {
        case .stt:
            catalog.stt.first { $0.provider == mix.stt.provider && $0.model == mix.stt.model }?.locations ?? []
        case .llm:
            catalog.llm.first { $0.model == mix.llm.model }?.locations ?? []
        case .tts:
            catalog.tts.first { $0.provider == mix.tts.provider && $0.model == mix.tts.model }?.locations ?? []
        case .turn, .realtime:
            []
        }
        return locations.map { VoiceStudioPickerOption(value: $0.value, label: $0.label) }
    }

    /// The location a leg holds, or the list's first entry when it holds none (which is what
    /// the model runs at).
    public static func heldLocation(
        for leg: VoiceStudioLeg,
        mix: EngineMix,
        options: [VoiceStudioPickerOption]
    ) -> String? {
        let held: String? = switch leg {
        case .stt: mix.stt.location
        case .llm: mix.llm.location
        case .tts: mix.tts.location
        case .turn, .realtime: nil
        }
        return held ?? options.first?.value
    }

    /// The realtime models a workspace may pick: offered and not refused in its region, plus
    /// the one held now.
    public static func realtimeModels(modelId: String, in studio: VoiceStudioResponse) -> [VoiceStudioPickerOption] {
        studio.catalog.realtime
            .filter { ($0.offered && !$0.refusedInRegion) || $0.model == modelId }
            .map {
                VoiceStudioPickerOption(value: $0.model, label: $0.label, channelLabel: $0.channelLabel, note: $0.note)
            }
    }

    // MARK: - Internals

    private static func listable(_ model: VoiceStudioSttModel, mix: EngineMix, bilingual: Bool) -> Bool {
        (model.provider == mix.stt.provider && model.model == mix.stt.model)
            || (model.offered && (bilingual ? model.forBilingual : model.forLanguage))
    }

    private static func listable(_ model: VoiceStudioTtsModel, mix: EngineMix, bilingual: Bool) -> Bool {
        (model.provider == mix.tts.provider && model.model == mix.tts.model)
            || (model.offered && (bilingual ? model.forBilingual : model.forLanguage))
    }

    /// One row per vendor, in the order the vendor first appears.
    private static func vendors(_ rows: [VoiceStudioPickerOption]) -> [VoiceStudioPickerOption] {
        var seen = Set<String>()
        return rows.filter { seen.insert($0.value).inserted }
    }

    private static func model(
        _ value: String,
        _ label: String,
        _ channel: String,
        _ channelLabel: String,
        _ studio: VoiceStudioResponse
    ) -> VoiceStudioPickerOption {
        VoiceStudioPickerOption(
            value: value,
            label: label,
            channelLabel: channelLabel,
            note: channel == previewChannel ? studio.labels.previewNote : nil
        )
    }
}
