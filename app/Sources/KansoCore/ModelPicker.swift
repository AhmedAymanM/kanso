import Foundation

/// One row of the local model picker on Privacy & AI.
public struct ModelOption: Identifiable, Sendable, Equatable {
    public var choice: ModelChoice?   // nil: not selectable (Kanso Local)
    public var name: String
    public var status: String         // honest, plain: "Ready", why it can't be used, "Not available yet"
    public var selectable: Bool
    public var selected: Bool
    public var id: String { name }
}

public enum ModelPicker {
    /// Apple Intelligence (selectable only when the system says it is ready), Rules and extensions only (always),
    /// and Kanso Local (shown, disabled: no model has earned its place in the benchmark yet).
    public static func options(_ settings: Settings, apple: Classifier) -> [ModelOption] {
        let a = apple.availability
        return [
            ModelOption(choice: .appleIntelligence, name: apple.name, status: a.reason, selectable: a.ready, selected: settings.modelChoice == .appleIntelligence),
            ModelOption(choice: .rulesOnly, name: RulesOnly().name, status: "Always available. Known types sort by extension; anything else waits in Unsorted.", selectable: true, selected: settings.modelChoice == .rulesOnly),
            ModelOption(choice: nil, name: "Kanso Local", status: "Not available yet", selectable: false, selected: false),
        ]
    }

    /// The classifier the engine should use for this setting.
    public static func classifier(_ settings: Settings, apple: Classifier) -> Classifier {
        settings.modelChoice == .rulesOnly ? RulesOnly() : apple
    }
}
