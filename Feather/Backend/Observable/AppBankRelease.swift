import Foundation

enum AppBankUpdatePreferences {
 static let automaticKey = "Feather.automaticUpdateChecks"
 static func shouldCheck(manual: Bool, defaults: UserDefaults = .standard) -> Bool {
  manual || (defaults.object(forKey: automaticKey) as? Bool ?? true)
 }
}

struct AppBankRelease: Decodable, Equatable {
 let build: String
 let version: String
 let notes: String
 let size: Int64
 let downloadURL: URL
 let sha256: String
 var installer: AppBankInstallerRelease? = nil
 func validate() throws {
  guard !build.isEmpty, !version.isEmpty, size > 0, size <= 300_000_000,
   downloadURL.scheme == "https", downloadURL.host == "cert.appbank.pw",
   downloadURL.user == nil, downloadURL.password == nil,
   sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
  else { throw AppBankUpdateError.message("Некорректные данные обновления.") }
 }
 func validateBundle(_ info: [String: Any], identifier: String = "thewonderofyou.Feather") throws {
  guard info["CFBundleIdentifier"] as? String == identifier,
   info["CFBundleVersion"] as? String == build,
   info["CFBundleShortVersionString"] as? String == version
  else { throw AppBankUpdateError.message("Загруженный файл не соответствует обновлению Feather.") }
 }
}

struct AppBankInstallerRelease: Decodable, Equatable {
 let build: String
 let version: String
 let size: Int64
 let downloadURL: URL
 let sha256: String
 var release: AppBankRelease { AppBankRelease(build: build, version: version, notes: "", size: size, downloadURL: downloadURL, sha256: sha256) }
}

enum AppBankUpdateError: LocalizedError {
 case message(String)
 var errorDescription: String? {
  if case .message(let text) = self { return text }
  return nil
 }
}
