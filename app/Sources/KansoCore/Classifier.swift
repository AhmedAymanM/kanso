import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A model's answer for an unknown type: an existing shelf, a new one (name, emoji, description) or unsure.
public struct Pick: Sendable, Equatable {
    public var folder: String
    public var name = ""
    public var emoji = ""
    public var description = ""
    /// 0...1 when the model reports how sure it is; nil when it gives no score (Apple's guided generation doesn't).
    public var confidence: Double?
    public init(folder: String, name: String = "", emoji: String = "", description: String = "", confidence: Double? = nil) {
        self.folder = folder; self.name = name; self.emoji = emoji; self.description = description; self.confidence = confidence
    }
}

/// What a model can be asked to do. A model that lacks a capability is never asked for it.
public enum ModelCapability: String, Sendable, Hashable, CaseIterable {
    case classify       // pick a shelf for an unknown file type
    case compileRules   // turn a plain-English sentence into a typed rule draft
    case ask            // the island's ask field
}

/// Whether a model can be used right now, with the plain reason when it can't.
public struct ModelAvailability: Sendable, Equatable {
    public var ready: Bool
    public var reason: String   // "Ready", or why not
    public init(ready: Bool, reason: String) { self.ready = ready; self.reason = reason }
    public static let ready = ModelAvailability(ready: true, reason: "Ready")
}

public protocol Classifier: Sendable {
    var available: Bool { get }
    /// Shown in the model picker.
    var name: String { get }
    var capabilities: Set<ModelCapability> { get }
    var availability: ModelAvailability { get }
    /// facts: metadata only. options: {shelf: description}. creating: whether "new" is allowed.
    func choose(facts: [(String, String)], options: [(String, String)], creating: Bool) async -> Pick?
}

public extension Classifier {
    // Defaults keep small conformers (tests, fakes) to `available` and `choose`.
    var name: String { "Model" }
    var capabilities: Set<ModelCapability> { [.classify] }
    var availability: ModelAvailability { available ? .ready : ModelAvailability(ready: false, reason: "Unavailable") }
}

/// No model at all: the extension table, rules and screenshot flag decide, and unknown types wait in Unsorted.
public struct RulesOnly: Classifier {
    public init() {}
    public var available: Bool { false }
    public var name: String { "Rules and extensions only" }
    public var capabilities: Set<ModelCapability> { [] }
    public var availability: ModelAvailability { ModelAvailability(ready: false, reason: "No model selected") }
    public func choose(facts: [(String, String)], options: [(String, String)], creating: Bool) async -> Pick? { nil }
}

public enum Brain {
    public static let new = "new"
    public static let unsure = "unsure"
    static let catchAll = try! NSRegularExpression(pattern: #"^((unknown|other|misc|miscellaneous|unsorted)( (files?|items?|types?))?|files?|items?)$"#, options: .caseInsensitive)

    /// What the model sees: metadata only.
    public static func facts(_ item: Item) -> [(String, String)] {
        var f = [("file name", item.name), ("type", item.isDir ? "folder" : (item.ext.isEmpty ? "unknown" : item.ext))]
        if item.screenshot { f.append(("screenshot", "yes, this is a screen capture")) }
        if let w = item.whereFrom.first { f.append(("downloaded from", w)) }
        if item.isDir, let names = try? FileManager.default.contentsOfDirectory(atPath: item.url.path) {
            f.append(("contains", names.sorted().prefix(20).joined(separator: ", ")))
        }
        return f
    }

    public static func options(_ s: Settings) -> [(String, String)] {
        // Keys is never offered: a model can't route files into the security shelf (the extension table does that).
        s.types.filter { ![Shelf.unsorted, Shelf.screenshots].contains($0.name) && Engine.automaticShelfAllowed($0.name) }.map { ($0.name, $0.description) }
    }

    public static func cleanName(_ n: String) -> String {
        let s = n.replacingOccurrences(of: #"[/:\\.]"#, with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ").prefix(30).trimmingCharacters(in: .whitespaces)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    public static func cleanEmoji(_ e: String) -> String {
        guard let first = e.split(separator: " ").first, let c = first.first, !c.isLetter, !c.isNumber else { return "📁" }
        return String(first.prefix(8))
    }

    public static func isCatchAll(_ name: String) -> Bool {
        catchAll.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }
}

/// Apple's on-device Foundation Model (macOS 26+), with guided generation constrained to the shelf names.
public struct AppleIntelligence: Classifier {
    public init() {}

    public var available: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return SystemLanguageModel.default.availability == .available }
        #endif
        return false
    }

