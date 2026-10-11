import SwiftUI
import UniformTypeIdentifiers

private struct AppBankBackupDocument: FileDocument {
 static var readableContentTypes: [UTType] { [.data] }
 var data: Data
 init(data: Data) { self.data = data }
 init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
 func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct AppBankBackupView: View {
 @State private var document = AppBankBackupDocument(data: Data())
 @State private var exporting = false
 @State private var importing = false
 @State private var message = ""
 @State private var showingMessage = false
 var body: some View {
  Form {
   Section {
    Button {
     do { document = AppBankBackupDocument(data: try Data(contentsOf: AppBankBackup.create())); exporting = true }
     catch { show(error.localizedDescription) }
    } label: { Label("Сохранить резервную копию", systemImage: "square.and.arrow.up") }
    Button { importing = true } label: { Label("Восстановить из файла", systemImage: "square.and.arrow.down") }
   } footer: {
    Text("Сохраняются настройки и список источников. Сертификаты и файлы приложений в копию не входят. При восстановлении источники добавляются к существующим; настройки заменяются настройками из файла.")
   }
  }
  .navigationTitle("Резервная копия")
  .fileExporter(isPresented: $exporting, document: document, contentType: .data, defaultFilename: "AppBank-Backup.plist") { result in
   if case .failure(let error) = result { show(error.localizedDescription) }
  }
  .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
   do {
    let url = try result.get()
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    try AppBankBackup.restore(Data(contentsOf: url))
    show("Настройки и источники восстановлены.")
   } catch { show(error.localizedDescription) }
  }
  .alert("Резервная копия", isPresented: $showingMessage) { Button("OK", role: .cancel) {} } message: { Text(message) }
 }
 private func show(_ text: String) { message = text; showingMessage = true }
}
