import KansoCore
import SwiftUI

// The feature pages of the App window: Showcase banner → Feature card → option sections (DESIGN_SYSTEM.md "Settings page rules").

/// Banner in the feature's pastel: big icon, one headline, a demo line and a "How it works" play button.
/// Playing walks the demo line one step at a time, the way the file travels.
struct Showcase: View {
    var tint: Tint
    var icon: String
    var art: Illustration.Kind? = nil
    var headline: String
    var demo: String
    @State private var shown = Int.max
    @State private var playing = false

    var steps: [String] { demo.components(separatedBy: " → ") }

    var body: some View {
        HStack(spacing: 28) {
            if let art { Illustration(kind: art, tint: tint) }
            else { Image(systemName: icon).font(.system(size: TS.hero, weight: .light)).foregroundStyle(tint.fg).frame(width: 64).symbolEffect(.bounce, value: playing) }
            VStack(alignment: .leading, spacing: 10) {
                Text(headline).font(.system(size: TS.headline, weight: .regular, design: .serif)).tracking(-0.4).foregroundStyle(tint.fg)
                HStack(spacing: 6) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        if i <= shown {
                            if i > 0 { Image(systemName: "arrow.right").font(.system(size: TS.micro, weight: .semibold)).transition(.opacity) }
                            Text(step).transition(.asymmetric(insertion: .offset(x: -8).combined(with: .opacity), removal: .opacity))
                        }
                    }
                }
                .font(.system(size: TS.small, design: .monospaced)).foregroundStyle(tint.fg)
                .padding(.horizontal, 12).frame(height: 28).background(Capsule().fill(K.card.opacity(0.6)))
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Button(action: play) {
                    Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: TS.emphasis)).foregroundStyle(tint.fg)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44).contentShape(Circle())
                        .liquid(Circle(), tint: K.card.opacity(0.5))
                }
                .buttonStyle(.plain).focusRing(22)
                .accessibilityLabel("How it works")
                Text("How it works").font(.system(size: TS.meta)).foregroundStyle(tint.fg)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint.bg))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.stroke, lineWidth: 0.75))
    }

    func play() {
        guard !playing else { playing = false; withAnimation(Motion.spring()) { shown = .max }; return }
        playing = true
        withAnimation(.easeOut(duration: 0.15)) { shown = 0 }
        guard !Motion.reduced else { shown = .max; playing = false; return }
        for i in 1...steps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7 * Double(i)) {
                guard playing else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { shown = i == steps.count ? .max : i }
                if i == steps.count { playing = false }
            }
        }
    }
}

/// The feature's master row: icon, name, contents badge, one sentence, switch.
struct FeatureCard: View {
    var icon: String, title: String, desc: String
    var reads: Bool
    @Binding var on: Bool
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: TS.heading)).foregroundStyle(K.text2).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(K.text)
                    Badge(icon: reads ? "text.viewfinder" : "doc", text: reads ? "Reads contents" : "Metadata only")
                }
                Text(desc).font(.system(size: TS.small)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            KToggle(on: $on, label: title)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .card(radius: 14)
    }
}

extension View {
    /// A switched-off feature dims its options (still visible, not editable).
    func gated(_ on: Bool = true) -> some View { opacity(on ? 1 : 0.4).allowsHitTesting(on).animation(.easeOut(duration: 0.15), value: on) }
}

/// Section header: title + one-line subtitle, optional glass capsule on the right.
struct PageSection<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    var action: (label: String, run: () -> Void)? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text)
                    if let subtitle { Text(subtitle).font(.system(size: TS.small)).foregroundStyle(K.text2) }
                }
                Spacer()
                if let action { Button { action.run() } label: { Label(action.label, systemImage: "plus") }.buttonStyle(CapsuleStyle()) }
            }
            .padding(.horizontal, 4)
            content
        }
    }
}