    /// Could turning Apple Intelligence on in System Settings make it available? False before macOS 26 and on Macs that can't run it,
    /// so the UI offers no dead-end button there and says plainly that sorting works without it.
    public var canBeTurnedOn: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .unavailable(.deviceNotEligible) = SystemLanguageModel.default.availability { return false }
            return true
        }
        #endif
        return false
    }

    public var name: String { "Apple Intelligence" }
    public var capabilities: Set<ModelCapability> { [.classify, .compileRules, .ask] }
    public var availability: ModelAvailability { ModelAvailability(ready: available, reason: status) }

    public var status: String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return "Ready"
            case .unavailable(.appleIntelligenceNotEnabled): return "Turned off in System Settings"
            case .unavailable(.modelNotReady): return "Downloading"
            case .unavailable(.deviceNotEligible): return "Not supported on this Mac"
            default: return "Unavailable"
            }
        }
        #endif
        return "Needs macOS 26"
    }

    public func choose(facts: [(String, String)], options: [(String, String)], creating: Bool) async -> Pick? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let keys = options.map(\.0) + (creating ? [Brain.new] : []) + [Brain.unsure]
            let str = DynamicGenerationSchema(type: String.self)
            let pick = DynamicGenerationSchema(name: "Pick", description: "Folder choice", properties: [
                .init(name: "folder", description: "Key of the folder this file belongs in", schema: DynamicGenerationSchema(name: "Folder", anyOf: keys)),
                .init(name: "name", description: "If folder is '\(Brain.new)': a short plural folder name for this file type, like 'Keys' or '3D Models'", schema: str),
                .init(name: "emoji", description: "If folder is '\(Brain.new)': one emoji for that folder", schema: str),
                .init(name: "description", description: "If folder is '\(Brain.new)': one sentence describing the files that belong there", schema: str),
            ])
            let menu = options.map { "- \($0.0): \($0.1)" }.joined(separator: "\n")
            let newLine = creating ? "\n- \(Brain.new): a file type none of these folders covers; name a new folder for it" : ""
            let prompt = "File:\n" + facts.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
                + "\n\nFolders:\n\(menu)\(newLine)\n- \(Brain.unsure): you can't tell what kind of file this is"
            let instructions = "You sort files into folders by file type, using only their name, extension and source. "
                + "Pick an existing folder only if its description clearly covers this file type. "
                + (creating ? "If the type is recognizable but no folder covers it (calendar invites, contacts, certificates, torrents...), answer '\(Brain.new)' and name a new folder. " : "")
                + "Answer '\(Brain.unsure)' when you can't tell what kind of file it is."
            do {
                let schema = try GenerationSchema(root: pick, dependencies: [])
                let session = LanguageModelSession(instructions: instructions)
                let r = try await session.respond(to: prompt, schema: schema)
                let c = r.content
                return Pick(folder: (try? c.value(String.self, forProperty: "folder")) ?? Brain.unsure,
                            name: (try? c.value(String.self, forProperty: "name")) ?? "",
                            emoji: (try? c.value(String.self, forProperty: "emoji")) ?? "",
                            description: (try? c.value(String.self, forProperty: "description")) ?? "")
            } catch {
                return nil  // guardrail refusal, model not ready…
            }
        }
        #endif
        return nil
    }
}
