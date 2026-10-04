import DistrictModel
import Foundation

/// The Voice Studio, loaded, with what it holds now: the state every screen of the Studio is
/// drawn from, and every edit's transition.
///
/// ⛔ EVERY TRANSITION IS A PURE FUNCTION HERE, so a screen model only routes calls and every
/// rule is tested without a UI. ⚠️ A transition during a save is refused by the screen model,
/// not here: an edit landing mid-request would change the state the request was built from.
public struct VoiceStudioSession: Equatable, Sendable {
    public let studio: VoiceStudioResponse
    public private(set) var held: VoiceStudioState
    /// `stable` or `latest`.
    public private(set) var tier: String
    /// The recipe the held engine started from ("Based on Fastest, 2 changes").
    public private(set) var baseRecipe: String
    /// The engine as that recipe applied it, for the change count and Reset.
    public private(set) var baseEngine: VoiceStudioEngine
    /// The leg the editor is open on.
    public private(set) var leg: VoiceStudioLeg

    /// The Studio as the service describes the saved persona.
    public init(studio: VoiceStudioResponse) {
        let held = VoiceStudioState(current: studio.current)
        self.studio = studio
        self.held = held
        tier = studio.current.tier
        baseRecipe = studio.current.recipeId
        baseEngine = held.engine
        leg = Self.leg(for: held.engine, from: .stt)
    }

    // MARK: - What it says

    public var savedEngine: VoiceStudioEngine {
        VoiceStudioEngine(chain: studio.current.chain)
    }

    /// What the persona saves as now: the baseline every edit is diffed against.
    public var savedFields: VoiceStudioFields {
        studio.current.fields
    }

    /// What the held state would save as.
    public var heldFields: VoiceStudioFields {
        VoiceStudioRules.fields(of: held, presets: studio.catalog.presets, language: studio.language)
    }

    /// The keys a save would send.
    public var pending: Set<VoiceStudioKey> {
        VoiceStudioRules.changedKeys(saved: savedFields, current: heldFields)
    }

    public var isDirty: Bool {
        !pending.isEmpty
    }

    /// How many settings differ from the recipe the held engine started from.
    public var changes: Int {
        VoiceStudioRules.countChanges(base: baseEngine, current: held.engine)
    }

    /// This tier's tiles, in the service's order.
    public var tiles: [VoiceStudioRecipe] {
        VoiceStudioRecipes.tiles(studio, tier: tier)
    }

    /// The name of the recipe the held engine started from, as this tier calls it; `""` when
    /// this tier has no such tile.
    public var baseName: String {
        tiles.first { $0.id == baseRecipe }?.name ?? ""
    }

    /// "Based on Fastest, 2 changes.", from the service's templates; nil when the held engine
    /// IS its recipe, or this tier has no such tile.
    public var basedOn: String? {
        VoiceStudioText.basedOn(recipe: baseName, changes: changes, labels: studio.labels)
    }

    // MARK: - Transitions

    /// Stable or Latest. The chosen recipe is re-applied on the new tier; "Your chain" is not a
    /// tier's, and a recipe the other tier lacks leaves the held engine alone.
    public func withTier(_ next: String) -> VoiceStudioSession {
        var moved = self
        moved.tier = next
        return baseRecipe == VoiceStudioRecipes.custom ? moved : moved.withRecipe(baseRecipe)
    }

    /// Apply one of this tier's tiles: its engine and its bilingual flag.
    public func withRecipe(_ id: String) -> VoiceStudioSession {
        guard let recipe = tiles.first(where: { $0.id == id }) else { return self }
        let engine = VoiceStudioRecipes.applied(recipe, saved: savedEngine, current: held.engine, studio: studio)
        var next = self
        next.held.engine = engine
        next.held.bilingual = recipe.bilingual
        next.baseRecipe = id
        next.baseEngine = engine
        next.leg = Self.leg(for: engine, from: leg)
        return next
    }

    /// Back to the engine the recipe applied.
    public func withReset() -> VoiceStudioSession {
        var state = held
        state.engine = baseEngine
        return withHeld(state)
    }

    /// Which leg the editor shows. ⚠️ Not an edit: choosing which leg to look at is allowed
    /// while a save is in the air.
    public func withLeg(_ next: VoiceStudioLeg) -> VoiceStudioSession {
        var moved = self
        moved.leg = Self.leg(for: held.engine, from: next)
        return moved
    }

    /// A chain edit. ⚠️ A no-op on a realtime engine, which has no mix.
    public func withMix(_ transform: (EngineMix) -> EngineMix) -> VoiceStudioSession {
        guard case let .chained(mix) = held.engine else { return self }
        var state = held
        state.engine = .chained(transform(mix))
        return withHeld(state)
    }

    public func withHeld(_ next: VoiceStudioState) -> VoiceStudioSession {
        var moved = self
        moved.held = next
        moved.leg = Self.leg(for: next.engine, from: leg)
        return moved
    }

    /// A realtime engine has one block; a chain opens on the leg it was on, or the ear.
    private static func leg(for engine: VoiceStudioEngine, from leg: VoiceStudioLeg) -> VoiceStudioLeg {
        if engine.mix == nil {
            return .realtime
        }
        return leg == .realtime ? .stt : leg
    }
}