/// Small glass-look capsule button.
struct CapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: TS.small, weight: .medium)).foregroundStyle(K.text).padding(.horizontal, 12).frame(height: 28)
            .contentShape(Capsule())
            .liquid(Capsule())
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Mutually exclusive choice with a preview: flat when unselected; outlined and raised with a "✓ Selected" tab when selected. No radio buttons.
struct ChoiceCard<Preview: View>: View {
    var title: String
    var caption: String
    var selected: Bool
    var soon = false
    var pick: () -> Void
    @ViewBuilder var preview: Preview
    var body: some View {
        Button { withAnimation(Motion.reduced ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.75)) { pick() } } label: {
            VStack(alignment: .leading, spacing: 10) {
                preview.frame(maxWidth: .infinity, minHeight: 86).background(RoundedRectangle(cornerRadius: 2).fill(K.window))   // 14 card − 12 padding
                HStack(spacing: 6) {
                    Text(title).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text)
                    if soon { Text("Soon").font(.system(size: TS.micro, weight: .medium)).foregroundStyle(K.text3).padding(.horizontal, 6).frame(height: 16).background(Capsule().fill(K.fill)) }
                }
                Text(caption).font(.system(size: TS.small)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // cards in a row share one height
            .background { if selected { RoundedRectangle(cornerRadius: 14).fill(K.card).liquid(RoundedRectangle(cornerRadius: 14), interactive: false) } else { RoundedRectangle(cornerRadius: 14).fill(K.fill) } }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? K.switchOn.opacity(0.55) : K.separator, lineWidth: selected ? 1.25 : 0.75))
            .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 12, y: 6)
            .scaleEffect(selected || Motion.reduced ? 1 : 0.985)
            .animation(Motion.reduced ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.75), value: selected)
            .opacity(soon ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainRowStyle())
        .focusRing(14)
        .disabled(soon)
        .accessibilityLabel("\(title). \(caption)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A Finder folder with the shelf's emoji on its front panel and the label under it (k3/Folder Icon).
struct ShelfFolder: View {
    var emoji: String
    var label: String
    var size: CGFloat = 54
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Image(nsImage: NSWorkspace.shared.icon(for: .folder)).resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size)
                Text(emoji).font(.system(size: size * 0.4)).offset(y: size * 0.08)
            }
            Text(label).font(.system(size: TS.meta, weight: .medium)).foregroundStyle(K.text)
        }
    }
}

struct EmojiRow: View {
    var items: [(String, String)]
    var body: some View {
        HStack(spacing: 14) { ForEach(items, id: \.1) { ShelfFolder(emoji: $0.0, label: $0.1) } }.padding(.vertical, 10)
    }
}

// MARK: Sorting

struct SortingPage: View {
    @EnvironmentObject var m: AppModel
    var on: Bool { m.sortingOn }

    var body: some View {
        Showcase(tint: .accent, icon: "square.3.layers.3d", art: .sorting, headline: "Every new file lands on the right shelf", demo: "Downloads → ✨ My Shelves → 📄 Documents").gated_showcase(on)
        FeatureCard(icon: "square.3.layers.3d", title: "Sorting", desc: "Files new downloads and clutter onto shelves in ✨ My Shelves.", reads: false, on: sortingBinding)
        Group {
            PageSection(title: "Watched folders", subtitle: "Kanso sorts new files in these folders.", action: ("Add folder…", { m.addFolders() })) { folders }
            PageSection(title: "Behavior") { behavior }
            PageSection(title: "Unknown file types") { unknown }
            ExcludesSection()
            RulesSection()
        }
        .gated(on)
    }

