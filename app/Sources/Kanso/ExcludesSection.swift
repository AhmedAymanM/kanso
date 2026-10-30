import KansoCore
import SwiftUI

/// "Never sort" on the Sorting page: name patterns for every watched folder, and subfolders to skip per watched folder.
/// The engine (`Engine.excluded`) looks at names only, so an excluded item is never read, hashed or tagged.
struct ExcludesSection: View {
    @EnvironmentObject var m: AppModel
    @State private var pattern = ""

    var trimmed: String { pattern.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        PageSection(title: "Never sort", subtitle: "Matching files and folders stay where they are. Kanso doesn't open them either.") {
            RowGroup {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Names").font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text)
                        Text(verbatim: "Patterns like *.tmp or Draft*, for every watched folder. Capital letters don't matter.").font(.system(size: TS.small)).foregroundStyle(K.text2)
                    }
                    ForEach(m.settings.excludes, id: \.self) { g in
                        removable(Text(g).font(.system(size: TS.small, design: .monospaced)).foregroundStyle(K.text), label: "Remove pattern \(g)") {
                            m.set(\.excludes, m.settings.excludes.filter { $0 != g })
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("*.tmp", text: $pattern).textFieldStyle(.plain).font(.system(size: TS.body, design: .monospaced))
                            .padding(.horizontal, 12).frame(height: 30).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(K.fill))
                            .onSubmit(addPattern)
                            .accessibilityLabel("Name pattern to never sort")
                        Button("Add", action: addPattern).buttonStyle(CapsuleStyle()).disabled(trimmed.isEmpty)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                ForEach(m.settings.roots, id: \.self) { root in
                    Rectangle().fill(K.separator).frame(height: 0.75)
                    rootRow(root)
                }
            }
        }
    }

    func rootRow(_ root: String) -> some View {
        let skipped = m.settings.rootExcludes[root] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(folderEmoji(root)).font(.system(size: TS.heading))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Folders in \((root as NSString).lastPathComponent)").font(.system(size: TS.body, weight: .medium)).foregroundStyle(K.text)
                    Text("Subfolders Kanso leaves alone.").font(.system(size: TS.small)).foregroundStyle(K.text2)
                }
                Spacer()
                let choices = subfolders(of: root).filter { n in !skipped.contains { $0.lowercased() == n.lowercased() } }
                Menu {
                    ForEach(choices, id: \.self) { n in Button(n) { skip(n, in: root) } }
                } label: { Label("Skip a folder", systemImage: "plus") }
                    .menuStyle(.button).buttonStyle(CapsuleStyle()).menuIndicator(.hidden).fixedSize().disabled(choices.isEmpty)
            }
            ForEach(skipped, id: \.self) { n in
                removable(Label(n, systemImage: "folder").font(.system(size: TS.small)).foregroundStyle(K.text), label: "Stop skipping \(n)") {
                    var all = m.settings.rootExcludes
                    all[root] = skipped.filter { $0 != n }
                    if all[root]?.isEmpty == true { all[root] = nil }
                    m.set(\.rootExcludes, all)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    func removable<L: View>(_ content: L, label: String, remove: @escaping () -> Void) -> some View {
        HStack {
            content
            Spacer()
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(PlainRowStyle()).foregroundStyle(K.text3).help(label).accessibilityLabel(label)
        }
    }

    func addPattern() {
        guard !trimmed.isEmpty else { return }
        if !m.settings.excludes.contains(trimmed) { m.set(\.excludes, m.settings.excludes + [trimmed]) }
        pattern = ""
    }

    func skip(_ name: String, in root: String) {
        var all = m.settings.rootExcludes
        all[root, default: []].append(name)
        m.set(\.rootExcludes, all)
    }

    /// Top-level folders of a watched folder that could be skipped (not Kanso's own, not hidden).
    func subfolders(of root: String) -> [String] {
        let dir = (root as NSString).expandingTildeInPath
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { n in
            var isDir: ObjCBool = false
            return !n.hasPrefix(".") && !Library.all.contains(n)
                && FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(n), isDirectory: &isDir) && isDir.boolValue
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
