import Foundation

extension KeyedDecodingContainer {
	// Repository extras are optional. An empty/malformed GitHub URL must not
	// prevent the rest of a repository from loading.
	func downloadURL(forKeys keys: [Key]) -> URL? {
		for key in keys {
			guard let raw = try? decode(String.self, forKey: key),
				let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
				let scheme = url.scheme?.lowercased(),
				["http", "https"].contains(scheme),
				let host = url.host, !host.isEmpty else { continue }
			return url
		}
		return nil
	}
}