    var folders: some View {
        RowGroup {
            ForEach(Array(m.settings.roots.enumerated()), id: \.element) { i, r in
                let allowed = AppModel.canRead(r)
                let placed = m.actions.filter { $0.root == r || $0.root == (r as NSString).expandingTildeInPath }.filter { Calendar.current.isDateInToday($0.ts) && $0.kind == .sorted }.count
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text(folderEmoji(r)).font(.system(size: TS.headline)).frame(width: 30)
                            .overlay(alignment: .bottomTrailing) { if !allowed { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: TS.meta)).foregroundStyle(.yellow).offset(x: 6, y: 4) } }
                        VStack(alignment: .leading, spacing: 1) {
                            Text((r as NSString).lastPathComponent).font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text)
                            Text(allowed ? "\((r as NSString).abbreviatingWithTildeInPath) · \(placed) placed today" : "Permission not allowed").lineLimit(1).truncationMode(.middle).help(allowed ? (r as NSString).expandingTildeInPath : "Kanso can't read this folder. Allow it in Privacy & Security.").font(.system(size: TS.small)).foregroundStyle(allowed ? K.text2 : Tint.duplicate.fg)
                        }
                        Spacer()
                        if allowed {
                            KToggle(on: Binding(get: { !m.settings.pausedRoots.contains(r) }, set: { on in m.set(\.pausedRoots, on ? m.settings.pausedRoots.filter { $0 != r } : m.settings.pausedRoots + [r]) }), label: "Sort \((r as NSString).lastPathComponent)")
                        } else {
                            Button("Open Privacy Settings…") { m.openPrivacySettings() }.buttonStyle(LinkStyle())
                        }
                        Button { m.removeFolder(r) } label: { Image(systemName: "minus.circle") }.buttonStyle(PlainRowStyle()).foregroundStyle(K.text3).help("Remove folder").accessibilityLabel("Remove \((r as NSString).lastPathComponent)")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    if i < m.settings.roots.count - 1 { Rectangle().fill(K.separator).frame(height: 0.75).padding(.leading, 58) }
                }
            }
            if m.settings.roots.isEmpty {   // the section's Add folder… button stays in its header
                Text("No folders watched").font(.system(size: TS.body)).foregroundStyle(K.text2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }

    /// Sorting never depends on a model: the extension table decides every known type. The model only sees types it doesn't know.
    var unknown: some View {
        RowGroup {
            Row(icon: "sparkles", title: "Ask Apple Intelligence", desc: unknownLine, last: true) {
                KToggle(on: m.binding(\.appleIntelligence), label: "Ask Apple Intelligence about unknown file types").disabled(!m.ai.available)
            }
        }
    }

    var unknownLine: String {
        if !m.ai.available { return "\(m.ai.status). Sorting works the same without it: known types sort by extension, anything else goes to ❓ Unsorted." }
        return m.settings.appleIntelligence ? "Only for types Kanso doesn't know yet, from the name, on this Mac. Known types never use it." : "Off. Types Kanso doesn't know go to ❓ Unsorted."
    }

    var behavior: some View {
        VStack(spacing: 12) {
            RowGroup {
                Option(title: "Recents", desc: m.settings.recents == .hold ? "New files wait in Recents, then move to a shelf." : m.settings.recents == .links ? "Shortcuts to everything sorted in the last \(m.settings.recentDays) days." : "No Recents folder.") {
                    HStack {
                        Segmented(options: [(RecentsMode.links, "Symlinks"), (.hold, "Hold"), (.off, "Off")], value: m.binding(\.recents))
                        if m.settings.recents != .off { MenuPicker(options: [(1, "1 day"), (3, "3 days"), (7, "7 days"), (14, "14 days"), (30, "30 days")], value: m.binding(\.recentDays)) }
                    }
                }.padding(.horizontal, 16).padding(.vertical, 6)
                Rectangle().fill(K.separator).frame(height: 0.75)
                Option(title: "Wait before sorting", desc: "Files still downloading or changing are never moved.") {
                    MenuPicker(options: [(0, "No wait"), (5, "5 seconds"), (10, "10 seconds"), (30, "30 seconds"), (60, "1 minute"), (300, "5 minutes")], value: m.binding(\.settleSeconds))
                }.padding(.horizontal, 16).padding(.vertical, 6)
                Rectangle().fill(K.separator).frame(height: 0.75)
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Approach").font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text)
                        Text("Switching affects new files only.").font(.system(size: TS.small)).foregroundStyle(K.text2)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        ChoiceCard(title: "By kind", caption: "Shelves by file type. Reads only names and metadata.", selected: true, pick: { m.set(\.approach, .kind) }) { EmojiRow(items: [("📄", "Documents"), ("🖼️", "Images"), ("📦", "Archives")]) }
                        ChoiceCard(title: "By purpose", caption: "Shelves by what a file is for. Reads contents on this Mac.", selected: false, soon: true, pick: {}) { EmojiRow(items: [("💼", "Work"), ("🏠", "Personal"), ("🧾", "Expenses")]) }
                    }
                    .fixedSize(horizontal: false, vertical: true)   // equal card heights
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }

    /// Turning Sorting off asks for how long, like in Quick settings.
    var sortingBinding: Binding<Bool> {
        Binding(get: { m.sortingOn }, set: { on in
            if on { m.setSorting(true); return }
            let menu = NSMenu()
            for d in OffDuration.allCases {
                let item = NSMenuItem(title: d.label, action: #selector(OffMenu.pick(_:)), keyEquivalent: "")
                item.target = OffMenu.shared
                item.representedObject = d.label
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        })
    }
}

extension View {
    /// The showcase dims to 50% while its feature is off.
    func gated_showcase(_ on: Bool) -> some View { opacity(on ? 1 : 0.5) }
}

/// Rules live inline on the Sorting page: list, inline editor, Add Rule at the bottom right.
struct RulesSection: View {
    @EnvironmentObject var m: AppModel
    @State private var open: UUID?
    @State private var draft: Rule?
    @State private var draftShelf: NewShelf?
    @State private var sentence = ""
    @State private var drafting = false
    @State private var draftError: String?

    var mine: [Rule] { m.settings.rules.filter { !$0.builtIn } }

    var body: some View {
        PageSection(title: "Rules", subtitle: "Your own rules run before Kanso's built-in types. The first match wins.") {
            RowGroup {
                let rules = mine + (draft.map { d in mine.contains { $0.id == d.id } ? [] : [d] } ?? [])
                ForEach(rules) { r in
                    RuleRow(rule: r, open: open == r.id, count: m.actions.filter { $0.why == "rule \(Engine.describe(r))" && !$0.undone }.count,
                            toggle: { withAnimation(Motion.spring(0.35)) { open = open == r.id ? nil : r.id } }, close: { withAnimation(Motion.spring(0.35)) { open = nil; draft = nil; draftShelf = nil } },
                            newShelf: r.id == draft?.id ? draftShelf : nil)
                    if r.id != rules.last?.id { Rectangle().fill(K.separator).frame(height: 0.75) }
                }
                if rules.isEmpty {
                    Text("No rules yet. Kanso sorts by type, and moving a file to another shelf teaches it.").font(.system(size: TS.small)).foregroundStyle(K.text2).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            describeField
            HStack {
                Spacer()
                Button { let r = Rule([Condition(.name, "")], dest: "Documents"); withAnimation(Motion.spring(0.35)) { draft = r; open = r.id } } label: { Label("Add rule", systemImage: "plus") }.buttonStyle(CapsuleStyle())
            }
        }
        suggestedFromMoves
    }

    /// "Describe a rule": on-device model, a draft you review and save yourself. Hidden, with the reason, when no model can do it.
    @ViewBuilder var describeField: some View {
        if let why = m.ruleFieldReason {
            Label(why, systemImage: "sparkles").font(.system(size: TS.small)).foregroundStyle(K.text2)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Tint.rule.fg)
                    TextField("Describe a rule: Move invoices from Stripe to Invoices", text: $sentence).textFieldStyle(.plain).font(.system(size: TS.body))
                        .onSubmit { draftRule() }.disabled(drafting).accessibilityLabel("Describe a rule in plain English")
                    if drafting { ProgressView().controlSize(.small) }
                    else { Button("Draft rule") { draftRule() }.buttonStyle(CapsuleStyle()).disabled(sentence.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
                .padding(.horizontal, 12).frame(height: 36).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(K.fill))
                Text(draftError ?? "Apple Intelligence on this Mac writes a draft. You preview it and press Save; nothing is saved or moved before that.")
                    .font(.system(size: TS.small)).foregroundStyle(draftError == nil ? K.text2 : Tint.duplicate.fg).padding(.horizontal, 4)
            }
        }
    }

    func draftRule() {
        let text = sentence
        guard !drafting, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        drafting = true; draftError = nil
        let settings = m.settings, ai = m.ai
        Task {
            let result = await RuleDrafting.draft(text, settings: settings, model: ai, compiler: ai)
            drafting = false
            switch result {
            case .failure(let e): draftError = e.message
            case .success(let d):
                sentence = ""
                withAnimation(Motion.spring(0.35)) { draft = d.rule; draftShelf = d.newShelf; open = d.rule.id }
            }
        }
    }

    @ViewBuilder var suggestedFromMoves: some View {
        if !m.pending.suggestions.isEmpty {
            PageSection(title: "Suggested from your moves") {
                VStack(spacing: 8) {
                    ForEach(m.pending.suggestions) { s in
                        HStack(spacing: 12) {
                            RulePreviewRow(condition: s.condition, shelf: s.shelf, emoji: m.settings.emoji(for: s.shelf))
                            Button("Not now") { m.dismissSuggestion(s.id) }.buttonStyle(LinkStyle(color: K.text2))
                            Button("Create rule") { m.acceptSuggestion(s.id) }.buttonStyle(PrimaryStyle(tint: .rule, small: true))
                        }
                        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Tint.rule.bg))
                    }
                }
            }
        }
    }
}

// MARK: Renaming

struct RenamingPage: View {
    @EnvironmentObject var m: AppModel
    @State private var custom = false
    @State private var dragged: String?
    static let presets = ["yyyy-MM", "yy-MM", "MMM yyyy"]
    static let partNames = ["kind": "Kind", "organization": "Organization", "date": "Date"]

    var body: some View {
        Showcase(tint: .rename, icon: "pencil", art: .renaming, headline: "Meaningless names become clear ones", demo: "Scan_0012.pdf → Invoice-Vattenfall-2026-03.pdf").gated_showcase(m.settings.renaming)
        FeatureCard(icon: "pencil", title: "Renaming", desc: "Gives meaningless names (Scan_0012, IMG_1615) clear ones.", reads: true, on: m.binding(\.renaming))
        Group {
            PageSection(title: "Name format", subtitle: "Drag to reorder. Kanso fills each part from the file.") {
                RowGroup {
                    HStack(spacing: 8) {
                        ForEach(Array(m.settings.nameParts.enumerated()), id: \.element) { i, p in
                            if i > 0 { Text(m.settings.separator == " " ? "·" : m.settings.separator).font(.system(size: TS.small)).foregroundStyle(K.text2) }
                            partChip(p)
                        }
                        Spacer()
                        let missing = ["kind", "organization", "date"].filter { !m.settings.nameParts.contains($0) }
                        Menu {
                            ForEach(missing, id: \.self) { p in Button(Self.partNames[p] ?? p) { m.set(\.nameParts, m.settings.nameParts + [p]) } }
                        } label: { Label("Add part", systemImage: "plus") }
                            .menuStyle(.button).buttonStyle(CapsuleStyle()).menuIndicator(.hidden).fixedSize().disabled(missing.isEmpty)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    Rectangle().fill(K.separator).frame(height: 0.75)
                    Option(title: "Separator") { Segmented(options: [("-", "Hyphen -"), ("_", "Underscore _"), (" ", "Space")], value: m.binding(\.separator)) }.padding(.horizontal, 16).padding(.vertical, 6)
                    Rectangle().fill(K.separator).frame(height: 0.75)
                    Option(title: "Date format") {
                        Segmented(options: [("yyyy-MM", "2026-03"), ("yy-MM", "26-03"), ("MMM yyyy", "Mar 2026"), ("custom", "Custom")], value: Binding(
                            get: { custom || !Self.presets.contains(m.settings.dateFormat) ? "custom" : m.settings.dateFormat },
                            set: { v in if v == "custom" { custom = true } else { custom = false; m.set(\.dateFormat, v) } }))
                    }.padding(.horizontal, 16).padding(.vertical, 6)
                    if custom || !Self.presets.contains(m.settings.dateFormat) {
                        Rectangle().fill(K.separator).frame(height: 0.75)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                TextField("yyyy-MM-dd", text: m.binding(\.dateFormat)).textFieldStyle(.plain).font(.system(size: TS.body, design: .monospaced))
                                    .padding(.horizontal, 12).frame(width: 220, height: 30).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(K.fill))
                                Chip(text: dateExample, tint: .rename)
                            }
                            Text("Patterns: yyyy, MM, MMM, dd, HH. Put literal text in single quotes.").font(.system(size: TS.small)).foregroundStyle(K.text2)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "eye").font(.system(size: TS.body)).foregroundStyle(Tint.rename.fg)
                VStack(alignment: .leading, spacing: 1) {
                    Text("PREVIEW").font(.system(size: TS.micro, weight: .semibold)).kerning(0.6).foregroundStyle(Tint.rename.fg)
                    Text(preview).font(.system(size: TS.emphasis, weight: .medium, design: .monospaced)).foregroundStyle(Tint.rename.fg).textSelection(.enabled)
                }
                Spacer()
                Text("from Scan_0012.pdf").font(.system(size: TS.small)).foregroundStyle(Tint.rename.fg)
            }
            .padding(.horizontal, 16).padding(.vertical, 12).background(RoundedRectangle(cornerRadius: 14).fill(Tint.rename.bg))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tint.rename.stroke, lineWidth: 0.75))
            PageSection(title: "Review") {
                RowGroup {
                    Option(title: "Ask before renaming more than \(m.settings.massRenameThreshold) at once", desc: "Opens the review window instead.") {
                        KToggle(on: m.binding(\.askBeforeMassRenames), label: "Ask before mass renames")
                    }.padding(.horizontal, 16).padding(.vertical, 6)
                    Rectangle().fill(K.separator).frame(height: 0.75)
                    Option(title: "Only rename meaningless names", desc: "Names you typed yourself are never touched.") {
                        Image(systemName: "lock").font(.system(size: TS.body)).foregroundStyle(K.text2)
                    }.padding(.horizontal, 16).padding(.vertical, 6)
                }
            }
        }
        .gated(m.settings.renaming)
    }

    func partChip(_ p: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal").font(.system(size: 8)).foregroundStyle(K.text3)
            Text(Self.partNames[p] ?? p).font(.system(size: TS.small, weight: .medium)).foregroundStyle(K.text)
        }
        .padding(.horizontal, 12).frame(height: 28)
        .background(Capsule().fill(K.card).shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)).overlay(Capsule().strokeBorder(K.separator, lineWidth: 0.75))
        .draggable(p) { Text(Self.partNames[p] ?? p).padding(6) }
        .dropDestination(for: String.self) { items, _ in
            guard let from = items.first, from != p, var parts = Optional(m.settings.nameParts), let fi = parts.firstIndex(of: from), let ti = parts.firstIndex(of: p) else { return false }
            parts.move(fromOffsets: IndexSet(integer: fi), toOffset: ti > fi ? ti + 1 : ti)
            m.set(\.nameParts, parts)
            return true
        }
        .contextMenu { if m.settings.nameParts.count > 1 { Button("Remove \(Self.partNames[p] ?? p)") { m.set(\.nameParts, m.settings.nameParts.filter { $0 != p }) } } }
        .accessibilityLabel("\(Self.partNames[p] ?? p), part of the name")
    }

    var dateExample: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = m.settings.dateFormat
        var c = DateComponents(); c.year = 2026; c.month = 3; c.day = 12
        return f.string(from: Calendar.current.date(from: c) ?? Date())
    }

    var preview: String {
        var c = DateComponents(); c.year = 2026; c.month = 3; c.day = 12
        return Renamer.name(Extracted(kind: "Invoice", organization: "Vattenfall", date: Calendar.current.date(from: c), source: ""), ext: "pdf",
                            separator: m.settings.separator, dateFormat: m.settings.dateFormat, parts: m.settings.nameParts) ?? ""
    }
}

