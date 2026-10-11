import Foundation

@main struct HandoffTests {
 static func main() throws {
  let token = String(repeating: "a", count: 32), hash = String(repeating: "b", count: 64)
  func request(source: String? = nil, size: Int64 = 1234, id: String = "thewonderofyou.Feather", sha: String? = nil, key: String? = nil) -> InstallerHandoff {
   InstallerHandoff(source: URL(string: source ?? "http://127.0.0.1:23456/transfer/\(token)/Update.ipa")!, sha256: sha ?? hash,
        size: size, identifier: id, version: "2.9.2", build: "newbuild", token: key ?? token)
  }
  func fails(_ action: () throws -> Void) { do { try action(); fatalError("Expected failure") } catch {} }
  let valid = request()
  try valid.validate()
  let decoded = try InstallerHandoff.parse(valid.link())
  precondition(decoded == valid)
  precondition(valid.acknowledgement.path == "/ack/\(token)")
  for url in ["http://evil.example:23456/transfer/\(token)/Update.ipa", "file:///Update.ipa", "http://127.0.0.1:80/transfer/\(token)/Update.ipa", "http://user:pass@127.0.0.1:23456/transfer/\(token)/Update.ipa", "http://127.0.0.1:23456/wrong", "http://127.0.0.1:23456/transfer/\(token)/Update.ipa?x=1"] { fails { try request(source: url).validate() } }
  fails { try request(size: 0).validate() }
  fails { try request(size: 300_000_001).validate() }
  fails { try request(id: InstallerHandoff.bundleIdentifier).validate() }
  fails { try request(sha: "bad").validate() }
  fails { try request(key: "bad").validate() }
  fails { _ = try InstallerHandoff.parse(URL(string: "\(InstallerHandoff.scheme)://install?request=bad")!) }
  fails { _ = try InstallerHandoff.parse(URL(string: "https://evil.example/install")!) }
  print("16 installer handoff checks passed")
 }
}
