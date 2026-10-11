import Foundation
import CoreData

@MainActor
enum AppBankBackup {
 static let keys: Set<String> = ["Feather.userInterfaceStyle", "Feather.shouldTintIcons", "Feather.shouldChangeIconsBasedOffStyle", "Feather.storeCellAppearance", "Feather.userTintColor", "Feather.compressionLevel", "Feather.useShareSheetForArchiving", "Feather.installationMethod", "Feather.ipFix", "Feather.serverMethod", "signing_options"]
 static var location: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("AppBank-Backup.plist") }
 static func create() throws -> URL {
  let settings = UserDefaults.standard.dictionaryRepresentation().filter { keys.contains($0.key) }
  let sources: [[String: String]] = Storage.shared.getSources().compactMap { source in
   guard let url = source.sourceURL else { return nil }
   return ["url": url.absoluteString, "name": source.name ?? "Источник", "identifier": source.identifier ?? url.absoluteString, "icon": source.iconURL?.absoluteString ?? ""]
  }
  let data = try PropertyListSerialization.data(fromPropertyList: ["format": "AppBankBackup", "version": 1, "settings": settings, "sources": sources], format: .binary, options: 0)
  try data.write(to: location, options: .atomic)
  return location
 }
 static func restore(_ data: Data) throws {
  guard data.count <= 1_000_000,
   let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
   root["format"] as? String == "AppBankBackup", root["version"] as? Int == 1,
   let settings = root["settings"] as? [String: Any], let sources = root["sources"] as? [[String: String]], sources.count <= 1000
  else { throw AppBankUpdateError.message("Файл не является резервной копией AppBank.") }
  var validated: [(URL, String, String, URL?)] = []
  for source in sources {
   guard let raw = source["url"], let url = URL(string: raw), ["https", "http"].contains(url.scheme ?? ""), url.host != nil,
    url.user == nil, url.password == nil, let id = source["identifier"], !id.isEmpty, id.count <= 1000
   else { throw AppBankUpdateError.message("В резервной копии некорректный адрес источника.") }
   validated.append((url, source["name"] ?? "Источник", id, source["icon"].flatMap(URL.init(string:))))
  }
  var options: Options?
  if let raw = settings["signing_options"] {
   guard let encoded = raw as? Data else { throw AppBankUpdateError.message("Некорректные настройки подписи.") }
   options = try JSONDecoder().decode(Options.self, from: encoded)
   // Referenced files are not part of a settings/source backup.
   options?.appEntitlementsFile = nil
   options?.injectionFiles = []
  }
  let context = Storage.shared.context
  try context.save()
  do {
   for (url, name, id, icon) in validated {
    if Storage.shared.sourceExists(id) || Storage.shared.getSources().contains(where: { $0.sourceURL == url }) { continue }
    let source = AltSource(context: context)
    source.sourceURL = url; source.name = name; source.identifier = id; source.iconURL = icon; source.date = Date()
   }
   try context.save()
  } catch { context.rollback(); throw error }
  for (key, value) in settings where keys.contains(key) && key != "signing_options" { UserDefaults.standard.set(value, forKey: key) }
  if let options { OptionsManager.shared.options = options; OptionsManager.shared.saveOptions() }
 }
}
