import KansoCore
import SwiftUI

/// While the onboarding demo waits for ⌥⌘K, the global hot key goes to the demo instead of the real island.
@MainActor
final class OnboardingDemo: ObservableObject {
    static let shared = OnboardingDemo()
    @Published var active = false
    @Published var pressed = false
}

/// First run, learning by doing (PRODUCT.md "Onboarding"): folders → the island → existing files,
/// plus an Apple Intelligence step only when it's off or unavailable.
struct OnboardingView: View {
    enum Step { case folders, island, ai, files, declined }

    @EnvironmentObject var m: AppModel
    @ObservedObject var demo = OnboardingDemo.shared
    @State var step = Step.folders
    @State private var chosen: Set<String> = []
    @State private var asking = false
    @State private var cleanup = false

    init(step: Step = .folders) { _step = State(initialValue: step) }

    var steps: [Step] { m.ai.available ? [.folders, .island, .files] : [.folders, .island, .ai, .files] }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .folders: folders
                case .island: island
                case .ai: aiStep
                case .files: files
                case .declined: declined
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 48).padding(.top, 40)
            footer
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 540, maxHeight: .infinity)
        .background(K.window)
        .ignoresSafeArea()
        .onAppear { if chosen.isEmpty { chosen = Set(m.settings.roots) } }
    }

    func title(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t).font(.system(size: TS.display, weight: .regular, design: .serif)).tracking(-0.5).foregroundStyle(K.text).multilineTextAlignment(.leading)
            if !s.isEmpty { Text(s).font(.system(size: TS.body)).foregroundStyle(K.text2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 1. Folders: explain first, then one Continue that triggers macOS's prompt per folder (HIG pre-alert rules).
    var folders: some View {
        VStack(alignment: .leading, spacing: 22) {
            title("Kanso needs to open \(folderCount).", "")
            VStack(alignment: .leading, spacing: 8) {
                ForEach([("square.3.layers.3d", "Only the top level is sorted; shelves go inside the same folder."), ("laptopcomputer", "Your files never leave this Mac. The only network use is a daily update check (switch it off in Settings)."), ("checkmark.shield", "macOS asks once per folder. Uncheck one to leave it out.")], id: \.1) { b in
                    Label { Text(b.1).font(.system(size: TS.body)).foregroundStyle(K.text2) } icon: { Image(systemName: b.0).foregroundStyle(Tint.accent.fg).frame(width: 18) }
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(m.settings.roots.enumerated()), id: \.element) { i, r in
                    Toggle(isOn: Binding(get: { chosen.contains(r) }, set: { on in if on { chosen.insert(r) } else { chosen.remove(r) } })) {
                        HStack(spacing: 10) {
                            Text(folderEmoji(r)).font(.system(size: TS.heading))
                            Text((r as NSString).lastPathComponent).font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text)
                            Spacer()
                            Text((r as NSString).abbreviatingWithTildeInPath).font(.system(size: TS.meta)).foregroundStyle(K.text2).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .toggleStyle(.checkbox).tint(K.accent)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if i < m.settings.roots.count - 1 { Rectangle().fill(K.separator).frame(height: 0.75) }
                }
            }
            .card(radius: 14)
        }
    }

    var folderCount: String {
        let n = m.settings.roots.count
        return n == 1 ? "one folder" : "\(["zero", "one", "two", "three", "four", "five"].indices.contains(n) ? ["zero", "one", "two", "three", "four", "five"][n] : "\(n)") folders"
    }

    func folderCard(_ e: String, _ n: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(e).font(.system(size: TS.heading))
            VStack(alignment: .leading, spacing: 2) {
                Text(n).font(.system(size: TS.small, weight: .semibold)).foregroundStyle(K.text)
                Text(d).font(.system(size: TS.meta)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Continue: asks macOS for each chosen folder in turn; declined folders are skipped silently.
    func requestAccess() {
        asking = true
        let list = m.settings.roots.filter { chosen.contains($0) }
        Task.detached {
            let granted = list.filter { AppModel.canRead($0) }   // reading a protected folder triggers macOS's own prompt
            await MainActor.run {
                asking = false
                m.update { s in s.pausedRoots = s.roots.filter { !granted.contains($0) } }
                step = granted.isEmpty ? .declined : .island
            }
        }
    }

    // 2. The island: a live demo with a pretend file; press ⌥⌘K to open it.
    var island: some View {
        VStack(alignment: .leading, spacing: 22) {
            if demo.pressed {
                title("That's the island.", "It shows what Kanso did and lets you undo it. \(m.settings.islandShortcut.display) opens it any time.")
            } else {
                title("This is the island.", "A pretend file, so nothing real changes. Scan_0012.pdf just got a clear name.")
            }
            DemoIsland(expanded: demo.pressed).frame(height: demo.pressed ? 230 : 130).frame(maxWidth: .infinity)
            if !demo.pressed {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Press").font(.system(size: TS.body)).foregroundStyle(K.text2)
                        ForEach(Array(m.settings.islandShortcut.display.map(String.init).enumerated()), id: \.offset) { BigKeycap(key: $0.element) }
                        Text("to open it").font(.system(size: TS.body)).foregroundStyle(K.text2)
                    }
                    Text("or click the island · it opens by itself after 10 s").font(.system(size: TS.meta)).foregroundStyle(K.text3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            demo.pressed = false
            demo.active = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { withAnimation(Motion.spring()) { demo.pressed = true } }   // never blocking
        }
        .onDisappear { demo.active = false }
    }

    var aiStep: some View {
        let canTurnOn = m.ai.canBeTurnedOn
        return VStack(alignment: .leading, spacing: 22) {
            if canTurnOn {
                title("Turn on Apple Intelligence?", "Kanso uses it on this Mac for file types it doesn't know yet. Without it, those files go to ❓ Unsorted and everything else works the same.")
                RowGroup {
                    Row(icon: "sparkles", title: "Apple Intelligence", desc: "\(m.ai.status). Turn it on in System Settings → Apple Intelligence & Siri.", last: true) {
                        Button("Open System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!) }.buttonStyle(SecondaryStyle(small: true))
                    }
                }
            } else {
                // macOS 14-15 and Macs that can't run it: nothing to turn on, so no button, and the way forward is the same as everywhere.
                title("Sorting works without Apple Intelligence.", "\(m.ai.status). Kanso sorts every known file type by its extension. Files it doesn't know go to ❓ Unsorted, and you can move them yourself. Nothing else is missing.")
            }
            Text("Your files never leave this Mac either way. You can change this later in Settings → Privacy & AI.").font(.system(size: TS.small)).foregroundStyle(K.text2)
        }
    }

    // 3. Existing files
    var files: some View {
        VStack(alignment: .leading, spacing: 24) {
            title("What about files already there?", "Kanso sorts new files from now on. Your existing clutter can wait, or you can look at a plan first.")
            HStack(spacing: 16) {
                choice(false, "sparkle", "Only sort new files", "Leave what's there alone. Sort everything later from the Overview.")
                choice(true, "checklist", "Preview a cleanup", "See the plan as a list, uncheck anything, then apply. Nothing moves before you do.")
            }
            Text("The first Sort everything is always a preview. Everything can be undone.").font(.system(size: TS.small)).foregroundStyle(K.text2)
        }
    }

    func choice(_ v: Bool, _ icon: String, _ t: String, _ d: String) -> some View {
        let sel = cleanup == v
        return Button { cleanup = v } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).font(.system(size: TS.emphasis)).foregroundStyle(sel ? Tint.accent.fg : K.text2).frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 9).fill(sel ? Tint.accent.bg : K.fillStrong))
                Text(t).font(.system(size: TS.emphasis, weight: .semibold)).foregroundStyle(K.text)
                Text(d).font(.system(size: TS.small)).foregroundStyle(K.text2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14).fill(sel ? K.card : K.fill))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(sel ? K.switchOn : K.separator, lineWidth: sel ? 2 : 0.75))
            .shadow(color: .black.opacity(sel ? 0.1 : 0), radius: 10, y: 6)
        }
        .buttonStyle(PlainRowStyle())
        .focusRing(14)
        .accessibilityAddTraits(sel ? .isSelected : [])
    }

    var declined: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer().frame(height: 50)
            Image(systemName: "folder.badge.minus").font(.system(size: TS.hero)).foregroundStyle(K.text2)
            title("Kanso needs at least one folder to work.", "You can allow Downloads, Desktop or Documents in Privacy & Security → Files & Folders. Kanso picks them up as soon as you do.")
        }
    }

    // One primary button per step; the folder step has no way around the system prompt (HIG).
    var footer: some View {
        HStack {
            if step == .island || step == .ai || step == .files {
                Button("Back") { step = previous() }.buttonStyle(SecondaryStyle())
            }
            if step != .declined {
                HStack(spacing: 6) {
                    ForEach(steps, id: \.self) { st in Capsule().fill(st == step ? K.accent : K.fillStrong).frame(width: st == step ? 22 : 8, height: 6) }
                    Text(step == .ai ? "Before step 3 · only if Apple Intelligence is off" : "Step \((steps.firstIndex(of: step) ?? 0) + 1) of \(steps.count)").font(.system(size: TS.meta)).foregroundStyle(K.text2).padding(.leading, 6)
                }
                .animation(Motion.spring(), value: step)
            }
            Spacer()
            if step == .island && !demo.pressed {
                Button("Skip") { withAnimation { demo.pressed = true } }.buttonStyle(LinkStyle(color: K.text2)).padding(.trailing, 8)
            }
            switch step {
            case .folders:
                Button { requestAccess() } label: { HStack(spacing: 6) { Text(asking ? "Waiting for macOS…" : "Continue"); Hint(text: "↩") } }
                    .buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction).disabled(chosen.isEmpty || asking)
            case .declined:
                Button("Open Privacy Settings") { m.openPrivacySettings() }.buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction)
            case .files:
                Button { m.finishOnboarding(previewCleanup: cleanup); Windows.shared.closeOnboarding() } label: { HStack(spacing: 6) { Text(cleanup ? "Start and preview" : "Start Kanso"); Hint(text: "↩") } }
                    .buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction)
            default:
                Button { step = next() } label: { HStack(spacing: 6) { Text(step == .ai ? "Continue without it" : "Continue"); Hint(text: "↩") } }.buttonStyle(PrimaryStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 20)
    }

    func next() -> Step { steps.firstIndex(of: step).map { steps[min($0 + 1, steps.count - 1)] } ?? .files }
    func previous() -> Step { steps.firstIndex(of: step).map { steps[max($0 - 1, 0)] } ?? .folders }
}

