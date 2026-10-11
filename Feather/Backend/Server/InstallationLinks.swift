// AppBank installation helpers. GPL-3.0.
import Foundation

enum InstallationLinks {
    static func manifestURL(identifier: String, name: String, version: String, payload: URL) -> URL {
        var components = URLComponents(string: "https://api.palera.in/genPlist")!
        components.queryItems = [
            URLQueryItem(name: "bundleid", value: identifier),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "fetchurl", value: payload.absoluteString),
        ]
        return components.url!
    }

    static func installURL(manifest: URL) -> URL {
        // Encode the entire nested URL: an '&' in an app name must not become
        // another parameter of either genPlist or itms-services.
        let encoded = manifest.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        return URL(string: "itms-services://?action=download-manifest&url=\(encoded)")!
    }

    static func concreteHost(_ commonName: String) -> String? {
        let name = commonName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return name.hasPrefix("*.") ? "local" + name.dropFirst() : name
    }

    static func semiLocalHost(wifiAddress: String?, onlyLocalhost: Bool) -> String {
        onlyLocalhost ? "127.0.0.1" : (wifiAddress ?? "127.0.0.1")
    }

    static func validatesManifest(_ data: Data, identifier: String, payload: URL) -> Bool {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let item = (plist["items"] as? [[String: Any]])?.first,
              let metadata = item["metadata"] as? [String: Any],
              metadata["bundle-identifier"] as? String == identifier,
              let assets = item["assets"] as? [[String: Any]] else { return false }
        return assets.contains { $0["kind"] as? String == "software-package" && $0["url"] as? String == payload.absoluteString }
    }
}