// MARK: Duplicates

struct DuplicatesPage: View {
    @EnvironmentObject var m: AppModel
    @State private var held: (files: Int, parts: [(String, Int64)]) = (0, [])

    var body: some View {
        Showcase(tint: .duplicate, icon: "doc.on.doc", art: .duplicates, headline: "Extra copies wait, never vanish", demo: "invoice (1).pdf → 🪞 Duplicates").gated_showcase(m.settings.duplicates)
        FeatureCard(icon: "doc.on.doc", title: "Duplicates", desc: "Holds extra copies of new downloads on the 🪞 Duplicates shelf.", reads: false, on: m.binding(\.duplicates))
        Group {
            PageSection(title: "Where extra copies go") {
                HStack(alignment: .top, spacing: 14) {
                    ChoiceCard(title: "Duplicates shelf", caption: "Held until you move them to the Trash. Default.", selected: !m.settings.duplicatesToTrash, pick: { m.set(\.duplicatesToTrash, false) }) { ShelfGlyph(emoji: "🪞") }
                    ChoiceCard(title: "Trash", caption: "Straight to the Trash. Put Back or ⌘Z restores.", selected: m.settings.duplicatesToTrash, pick: { m.set(\.duplicatesToTrash, true) }) { ShelfGlyph(emoji: "🗑️") }
                }
                .fixedSize(horizontal: false, vertical: true)   // equal card heights
            }
            PageSection(title: "Clean up") {
                RowGroup {
                    Option(title: "Automatically move duplicates to Trash", desc: "Only untouched copies. Opening a held copy resets its timer.") { KToggle(on: m.binding(\.autoTrashDuplicates), label: "Automatically move duplicates to Trash") }.padding(.horizontal, 16).padding(.vertical, 6)
                    Rectangle().fill(K.separator).frame(height: 0.75)
                    Option(title: "Move duplicates to Trash after", desc: m.settings.autoTrashDuplicates ? nil : "Available when automatic moving is on.") {
                        MenuPicker(options: [(7, "7 days"), (14, "14 days"), (30, "30 days"), (60, "60 days"), (90, "90 days")], value: m.binding(\.autoTrashDays))
                    }.padding(.horizontal, 16).padding(.vertical, 6).gated(m.settings.autoTrashDuplicates && !m.settings.duplicatesToTrash)
                }
            }
            if m.duplicatesBytes > 0 || held.files > 0 { heldCard.transition(.opacity) }   // nothing held: no Trash card
        }
        .gated(m.settings.duplicates)
        .task(id: m.duplicatesBytes) { held = await Task.detached { [s = m.settings] in Self.breakdown(s) }.value }
    }

