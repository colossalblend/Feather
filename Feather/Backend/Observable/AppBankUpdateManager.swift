import Foundation
import NimbleJSON
import SwiftUI
import CryptoKit
import Zip
import ZsignSwift
import IDeviceSwift

struct AppBankUpdate: Equatable {
 let release: AppBankRelease
 var build: String { release.build }
 var version: String { release.version }
 var notes: String { release.notes }
 var size: Int64 { release.size }
 var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}
enum AppBankUpdateOutcome { case updateAvailable, upToDate, unavailable }

@MainActor
final class AppBankUpdateManager: ObservableObject {
 static let shared = AppBankUpdateManager()
 @Published private(set) var available: AppBankUpdate?
 @Published private(set) var isChecking = false
 @Published var isPresented = false
 @Published private(set) var isWorking = false
 @Published private(set) var isInstalling = false
 @Published private(set) var stage: String?
 @Published private(set) var errorMessage: String?
 @Published private(set) var hasPreparedUpdate = false
 @Published private(set) var preparedUpdateURL: URL?
 var usesExternalInstaller: Bool { UserDefaults.standard.integer(forKey: "Feather.installationMethod") != 1 }
 private var shownBuild: String?
 private var transfer: InstallerTransferServer?
 private var bootstrap: ServerInstaller?
 private var handoffTimeout: Task<Void, Never>?
 private let cache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AppBankUpdate", isDirectory: true)
 private var endpoint: URL {
  if let value = Bundle.main.object(forInfoDictionaryKey: "AppBankReleaseEndpoint") as? String,
     let url = URL(string: value), url.scheme == "https", url.host == "cert.appbank.pw", url.user == nil, url.password == nil { return url }
  return URL(string: "https://cert.appbank.pw/feather_update.php?mode=local")!
 }
 private init() {
  if let data = try? Data(contentsOf: cache.appendingPathComponent("prepared.json")),
   let marker = try? JSONDecoder().decode([String: String].self, from: data),
   marker["build"] == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
   try? FileManager.default.removeItem(at: cache)
  }
  Task { await confirmInstalledBuild() }
 }

 @discardableResult
 func check(presenting: Bool = true, manual: Bool = false) async -> AppBankUpdateOutcome {
  guard !isChecking, !isWorking else { return .unavailable }
  guard AppBankUpdatePreferences.shouldCheck(manual: manual) else { return .unavailable }
  isChecking = true
  defer { isChecking = false }
  do {
   var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
   request.setValue(NBFetchService.userAgent, forHTTPHeaderField: "User-Agent")
   let (data, response) = try await URLSession.shared.data(for: request)
   guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .unavailable }
   let release = try JSONDecoder().decode(AppBankRelease.self, from: data)
   try release.validate()
   guard AppBankUpdatePreferences.shouldCheck(manual: manual) else { return .unavailable }
   guard release.build != Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
    available = nil
    preparedUpdateURL = nil
    return .upToDate
   }
   if available?.release != release { preparedUpdateURL = nil }
   available = AppBankUpdate(release: release)
   if presenting, manual || shownBuild != release.build {
    shownBuild = release.build
    isPresented = true
   }
   return .updateAvailable
  } catch { return .unavailable }
 }

 func install() {
  guard let update = available, !isWorking, !isInstalling else { return }
  isWorking = true
  #if !targetEnvironment(macCatalyst)
  BackgroundAudioManager.shared.start()
  #endif
  errorMessage = nil
  preparedUpdateURL = nil
  Task {
   do {
    guard let cert = Storage.shared.selectedCertificate(), let uuid = cert.uuid,
     let p12 = Storage.shared.getFile(.certificate, from: cert),
     let profile = Storage.shared.getFile(.provision, from: cert)
    else { throw AppBankUpdateError.message("Выбери сертификат в настройках Feather.") }
    guard !cert.revoked else { throw AppBankUpdateError.message("Выбранный сертификат отозван. Выбери действующий сертификат.") }
    let password = cert.password ?? ""
    stage = "Проверка сертификата…"
    let profileData = try Data(contentsOf: profile)
    let p12Data = try Data(contentsOf: p12)
    guard let decoded = Storage.shared.getProvisionFileDecoded(for: cert), decoded.ExpirationDate > Date(),
     cert.expiration.map({ $0 > Date() }) ?? false else {
     throw AppBankUpdateError.message("Срок сертификата истёк или профиль повреждён.")
    }
    let status: Int32 = await withCheckedContinuation { continuation in
     DispatchQueue.global(qos: .utility).async {
      Zsign.checkRevokage(provisionPath: profile.path, p12Path: p12.path, p12Password: password) { status, _, _ in
       continuation.resume(returning: status)
      }
     }
    }
    guard status == 0 else {
     if status == 1 { cert.revoked = true; Storage.shared.saveContext() }
     throw AppBankUpdateError.message(status == 1 ? "Выбранный сертификат отозван." : "Не удалось проверить сертификат. Проверь подключение и повтори.")
    }
    let fingerprint = Self.hash(p12Data + profileData + Data((uuid + password).utf8))
    let ipa = cache.appendingPathComponent("Update.ipa")
    let marker = cache.appendingPathComponent("prepared.json")
    let expected = ["build": update.build, "certificate": fingerprint, "source": update.release.sha256, "bundle": Bundle.main.bundleIdentifier ?? ""]
    let cached = (try? Data(contentsOf: marker)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    let source = cache.appendingPathComponent("Source.ipa")
    // Download the main update while preparing the first Installer installation.
    let needsSigning = cached != expected || !FileManager.default.fileExists(atPath: ipa.path)
    let downloading = Task { if needsSigning { try await downloadSource(update.release, to: source) } }
    defer { downloading.cancel() }
    if usesExternalInstaller, !installerAvailable {
     try await prepareInstaller(update.release.installer, p12: p12, profile: profile, password: password)
    }
    if needsSigning {
     hasPreparedUpdate = false
     try? FileManager.default.removeItem(at: marker)
     try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
     stage = "Скачивание обновления…"
     try await downloading.value
     stage = "Подпись выбранным сертификатом…"
     let identifier = Bundle.main.bundleIdentifier ?? "thewonderofyou.Feather"
     let directory = cache
     try await Task.detached(priority: .utility) {
      try Self.prepareIPA(release: update.release, source: source, destination: ipa, directory: directory, p12: p12, profile: profile, password: password, identifier: identifier)
     }.value
     try JSONEncoder().encode(expected).write(to: marker, options: .atomic)
    }
    guard Storage.shared.selectedCertificate()?.uuid == uuid else {
     throw AppBankUpdateError.message("Сертификат изменился. Повтори обновление.")
    }
    hasPreparedUpdate = true
    stage = "Подготовка установки…"
    _ = try AppBankBackup.create()
    if UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1 {
     let viewModel = InstallerStatusViewModel(isIdevice: true)
     let proxy = InstallationProxy(viewModel: viewModel)
     try await proxy.install(at: ipa, suspend: true)
    } else {
     preparedUpdateURL = ipa
     try await waitForInstaller()
     guard Storage.shared.selectedCertificate()?.uuid == uuid else { throw AppBankUpdateError.message("Сертификат изменился. Повтори обновление.") }
     bootstrap = nil
     try await handoff(ipa, update: update)
    }
    isWorking = false
   } catch {
    bootstrap = nil; transfer = nil; handoffTimeout?.cancel()
    isWorking = false
    errorMessage = error.localizedDescription
    isInstalling = false
    stage = nil
    #if !targetEnvironment(macCatalyst)
    BackgroundAudioManager.shared.stop()
    #endif
   }
  }
 }

 private var installerAvailable: Bool { UIApplication.shared.canOpenURL(URL(string: "\(InstallerHandoff.scheme)://install")!) }

 private func downloadSource(_ release: AppBankRelease, to source: URL) async throws {
  try release.validate()
  if (try? Data(contentsOf: source)).map(Self.hash) == release.sha256 { return }
  let (temporary, response) = try await URLSession.shared.download(for: URLRequest(url: release.downloadURL, timeoutInterval: 120))
  defer { try? FileManager.default.removeItem(at: temporary) }
  guard (response as? HTTPURLResponse)?.statusCode == 200, response.url?.scheme == "https", response.url?.host == "cert.appbank.pw" else { throw AppBankUpdateError.message("Не удалось скачать обновление.") }
  let data = try Data(contentsOf: temporary)
  guard data.count == release.size, Self.hash(data) == release.sha256 else { throw AppBankUpdateError.message("Файл обновления повреждён. Повтори скачивание.") }
  try data.write(to: source, options: .atomic)
 }

 private func prepareInstaller(_ release: AppBankInstallerRelease?, p12: URL, profile: URL, password: String) async throws {
  guard let release else { throw AppBankUpdateError.message("Installer пока недоступен для этой сборки.") }
  stage = "Подготовка Feather Installer…"
  let source = cache.appendingPathComponent("InstallerSource.ipa"), signed = cache.appendingPathComponent("Installer.ipa")
  try await downloadSource(release.release, to: source)
  let directory = cache
  try await Task.detached(priority: .utility) {
   try Self.prepareIPA(release: release.release, source: source, destination: signed, directory: directory,
       p12: p12, profile: profile, password: password, identifier: InstallerHandoff.bundleIdentifier, sourceIdentifier: InstallerHandoff.bundleIdentifier)
  }.value
  let model = InstallerBootstrapApp()
  let status = InstallerStatusViewModel(isIdevice: false)
  let server = try ServerInstaller(app: model, viewModel: status)
  server.packageUrl = signed; bootstrap = server
  try await server.prepare()
  let link = server.getServerMethod() == 0 ? server.iTunesLink : server.iTunesLinkExternal
  guard let url = URL(string: link), await UIApplication.shared.open(url) else { throw AppBankUpdateError.message("Не удалось открыть установку Installer.") }
  stage = "Подтверди установку Feather Installer. Обновление Feather готовится параллельно."
 }

 private func waitForInstaller() async throws {
  for attempt in 0..<240 {
   if installerAvailable { return }
   if attempt == 20, let bootstrap, bootstrap.getServerMethod() == 0, case .none = bootstrap.viewModel.status {
    if try await bootstrap.recoverToSemiLocal(), let url = URL(string: bootstrap.iTunesLinkExternal) { _ = await UIApplication.shared.open(url) }
   }
   stage = "Дождись установки Feather Installer и вернись в Feather."
   try await Task.sleep(nanoseconds: 1_000_000_000)
   if let bootstrap, case .broken(let error) = bootstrap.viewModel.status { throw error }
  }
  throw AppBankUpdateError.message("Installer ещё не установлен. Заверши его установку и повтори обновление — подписанный файл сохранён.")
 }

 private func handoff(_ ipa: URL, update: AppBankUpdate) async throws {
  transfer = nil; handoffTimeout?.cancel()
  let server = try InstallerTransferServer(ipa: ipa, identifier: Bundle.main.bundleIdentifier ?? "", version: update.version, build: update.build) { [weak self] receipt in
   Task { @MainActor in
    guard let self else { return }
    UserDefaults.standard.set(try? JSONEncoder().encode(receipt), forKey: "AppBank.installerReceipt")
    self.stage = "Файл сохранён в Installer. Подтверди установку Feather."
    self.handoffTimeout?.cancel()
    try? await Task.sleep(nanoseconds: 500_000_000)
    self.transfer = nil
    #if !targetEnvironment(macCatalyst)
    BackgroundAudioManager.shared.stop()
    #endif
   }
  }
  transfer = server
  guard await UIApplication.shared.open(try server.request.link()) else {
   transfer = nil
   throw AppBankUpdateError.message("Не удалось открыть Installer. Вернись в Feather и повтори передачу.")
  }
  isInstalling = true; stage = "Передача обновления в Installer…"
  handoffTimeout = Task { [weak self] in
   try? await Task.sleep(nanoseconds: 180_000_000_000)
   guard !Task.isCancelled, let self else { return }
   self.transfer = nil; self.isInstalling = false
   self.errorMessage = "Installer не подтвердил получение файла. Вернись в Feather и повтори передачу."
   #if !targetEnvironment(macCatalyst)
   BackgroundAudioManager.shared.stop()
   #endif
  }
 }

 private func confirmInstalledBuild() async {
  guard let data = UserDefaults.standard.data(forKey: "AppBank.installerReceipt"),
        let receipt = try? JSONDecoder().decode(InstallerReceipt.self, from: data),
        receipt.build == Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
        receipt.cleanup.scheme == "http", receipt.cleanup.host == "127.0.0.1" else { return }
  var request = URLRequest(url: receipt.cleanup, timeoutInterval: 5)
  request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  request.httpBody = try? JSONEncoder().encode(["build": receipt.build])
  if let (_, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 {
   UserDefaults.standard.removeObject(forKey: "AppBank.installerReceipt")
  }
 }

 nonisolated private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
 nonisolated private static func prepareIPA(release: AppBankRelease, source: URL, destination: URL, directory: URL, p12: URL, profile: URL, password: String, identifier: String, sourceIdentifier: String = "thewonderofyou.Feather") throws {
  let work = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: work) }
  Zip.addCustomFileExtension("ipa")
  try Zip.unzipFile(source, destination: work, overwrite: false, password: nil)
  let payload = work.appendingPathComponent("Payload")
  let apps = try FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
  guard apps.count == 1 else { throw AppBankUpdateError.message("Некорректный архив обновления.") }
  let app = apps[0], infoURL = app.appendingPathComponent("Info.plist")
  guard var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any] else { throw AppBankUpdateError.message("Некорректный Info.plist.") }
  try release.validateBundle(info, identifier: sourceIdentifier)
  // Self updates bypass all user rename, PPQ, tweak and custom-version options.
  info["CFBundleIdentifier"] = identifier
  if sourceIdentifier == "thewonderofyou.Feather" { info["AppBankUpdateURL"] = "https://cert.appbank.pw/feather_update.php?mode=local" }
  try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: infoURL, options: .atomic)
  var signingError: Error?
  let success = Zsign.sign(appPath: app.path, provisionPath: profile.path, p12Path: p12.path, p12Password: password, removeProvision: true) { _, error in signingError = error }
  if let signingError { throw signingError }
  guard success, FileManager.default.fileExists(atPath: app.appendingPathComponent("embedded.mobileprovision").path) else { throw AppBankUpdateError.message("Не удалось подписать обновление.") }
  let profileData = try Data(contentsOf: app.appendingPathComponent("embedded.mobileprovision"))
  let resources = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("_CodeSignature/CodeResources")), format: nil) as? [String: Any]
  let files = resources?["files2"] as? [String: Any]
  let sealed = files?["embedded.mobileprovision"] as? [String: Any]
  guard let profileHash = sealed?["hash2"] as? Data, profileHash == Data(SHA256.hash(data: profileData)) else {
   throw AppBankUpdateError.message("Подпись профиля обновления некорректна. Установка остановлена.")
  }
  let archive = work.appendingPathComponent("Signed.zip")
  try Zip.zipFiles(paths: [payload], zipFilePath: archive, password: nil, compression: .DefaultCompression, progress: nil)
  try? FileManager.default.removeItem(at: destination)
  try FileManager.default.moveItem(at: archive, to: destination)
 }
}

private struct InstallerBootstrapApp: AppInfoPresentable {
 var name: String? { "Feather Installer" }
 var version: String? { "1.0.0" }
 var identifier: String? { InstallerHandoff.bundleIdentifier }
 var date: Date? { nil }
 var icon: String? { nil }
 var uuid: String? { nil }
 var source: URL? { nil }
 var isSigned: Bool { true }
}
