import KansoCore
import SwiftUI

// General and Privacy & AI pages. The feature pages are in FeaturePages.swift.

@MainActor
final class OffMenu: NSObject {
    static let shared = OffMenu()
    @objc func pick(_ item: NSMenuItem) {
        if let d = OffDuration.allCases.first(where: { $0.label == item.representedObject as? String }) { AppModel.shared.setSorting(false, for: d) }
    }
}

struct Option<Trailing: View>: View {
    var title: String
    var desc: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text)
                if let desc { Text(desc).font(.system(size: TS.small)).foregroundStyle(K.text2).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 5)
    }
}

// MARK: General

/// A little illustrated screen showing where the island appears (the design's visual picker).
struct IslandPlacement: View {
    var mode: IslandMode
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(nsColor: NSColor(hex: 0xA9C8F5)), Color(nsColor: NSColor(hex: 0xD5BDF0))], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.white.opacity(0.35)).frame(height: 10).frame(maxHeight: .infinity, alignment: .top)
            switch mode {
            case .automatic:
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black).frame(width: 74, height: 22)
                Capsule().fill(Color.black.opacity(0.55)).frame(width: 58, height: 14).padding(.top, 34)
            case .notch:
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(.black).frame(width: 74, height: 26)
            case .below:
                Capsule().fill(.black).frame(width: 86, height: 18).padding(.top, 20)
            }
        }
        .frame(height: 70).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).padding(0)
        .accessibilityHidden(true)
    }
}

struct GeneralPage: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        PageSection(title: "Startup & visibility") {
            RowGroup {
                Row(icon: "circle.lefthalf.filled", title: "Appearance", desc: "Kanso's windows follow the system, or stay light or dark.") {
                    Segmented(options: [("system", "System"), ("light", "Light"), ("dark", "Dark")], value: m.binding(\.appearance))
                }
                Row(icon: "menubar.rectangle", title: "Menu bar icon", desc: "When hidden, open Kanso from the island's gear or \(m.settings.islandShortcut.display).") { KToggle(on: m.binding(\.showMenuBarIcon), label: "Menu bar icon") }
                Row(icon: "power", title: "Open at login", desc: "Kanso starts quietly in the menu bar.") { KToggle(on: m.binding(\.openAtLogin), label: "Open at login") }
                Row(icon: "arrow.triangle.2.circlepath", title: "Auto update", desc: "Checks GitHub Releases once a day. Only the app version is sent.", last: true) { KToggle(on: m.binding(\.updateChecks), label: "Auto update") }
            }
        }
        PageSection(title: "Island") {
            RowGroup {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(systemName: "capsule.tophalf.filled").font(.system(size: TS.emphasis)).foregroundStyle(K.text2).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Where the island appears").font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text)
                            Text("Click a preview to choose. \(islandDesc)").font(.system(size: TS.small)).foregroundStyle(K.text2)
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        ForEach([(IslandMode.automatic, "Automatic", "Notch; moves below while another notch app runs."), (.notch, "From the notch", "Always drops from the notch."), (.below, "Below the notch", "A capsule under the menu bar.")], id: \.1) { o in
                            ChoiceCard(title: o.1, caption: o.2, selected: m.settings.islandMode == o.0, pick: { m.set(\.islandMode, o.0) }) { IslandPlacement(mode: o.0).padding(6) }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)   // equal card heights
                }
                .padding(.horizontal, 16).padding(.top, 12)
                Rectangle().fill(K.separator).frame(height: 0.75)
                ShortcutRow(icon: "keyboard", title: "Island shortcut", desc: "Opens the island, or the notice that's showing.", kp: \.islandShortcut)
                Row(icon: "lightbulb", title: "Show the \(m.settings.islandShortcut.display) hint", desc: "On the compact island for your first days; turns itself off.", last: true) { KToggle(on: m.binding(\.showShortcutHint), label: "Show the shortcut hint") }
            }
        }
        PageSection(title: "Notices") {
            RowGroup {
                Row(icon: "moon", title: "Collect notices quietly during Focus and full-screen", desc: "They wait in the menu bar, which shows a dot.", last: true) { KToggle(on: m.binding(\.collectDuringFocus), label: "Collect quietly") }
            }
        }
    }

    var islandDesc: String {
        let others = NotchApps.running().compactMap(\.localizedName)
        return others.isEmpty ? "" : "\(others[0]) uses the notch."
    }
}