    var heldCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("🪞").font(.system(size: TS.headline))
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.duplicatesBytes.bytes).font(.system(size: TS.title, weight: .semibold)).foregroundStyle(Tint.duplicate.fg)
                    Text("in Duplicates · \(held.files) \(held.files == 1 ? "file" : "files")").font(.system(size: TS.small)).foregroundStyle(Tint.duplicate.fg)
                }
                Spacer()
                Button { m.trashAllDuplicates() } label: { Label("Move all to Trash…", systemImage: "trash") }.buttonStyle(CapsuleStyle()).disabled(m.duplicatesBytes == 0)
            }
            if !held.parts.isEmpty {
                let total = Double(max(held.parts.reduce(0) { $0 + $1.1 }, 1))
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(held.parts.enumerated()), id: \.offset) { i, p in
                            Rectangle().fill(Tint.duplicate.fg.opacity(1 - Double(i) * 0.3)).frame(width: max(4, g.size.width * CGFloat(Double(p.1) / total)))
                        }
                        Spacer(minLength: 0)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 6)
                HStack(spacing: 14) {
                    ForEach(Array(held.parts.enumerated()), id: \.offset) { i, p in
                        HStack(spacing: 5) { Circle().fill(Tint.duplicate.fg.opacity(1 - Double(i) * 0.3)).frame(width: 6, height: 6); Text("\(p.0) \(p.1.bytes)").font(.system(size: TS.meta)).foregroundStyle(Tint.duplicate.fg) }
                    }
                }
            }
        }
        .padding(16).background(RoundedRectangle(cornerRadius: 14).fill(Tint.duplicate.bg))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Tint.duplicate.stroke, lineWidth: 0.75))
    }

    /// File count and size by kind in the Duplicates shelf, biggest first.
    nonisolated static func breakdown(_ s: Settings) -> (files: Int, parts: [(String, Int64)]) {
        var kinds: [String: Int64] = [:]; var n = 0
        let video: Set<String> = ["mov", "mp4", "m4v", "mkv", "avi", "webm"], image: Set<String> = ["jpg", "jpeg", "png", "heic", "gif", "webp", "tiff"]
        for root in s.activeRoots {
            let dir = root.appendingPathComponent(Library.mine).appendingPathComponent(Shelf.duplicates)
            let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles])
            while let u = e?.nextObject() as? URL {
                guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let ext = u.pathExtension.lowercased()
                let k = video.contains(ext) ? "Videos" : image.contains(ext) ? "Images" : ext == "pdf" ? "PDFs" : "Other"
                kinds[k, default: 0] += Int64((try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
                n += 1
            }
        }
        return (n, kinds.sorted { $0.value > $1.value }.map { ($0.key, $0.value) })
    }
}

