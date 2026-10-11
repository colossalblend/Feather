import SwiftUI
import CryptoKit
import Zip

@main
struct FeatherInstallerApp: App {
 @StateObject private var model = InstallerModel()
 var body: some Scene {
  WindowGroup {
   VStack(spacing: 22) {
    Image(systemName: "shippingbox.and.arrow.backward.fill").font(.system(size: 64)).foregroundStyle(.orange)
    Text("Feather Installer").font(.title.bold())
    Text(model.stage).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    if model.busy { ProgressView() }
    if let error = model.error { Text(error).foregroundStyle(.red).multilineTextAlignment(.center) }
    if !model.busy, model.pending != nil {
     Button("Повторить установку") { model.retry() }.buttonStyle(.borderedProminent)
    }
    Text("Установщик обновлений Feather").font(.footnote).foregroundStyle(.secondary)
   }.padding(28).onOpenURL { model.open($0) }
  }
 }
}

@MainActor
final class InstallerModel: ObservableObject {
 @Published var stage = "Открой обновление в основном Feather. Подписанный файл появится здесь автоматически."
 @Published var error: String?
 @Published var busy = false
 @Published var pending: InstallerHandoff?
 private var server: InstallerServer?
 private var timer: Task<Void, Never>?
 private let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Installer", isDirectory: true)
 private var ipa: URL { directory.appendingPathComponent("Update.ipa") }
 init() {
  if let data = try? Data(contentsOf: directory.appendingPathComponent("request.json")),
     let saved = try? JSONDecoder().decode(InstallerHandoff.self, from: data),
     FileManager.default.fileExists(atPath: ipa.path) { pending = saved; stage = "Обновление сохранено. Можно повторить установку." }
 }
 func open(_ url: URL) {
  do { let request = try InstallerHandoff.parse(url); receive(request) }
  catch { self.error = error.localizedDescription }
 }
 func retry() { if let pending { receive(pending) } }
 private func receive(_ request: InstallerHandoff) {
  guard !busy else { return }
  busy = true; error = nil
  BackgroundAudioManager.shared.start()
  Task {
   do {
    try request.validate()
    timer?.cancel(); server = nil
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if !matches(request) {
     stage = "Получение подписанного обновления…"
     let (temporary, response) = try await URLSession.shared.download(for: URLRequest(url: request.source, timeoutInterval: 120))
     defer { try? FileManager.default.removeItem(at: temporary) }
     guard (response as? HTTPURLResponse)?.statusCode == 200, response.url == request.source else { throw HandoffError.invalid }
     let data = try Data(contentsOf: temporary)
     guard data.count == request.size, Self.hash(data) == request.sha256 else { throw HandoffError.invalid }
     try data.write(to: ipa, options: .atomic)
    }
    // Only hand iOS a fully received, verified file in THIS app's container.
    try verifyBundle(request)
    try JSONEncoder().encode(request).write(to: directory.appendingPathComponent("request.json"), options: .atomic)
    pending = request; stage = "Подготовка установки…"
    let local = InstallerServer(ipa: ipa, request: request, completed: { [weak self] in
     Task { @MainActor in
      try? await Task.sleep(nanoseconds: 500_000_000)
      self?.confirmed()
     }
    }, delivered: { [weak self] in
     Task { @MainActor in self?.delivered() }
    })
    server = local
    try await local.prepare()
    // A retry after the sending app has exited uses the already saved file.
    var ack = URLRequest(url: request.acknowledgement, timeoutInterval: 8)
    ack.httpMethod = "POST"; ack.setValue("application/json", forHTTPHeaderField: "Content-Type")
    ack.httpBody = try JSONEncoder().encode(InstallerReceipt(build: request.build, sha256: request.sha256, cleanup: local.cleanup))
    _ = try? await URLSession.shared.data(for: ack)
    guard let manifest = local.manifest, await UIApplication.shared.open(InstallationLinks.installURL(manifest: manifest)) else { throw HandoffError.invalid }
    stage = "Подтверди установку Feather в системном окне."
    timer = Task { [weak self] in
     try? await Task.sleep(nanoseconds: 300_000_000_000)
     guard !Task.isCancelled, let self else { return }
     self.server = nil; self.busy = false
     self.stage = "Открой основной Feather и проверь версию. При ошибке можно повторить установку сохранённого файла."
     BackgroundAudioManager.shared.stop()
    }
   } catch {
    self.error = error.localizedDescription; busy = false; server = nil
    BackgroundAudioManager.shared.stop()
   }
  }
 }
 private func matches(_ request: InstallerHandoff) -> Bool {
  guard let data = try? Data(contentsOf: ipa) else { return false }
  return data.count == request.size && Self.hash(data) == request.sha256
 }
 private func verifyBundle(_ request: InstallerHandoff) throws {
  let work = directory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: work) }
  Zip.addCustomFileExtension("ipa")
  try Zip.unzipFile(ipa, destination: work, overwrite: false, password: nil)
  let apps = try FileManager.default.contentsOfDirectory(at: work.appendingPathComponent("Payload"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "app" }
  guard apps.count == 1,
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: apps[0].appendingPathComponent("Info.plist")), format: nil) as? [String: Any],
        info["CFBundleIdentifier"] as? String == request.identifier,
        info["CFBundleVersion"] as? String == request.build,
        info["CFBundleShortVersionString"] as? String == request.version,
        FileManager.default.fileExists(atPath: apps[0].appendingPathComponent("embedded.mobileprovision").path) else { throw HandoffError.invalid }
 }
 private func delivered() { stage = "iOS получила файл. Дождись установки и открой основной Feather." }
 private func confirmed() {
  timer?.cancel(); server = nil; pending = nil; busy = false
  try? FileManager.default.removeItem(at: directory)
  stage = "Feather обновлён. Временный файл удалён."
  BackgroundAudioManager.shared.stop()
 }
 private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