// MARK: Privacy & AI (with About)

struct PrivacyPage: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        PageSection(title: "Model") {
            HStack(spacing: 12) {
                Image(systemName: "cpu").font(.system(size: TS.emphasis)).foregroundStyle(Tint.accent.fg).frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Tint.accent.bg))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Apple Intelligence").font(.system(size: TS.body, weight: .semibold)).foregroundStyle(K.text)
                    Text("Runs on this Mac. Used for unknown file types and naming.").font(.system(size: TS.small)).foregroundStyle(K.text2)
                }
                Spacer()
                Dot(on: m.aiReady, size: 6)
                Text(m.aiReady ? "Ready" : m.ai.status).font(.system(size: TS.small, weight: .medium)).foregroundStyle(m.aiReady ? Tint.accent.fg : K.text2)
            }
            .padding(.horizontal, 14).padding(.vertical, 12).card(radius: 14)
        }
        PageSection(title: "What reads inside files") {
            RowGroup {
                reads("Renaming", "first page, on this Mac, nothing kept", on: m.settings.renaming)
                reads("Tagging", "first page, on this Mac, nothing kept", on: m.settings.tagging)
                HStack { Text("Sorting · Duplicates · Smart Eject").font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text); Spacer(); Text("metadata only").font(.system(size: TS.small)).foregroundStyle(K.text2) }
                    .padding(.horizontal, 16).frame(height: 38)
            }
            HStack(spacing: 8) {
                Image(systemName: "lock").font(.system(size: TS.small)).foregroundStyle(K.text2)
                Text("Never read: 🔑 Keys, password vaults, 🏠 Manual Shelves and iCloud placeholders.").font(.system(size: TS.small)).foregroundStyle(K.text2)
                Spacer()
            }
            .padding(.horizontal, 14).frame(height: 38).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(K.fill))
        }
        PageSection(title: "About") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kanso \(Bundle.main.version)").font(.system(size: TS.heading, weight: .regular, design: .serif)).foregroundStyle(K.text)
                    Text("Open source · GPL-3.0").font(.system(size: TS.small)).foregroundStyle(K.text2)
                }
                Spacer()
                Button { NSWorkspace.shared.open(Links.repo) } label: { Label("GitHub", systemImage: "arrow.up.right").labelStyle(TrailingIcon()) }.buttonStyle(CapsuleStyle())
                Button { NSWorkspace.shared.open(Links.repo.appendingPathComponent("releases")) } label: { Label("Changelog", systemImage: "arrow.up.right").labelStyle(TrailingIcon()) }.buttonStyle(CapsuleStyle())
                Button("Send feedback…") { NSWorkspace.shared.open(Links.feedback()) }.buttonStyle(CapsuleStyle())
            }
            .padding(.horizontal, 16).padding(.vertical, 12).card(radius: 14)
        }
        Button("Show onboarding") { Windows.shared.showOnboarding() }.buttonStyle(LinkStyle(color: K.text2))
    }

    func reads(_ name: String, _ detail: String, on: Bool) -> some View {
        HStack(spacing: 10) {
            Text(name).font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text)
            Spacer()
            Text(detail).font(.system(size: TS.small)).foregroundStyle(K.text2)
            Chip(text: on ? "On" : "Off", tint: on ? .accent : .neutral)
        }
        .padding(.horizontal, 16).frame(height: 38)
        .overlay(alignment: .bottom) { Rectangle().fill(K.separator).frame(height: 0.75) }
    }
}

/// Label with the icon after the text (GitHub ↗).
struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.title; configuration.icon.font(.system(size: 9, weight: .semibold)) }
    }
}
