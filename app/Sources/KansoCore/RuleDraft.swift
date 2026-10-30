import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Plain-English rules. A model turns one sentence into a typed draft; plain code then validates it against the sentence and the
// closed lists before the user sees it. The draft is never saved by itself: the user previews it ("What would match") and presses Save.
//
// Invariants (docs/research/panel/security.md):
// - the model's output is a choice from closed sets or typed strings, never a path, glob, command or URL;
// - every condition value must literally occur in the user's sentence, and glob characters in it are escaped;
// - the destination is an existing shelf from the closed list, or a new shelf name that passes `Engine.automaticShelfAllowed`
//   (never Manual Shelves, Recents, My Shelves, Keys, Duplicates, Unsorted, Screenshots or the Trash).

/// What the model returns, unvalidated.
public struct RawRuleDraft: Sendable, Equatable {
    public struct RawCondition: Sendable, Equatable {
        public var field: String   // name, ext, from or size
        public var value: String
        public init(field: String, value: String) { self.field = field; self.value = value }
    }
    public var matchAny = false
    public var conditions: [RawCondition]
    public var destination: String   // an existing shelf name, or "new"
    public var newName = ""
    public var newEmoji = ""
    public var newDescription = ""
    public init(matchAny: Bool = false, conditions: [RawCondition], destination: String, newName: String = "", newEmoji: String = "", newDescription: String = "") {
        self.matchAny = matchAny; self.conditions = conditions; self.destination = destination
        self.newName = newName; self.newEmoji = newEmoji; self.newDescription = newDescription
    }
}

/// A shelf the draft would create on Save (inside My Shelves, created on its first move).
public struct NewShelf: Sendable, Equatable {
    public var name: String
    public var emoji: String
    public var description: String
}

/// A validated draft: an editable rule plus the shelf it would create. Not saved yet.
public struct RuleDraft: Sendable, Equatable {
    public var rule: Rule
    public var newShelf: NewShelf?
}

public enum RuleDraftError: Error, Equatable, Sendable {
    case unavailable(String)
    case emptySentence
    case notUnderstood        // the model gave nothing usable
    case noValidConditions    // nothing the sentence actually said survived validation
    case badDestination       // not an allowed shelf
    public var message: String {
        switch self {
        case .unavailable(let why): return why
        case .emptySentence: return "Type what the rule should do, like “Move invoices from Stripe to Invoices”."
        case .notUnderstood: return "Kanso couldn't turn that into a rule. Try naming what to match and a shelf."
        case .noValidConditions: return "Kanso couldn't find anything in that sentence to match files by. Name a word in the file, an extension or a site."
        case .badDestination: return "That shelf isn't allowed for a rule made by a model. Pick one of your shelves, or name a new one."
        }
    }
}

/// The model side, behind a protocol so tests use a fake.
public protocol RuleCompiler: Sendable {
    /// `shelves` is the closed list of existing shelves the model may name.
    func compile(_ sentence: String, shelves: [String]) async -> RawRuleDraft?
}

public enum RuleDrafting {
    static let maxConditions = 4
    static let reservedNames: Set<String> = ["trash", "bin", "unsorted", "screenshots", "duplicates", "keys"]

    /// Why plain-English rules can't be used right now; nil when they can.
    public static func unavailableReason(_ settings: Settings, model: Classifier) -> String? {
        if settings.modelChoice == .rulesOnly { return "Plain-English rules need a model. Choose Apple Intelligence in Privacy & AI." }
        let a = model.availability
        if !a.ready { return "Apple Intelligence isn't ready: \(a.reason)." }
        if !model.capabilities.contains(.compileRules) { return "The selected model can't write rules." }
        return nil
    }

    /// Existing shelves a model-made rule may name.
    public static func shelves(_ settings: Settings) -> [String] {
        settings.types.map(\.name).filter { allowedShelf($0) }
    }

    static func allowedShelf(_ name: String) -> Bool {
        Engine.automaticShelfAllowed(name) && !reservedNames.contains(Engine.fold(name))
    }

