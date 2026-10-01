import KansoCore
import SwiftUI

// Shared pieces kept from the v1 screens.

func section<C: View>(_ title: String, trailing: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        SectionTitle(title: title, trailing: trailing)
        RowGroup { content() }
    }
}

struct ShortcutRow: View {
    @EnvironmentObject var m: AppModel
    var icon: String, title: String, desc: String
    var kp: WritableKeyPath<Settings, Shortcut>
    var last = false
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Row(icon: icon, title: title, desc: desc, last: last) {
            HStack(spacing: 4) {
                if recording {
                    Text("Press keys…").font(.system(size: TS.small)).foregroundStyle(K.accent)
                } else {
                    ForEach(Array(m.settings[keyPath: kp].display.map(String.init).enumerated()), id: \.offset) { Keycap(key: $0.element) }
                }
                Button(recording ? "Cancel" : "Change") { recording ? stop() : start() }.buttonStyle(SecondaryStyle(small: true)).padding(.leading, 8)
            }
        }
    }

    func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }
            if let sc = HotKeys.shortcut(from: e) { m.set(kp, sc); stop(); return nil }
            return e
        }
    }

    func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}


struct ApproachCard: View {
    var selected: Bool
    var title: String
    var badge: String
    var examples: [(String, String)]
    var text: String
    var foot: (String, String)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle().strokeBorder(selected ? K.accent : K.text3, lineWidth: selected ? 5 : 1.5).frame(width: 18, height: 18)
                Text(title).font(.system(size: TS.heading, weight: .semibold))
                if !selected { Text(badge).font(.system(size: TS.micro, weight: .medium)).foregroundStyle(K.text2).padding(.horizontal, 6).frame(height: 17).background(RoundedRectangle(cornerRadius: 4).fill(K.fill)) }
                Spacer()
                if selected { Text(badge).font(.system(size: TS.small, weight: .medium)).foregroundStyle(K.accent) }
            }
            HStack {
                ForEach(examples, id: \.1) { e in
                    VStack(spacing: 6) { Text(e.0).font(.system(size: TS.headline)); Text(e.1).font(.system(size: TS.meta)).foregroundStyle(K.text2) }.frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(K.fill))
            Text(text).font(.system(size: TS.small)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true)
            Badge(icon: foot.0, text: foot.1)
        }
        .foregroundStyle(K.text)
        .opacity(selected ? 1 : 0.5)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(K.card))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? K.accent : K.separator, lineWidth: selected ? 1.5 : 0.75))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(selected ? "selected" : badge)")
    }
}


