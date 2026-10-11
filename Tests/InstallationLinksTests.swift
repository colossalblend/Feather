import Foundation

@main
struct InstallationLinksTests {
    static func main() throws {
        let payload = URL(string: "http://127.0.0.1:5432/test.ipa")!
        let name = "AppBank & Приложение + #? 100%"
        let manifest = InstallationLinks.manifestURL(identifier: "test.app", name: name, version: "1.2", payload: payload)
        let items = URLComponents(url: manifest, resolvingAgainstBaseURL: false)!.queryItems!
        assert(items.first { $0.name == "name" }?.value == name)
        assert(items.first { $0.name == "fetchurl" }?.value == payload.absoluteString)
        let nested = URLComponents(url: InstallationLinks.installURL(manifest: manifest), resolvingAgainstBaseURL: false)!.queryItems!
        assert(nested.count == 2)
        assert(nested.first { $0.name == "url" }?.value == manifest.absoluteString)
        assert(InstallationLinks.semiLocalHost(wifiAddress: nil, onlyLocalhost: false) == "127.0.0.1")
        assert(InstallationLinks.semiLocalHost(wifiAddress: "192.168.1.7", onlyLocalhost: false) == "192.168.1.7")
        assert(InstallationLinks.semiLocalHost(wifiAddress: "192.168.1.7", onlyLocalhost: true) == "127.0.0.1")
        assert(InstallationLinks.concreteHost("*.backloop.dev\n") == "local.backloop.dev")
        assert(InstallationLinks.concreteHost("localhost.backloop.dev") == "localhost.backloop.dev")
        assert(InstallationLinks.concreteHost("  ") == nil)
        let plist: [String: Any] = ["items": [["metadata": ["bundle-identifier": "test.app"], "assets": [["kind": "software-package", "url": payload.absoluteString]]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        assert(InstallationLinks.validatesManifest(data, identifier: "test.app", payload: payload))
        assert(!InstallationLinks.validatesManifest(data, identifier: "other.app", payload: payload))
        assert(!InstallationLinks.validatesManifest(data, identifier: "test.app", payload: URL(string: "http://127.0.0.1/wrong.ipa")!))
        assert(!InstallationLinks.validatesManifest(Data("<html>Error</html>".utf8), identifier: "test.app", payload: payload))
        print("Installation regression checks passed (14 assertions)")
    }
}