    static func clean(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.properties.generalCategory != .control && $0.properties.generalCategory != .format }))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Asks the compiler, then validates. Nothing is saved.
    public static func draft(_ sentence: String, settings: Settings, model: Classifier, compiler: RuleCompiler) async -> Result<RuleDraft, RuleDraftError> {
        if let why = unavailableReason(settings, model: model) { return .failure(.unavailable(why)) }
        let text = String(clean(sentence).prefix(300))
        guard !text.isEmpty else { return .failure(.emptySentence) }
        guard let raw = await compiler.compile(text, shelves: shelves(settings)) else { return .failure(.notUnderstood) }
        return validate(raw, sentence: text, settings: settings)
    }

    public static func validate(_ raw: RawRuleDraft, sentence: String, settings: Settings) -> Result<RuleDraft, RuleDraftError> {
        let said = SentenceTokens(sentence)
        var conditions: [Condition] = []
        for rc in raw.conditions.prefix(maxConditions) {
            guard let field = Condition.Field(rawValue: rc.field.lowercased()) else { continue }
            let rawValue = clean(rc.value)
            guard !rawValue.isEmpty, rawValue.count <= 80 else { continue }
            // Literal rule: the model may only use whole words the user wrote (not a letter, a dot or a digit inside another word).
            switch field {
            case .name: guard meaningful(rawValue), said.contains(rawValue, stem: true) else { continue }
            case .from: guard meaningful(rawValue), said.contains(rawValue, stem: false) else { continue }
            case .ext:
                let parts = rawValue.split(whereSeparator: { " ,.".contains($0) }).map(String.init)
                guard !parts.isEmpty, parts.allSatisfy({ meaningful($0) && said.contains($0, stem: false) }) else { continue }
            case .size: guard said.sizes.contains(where: { sizePairs(rawValue) == [$0] }) else { continue }
            }
            var c: Condition?
            switch field {
            case .name:
                // Path separators can't occur in a name; drop them. Glob characters are escaped so the value only ever matches literally.
                let v = rawValue.replacingOccurrences(of: "/", with: " ").replacingOccurrences(of: "\\", with: " ")
                let name = clean(v)
                if !name.isEmpty { c = Condition(.name, "*" + escapeGlob(name) + "*") }
            case .ext:
                let tokens = rawValue.lowercased().split(whereSeparator: { " ,.".contains($0) })
                    .map { String($0.filter { $0.isLetter || $0.isNumber }) }.filter { !$0.isEmpty && $0.count <= 12 }
                if !tokens.isEmpty { c = Condition(.ext, tokens.joined(separator: " ")) }
            case .from:
                let v = String(rawValue.filter { $0.isLetter || $0.isNumber || ".-_".contains($0) })
                if !v.isEmpty { c = Condition(.from, v) }
            case .size:
                if let bytes = Engine.parseSize(rawValue), bytes > 0 { c = Condition(.size, rawValue) }
            }
            if let c, !conditions.contains(c) { conditions.append(c) }
        }
        guard !conditions.isEmpty else { return .failure(.noValidConditions) }

        // Destination: the closed list, or a new shelf.
        let choice = clean(raw.destination)
        var dest = ""
        var newShelf: NewShelf?
        if let t = settings.types.first(where: { $0.name == choice }) {
            guard allowedShelf(t.name) else { return .failure(.badDestination) }
            dest = t.name
        } else if choice.lowercased() == Brain.new {
            let name = Brain.cleanName(clean(raw.newName))
            guard !name.isEmpty, !Brain.isCatchAll(name), allowedShelf(name) else { return .failure(.badDestination) }
            if let existing = settings.types.first(where: { Engine.fold($0.name) == Engine.fold(name) }) {
                guard allowedShelf(existing.name) else { return .failure(.badDestination) }
                dest = existing.name
            } else {
                // A shelf the model invents must be one the user named.
                guard meaningful(name), said.contains(name, stem: true) else { return .failure(.badDestination) }
                dest = name
                newShelf = NewShelf(name: name, emoji: Brain.cleanEmoji(raw.newEmoji),
                                    description: String(clean(raw.newDescription).prefix(200)))
            }
        } else {
            return .failure(.badDestination)
        }
        var rule = Rule(conditions, dest: dest)
        rule.matchAny = raw.matchAny && conditions.count > 1 && said.split.contains("or")
        rule.automatic = true   // made by a model: its destination stays a shelf inside My Shelves
        return .success(RuleDraft(rule: rule, newShelf: newShelf))
    }

    /// At least two characters, at least one a letter or digit.
    static func meaningful(_ v: String) -> Bool {
        v.count >= 2 && v.contains { $0.isLetter || $0.isNumber }
    }

    /// The size ("2 GB") as number and unit tokens, like ["2|gb"].
    static func sizePairs(_ text: String) -> [String] {
        let t = Engine.fold(text)
        guard let re = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}.])(\d+(?:\.\d+)?)\s*([a-z]+)(?![\p{L}\p{N}])"#) else { return [] }
        let ns = t as NSString
        return re.matches(in: t, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) + "|" + ns.substring(with: $0.range(at: 2)) }
    }

    /// The sentence as whole words. `full` keeps dots inside a word ("stripe.com"); `split` breaks on everything that isn't a letter or digit.
    struct SentenceTokens {
        var full: [String], split: [String], sizes: [String]
        init(_ text: String) {
            let f = Engine.fold(text)
            full = SentenceTokens.full(f); split = SentenceTokens.split(f)
            sizes = RuleDrafting.sizePairs(text).filter { p in
                let pair = p.split(separator: "|").map(String.init)
                return Engine.parseSize(pair[0] + pair[1]) != nil
            }
        }
        static func full(_ f: String) -> [String] {
            f.split(whereSeparator: { !($0.isLetter || $0.isNumber || ".-_".contains($0)) })
                .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".-_")) }.filter { !$0.isEmpty }
        }
        static func split(_ f: String) -> [String] { f.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init) }
        /// `stem`: a plural matches its singular ("invoice" in "invoices").
        func contains(_ value: String, stem: Bool) -> Bool {
            let f = Engine.fold(value)
            let m: (String) -> String = { stem && $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
            func has(_ v: [String], _ s: [String]) -> Bool {
                let v = v.map(m), s = s.map(m)
                guard !v.isEmpty, v.count <= s.count else { return false }
                return (0...(s.count - v.count)).contains { Array(s[$0..<($0 + v.count)]) == v }
            }
            return has(SentenceTokens.full(f), full) || has(SentenceTokens.split(f), split)
        }
    }

    /// fnmatch metacharacters made literal.
    static func escapeGlob(_ s: String) -> String {
        var out = ""
        for ch in s { if "*?[]\\".contains(ch) { out.append("\\") }; out.append(ch) }
        return out
    }
}

