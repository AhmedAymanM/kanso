import Foundation

/// The update check gets its release page from GitHub's JSON; only a page of the pinned repo's releases is opened.
public enum ReleaseLink {
    public static func isTrusted(_ url: URL, slug: String) -> Bool {
        guard url.scheme == "https", url.host?.lowercased() == "github.com",
              url.user == nil, url.password == nil, url.port == nil else { return false }
        let path = url.standardized.path
        return path.lowercased().hasPrefix("/\(slug.lowercased())/releases/") && !path.contains("..")
    }
}