/// A single big shelf emoji in a choice card preview.
struct ShelfGlyph: View {
    var emoji: String
    var body: some View { Text(emoji).font(.system(size: TS.hero)).frame(maxWidth: .infinity, minHeight: 86) }
}

// MARK: Tagging and Smart Eject (not designed yet: same anatomy, minimal)

/// A Finder tag: coloured dot and name.
struct TagChip: View {
    var text: String
    var color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(Tint.neutral.fg)
        }
        .padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(Tint.neutral.bg))
    }
}

struct TaggingPage: View {
    @EnvironmentObject var m: AppModel
    var recent: [Action] { Array(m.actions.filter { !$0.undone && !$0.tags.isEmpty }.suffix(3).reversed()) }
    var total: Int { m.actions.filter { !$0.undone && !$0.tags.isEmpty }.count }

    var body: some View {
        Showcase(tint: .where, icon: "tag", art: .tagging, headline: "Files carry what they are as Finder tags", demo: "Scan_0012.pdf → Invoice, Vattenfall").gated_showcase(m.settings.tagging)
        FeatureCard(icon: "tag", title: "Tagging", desc: "Adds Finder tags like Invoice and the company name.", reads: true, on: m.binding(\.tagging))
        Group {
            PageSection(title: "What gets tagged") {
                RowGroup {
                    Row(icon: "doc.text", title: "Kind", desc: "Invoice, Receipt, Contract, Report, Letter…") { KToggle(on: m.binding(\.tagKind), label: "Tag the kind") }
                    Row(icon: "building.2", title: "Organization", desc: "The company named on the first page, like Vattenfall.", last: true) { KToggle(on: m.binding(\.tagOrganization), label: "Tag the organization") }
                }
            }
            PageSection(title: "What it looks like in Finder") {
                RowGroup {
                    Row(icon: "doc.text", title: "Invoice-Vattenfall-2026-03.pdf", desc: "Documents · tagged just now", last: true) { tagChips(["Invoice", "Vattenfall"]) }
                }
            }
            PageSection(title: "Keep tag") {
                RowGroup {
                    Row(icon: "hand.raised", title: "Files tagged “\(m.settings.keepTag)” are left alone", desc: "Never moved, renamed or tagged. Added automatically to anything you undo.", last: true) { TagChip(text: m.settings.keepTag, color: .gray) }
                }
            }
            PageSection(title: "Recently tagged", subtitle: total == 0 ? "Nothing tagged yet." : "\(total.formatted()) files tagged since you started") {
                if recent.isEmpty {
                    Text("Tags appear here after Kanso reads a file's first page.").font(.system(size: TS.small)).foregroundStyle(K.text2).padding(.horizontal, 4)
                } else {
                    RowGroup {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { i, a in
                            Row(icon: "doc.text", title: a.name, desc: a.ts.relative, last: i == recent.count - 1) { tagChips(a.tags) }
                        }
                    }
                }
            }
        }
        .gated(m.settings.tagging)
    }