/// Big keycap for the onboarding demo.
struct BigKeycap: View {
    var key: String
    var body: some View {
        Text(key).font(.system(size: TS.emphasis, weight: .medium)).foregroundStyle(K.text).frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(K.card).shadow(color: .black.opacity(0.08), radius: 2, y: 1))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(K.separator, lineWidth: 0.75))
    }
}

/// The onboarding's pretend island (real files are never touched): compact, then the expanded rename notice.
struct DemoIsland: View {
    var expanded: Bool
    @EnvironmentObject var m: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0xA9C3D6)), Color(nsColor: NSColor(hex: 0xEAD9C6))], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    if expanded {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark").font(.system(size: TS.micro, weight: .bold)).foregroundStyle(Tint.rename.fg).frame(width: 20, height: 20).background(Circle().fill(Tint.rename.soft))
                            Text("Renamed").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(.white)
                            Spacer()
                            Text("demo").font(.system(size: TS.meta)).foregroundStyle(.white.opacity(0.4))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan_0012.pdf").font(.system(size: TS.meta, design: .monospaced)).strikethrough().foregroundStyle(.white.opacity(0.35))
                            Text("Invoice-Vattenfall-2026-03.pdf").font(.system(size: TS.heading, weight: .bold)).foregroundStyle(.white)
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                        HStack(spacing: 8) {
                            ForEach([("arrow.uturn.backward", "Undo  ⌘Z"), ("folder.badge.magnifyingglass", "Reveal in Finder  ⌘R")], id: \.1) { t in
                                Label(t.1, systemImage: t.0).font(.system(size: TS.small, weight: .medium)).foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(Color.white.opacity(0.1)))
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "pencil").font(.system(size: TS.micro, weight: .semibold)).foregroundStyle(Tint.rename.fg).frame(width: 20, height: 20).background(RoundedRectangle(cornerRadius: 6).fill(Tint.rename.soft))
                            SweepText(from: "Scan_0012.pdf", to: "Invoice-Vattenfall-2026-03.pdf", glyphColor: Color(nsColor: NSColor(hex: 0x8FC9A8))).font(.system(size: TS.small, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(m.settings.islandShortcut.display).font(.system(size: TS.meta, weight: .medium)).foregroundStyle(.white.opacity(0.7)).padding(.horizontal, 6).frame(height: 18).background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.12)))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12).padding(.bottom, expanded ? 26 : 10)
                .frame(width: expanded ? 380 : 330, alignment: .leading)
                .background(UnevenRoundedRectangle(bottomLeadingRadius: expanded ? 28 : 20, bottomTrailingRadius: expanded ? 28 : 20).fill(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.72), .init(color: .black.opacity(0.4), location: 1)], startPoint: .top, endPoint: .bottom)))
                .environment(\.colorScheme, .dark)
                .animation(Motion.spring(0.3), value: expanded)
            }
        }
        .frame(width: 520)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(expanded ? "Example island, opened: renamed Scan_0012 to Invoice-Vattenfall-2026-03" : "Example island: renamed Scan_0012 to Invoice-Vattenfall-2026-03")
    }
}
