import XCTest
@testable import AltSourceKit

final class DownloadURLTests: XCTestCase {
	private func app(_ extra: String) throws -> ASRepository.App {
		let json = "{\"name\":\"Test\",\"bundleIdentifier\":\"test.app\",\"iconURL\":\"https://example.org/icon.png\",\(extra)}"
		return try JSONDecoder().decode(ASRepository.App.self, from: Data(json.utf8))
	}

	func testCapitalizedFields() throws {
		let decoded = try app("\"DownloadURL\":\"https://example.org/app.ipa\",\"DownloadURL-git\":\"https://github.com/test/app.ipa\"")
		XCTAssertEqual(decoded.currentDownloadUrl?.host, "example.org")
		XCTAssertEqual(decoded.currentGitDownloadUrl?.host, "github.com")
	}

	func testStandardAltStoreFields() throws {
		let decoded = try app("\"downloadURL\":\"https://example.org/app.ipa\",\"downloadURL-git\":\"https://github.com/test/app.ipa\"")
		XCTAssertEqual(decoded.currentDownloadUrl?.host, "example.org")
		XCTAssertEqual(decoded.currentGitDownloadUrl?.host, "github.com")
	}

	func testOptionalGitURLDoesNotBreakLegacyRepository() throws {
		let decoded = try app("\"downloadURL\":\"https://example.org/app.ipa\"")
		XCTAssertNotNil(decoded.currentDownloadUrl)
		XCTAssertNil(decoded.currentGitDownloadUrl)
	}

	func testInvalidGitFieldsAreIgnored() throws {
		for value in ["null", "42", "\"\"", "\"not-a-url\"", "\"file:///tmp/app.ipa\""] {
			let decoded = try app("\"downloadURL\":\"https://example.org/app.ipa\",\"DownloadURL-git\":\(value)")
			XCTAssertNotNil(decoded.currentDownloadUrl)
			XCTAssertNil(decoded.currentGitDownloadUrl)
		}
	}

	func testVersionURLsAndTopLevelGitFallback() throws {
		let decoded = try app("\"DownloadURL-git\":\"https://github.com/latest.ipa\",\"versions\":[{\"version\":\"2\",\"DownloadURL\":\"https://example.org/v2.ipa\",\"DownloadURL-git\":\"https://github.com/v2.ipa\"},{\"version\":\"1\",\"downloadURL\":\"https://example.org/v1.ipa\"}]")
		XCTAssertEqual(decoded.currentDownloadUrl?.lastPathComponent, "v2.ipa")
		XCTAssertEqual(decoded.currentGitDownloadUrl?.lastPathComponent, "v2.ipa")
		XCTAssertNil(decoded.versions?.last?.gitDownloadURL)
	}

	func testEmptyLowercaseFieldFallsBackToCapitalizedField() throws {
		let decoded = try app("\"downloadURL-git\":\"\",\"DownloadURL-git\":\"https://github.com/test/app.ipa\"")
		XCTAssertEqual(decoded.currentGitDownloadUrl?.host, "github.com")
	}
}