/// One rule in the inline list: destination emoji, the rule as a sentence, a chevron and a switch. Opens in place into the editor.
struct RuleRow: View {
    @EnvironmentObject var m: AppModel
    var rule: Rule
    var open: Bool
    var count: Int
    var toggle: () -> Void
    var close: () -> Void
    @State private var edit: Rule?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The sentence is a button (keyboard and VoiceOver open the editor); the switch stays its own control.
            HStack(spacing: 12) {
                Button(action: toggle) {
            HStack(spacing: 12) {
                Text(m.settings.emoji(for: rule.dest)).font(.system(size: TS.title)).frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sentence(rule)).font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text).lineLimit(1)
                    Text("\(roots) · \(count) \(count == 1 ? "file" : "files") so far").font(.system(size: TS.small)).foregroundStyle(K.text2)
                }
                .opacity(rule.enabled ? 1 : 0.45)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: TS.micro, weight: .semibold)).foregroundStyle(K.text2).rotationEffect(.degrees(open ? 180 : 0))
            }
            .contentShape(Rectangle())
                }
                .buttonStyle(PlainRowStyle()).focusRing(10)
                .accessibilityHint(open ? "Closes the rule editor" : "Opens the rule editor")
                KToggle(on: Binding(get: { rule.enabled }, set: { v in m.update { s in if let i = s.rules.firstIndex(where: { $0.id == rule.id }) { s.rules[i].enabled = v } } }), label: "Rule enabled")
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            if open, edit != nil { editor.padding(.horizontal, 16).padding(.bottom, 14).transition(Motion.reduced ? .opacity : .opacity.combined(with: .offset(y: -8))) }
        }
        .onAppear { if open { edit = rule } }
        .onChange(of: open) { _, o in edit = o ? rule : nil }
    }

    var roots: String { m.settings.activeRoots.map(\.lastPathComponent).joined(separator: ", ") }

    func sentence(_ r: Rule) -> String {
        let parts = r.conditions.map { c -> String in
            switch c.field {
            case .name: return isContains(c) ? "Name contains “\(stripped(c))”" : "Name matches “\(c.value)”"
            case .ext: return "Extension is .\(c.value)"
            case .from: return "Downloaded from \(c.value)"
            case .size: return "Size is over \(c.value)"
            }
        }
        return parts.joined(separator: r.matchAny ? " or " : " and ") + " → " + (r.dest as NSString).lastPathComponent
    }

    func isContains(_ c: Condition) -> Bool { c.value.count > 1 && c.value.hasPrefix("*") && c.value.hasSuffix("*") }
    func stripped(_ c: Condition) -> String { isContains(c) ? String(c.value.dropFirst().dropLast()) : c.value }

    @ViewBuilder var editor: some View {
        let b = Binding(get: { edit ?? rule }, set: { edit = $0 })
        let preview = previewCount(b.wrappedValue)
        VStack(alignment: .leading, spacing: 10) {
            Text("MATCH").font(.system(size: TS.micro, weight: .semibold)).kerning(0.6).foregroundStyle(Tint.rule.fg)
            HStack(spacing: 8) {
                MenuPicker(options: [(false, "all"), (true, "any")], value: b.matchAny)
                Text("of these conditions").font(.system(size: TS.small)).foregroundStyle(K.text2)
            }
            Text("IF").font(.system(size: TS.micro, weight: .semibold)).kerning(0.6).foregroundStyle(Tint.rule.fg).padding(.top, 4)
            ForEach(b.wrappedValue.conditions.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    MenuPicker(options: [(Condition.Field.name, "Name"), (.ext, "Extension"), (.from, "Downloaded from"), (.size, "Size")], value: b.conditions[i].field).frame(width: 150, alignment: .leading)
                    operatorPicker(b.conditions[i])
                    TextField(placeholder(b.wrappedValue.conditions[i].field), text: valueBinding(b.conditions[i])).textFieldStyle(.plain).font(.system(size: TS.body))
                        .padding(.horizontal, 12).frame(height: 30).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(K.fill))
                    if b.wrappedValue.conditions.count > 1 {
                        Button { b.wrappedValue.conditions.remove(at: i) } label: { Image(systemName: "minus.circle").font(.system(size: TS.emphasis)) }.buttonStyle(PlainRowStyle()).foregroundStyle(K.text3).accessibilityLabel("Remove condition")
                    } else { Color.clear.frame(width: 16, height: 16) }
                }
            }
            Button { b.wrappedValue.conditions.append(Condition(.ext, "")) } label: { Label("Add condition", systemImage: "plus") }.buttonStyle(LinkStyle())
            Text("THEN").font(.system(size: TS.micro, weight: .semibold)).kerning(0.6).foregroundStyle(Tint.rule.fg).padding(.top, 4)
            HStack(spacing: 8) {
                MenuPicker(options: [(0, "Move to shelf")], value: .constant(0)).frame(width: 150, alignment: .leading)
                MenuPicker(options: shelfOptions(b.wrappedValue.dest), value: b.dest, emoji: { m.settings.emoji(for: $0) })
                Spacer()
            }
            HStack(spacing: 8) {
                Text("Matches \(preview) \(preview == 1 ? "file" : "files") in your watched folders now").font(.system(size: TS.small)).foregroundStyle(K.text2)
                Spacer()
                Button { m.update { $0.rules.removeAll { $0.id == rule.id } }; close() } label: { Image(systemName: "trash") }.buttonStyle(PlainRowStyle()).foregroundStyle(K.text3).help("Delete rule").accessibilityLabel("Delete rule")
                Button { close() } label: { HStack(spacing: 6) { Text("Cancel"); Text("esc").font(.system(size: TS.meta)).foregroundStyle(K.text2) } }.buttonStyle(SecondaryStyle(small: true)).keyboardShortcut(.cancelAction)
                Button {
                    let r = b.wrappedValue
                    m.update { s in if let i = s.rules.firstIndex(where: { $0.id == r.id }) { s.rules[i] = r } else { s.rules.append(r) } }
                    close()
                } label: { HStack(spacing: 6) { Text("Save rule"); Image(systemName: "return").font(.system(size: TS.micro)) } }
                    .buttonStyle(SaveRuleStyle()).keyboardShortcut(.defaultAction).disabled(b.wrappedValue.conditions.contains { $0.value.trimmingCharacters(in: .whitespaces).isEmpty })
            }
            .padding(.top, 6)
        }
        .padding(.top, 4)
    }

    func shelfOptions(_ current: String) -> [(String, String)] {
        var o = m.settings.types.map { ($0.name, $0.name) }
        if !o.contains(where: { $0.0 == current }) { o.append((current, current)) }
        return o
    }

    @ViewBuilder func operatorPicker(_ c: Binding<Condition>) -> some View {
        switch c.wrappedValue.field {
        case .name:
            MenuPicker(options: [(true, "contains"), (false, "matches")], value: Binding(get: { isContains(c.wrappedValue) }, set: { wantContains in
                let v = stripped(c.wrappedValue)
                c.wrappedValue.value = wantContains ? "*\(v)*" : v
            })).frame(width: 120, alignment: .leading)
        case .ext, .from: MenuPicker(options: [(0, "is")], value: .constant(0)).frame(width: 120, alignment: .leading)
        case .size: MenuPicker(options: [(0, "is over")], value: .constant(0)).frame(width: 120, alignment: .leading)
        }
    }

    func valueBinding(_ c: Binding<Condition>) -> Binding<String> {
        Binding(get: { stripped(c.wrappedValue) }, set: { v in c.wrappedValue.value = isContains(c.wrappedValue) ? "*\(v)*" : v })
    }

    func placeholder(_ f: Condition.Field) -> String {
        switch f { case .name: return "invoice"; case .ext: return "dmg"; case .from: return "github.com"; case .size: return "2 GB" }
    }

    /// Files at the top level of the watched folders that this rule would take.
    func previewCount(_ r: Rule) -> Int {
        var n = 0
        var r = r; r.enabled = true
        for root in m.settings.activeRoots {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] where !name.hasPrefix(".") && !Library.all.contains(name) {
                if Engine.matches(r, Item.inspect(root.appendingPathComponent(name), root: root)) { n += 1 }
            }
        }
        return n
    }
}

