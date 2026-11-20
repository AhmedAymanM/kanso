import XCTest
@testable import KansoCore

final class ReleaseLinkTests: XCTestCase {
    func testOnlyThePinnedRepoReleasesAreTrusted() {
        let slug = "AhmedAymanM/kanso"
        func ok(_ s: String) -> Bool { ReleaseLink.isTrusted(URL(string: s)!, slug: slug) }
        XCTAssertTrue(ok("https://github.com/AhmedAymanM/kanso/releases/tag/v1.0.0"))
        XCTAssertTrue(ok("https://github.com/ahmedaymanm/kanso/releases/tag/v1.0.0"))
        XCTAssertFalse(ok("http://github.com/AhmedAymanM/kanso/releases/tag/v1.0.0"))
        XCTAssertFalse(ok("https://evil.example/AhmedAymanM/kanso/releases/tag/v1.0.0"))
        XCTAssertFalse(ok("https://github.com.evil.example/AhmedAymanM/kanso/releases/tag/v1"))
        XCTAssertFalse(ok("https://github.com@evil.example/AhmedAymanM/kanso/releases/tag/v1"))
        XCTAssertFalse(ok("https://github.com/someone/kanso/releases/tag/v1.0.0"))
        XCTAssertFalse(ok("https://github.com/AhmedAymanM/kanso-evil/releases/tag/v1"))
        XCTAssertFalse(ok("https://github.com/AhmedAymanM/kanso/releases/../../evil/releases/x"))
        XCTAssertFalse(ok("https://github.com:8443/AhmedAymanM/kanso/releases/tag/v1"))
        XCTAssertFalse(ok("file:///AhmedAymanM/kanso/releases/x"))
    }
}
