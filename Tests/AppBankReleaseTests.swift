import Foundation

@main
struct ReleaseTests {
 static func main() throws {
  let hash = String(repeating: "a", count: 64)
  func release(url: String = "https://cert.appbank.pw/Feather.ipa", size: Int64 = 1234, sha: String? = nil) -> AppBankRelease {
   AppBankRelease(build: "abc1234", version: "2.9.2", notes: "Исправления установки и исправление ошибок.", size: size, downloadURL: URL(string: url)!, sha256: sha ?? hash)
  }
  func fails(_ action: () throws -> Void) { do { try action(); fatalError("Expected validation failure") } catch {} }
  try release().validate()
  fails { try release(url: "http://cert.appbank.pw/Feather.ipa").validate() }
  fails { try release(url: "https://evil.example/Feather.ipa").validate() }
  fails { try release(url: "https://cert.appbank.pw.evil.example/Feather.ipa").validate() }
  fails { try release(url: "https://user:pass@cert.appbank.pw/Feather.ipa").validate() }
  fails { try release(size: 0).validate() }
  fails { try release(size: 300_000_001).validate() }
  fails { try release(sha: "invalid").validate() }
  var info: [String: Any] = ["CFBundleIdentifier": "thewonderofyou.Feather", "CFBundleVersion": "abc1234", "CFBundleShortVersionString": "2.9.2"]
  try release().validateBundle(info)
  info["CFBundleVersion"] = "old"
  fails { try release().validateBundle(info) }
  info["CFBundleVersion"] = "abc1234"; info["CFBundleIdentifier"] = "other.app"
  fails { try release().validateBundle(info) }
  info["CFBundleIdentifier"] = "thewonderofyou.Feather"; info["CFBundleShortVersionString"] = "2.9.0"
  fails { try release().validateBundle(info) }
  print("12 release validation checks passed")
 }
}
