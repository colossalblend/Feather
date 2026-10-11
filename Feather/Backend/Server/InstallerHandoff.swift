import Foundation

/// A capability URL transfers only a signed IPA, never a key or certificate password.
struct InstallerHandoff: Codable, Equatable {
 static let scheme = "appbank-feather-installer"
 static let bundleIdentifier = "pw.appbank.FeatherInstaller"
 let source: URL
 let sha256: String
 let size: Int64
 let identifier: String
 let version: String
 let build: String
 let token: String

 func validate() throws {
  guard source.scheme == "http", source.host == "127.0.0.1",
        let port = source.port, (1024...65535).contains(port),
        source.user == nil, source.password == nil, source.query == nil, source.fragment == nil,
        token.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
        source.path == "/transfer/\(token)/Update.ipa",
        sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
        size > 0, size <= 300_000_000,
        identifier == "thewonderofyou.Feather", !version.isEmpty, !build.isEmpty
  else { throw HandoffError.invalid }
 }
 var acknowledgement: URL {
  var parts = URLComponents(url: source, resolvingAgainstBaseURL: false)!
  parts.path = "/ack/\(token)"
  return parts.url!
 }
 func link() throws -> URL {
  try validate()
  var parts = URLComponents()
  parts.scheme = Self.scheme; parts.host = "install"
  parts.queryItems = [URLQueryItem(name: "request", value: try JSONEncoder().encode(self).base64EncodedString())]
  return parts.url!
 }
 static func parse(_ url: URL) throws -> Self {
  guard url.scheme == scheme, url.host == "install", url.path.isEmpty,
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
        items.count == 1, items[0].name == "request",
        let value = items[0].value, value.count <= 8192,
        let data = Data(base64Encoded: value) else { throw HandoffError.invalid }
  let request = try JSONDecoder().decode(Self.self, from: data)
  try request.validate()
  return request
 }
}

struct InstallerReceipt: Codable {
 let build: String
 let sha256: String
 let cleanup: URL
}

enum HandoffError: LocalizedError {
 case invalid
 var errorDescription: String? { "Некорректный запрос установки." }
}