extension Engine {
    /// Saves a draft the user approved: creates its shelf type if it is new (still checked), then appends the rule.
    /// The caller passes a draft the user has seen; this re-checks the destination anyway.
    @discardableResult
    public func saveDraft(_ rule: Rule, newShelf: NewShelf?) -> Bool {
        var rule = rule
        guard !rule.automatic || RuleDrafting.allowedShelf(rule.dest) else { return false }
        store.update { s in
            if let n = newShelf, n.name == rule.dest, s.type(named: n.name) == nil, RuleDrafting.allowedShelf(n.name) {
                let at = s.types.firstIndex { $0.name == Shelf.unsorted } ?? s.types.endIndex
                s.types.insert(FileType(n.name, n.emoji, n.description, []), at: at)
            }
            rule.builtIn = false
            s.rules.append(rule)
        }
        return true
    }
}

extension AppleIntelligence: RuleCompiler {
    /// Guided generation into a closed schema: field and destination are enums, values are plain strings that
    /// `RuleDrafting.validate` checks against the sentence.
    public func compile(_ sentence: String, shelves: [String]) async -> RawRuleDraft? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), available {
            let str = DynamicGenerationSchema(type: String.self)
            let condition = DynamicGenerationSchema(name: "Condition", description: "One test on a file", properties: [
                .init(name: "field", description: "name: a word in the file name. ext: file extension without the dot. from: a website the file was downloaded from. size: a minimum size like 2 GB", schema: DynamicGenerationSchema(name: "Field", anyOf: ["name", "ext", "from", "size"])),
                .init(name: "value", description: "The word, extension, site or size, copied from the request", schema: str),
            ])
            let root = DynamicGenerationSchema(name: "RuleDraft", description: "A file sorting rule", properties: [
                .init(name: "match", description: "all: every condition must hold. any: one is enough", schema: DynamicGenerationSchema(name: "Match", anyOf: ["all", "any"])),
                .init(name: "conditions", description: "What identifies the files", schema: DynamicGenerationSchema(arrayOf: condition, minimumElements: 1, maximumElements: RuleDrafting.maxConditions)),
                .init(name: "destination", description: "The shelf the files go to, or '\(Brain.new)' for a shelf that does not exist yet", schema: DynamicGenerationSchema(name: "Destination", anyOf: shelves + [Brain.new])),
                .init(name: "newName", description: "If destination is '\(Brain.new)': a short plural shelf name taken from the request", schema: str),
                .init(name: "newEmoji", description: "If destination is '\(Brain.new)': one emoji for it", schema: str),
                .init(name: "newDescription", description: "If destination is '\(Brain.new)': one sentence about the files", schema: str),
            ])
            let instructions = "You turn one request into a file sorting rule. Use only words that appear in the request. "
                + "Never invent paths, folders or commands. Choose the destination from the given shelves; answer '\(Brain.new)' only when the request names a shelf that is not in the list."
            let prompt = "Shelves: \(shelves.joined(separator: ", "))\n\nRequest: \(sentence)"
            do {
                let schema = try GenerationSchema(root: root, dependencies: [])
                let r = try await LanguageModelSession(instructions: instructions).respond(to: prompt, schema: schema)
                let c = r.content
                let parts = (try? c.value([GeneratedContent].self, forProperty: "conditions")) ?? []
                let conditions = parts.map {
                    RawRuleDraft.RawCondition(field: (try? $0.value(String.self, forProperty: "field")) ?? "", value: (try? $0.value(String.self, forProperty: "value")) ?? "")
                }
                return RawRuleDraft(matchAny: ((try? c.value(String.self, forProperty: "match")) ?? "all") == "any", conditions: conditions,
                                    destination: (try? c.value(String.self, forProperty: "destination")) ?? "",
                                    newName: (try? c.value(String.self, forProperty: "newName")) ?? "",
                                    newEmoji: (try? c.value(String.self, forProperty: "newEmoji")) ?? "",
                                    newDescription: (try? c.value(String.self, forProperty: "newDescription")) ?? "")
            } catch { return nil }
        }
        #endif
        return nil
    }
}