/// The one green button of the rule editor (Save rule ↩), as in the design.
struct SaveRuleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        // Pastel fill with an ink label (no white-text buttons: white on green measured 2.2:1).
        configuration.label.font(.system(size: TS.small, weight: .semibold)).foregroundStyle(Tint.accent.fg).padding(.horizontal, 14).frame(height: 28)
            .background(Capsule().fill(Tint.accent.bg)).overlay(Capsule().strokeBorder(Tint.accent.stroke, lineWidth: 0.75))
            .scaleEffect(configuration.isPressed && !Motion.reduced ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.4)
    }
}

struct AppIcon: View {
    var body: some View {
        GeometryReader { g in
            RoundedRectangle(cornerRadius: g.size.width * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x4A7A69)), Color(nsColor: NSColor(hex: 0x365D4F))], startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: "tray").font(.system(size: g.size.width * 0.42, weight: .regular)).foregroundStyle(.white))
                .shadow(color: .black.opacity(0.15), radius: g.size.width * 0.04, y: g.size.width * 0.02)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += sz.width + spacing; row = max(row, sz.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; row = max(row, sz.height)
        }
    }
}

struct InsightCard<Chart: View>: View {
    var icon: String
    var tag: String
    var color: Color
    var sentence: String
    var sub: String
    @ViewBuilder var chart: Chart
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tag, systemImage: icon).font(.system(size: TS.meta, weight: .semibold)).kerning(0.4).textCase(.uppercase).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(sentence).font(.system(size: TS.emphasis, weight: .medium)).foregroundStyle(K.text).fixedSize(horizontal: false, vertical: true)
                Text(sub).font(.system(size: TS.small)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true)
            }
            chart.padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(K.card))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(K.separator, lineWidth: 0.75))
    }
}

struct BarChart: View {
    var values: [Int]
    var labels: [String]
    var highlight: Int
    var color: Color
    var body: some View {
        let mx = max(values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(i == highlight ? color : color.opacity(0.15))
                        .frame(height: max(6, CGFloat(v) / CGFloat(mx) * 44))
                    Text(i < labels.count ? labels[i] : "").font(.system(size: TS.micro, weight: i == highlight ? .semibold : .regular)).foregroundStyle(i == highlight ? K.text : K.text2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 62, alignment: .bottom)
    }
}

struct HBars: View {
    var rows: [(String, Int)]
    var color: Color
    var plus = false
    var body: some View {
        let mx = max(rows.map(\.1).max() ?? 1, 1)
        VStack(spacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 8) {
                    Text(r.0).font(.system(size: TS.meta)).foregroundStyle(K.text2).frame(width: 110, alignment: .leading).lineLimit(1)
                    GeometryReader { g in Capsule().fill(i == 0 ? color : color.opacity(0.18)).frame(width: max(4, g.size.width * CGFloat(r.1) / CGFloat(mx))) }.frame(height: 6)
                    Text((plus ? "+" : "") + "\(r.1)").font(.system(size: TS.meta, weight: i == 0 ? .semibold : .regular)).foregroundStyle(i == 0 ? color : K.text2).frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}

enum Links {
    static let repo = URL(string: "https://github.com/ahmedayman/kanso")!
    static let coffee = URL(string: "https://buymeacoffee.com/kanso")!
    static func feedback() -> URL {
        let info = "Kanso \(Bundle.main.version) (\(Bundle.main.build)) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        var c = URLComponents(string: "https://github.com/ahmedayman/kanso/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: ""), URLQueryItem(name: "body", value: "**What happened?**\n\n\n**What did you expect?**\n\n\n---\n\(info)")]
        return c.url!
    }
}
