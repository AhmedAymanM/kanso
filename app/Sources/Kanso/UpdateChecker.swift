import AppKit
import Foundation
import SwiftUI

/// Asks GitHub Releases whether a newer Kanso exists. Only a User-Agent with the app version is sent.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let lastCheckKey = "kanso.lastUpdateCheck"
    private let notifiedKey = "kanso.updateNotifiedVersion"

    /// "owner/repo" from the KansoRepoURL Info.plist key, else the default.
    private var repoSlug: String {
        if let s = Bundle.main.object(forInfoDictionaryKey: "KansoRepoURL") as? String, let u = URL(string: s) {
            let parts = u.path.split(separator: "/").map(String.init)
            if parts.count >= 2 { return parts[0] + "/" + parts[1].replacingOccurrences(of: ".git", with: "") }
        }
        return "AhmedAymanM/kanso"
    }

    /// The release page of the version the island announced; the island action opens it.
    var availableURL: URL? { if case .available(_, let u) = state { return u } else { return nil } }

    /// Launch and hourly tick: runs only when the setting is on and the last check is over 24 h old.
    func checkAutomatically(enabled: Bool) {
        guard enabled, state != .checking else { return }
        if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86400 { return }
        Task { await check(automatic: true) }
    }

    func check(automatic: Bool = false) async {
        if state == .checking { return }
        state = .checking
        let current = Bundle.main.version
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest")!, timeoutInterval: 10)
        req.setValue("Kanso/\(current)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { state = .upToDate; return }
            guard code == 200 else { state = .failed("GitHub answered \(code). Try again later."); return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var tag = json["tag_name"] as? String else { state = .failed("Unexpected answer from GitHub."); return }
            if tag.hasPrefix("v") || tag.hasPrefix("V") { tag.removeFirst() }
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? Links.repo.appendingPathComponent("releases")
            if tag.compare(current, options: .numeric) == .orderedDescending {
                state = .available(version: tag, url: page)
                if automatic, UserDefaults.standard.string(forKey: notifiedKey) != tag {
                    UserDefaults.standard.set(tag, forKey: notifiedKey)
                    Island.shared.show(.info(icon: "arrow.down.circle", text: "Kanso \(tag) is available"))
                }
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed("Couldn't reach GitHub. Check your connection.")
        }
    }
}

/// The About row's update control: a button, then the result.
struct UpdateStatus: View {
    @ObservedObject var checker = UpdateChecker.shared

    var body: some View {
        HStack(spacing: 8) {
            switch checker.state {
            case .idle: EmptyView()
            case .checking: ProgressView().controlSize(.small)
            case .upToDate: Text("Kanso is up to date").font(.system(size: TS.small)).foregroundStyle(K.text2)
            case .available(let v, let url):
                Text("Version \(v) available").font(.system(size: TS.small)).foregroundStyle(K.text2)
                Button("Download") { NSWorkspace.shared.open(url) }.buttonStyle(LinkStyle(color: K.text))
            case .failed(let msg): Text(msg).font(.system(size: TS.small)).foregroundStyle(K.text2)
            }
            Button("Check for updates") { Task { await checker.check() } }
                .buttonStyle(CapsuleStyle()).disabled(checker.state == .checking)
        }
    }
}