    func tagChips(_ tags: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(tags.prefix(3).enumerated()), id: \.offset) { i, t in TagChip(text: t, color: [Color.orange, .blue, .green][i % 3]) }
        }
    }
}

struct SmartEjectPage: View {
    @EnvironmentObject var m: AppModel
    var ejected: [Action] { m.actions.filter { !$0.undone && $0.kind == .trashed && $0.details["installer"] != nil } }

    var body: some View {
        Showcase(tint: .accent, icon: "eject", art: .eject, headline: "Installed? The installer cleans up after itself", demo: "Figma.dmg → ⏏ ejected → 🗑️ Trash").gated_showcase(m.settings.smartEject)
        FeatureCard(icon: "eject", title: "Smart Eject", desc: "After an app is installed, ejects its disk image and moves the installer to the Trash.", reads: false, on: m.binding(\.smartEject))
        Group {
            PageSection(title: "How it decides", subtitle: "Only when all three are true. Otherwise the installer stays where it is.") {
                HStack(alignment: .top, spacing: 12) {
                    step("opticaldisc", "You open the disk image", "It mounts, and Kanso notes the time.")
                    step("macwindow", "The app lands in Applications", "With a newer creation time than the mount.")
                    step("trash", "Kanso ejects and trashes it", "Journaled. ⌘Z puts it back.")
                }
            }
            PageSection(title: "Options") {
                RowGroup {
                    Row(icon: "bell", title: "Show a notice with Put Back", desc: "Every Smart Eject appears in the island for a few seconds.") { KToggle(on: m.binding(\.smartEjectNotice), label: "Show a notice") }
                    Row(icon: "eject.circle", title: "Only eject, never trash", desc: "Leave the installer where it is after ejecting it.", last: true) { KToggle(on: m.binding(\.smartEjectOnlyEject), label: "Only eject") }
                }
            }
            PageSection(title: "Recently ejected", subtitle: ejected.isEmpty ? "No installers yet." : "\(ejected.count) installers · \(ejected.reduce(Int64(0)) { $0 + (Int64($1.details["size"] ?? "") ?? 0) }.bytes) freed") {
                if ejected.isEmpty {
                    Text("Eject a disk image after installing an app and it shows up here.").font(.system(size: TS.small)).foregroundStyle(K.text2).padding(.horizontal, 4)
                } else {
                    let rows = Array(ejected.suffix(3).reversed())
                    RowGroup {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, a in
                            Row(icon: "shippingbox", title: a.srcName, desc: "\((Int64(a.details["size"] ?? "") ?? 0).bytes) · \(a.details["installer"] ?? "The app") is in Applications · \(a.ts.relative)", last: i == rows.count - 1) {
                                Button("Put Back") { m.undo([a.id]) }.buttonStyle(SecondaryStyle(small: true))
                            }
                        }
                    }
                }
            }
        }
        .gated(m.settings.smartEject)
    }

    func step(_ icon: String, _ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: TS.body)).foregroundStyle(Tint.accent.fg).frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Tint.accent.bg))
            Text(title).font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text).fixedSize(horizontal: false, vertical: true)
            Text(sub).font(.system(size: TS.small)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).card(radius: 16)
    }
}
