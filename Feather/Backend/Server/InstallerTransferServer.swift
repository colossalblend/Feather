import Foundation
import Vapor
import CryptoKit

final class InstallerTransferServer {
 private let server: Application
 let request: InstallerHandoff
 init(ipa: URL, identifier: String, version: String, build: String,
      received: @escaping (InstallerReceipt) -> Void) throws {
  let port = Int.random(in: 20000...50000), token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
  let data = try Data(contentsOf: ipa)
  request = InstallerHandoff(source: URL(string: "http://127.0.0.1:\(port)/transfer/\(token)/Update.ipa")!,
      sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), size: Int64(data.count),
      identifier: identifier, version: version, build: build, token: token)
  try request.validate()
  server = Application(.production)
  server.http.server.configuration.hostname = "127.0.0.1"
  server.http.server.configuration.port = port
  server.threadPool = .init(numberOfThreads: 1)
  server.routes.defaultMaxBodySize = "8kb"
  let expected = request
  server.get("transfer", .constant(token), "Update.ipa") { req -> Response in
   req.fileio.streamFile(at: ipa.path)
  }
  server.post("ack", .constant(token)) { req -> HTTPStatus in
   guard let body = req.body.data,
         let receipt = try? JSONDecoder().decode(InstallerReceipt.self, from: Data(body.readableBytesView)),
         receipt.build == expected.build, receipt.sha256 == expected.sha256,
         receipt.cleanup.scheme == "http", receipt.cleanup.host == "127.0.0.1",
         receipt.cleanup.port.map({ (1024...65535).contains($0) }) == true,
         receipt.cleanup.path == "/complete/\(token)", receipt.cleanup.query == nil,
         receipt.cleanup.user == nil, receipt.cleanup.password == nil else { return .badRequest }
   received(receipt)
   return .ok
  }
  do { try server.server.start() } catch { server.shutdown(); throw error }
 }
 deinit { server.server.shutdown(); server.shutdown() }
}
