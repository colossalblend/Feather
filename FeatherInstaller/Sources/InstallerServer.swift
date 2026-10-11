import Foundation
import Vapor
import NIOSSL

final class InstallerServer {
 private var app: Application?
 private let ipa: URL
 private let request: InstallerHandoff
 private let completed: () -> Void
 private let delivered: () -> Void
 private let coverage = PayloadCoverage()
 private var port = Int.random(in: 20000...50000)
 private var host = "127.0.0.1"
 private var secure = true
 private(set) var manifest: URL?
 var cleanup: URL { URL(string: "http://127.0.0.1:\(receiptPort)/complete/\(request.token)")! }
 private let receiptPort = Int.random(in: 50001...60000)
 private var receiptServer: Application?

 init(ipa: URL, request: InstallerHandoff, completed: @escaping () -> Void, delivered: @escaping () -> Void) {
  self.ipa = ipa; self.request = request; self.completed = completed; self.delivered = delivered
 }
 private func start(secure: Bool) throws {
  self.secure = secure
  let server = Application(.production)
  server.threadPool = .init(numberOfThreads: 1)
  server.http.server.configuration.hostname = "127.0.0.1"
  server.http.server.configuration.port = port
  do {
   if secure {
    guard let cert = Bundle.main.url(forResource: "server", withExtension: "crt"),
          let key = Bundle.main.url(forResource: "server", withExtension: "pem"),
          let name = Bundle.main.url(forResource: "commonName", withExtension: "txt"),
          let concrete = InstallationLinks.concreteHost(try String(contentsOf: name)) else { throw HandoffError.invalid }
    host = concrete
    server.http.server.configuration.tlsConfiguration = try TLSConfiguration.makeServerConfiguration(
        certificateChain: NIOSSLCertificate.fromPEMFile(cert.path).map { .certificate($0) },
        privateKey: .privateKey(NIOSSLPrivateKey(file: key.path, format: .pem)))
   } else { host = "127.0.0.1" }
   let payload = payloadURL
   let manifestData = try PropertyListSerialization.data(fromPropertyList: ["items": [[
     "assets": [["kind": "software-package", "url": payload.absoluteString]],
     "metadata": ["bundle-identifier": request.identifier, "bundle-version": request.version, "kind": "software", "title": "Feather"]
   ]]], format: .xml, options: 0)
   server.get("healthz") { _ in HTTPStatus.ok }
   server.get("manifest.plist") { _ in Response(status: .ok, headers: ["Content-Type": "text/xml"], body: .init(data: manifestData)) }
   let ipa = self.ipa, coverage = self.coverage, delivered = self.delivered, size = request.size
   server.get("Update.ipa") { req -> Response in
    let range = req.headers.first(name: .range)
    return req.fileio.streamFile(at: ipa.path) { result in
     if case .success = result, coverage.record(rangeHeader: range, size: size) { delivered() }
    }
   }
   try server.server.start()
   app = server
  } catch { server.shutdown(); throw error }
 }
 private var payloadURL: URL { URL(string: "\(secure ? "https" : "http")://\(host):\(port)/Update.ipa")! }
 func prepare() async throws {
  do {
   try start(secure: true)
   let health = URL(string: "https://\(host):\(port)/healthz")!
   let (_, response) = try await URLSession.shared.data(for: URLRequest(url: health, timeoutInterval: 8))
   guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw HandoffError.invalid }
   manifest = URL(string: "https://\(host):\(port)/manifest.plist")!
  } catch {
   await app?.server.shutdown(); app?.shutdown(); app = nil
   port = Int.random(in: 20000...50000)
   try start(secure: false)
   for endpoint in ["https://ryuksign-install.ryuksign.workers.dev/genPlist", "https://api.palera.in/genPlist"] {
    let url = InstallationLinks.manifestURL(identifier: request.identifier, name: "Feather", version: request.version, payload: payloadURL, endpoint: endpoint)
    guard let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)),
          (response as? HTTPURLResponse)?.statusCode == 200,
          InstallationLinks.validatesManifest(data, identifier: request.identifier, payload: payloadURL) else { continue }
    manifest = url; break
   }
   guard manifest != nil else { throw NSError(domain: "Installer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Не удалось подготовить установку. Проверь интернет и повтори."]) }
  }
  let receiver = Application(.production)
  receiver.threadPool = .init(numberOfThreads: 1)
  receiver.http.server.configuration.hostname = "127.0.0.1"
  receiver.http.server.configuration.port = receiptPort
  receiver.routes.defaultMaxBodySize = "8kb"
  let build = request.build, completed = self.completed
  receiver.post("complete", .constant(request.token)) { req -> HTTPStatus in
   guard let data = req.body.data,
         let confirmation = try? JSONDecoder().decode([String: String].self, from: Data(data.readableBytesView)),
         confirmation["build"] == build else { return .badRequest }
   completed(); return .ok
  }
  do { try receiver.server.start(); receiptServer = receiver } catch { receiver.shutdown(); throw error }
 }
 deinit {
  app?.server.shutdown(); app?.shutdown()
  receiptServer?.server.shutdown(); receiptServer?.shutdown()
 }
}
