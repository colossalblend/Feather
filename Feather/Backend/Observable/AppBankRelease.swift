import Foundation

struct AppBankRelease: Decodable, Equatable {
 let build: String
 let version: String
 let notes: String
 let size: Int64
 let downloadURL: URL
 let sha256: String
 func validate() throws {
  guard !build.isEmpty, !version.isEmpty, size > 0, size <= 300_000_000,
   downloadURL.scheme == "https", downloadURL.host == "cert.appbank.pw",
   downloadURL.user == nil, downloadURL.password == nil,
   sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
  else { throw AppBankUpdateError.message("Некорректные данные обновления.") }
 }
 func validateBundle(_ info: [String: Any]) throws {
  guard info["CFBundleIdentifier"] as? String == "thewonderofyou.Feather",
   info["CFBundleVersion"] as? String == build,
   info["CFBundleShortVersionString"] as? String == version
  else { throw AppBankUpdateError.message("Загруженный файл не соответствует обновлению Feather.") }
 }
}

enum AppBankUpdateError: LocalizedError {
 case message(String)
 var errorDescription: String? {
  if case .message(let text) = self { return text }
  return nil
 }
}
